#include "renditionlocalstore.h"
#include "renditionvalidation.h"
#include "renditioncontract.h"
#include "renditionattachmentcontract.h"

#include "appcontext.h"
#include "authsession.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QList>
#include <QPair>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUuid>
#include <QUrl>

namespace {
constexpr auto LocalOnly = "LOCAL_ONLY";
constexpr auto PendingCreate = "PENDING_CREATE";
constexpr auto PendingUpdate = "PENDING_UPDATE";
constexpr auto Syncing = "SYNCING";
constexpr auto Synced = "SYNCED";
constexpr auto Conflict = "CONFLICT";
constexpr auto NeedsReconciliation = "NEEDS_RECONCILIATION";
constexpr auto Error = "ERROR";

QString stateOf(const QVariantMap &value)
{
    return value.value(QStringLiteral("syncState"), QString::fromLatin1(LocalOnly)).toString();
}

QVariant valueFor(const QVariantMap &map, const QString &camel,
                  const QString &snake)
{
    const QVariant camelValue = map.value(camel);
    return camelValue.isValid() ? camelValue : map.value(snake);
}

QString referenceFor(const QVariantMap &map)
{
    for (const QString &key : {QStringLiteral("reference"),
                               QStringLiteral("reference_code"),
                               QStringLiteral("shortReference"),
                               QStringLiteral("short_reference"),
                               QStringLiteral("renditionReference"),
                               QStringLiteral("rendition_reference")}) {
        const QString candidate = map.value(key).toString().trimmed();
        if (!candidate.isEmpty())
            return candidate;
    }
    QString identifier = map.value(QStringLiteral("id")).toString();
    if (identifier.isEmpty())
        identifier = map.value(QStringLiteral("rendition_id")).toString();
    const int separator = identifier.indexOf(QLatin1Char('-'));
    return separator > 0 ? identifier.left(separator) : QString{};
}
}

RenditionLocalStore::RenditionLocalStore(AuthSession *auth, QObject *parent)
    : QObject(parent), m_auth(auth)
{
    if (m_auth) {
        const auto refreshAccount = [this]() {
            const QString userId = m_auth->logged() ? m_auth->userId().trimmed() : QString{};
            const QString environment = appContext()
                ? appContext()->supabaseUrl().trimmed() : QString{};
            selectAccount(userId.isEmpty() || environment.isEmpty()
                              ? QString{} : environment + QLatin1Char('|') + userId);
        };
        connect(m_auth, &AuthSession::currentAccountChanged, this, refreshAccount);
        connect(m_auth, &AuthSession::userInfoChanged, this, refreshAccount);
        connect(m_auth, &AuthSession::loggedOut, this, [this]() { selectAccount({}); });
        refreshAccount();
    }
}

int RenditionLocalStore::pendingCount() const
{
    int count = 0;
    for (const QVariant &item : m_outbox) {
        const QString state = item.toMap().value(QStringLiteral("state")).toString();
        if (state != QLatin1String(Synced) && state != QLatin1String(LocalOnly))
            ++count;
    }
    return count;
}

QVariantList RenditionLocalStore::renditions() const
{
    QVariantList visible;
    for (const auto &row : m_renditions)
        if (!row.toMap().value(QStringLiteral("archived")).toBool()) visible.append(row);
    return visible;
}

bool RenditionLocalStore::removeDraft(const QString &localId)
{
    const int index = renditionIndex(localId);
    if (index < 0) return false;
    auto draft = m_renditions[index].toMap();
    if (draft.value(QStringLiteral("archived")).toBool()) return true;
    if (!assertDraftStatus(draft)) return false;
    const auto remote = draft.value(QStringLiteral("remoteId")).toString();
    if (stateOf(draft) == QLatin1String(Conflict) || stateOf(draft) == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Sincroniza y revisa los cambios antes de eliminar el borrador.")); return false;
    }
    for (const auto &value : m_outbox) {
        const auto op = value.toMap();
        if (op.value(QStringLiteral("aggregateLocalId")).toString() != localId) continue;
        if (op.value(QStringLiteral("state")).toString() == QLatin1String(Syncing)
            || (remote.isEmpty() && op.value(QStringLiteral("attempts")).toInt() > 0)) {
            setLastError(QStringLiteral("Confirma la sincronización pendiente antes de eliminar el borrador.")); return false;
        }
    }
    const auto oldRows = m_renditions, oldOutbox = m_outbox;
    const auto oldDrafts = m_editorDrafts;
    for (int i = m_outbox.size() - 1; i >= 0; --i)
        if (m_outbox[i].toMap().value(QStringLiteral("aggregateLocalId")).toString() == localId) m_outbox.removeAt(i);
    for (const auto &key : m_editorDrafts.keys())
        if (key == QStringLiteral("header:") + localId || key.startsWith(QStringLiteral("expense:") + localId + ':')
            || m_editorDrafts.value(key).toMap().value(QStringLiteral("renditionLocalId")).toString() == localId) m_editorDrafts.remove(key);
    if (remote.isEmpty()) m_renditions.removeAt(index);
    else {
        draft.insert(QStringLiteral("archived"), true);
        draft.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
        m_renditions[index] = draft;
        upsertOutbox(QStringLiteral("rendition_delete"), localId, remote, {}, newUuid(),
            {{QStringLiteral("expectedRowVersion"), draft.value(QStringLiteral("rowVersion"))}}, QString::fromLatin1(PendingUpdate));
    }
    if (persist()) return true;
    m_renditions = oldRows; m_outbox = oldOutbox; m_editorDrafts = oldDrafts;
    return false;
}

bool RenditionLocalStore::markDraftDeleted(const QString &localId, const QVariantMap &remote)
{
    const int index = renditionIndex(localId);
    if (index < 0 || remoteId(remote) != m_renditions[index].toMap().value(QStringLiteral("remoteId")).toString()
        || remote.value(QStringLiteral("archived_at")).toString().isEmpty()) return false;
    auto draft = m_renditions[index].toMap();
    draft.insert(QStringLiteral("expenses"), QVariantList{});
    draft.insert(QStringLiteral("archived"), true);
    draft.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    m_renditions[index] = draft;
    markOutboxState(QStringLiteral("rendition_delete"), localId, {}, QString::fromLatin1(Synced));
    return persist();
}

RenditionLocalStore::RenditionLocalStore(const QString &accountScope, QObject *parent)
    : QObject(parent)
{
    selectAccount(accountScope);
}

void RenditionLocalStore::selectAccount(const QString &accountScope)
{
    if (m_accountScope == accountScope)
        return;
    m_accountScope = accountScope;
    m_renditions.clear();
    m_outbox.clear();
    m_editorDrafts.clear();
    m_nextSequence = 1;
    emit accountIdChanged();
    reload();
}

QString RenditionLocalStore::storagePath() const
{
    if (m_accountScope.isEmpty())
        return {};
    const QByteArray digest = QCryptographicHash::hash(
        m_accountScope.toUtf8(), QCryptographicHash::Sha256).toHex();
    const QString root = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation) + QStringLiteral("/renditions/accounts");
    return root + QLatin1Char('/') + QString::fromLatin1(digest) + QStringLiteral(".json");
}

void RenditionLocalStore::reload()
{
    m_renditions.clear();
    m_outbox.clear();
    m_editorDrafts.clear();
    m_nextSequence = 1;
    setLastError({});
    const QString path = storagePath();
    if (!path.isEmpty() && QFile::exists(path)) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            setLastError(QStringLiteral("No se pudo abrir el almacén local de rendiciones."));
        } else {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
            if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
                setLastError(QStringLiteral("El almacén local de rendiciones no es válido."));
            } else {
                const QVariantMap root = document.object().toVariantMap();
                m_renditions = root.value(QStringLiteral("renditions")).toList();
                m_outbox = root.value(QStringLiteral("outbox")).toList();
                m_editorDrafts = root.value(QStringLiteral("editorDrafts")).toMap();
                m_nextSequence = qMax<qint64>(1,
                    root.value(QStringLiteral("nextSequence"), 1).toLongLong());
                if (m_outbox.isEmpty() && !m_renditions.isEmpty())
                    rebuildLegacyOutbox();
            }
        }
    }
    // A process can die after sending a request and before saving its result.
    // Replay only idempotent intentions; CAS updates need a remote reconciliation.
    const auto interrupted = m_outbox;
    for (const auto &value : interrupted) {
        const auto entry = value.toMap();
        if (entry.value(QStringLiteral("state")).toString() != QLatin1String(Syncing)) continue;
        const auto operation = entry.value(QStringLiteral("operation")).toString();
        const auto aggregate = entry.value(QStringLiteral("aggregateLocalId")).toString();
        const auto child = entry.value(QStringLiteral("childLocalId")).toString();
        const QString message = QStringLiteral("La operación fue interrumpida; sincroniza para confirmar su resultado.");
        if (operation.startsWith(QLatin1String("expense_")))
            markExpenseState(aggregate, child, operation == QLatin1String("expense_create") ? QString::fromLatin1(Error) : QString::fromLatin1(NeedsReconciliation), message);
        else if (operation == QLatin1String("present"))
            markPresentationState(aggregate, QString::fromLatin1(NeedsReconciliation), message);
        else if (operation.startsWith(QLatin1String("rendition_")))
            markRenditionState(aggregate, operation == QLatin1String("rendition_create") ? QString::fromLatin1(Error) : QString::fromLatin1(NeedsReconciliation), message);
    }
    emit renditionsChanged();
    emit outboxChanged();
    emit pendingCountChanged();
}

QString RenditionLocalStore::createDraft(const QString &periodStart,
                                         const QString &periodEnd,
                                         const QVariantList &projectIds,
                                         const QString &primaryProjectId,
                                         const QString &documentParentNodeId,
                                         const QString &spaceId,
                                         bool stageForSync)
{
    if (m_accountScope.isEmpty()) {
        setLastError(QStringLiteral("Selecciona una cuenta antes de guardar."));
        return {};
    }
    const auto invalid = RenditionValidation::header(periodStart, periodEnd, projectIds, primaryProjectId, documentParentNodeId, spaceId);
    if (!invalid.isEmpty()) { setLastError(invalid); return {}; }
    const QString localId = newUuid();
    const QString requestId = newUuid();
    const QString timestamp = nowUtc();
    QVariantMap draft{
        {QStringLiteral("localId"), localId},
        {QStringLiteral("remoteId"), QString()},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("visibleCode"), QString()},
        {QStringLiteral("rowVersion"), 0},
        {QStringLiteral("periodStart"), periodStart},
        {QStringLiteral("periodEnd"), periodEnd},
        {QStringLiteral("projectIds"), projectIds},
        {QStringLiteral("primaryProjectId"), primaryProjectId},
        {QStringLiteral("documentParentNodeId"), documentParentNodeId},
        {QStringLiteral("documentNodeId"), QString()},
        {QStringLiteral("documentNodeVersion"), 0},
        {QStringLiteral("spaceId"), spaceId},
        {QStringLiteral("status"), QStringLiteral("BORRADOR")},
        {QStringLiteral("syncState"), QString::fromLatin1(
             stageForSync ? PendingCreate : LocalOnly)},
        {QStringLiteral("createdAt"), timestamp},
        {QStringLiteral("updatedAt"), timestamp},
        {QStringLiteral("expenses"), QVariantList{}}
    };
    draft.insert(QStringLiteral("payload"), canonicalDraftPayload(draft));
    m_renditions.prepend(draft);
    if (stageForSync) {
        upsertOutbox(QStringLiteral("rendition_create"), localId, {}, {}, requestId,
                     canonicalDraftPayload(draft), QString::fromLatin1(PendingCreate));
    }
    return persist() ? localId : QString{};
}

bool RenditionLocalStore::saveDraft(const QString &localId,
                                    const QString &periodStart,
                                    const QString &periodEnd,
                                    const QVariantList &projectIds,
                                    const QString &primaryProjectId,
                                    qint64 rowVersion,
                                    const QString &documentParentNodeId,
                                    const QString &documentNodeId,
                                    qint64 documentNodeVersion,
                                    const QString &spaceId,
                                    bool stageForSync)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return false;
    const QString currentState = stateOf(draft);
    if (currentState == QLatin1String(Syncing)
        || currentState == QLatin1String(Conflict)
        || currentState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar la cabecera antes de volver a editar."));
        return false;
    }
    const QString previousPrimary = draft.value(QStringLiteral("primaryProjectId")).toString();
    const auto invalid = RenditionValidation::header(periodStart, periodEnd, projectIds, primaryProjectId, documentParentNodeId, spaceId);
    if (!invalid.isEmpty()) { setLastError(invalid); return false; }
    for (const auto &value : draft.value(QStringLiteral("expenses")).toList()) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("archived")).toBool()) continue;
        const auto day = row.value(QStringLiteral("expenseDate")).toString();
        if (day < periodStart || day > periodEnd || !projectIds.contains(row.value(QStringLiteral("projectId")))) {
            setLastError(QStringLiteral("El cambio dejaría gastos fuera del período o de los proyectos asociados."));
            return false;
        }
    }
    draft.insert(QStringLiteral("periodStart"), periodStart);
    draft.insert(QStringLiteral("periodEnd"), periodEnd);
    draft.insert(QStringLiteral("projectIds"), projectIds);
    draft.insert(QStringLiteral("primaryProjectId"), primaryProjectId);
    draft.insert(QStringLiteral("rowVersion"), rowVersion);
    if (previousPrimary != primaryProjectId) {
        draft.insert(QStringLiteral("documentParentNodeId"), QString());
        draft.insert(QStringLiteral("documentNodeId"), QString());
        draft.insert(QStringLiteral("documentNodeVersion"), 0);
        draft.insert(QStringLiteral("spaceId"), QString());
    }
    if (!documentParentNodeId.isEmpty())
        draft.insert(QStringLiteral("documentParentNodeId"), documentParentNodeId);
    if (!documentNodeId.isEmpty())
        draft.insert(QStringLiteral("documentNodeId"), documentNodeId);
    if (documentNodeVersion > 0)
        draft.insert(QStringLiteral("documentNodeVersion"), documentNodeVersion);
    if (!spaceId.isEmpty())
        draft.insert(QStringLiteral("spaceId"), spaceId);
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    const bool localOnly = draft.value(QStringLiteral("remoteId")).toString().isEmpty();
    if (!stageForSync) {
        const QString operation = localOnly
            ? QStringLiteral("rendition_create")
            : QStringLiteral("rendition_update");
        const int pendingOutbox = outboxIndex(operation, localId);
        if (pendingOutbox >= 0
            && m_outbox.at(pendingOutbox).toMap().value(
                   QStringLiteral("state")).toString()
                   != QLatin1String(Synced)) {
            setLastError(QStringLiteral(
                "Espera a que termine la sincronización antes de seguir editando."));
            return false;
        }
    }
    draft.insert(QStringLiteral("syncState"), stageForSync
                     ? (localOnly ? QString::fromLatin1(PendingCreate)
                                  : QString::fromLatin1(PendingUpdate))
                     : QString::fromLatin1(LocalOnly));
    draft.remove(QStringLiteral("syncError"));
    const QVariantMap payload = canonicalDraftPayload(draft);
    if (stageForSync && localOnly) {
        const int createOutbox = outboxIndex(QStringLiteral("rendition_create"),
                                             localId);
        if (createOutbox >= 0) {
            const QVariantMap entry = m_outbox.at(createOutbox).toMap();
            const QByteArray previousHash = entry.value(
                QStringLiteral("payloadHash")).toString().toLatin1();
            if (entry.value(QStringLiteral("attempts")).toInt() > 0
                && previousHash != payloadHash(payload)) {
                setLastError(QStringLiteral(
                    "La creación ya fue enviada. Reintenta el mismo payload antes de editarlo."));
                return false;
            }
        }
    }
    draft.insert(QStringLiteral("payload"), payload);
    m_renditions[index] = draft;
    if (stageForSync) {
        upsertOutbox(localOnly ? QStringLiteral("rendition_create")
                               : QStringLiteral("rendition_update"),
                     localId, draft.value(QStringLiteral("remoteId")).toString(), {},
                     localOnly ? draft.value(QStringLiteral("requestId")).toString() : QString{},
                     payload, localOnly ? QString::fromLatin1(PendingCreate)
                                        : QString::fromLatin1(PendingUpdate));
    }
    return persist();
}

QString RenditionLocalStore::addLocalExpense(const QString &renditionLocalId,
                                             const QVariantMap &expense,
                                             bool stageForSync)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return {};
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return {};
    const QString intent = expense.value(QStringLiteral("clientIntentId")).toString();
    if (!intent.isEmpty()) {
        for (const auto &entry : draft.value(QStringLiteral("expenses")).toList()) {
            const auto existing = entry.toMap();
            if (existing.value(QStringLiteral("clientIntentId")).toString() == intent)
                return existing.value(QStringLiteral("localId")).toString();
        }
    }
    const QString draftState = stateOf(draft);
    if (draftState == QLatin1String(Conflict)
        || draftState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar la cabecera antes de añadir gastos."));
        return {};
    }
    const auto invalid = RenditionValidation::expense(draft, expense);
    if (!invalid.isEmpty()) { setLastError(invalid); return {}; }
    QVariantMap localExpense = expense;
    const QString localId = newUuid();
    const QString requestId = newUuid();
    localExpense.insert(QStringLiteral("localId"), localId);
    localExpense.insert(QStringLiteral("remoteId"), QString());
    localExpense.insert(QStringLiteral("requestId"), requestId);
    localExpense.insert(QStringLiteral("rowVersion"), 0);
    localExpense.insert(QStringLiteral("amount"), expense.value(QStringLiteral("amount")).toString());
    localExpense.insert(QStringLiteral("reviewStatus"), QStringLiteral("PENDIENTE"));
    localExpense.insert(QStringLiteral("syncState"), QString::fromLatin1(
        stageForSync ? PendingCreate : LocalOnly));
    localExpense.insert(QStringLiteral("createdAt"), nowUtc());
    localExpense.insert(QStringLiteral("updatedAt"), nowUtc());
    localExpense.insert(QStringLiteral("attachments"), QVariantList{});
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    expenses.append(localExpense);
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    m_renditions[index] = draft;
    QVariantMap payload = localExpense;
    payload.insert(QStringLiteral("renditionLocalId"), renditionLocalId);
    payload.insert(QStringLiteral("renditionRemoteId"),
                   draft.value(QStringLiteral("remoteId")));
    payload.insert(QStringLiteral("expectedRenditionRowVersion"),
                   draft.value(QStringLiteral("rowVersion")));
    if (stageForSync) {
        upsertOutbox(QStringLiteral("expense_create"), renditionLocalId,
                     draft.value(QStringLiteral("remoteId")).toString(), localId,
                     requestId, payload, QString::fromLatin1(PendingCreate));
    }
    return persist() ? localId : QString{};
}

bool RenditionLocalStore::saveLocalExpense(const QString &renditionLocalId,
                                           const QString &expenseLocalId,
                                           const QVariantMap &values,
                                           bool stageForSync)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return false;
    const QString draftState = stateOf(draft);
    if (draftState == QLatin1String(Conflict)
        || draftState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar la cabecera antes de editar gastos."));
        return false;
    }
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int childIndex = expenseIndex(expenses, expenseLocalId);
    if (childIndex < 0)
        return false;
    QVariantMap expense = expenses.at(childIndex).toMap();
    const QString currentState = stateOf(expense);
    if (currentState == QLatin1String(Syncing)
        || currentState == QLatin1String(Conflict)
        || currentState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar el gasto antes de volver a editar."));
        return false;
    }
    if (expense.value(QStringLiteral("archived")).toBool()) return false;
    // Editable fields only: identity, attachments and sync metadata are native-owned.
    for (const auto &key : {"projectId", "expenseDate", "categoryCode", "concept", "beneficiary",
                           "paymentMethodCode", "paymentMethodDetail", "supportTypeCode", "supportNumber",
                           "supportDetail", "currencyCode", "amount", "justification",
                           "ruc", "subtotal", "igv", "receiptEvidence"}) {
        const QString field = QLatin1String(key);
        if (values.contains(field)) expense.insert(field, values.value(field));
    }
    const auto invalid = RenditionValidation::expense(draft, expense);
    if (!invalid.isEmpty()) { setLastError(invalid); return false; }
    expense.insert(QStringLiteral("amount"), values.value(
                       QStringLiteral("amount"), expense.value(QStringLiteral("amount"))).toString());
    expense.insert(QStringLiteral("updatedAt"), nowUtc());
    const bool localOnly = expense.value(QStringLiteral("remoteId")).toString().isEmpty();
    const QString operation = localOnly ? QStringLiteral("expense_create")
                                        : QStringLiteral("expense_update");
    const int pendingOutbox = outboxIndex(operation, renditionLocalId,
                                          expenseLocalId);
    if (!stageForSync && pendingOutbox >= 0
        && m_outbox.at(pendingOutbox).toMap().value(
               QStringLiteral("state")).toString()
               != QLatin1String(Synced)) {
        setLastError(QStringLiteral(
            "Espera a que termine la sincronización antes de seguir editando."));
        return false;
    }
    expense.insert(QStringLiteral("syncState"), stageForSync
                       ? (localOnly ? QString::fromLatin1(PendingCreate)
                                    : QString::fromLatin1(PendingUpdate))
                       : QString::fromLatin1(LocalOnly));
    QVariantMap payload = expense;
    payload.insert(QStringLiteral("renditionLocalId"), renditionLocalId);
    payload.insert(QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId")));
    payload.insert(QStringLiteral("expenseRemoteId"),
                   expense.value(QStringLiteral("remoteId")));
    payload.insert(QStringLiteral("expectedRenditionRowVersion"), draft.value(QStringLiteral("rowVersion")));
    if (stageForSync && localOnly) {
        const int createOutbox = outboxIndex(QStringLiteral("expense_create"),
                                             renditionLocalId,
                                             expenseLocalId);
        if (createOutbox >= 0) {
            const QVariantMap entry = m_outbox.at(createOutbox).toMap();
            const QByteArray previousHash = entry.value(
                QStringLiteral("payloadHash")).toString().toLatin1();
            if (entry.value(QStringLiteral("attempts")).toInt() > 0
                && previousHash != payloadHash(payload)) {
                setLastError(QStringLiteral(
                    "La creación del gasto ya fue enviada. Reintenta el mismo payload antes de editarlo."));
                return false;
            }
        }
    }
    expenses[childIndex] = expense;
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    if (stageForSync) {
        upsertOutbox(localOnly ? QStringLiteral("expense_create")
                               : QStringLiteral("expense_update"),
                     renditionLocalId, draft.value(QStringLiteral("remoteId")).toString(),
                     expenseLocalId,
                     localOnly ? expense.value(QStringLiteral("requestId")).toString() : QString{},
                     payload, localOnly ? QString::fromLatin1(PendingCreate)
                                        : QString::fromLatin1(PendingUpdate));
    }
    return persist();
}

bool RenditionLocalStore::stageLocalOnlyChanges(bool requireDocumentLocation)
{
    bool changed = false;
    for (int renditionRow = 0; renditionRow < m_renditions.size(); ++renditionRow) {
        QVariantMap draft = m_renditions.at(renditionRow).toMap();
        if (draft.value(QStringLiteral("status")).toString()
            != QLatin1String("BORRADOR"))
            continue;

        const QString localId = draft.value(QStringLiteral("localId")).toString();
        const QString renditionRemoteId = draft.value(
            QStringLiteral("remoteId")).toString();
        const bool headerComplete = !draft.value(
                QStringLiteral("projectIds")).toList().isEmpty()
            && !draft.value(QStringLiteral("primaryProjectId")).toString().isEmpty()
            && (!requireDocumentLocation
                || !draft.value(QStringLiteral("documentParentNodeId"))
                        .toString().isEmpty());

        if (stateOf(draft) == QLatin1String(LocalOnly) && headerComplete) {
            const bool create = renditionRemoteId.isEmpty();
            const QString state = create ? QString::fromLatin1(PendingCreate)
                                         : QString::fromLatin1(PendingUpdate);
            draft.insert(QStringLiteral("syncState"), state);
            const QVariantMap payload = canonicalDraftPayload(draft);
            draft.insert(QStringLiteral("payload"), payload);
            upsertOutbox(create ? QStringLiteral("rendition_create")
                                : QStringLiteral("rendition_update"),
                         localId, renditionRemoteId, {},
                         create ? draft.value(QStringLiteral("requestId")).toString()
                                : QString{},
                         payload, state);
            changed = true;
        }

        QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
        for (int expenseRow = 0; expenseRow < expenses.size(); ++expenseRow) {
            QVariantMap expense = expenses.at(expenseRow).toMap();
            if (stateOf(expense) != QLatin1String(LocalOnly)
                || expense.value(QStringLiteral("archived")).toBool())
                continue;
            const bool complete = headerComplete
                && !expense.value(QStringLiteral("projectId")).toString().isEmpty()
                && !expense.value(QStringLiteral("expenseDate")).toString().isEmpty()
                && !expense.value(QStringLiteral("categoryCode")).toString().isEmpty()
                && !expense.value(QStringLiteral("concept")).toString().trimmed().isEmpty()
                && !expense.value(QStringLiteral("paymentMethodCode")).toString().isEmpty()
                && !expense.value(QStringLiteral("supportTypeCode")).toString().isEmpty()
                && expense.value(QStringLiteral("amount")).toDouble() > 0.0;
            if (!complete)
                continue;

            const bool create = expense.value(
                QStringLiteral("remoteId")).toString().isEmpty();
            const QString state = create ? QString::fromLatin1(PendingCreate)
                                         : QString::fromLatin1(PendingUpdate);
            expense.insert(QStringLiteral("syncState"), state);
            QVariantMap payload = expense;
            payload.insert(QStringLiteral("renditionLocalId"), localId);
            payload.insert(QStringLiteral("renditionRemoteId"), renditionRemoteId);
            payload.insert(QStringLiteral("expenseRemoteId"),
                           expense.value(QStringLiteral("remoteId")));
            payload.insert(QStringLiteral("expectedRenditionRowVersion"),
                           draft.value(QStringLiteral("rowVersion")));
            upsertOutbox(create ? QStringLiteral("expense_create")
                                : QStringLiteral("expense_update"),
                         localId, renditionRemoteId,
                         expense.value(QStringLiteral("localId")).toString(),
                         create ? expense.value(QStringLiteral("requestId")).toString()
                                : QString{},
                         payload, state);
            expenses[expenseRow] = expense;
            changed = true;
        }
        draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
        m_renditions[renditionRow] = draft;
    }
    return !changed || persist();
}

bool RenditionLocalStore::removeLocalExpense(const QString &renditionLocalId,
                                             const QString &expenseLocalId)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return false;
    const QString draftState = stateOf(draft);
    if (draftState == QLatin1String(Conflict)
        || draftState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar la cabecera antes de eliminar gastos."));
        return false;
    }
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int childIndex = expenseIndex(expenses, expenseLocalId);
    if (childIndex < 0)
        return false;
    QVariantMap expense = expenses.at(childIndex).toMap();
    const QString currentState = stateOf(expense);
    if (currentState == QLatin1String(Syncing)
        || currentState == QLatin1String(Conflict)
        || currentState == QLatin1String(NeedsReconciliation)) {
        setLastError(QStringLiteral("Reconciliar el gasto antes de eliminarlo."));
        return false;
    }
    if (expense.value(QStringLiteral("archived")).toBool()) return true;
    // A lost CREATE response may already have committed remotely. Reconcile first.
    const int createAt = outboxIndex(QStringLiteral("expense_create"), renditionLocalId, expenseLocalId);
    if (expense.value(QStringLiteral("remoteId")).toString().isEmpty() && createAt >= 0
        && m_outbox[createAt].toMap().value(QStringLiteral("attempts")).toInt() > 0) {
        setLastError(QStringLiteral("Sincroniza el gasto pendiente antes de eliminarlo.")); return false;
    }
    const auto oldRows = m_renditions, oldOutbox = m_outbox;
    const auto oldDrafts = m_editorDrafts;
    for (int i = m_outbox.size() - 1; i >= 0; --i) {
        const auto op = m_outbox[i].toMap();
        if (op.value(QStringLiteral("aggregateLocalId")).toString() == renditionLocalId
            && (op.value(QStringLiteral("childLocalId")).toString() == expenseLocalId
                || op.value(QStringLiteral("payload")).toMap().value(QStringLiteral("expenseLocalId")).toString() == expenseLocalId)) {
            if (op.value(QStringLiteral("state")).toString() == QLatin1String(Syncing)) {
                m_outbox = oldOutbox;
                setLastError(QStringLiteral("Espera a que termine la sincronización del sustento.")); return false;
            }
            m_outbox.removeAt(i);
        }
    }
    for (const auto &key : m_editorDrafts.keys()) {
        const auto saved = m_editorDrafts.value(key).toMap().value(QStringLiteral("savedId")).toString();
        if (key == QStringLiteral("expense:") + renditionLocalId + ':' + expenseLocalId || saved == expenseLocalId) m_editorDrafts.remove(key);
    }
    if (expense.value(QStringLiteral("remoteId")).toString().isEmpty()) {
        expenses.removeAt(childIndex);
        const int outbox = outboxIndex(QStringLiteral("expense_create"),
                                       renditionLocalId, expenseLocalId);
        if (outbox >= 0)
            m_outbox.removeAt(outbox);
    } else {
        expense.insert(QStringLiteral("archived"), true);
        expense.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
        expenses[childIndex] = expense;
        QVariantMap payload{
            {QStringLiteral("renditionLocalId"), renditionLocalId},
            {QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId"))},
            {QStringLiteral("expenseRemoteId"), expense.value(QStringLiteral("remoteId"))},
            {QStringLiteral("expectedExpenseRowVersion"), expense.value(QStringLiteral("rowVersion"))},
            {QStringLiteral("expectedRenditionRowVersion"), draft.value(QStringLiteral("rowVersion"))}
        };
        upsertOutbox(QStringLiteral("expense_delete"), renditionLocalId,
                     draft.value(QStringLiteral("remoteId")).toString(), expenseLocalId,
                     newUuid(), payload, QString::fromLatin1(PendingUpdate));
    }
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    if (persist()) return true;
    m_renditions = oldRows; m_outbox = oldOutbox; m_editorDrafts = oldDrafts;
    return false;
}

QString RenditionLocalStore::addLocalAttachment(
    const QString &renditionLocalId, const QString &expenseLocalId,
    const QVariantMap &attachment)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return {};
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return {};
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int childIndex = expenseIndex(expenses, expenseLocalId);
    if (childIndex < 0)
        return {};
    QVariantMap expense = expenses.at(childIndex).toMap();
    const qint64 sizeBytes = attachment.value(QStringLiteral("sizeBytes")).toLongLong();
    if (sizeBytes <= 0 || sizeBytes > 20LL * 1024LL * 1024LL
        || attachment.value(QStringLiteral("localUri")).toString().isEmpty()) {
        setLastError(QStringLiteral("El sustento local no es válido o supera 20 MiB."));
        return {};
    }
    QVariantList attachments = expense.value(QStringLiteral("attachments")).toList();
    QVariantMap local = attachment;
    if (expense.value(QStringLiteral("archived")).toBool()) {
        setLastError(QStringLiteral("Este gasto fue eliminado."));
        return {};
    }
    for (const auto &value : attachments) {
        const auto existing = value.toMap();
        const QString digest = attachment.value(QStringLiteral("sha256")).toString();
        if (existing.value(QStringLiteral("archived_at")).toString().isEmpty()
            && (existing.value(QStringLiteral("localUri")) == attachment.value(QStringLiteral("localUri"))
                || (!digest.isEmpty() && digest == existing.value(QStringLiteral("sha256")).toString())))
            return existing.value(QStringLiteral("localId")).toString();
    }
    const auto intent = attachment.value(QStringLiteral("clientIntentId")).toString();
    if (!intent.isEmpty()) {
        for (const auto &entry : attachments)
            if (entry.toMap().value(QStringLiteral("clientIntentId")).toString() == intent)
                return entry.toMap().value(QStringLiteral("localId")).toString();
    }
    const QString localId = newUuid();
    const QString requestId = newUuid();
    // Materialize external/content URIs before enqueuing. URI permissions and
    // picker cache files need not survive process death; this mirror does.
    const QUrl sourceUrl(attachment.value(QStringLiteral("localUri")).toString());
    QFile source(sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : attachment.value(QStringLiteral("localUri")).toString());
    if (!source.open(QIODevice::ReadOnly) || source.size() != sizeBytes) {
        setLastError(QStringLiteral("No se pudo conservar el sustento original."));
        return {};
    }
    const auto bytes = source.readAll();
    const auto sha256 = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    for (const auto &entry : attachments) {
        const auto existing = entry.toMap();
        if (existing.value(QStringLiteral("archived_at")).toString().isEmpty()
            && existing.value(QStringLiteral("sha256")).toString() == sha256)
            return existing.value(QStringLiteral("localId")).toString();
    }
    const QString mirrorDirectory = storagePath() + QStringLiteral(".attachments/") + localId;
    const QString name = QFileInfo(attachment.value(QStringLiteral("fileName")).toString()).fileName();
    if (name.isEmpty() || name == QLatin1String(".") || name == QLatin1String("..")
        || bytes.size() != sizeBytes || !QDir().mkpath(mirrorDirectory)) {
        setLastError(QStringLiteral("No se pudo crear el mirror del sustento.")); return {};
    }
    const QString mirrorPath = QDir(mirrorDirectory).filePath(name);
    QSaveFile mirror(mirrorPath);
    if (!mirror.open(QIODevice::WriteOnly) || mirror.write(bytes) != bytes.size() || !mirror.commit()) {
        setLastError(QStringLiteral("No se pudo guardar el sustento para uso offline.")); return {};
    }
    local.insert(QStringLiteral("localUri"), mirrorPath);
    local.insert(QStringLiteral("sha256"), sha256);
    local.insert(QStringLiteral("projectId"), expense.value(QStringLiteral("projectId")));
    local.insert(QStringLiteral("localId"), localId);
    local.insert(QStringLiteral("remoteId"), QString());
    local.insert(QStringLiteral("requestId"), requestId);
    local.insert(QStringLiteral("phase"), QStringLiteral("RESERVE"));
    local.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingCreate));
    local.insert(QStringLiteral("createdAt"), nowUtc());
    const auto previousRenditions = m_renditions;
    const auto previousOutbox = m_outbox;
    const auto previousSequence = m_nextSequence;
    attachments.append(local);
    expense.insert(QStringLiteral("attachments"), attachments);
    expenses[childIndex] = expense;
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    QVariantMap payload = local;
    payload.insert(QStringLiteral("renditionLocalId"), renditionLocalId);
    payload.insert(QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId")));
    payload.insert(QStringLiteral("expenseLocalId"), expenseLocalId);
    payload.insert(QStringLiteral("expenseRemoteId"), expense.value(QStringLiteral("remoteId")));
    upsertOutbox(QStringLiteral("attachment_reserve"), renditionLocalId,
                 draft.value(QStringLiteral("remoteId")).toString(), localId,
                 requestId, payload, QString::fromLatin1(PendingCreate));
    if (persist()) return localId;
    m_renditions = previousRenditions; m_outbox = previousOutbox; m_nextSequence = previousSequence;
    return {};
}

bool RenditionLocalStore::updateAttachmentPhase(
    const QString &renditionLocalId, const QString &expenseLocalId,
    const QString &attachmentLocalId, const QString &phase,
    const QVariantMap &remote)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int expenseAt = expenseIndex(expenses, expenseLocalId);
    if (expenseAt < 0)
        return false;
    QVariantMap expense = expenses.at(expenseAt).toMap();
    QVariantList attachments = expense.value(QStringLiteral("attachments")).toList();
    for (int i = 0; i < attachments.size(); ++i) {
        QVariantMap attachment = attachments.at(i).toMap();
        if (attachment.value(QStringLiteral("localId")).toString() != attachmentLocalId)
            continue;
        attachment.insert(QStringLiteral("phase"), phase);
        for (auto it = remote.cbegin(); it != remote.cend(); ++it)
            attachment.insert(it.key(), it.value());
        const QString attachmentRemoteId = remoteId(remote, QStringLiteral("attachment"));
        if (!attachmentRemoteId.isEmpty())
            attachment.insert(QStringLiteral("remoteId"), attachmentRemoteId);
        const QVariant bucket = valueFor(remote, QStringLiteral("bucket"),
                                         QStringLiteral("bucket_id"));
        if (bucket.isValid())
            attachment.insert(QStringLiteral("bucket"), bucket);
        const QString objectPath = RenditionAttachmentContract::objectPath(remote);
        if (!objectPath.isEmpty())
            attachment.insert(QStringLiteral("objectPath"), objectPath);
        const QString attachmentState = phase == QLatin1String("READY")
            ? QString::fromLatin1(Synced)
            : (phase == QLatin1String("NEEDS_RECONCILIATION")
                   ? QString::fromLatin1(NeedsReconciliation)
                   : (phase == QLatin1String("CONFLICT")
                          ? QString::fromLatin1(Conflict)
                          : (phase == QLatin1String("ERROR")
                                 ? QString::fromLatin1(Error)
                                 : QString::fromLatin1(PendingUpdate))));
        attachment.insert(QStringLiteral("syncState"), attachmentState);
        if (phase == QLatin1String("READY") || phase == QLatin1String("UPLOAD") || phase == QLatin1String("FINALIZE"))
            attachment.remove(QStringLiteral("syncError"));
        attachments[i] = attachment;
        expense.insert(QStringLiteral("attachments"), attachments);
        expenses[expenseAt] = expense;
        draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
        m_renditions[index] = draft;
        markOutboxState(QStringLiteral("attachment_reserve"), renditionLocalId,
                        attachmentLocalId,
                        attachmentState,
                        remote.value(QStringLiteral("syncError")).toString());
        const int outbox = outboxIndex(QStringLiteral("attachment_reserve"),
                                       renditionLocalId, attachmentLocalId);
        if (outbox >= 0) {
            QVariantMap entry = m_outbox.at(outbox).toMap();
            QVariantMap payload = entry.value(QStringLiteral("payload")).toMap();
            payload.insert(QStringLiteral("phase"), phase);
            payload.insert(QStringLiteral("attachmentRemoteId"),
                           attachment.value(QStringLiteral("remoteId")));
            payload.insert(QStringLiteral("bucket"),
                           attachment.value(QStringLiteral("bucket")));
            payload.insert(QStringLiteral("objectPath"),
                           attachment.value(QStringLiteral("objectPath")));
            entry.insert(QStringLiteral("payload"), payload);
            entry.insert(QStringLiteral("payloadHash"),
                         QString::fromLatin1(payloadHash(payload)));
            m_outbox[outbox] = entry;
        }
        return persist();
    }
    return false;
}

QVariantMap RenditionLocalStore::rendition(const QString &localId) const
{
    const int index = renditionIndex(localId);
    return index < 0 ? QVariantMap{} : m_renditions.at(index).toMap();
}

QVariantList RenditionLocalStore::expensesFor(const QString &localId) const
{
    QVariantList visible;
    const QVariantList expenses = rendition(localId).value(
        QStringLiteral("expenses")).toList();
    for (const QVariant &value : expenses) {
        if (!value.toMap().value(QStringLiteral("archived")).toBool())
            visible.append(value);
    }
    return visible;
}

QVariantList RenditionLocalStore::attachmentsFor(
    const QString &localId, const QString &expenseLocalId) const
{
    const QVariantList expenses = expensesFor(localId);
    const int index = expenseIndex(expenses, expenseLocalId);
    return index < 0 ? QVariantList{}
                     : expenses.at(index).toMap().value(QStringLiteral("attachments")).toList();
}

void RenditionLocalStore::reconcileCompleteRenditionList(const QVariantList &remoteRows)
{
    QSet<QString> visible;
    for (const auto &value : remoteRows) visible.insert(remoteId(value.toMap()));
    bool changed = false;
    for (int i = 0; i < m_renditions.size(); ++i) {
        auto draft = m_renditions[i].toMap();
        const auto id = draft.value("remoteId").toString();
        if (id.isEmpty() || visible.contains(id) || draft.value("archived").toBool()) continue;
        bool pending = stateOf(draft) != QLatin1String(Synced);
        for (const auto &op : m_outbox) {
            const auto row = op.toMap();
            pending |= row.value("aggregateLocalId") == draft.value("localId") &&
                       row.value("state") != QLatin1String(Synced) && row.value("state") != QLatin1String(LocalOnly);
        }
        if (pending) {
            draft.insert("syncState", QString::fromLatin1(Conflict));
            draft.insert("syncError", "La rendición ya no está disponible. Se conservaron tus cambios para revisión.");
        } else {
            // Absence from a moving keyset is not proof of deletion. Keep an
            // explicit reconciliation marker until the server confirms it.
            draft.insert("remoteMissing", true);
        }
        m_renditions[i] = draft; changed = true;
    }
    if (changed) persist();
}

void RenditionLocalStore::mergeRemoteRenditions(const QVariantList &remoteRows)
{
    bool changed = false;
    for (const QVariant &value : remoteRows) {
        QVariantMap remote = value.toMap();
        const QString id = remoteId(remote);
        if (id.isEmpty())
            continue;
        int index = renditionIndexByRemoteId(id);
        if (index >= 0 && m_renditions[index].toMap().value(QStringLiteral("archived")).toBool()) continue;
        remote = RenditionContract::normalize(remote, index < 0 ? QVariantMap{} : m_renditions.at(index).toMap());
        if (index < 0) {
            QVariantMap draft{
                {QStringLiteral("localId"), newUuid()},
                {QStringLiteral("remoteId"), id},
                {QStringLiteral("requestId"), QString()},
                {QStringLiteral("visibleCode"), valueFor(remote, QStringLiteral("visibleCode"), QStringLiteral("visible_code"))},
                {QStringLiteral("rowVersion"), valueFor(remote, QStringLiteral("rowVersion"), QStringLiteral("row_version"))},
                {QStringLiteral("periodStart"), valueFor(remote, QStringLiteral("periodStart"), QStringLiteral("period_start"))},
                {QStringLiteral("periodEnd"), valueFor(remote, QStringLiteral("periodEnd"), QStringLiteral("period_end"))},
                {QStringLiteral("projectIds"), valueFor(remote, QStringLiteral("projectIds"), QStringLiteral("project_ids"))},
                {QStringLiteral("primaryProjectId"), valueFor(remote, QStringLiteral("primaryProjectId"), QStringLiteral("primary_project_id"))},
                {QStringLiteral("primaryProjectName"), valueFor(remote, QStringLiteral("primaryProjectName"), QStringLiteral("primary_project_name"))},
                {QStringLiteral("baseCurrency"), valueFor(remote, QStringLiteral("baseCurrency"), QStringLiteral("base_currency"))},
                {QStringLiteral("reference"), referenceFor(remote)},
                {QStringLiteral("createdAt"), valueFor(remote, QStringLiteral("createdAt"), QStringLiteral("created_at"))},
                {QStringLiteral("currentVersionId"), valueFor(remote, QStringLiteral("currentVersionId"), QStringLiteral("current_version_id"))},
                {QStringLiteral("versionNumber"), valueFor(remote, QStringLiteral("currentVersionNumber"), QStringLiteral("current_version_number"))},
                {QStringLiteral("totalPen"), valueFor(remote, QStringLiteral("totalPen"), QStringLiteral("total_pen"))},
                {QStringLiteral("totalUsd"), valueFor(remote, QStringLiteral("totalUsd"), QStringLiteral("total_usd"))},
                {QStringLiteral("expenseCount"), valueFor(remote, QStringLiteral("expenseCount"), QStringLiteral("expense_count"))},
                {QStringLiteral("status"), remote.value(QStringLiteral("status"), QStringLiteral("BORRADOR"))},
                {QStringLiteral("syncState"), QString::fromLatin1(Synced)},
                {QStringLiteral("updatedAt"), valueFor(remote, QStringLiteral("updatedAt"), QStringLiteral("updated_at"))},
                {QStringLiteral("expenses"), QVariantList{}}
            };
            m_renditions.append(draft);
            changed = true;
            continue;
        }
        QVariantMap draft = m_renditions.at(index).toMap();
        const QString localState = stateOf(draft);
        if (draft.value(QStringLiteral("status")).toString() == QLatin1String("PRESENTADA")
            && !draft.value(QStringLiteral("currentVersionId")).toString().isEmpty())
            continue;
        const qint64 localVersion = draft.value(
            QStringLiteral("rowVersion")).toLongLong();
        const qint64 observedVersion = valueFor(
            remote, QStringLiteral("rowVersion"),
            QStringLiteral("row_version")).toLongLong();
        const QString remoteStatus = remote.value(
            QStringLiteral("status"), draft.value(QStringLiteral("status"))).toString();
        // A delayed response must never roll back a newer local server version.
        if (localVersion > 0 && observedVersion < localVersion)
            continue;
        if (localState == QLatin1String(NeedsReconciliation)
            && remoteStatus == QLatin1String("BORRADOR") && observedVersion == localVersion) {
            // The failed CAS did not commit. Replay the original intention;
            // never advance its expected version to conceal a remote edit.
            draft.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
            draft.remove(QStringLiteral("syncError"));
            markOutboxState(QStringLiteral("rendition_update"),
                            draft.value(QStringLiteral("localId")).toString(), {},
                            QString::fromLatin1(PendingUpdate));
        }
        draft.insert(QStringLiteral("visibleCode"), valueFor(remote, QStringLiteral("visibleCode"), QStringLiteral("visible_code")));
        draft.insert(QStringLiteral("status"), remoteStatus);
        draft.insert(QStringLiteral("baseCurrency"), valueFor(remote, QStringLiteral("baseCurrency"), QStringLiteral("base_currency")));
        draft.insert(QStringLiteral("reference"), referenceFor(remote));
        draft.insert(QStringLiteral("createdAt"), valueFor(remote, QStringLiteral("createdAt"), QStringLiteral("created_at")));
        draft.insert(QStringLiteral("currentVersionId"), valueFor(remote, QStringLiteral("currentVersionId"), QStringLiteral("current_version_id")));
        draft.insert(QStringLiteral("versionNumber"), valueFor(remote, QStringLiteral("currentVersionNumber"), QStringLiteral("current_version_number")));
        // Once expenses are loaded, their persisted rows own local totals.
        // A concurrent header response must not erase pending local expenses.
        if (draft.value(QStringLiteral("expensesLoaded")).toBool()
            || !draft.value(QStringLiteral("expenses")).toList().isEmpty()) {
            RenditionValidation::totals(draft);
        } else {
            draft.insert(QStringLiteral("totalPen"), remote.value(QStringLiteral("totalPen")));
            draft.insert(QStringLiteral("totalUsd"), remote.value(QStringLiteral("totalUsd")));
            draft.insert(QStringLiteral("expenseCount"), remote.value(QStringLiteral("expenseCount")));
        }
        bool presentationResolved = false;
        const int presentOutbox = outboxIndex(QStringLiteral("present"),
                                              draft.value(QStringLiteral("localId")).toString());
        if (presentOutbox >= 0) {
            const QVariantMap presentation = m_outbox.at(presentOutbox).toMap();
            const QString presentationState = presentation.value(
                QStringLiteral("state")).toString();
            const qint64 expectedVersion = presentation.value(
                QStringLiteral("payload")).toMap().value(
                    QStringLiteral("expectedRowVersion")).toLongLong();
            const qint64 observedVersion = valueFor(
                remote, QStringLiteral("rowVersion"),
                QStringLiteral("row_version")).toLongLong();
            if (remoteStatus == QLatin1String("PRESENTADA")) {
                presentationResolved = true;
                draft.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
                draft.insert(QStringLiteral("versionId"), valueFor(
                    remote, QStringLiteral("currentVersionId"),
                    QStringLiteral("current_version_id")));
                markOutboxState(QStringLiteral("present"),
                                draft.value(QStringLiteral("localId")).toString(), {},
                                QString::fromLatin1(Synced));
            } else if ((presentationState == QLatin1String(NeedsReconciliation)
                        || presentationState == QLatin1String(Error))
                       && remoteStatus == QLatin1String("BORRADOR")
                       && observedVersion == expectedVersion) {
                draft.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
                draft.remove(QStringLiteral("syncError"));
                markOutboxState(QStringLiteral("present"),
                                draft.value(QStringLiteral("localId")).toString(), {},
                                QString::fromLatin1(LocalOnly));
            }
        }
        if (localState == QLatin1String(Synced) || presentationResolved) {
            draft.insert(QStringLiteral("rowVersion"), observedVersion);
            draft.insert(QStringLiteral("periodStart"), valueFor(remote, QStringLiteral("periodStart"), QStringLiteral("period_start")));
            draft.insert(QStringLiteral("periodEnd"), valueFor(remote, QStringLiteral("periodEnd"), QStringLiteral("period_end")));
            draft.insert(QStringLiteral("projectIds"), valueFor(remote, QStringLiteral("projectIds"), QStringLiteral("project_ids")));
            draft.insert(QStringLiteral("primaryProjectId"), valueFor(remote, QStringLiteral("primaryProjectId"), QStringLiteral("primary_project_id")));
            draft.insert(QStringLiteral("primaryProjectName"), valueFor(remote, QStringLiteral("primaryProjectName"), QStringLiteral("primary_project_name")));
            draft.insert(QStringLiteral("updatedAt"), valueFor(remote, QStringLiteral("updatedAt"), QStringLiteral("updated_at")));
            draft.remove(QStringLiteral("serverSnapshot"));
            draft.remove(QStringLiteral("serverRowVersion"));
        } else {
            // El servidor se conserva como sombra, pero los campos editables
            // locales no se pisan mientras exista outbox pendiente.
            draft.insert(QStringLiteral("serverSnapshot"), remote);
            draft.insert(QStringLiteral("serverRowVersion"), observedVersion);
            if ((localVersion > 0 && observedVersion > 0
                 && localVersion != observedVersion)
                || remoteStatus != QLatin1String("BORRADOR")) {
                const QString message = remoteStatus != QLatin1String("BORRADOR")
                    ? QStringLiteral(
                          "La rendición cambió de estado en Web mientras había cambios locales.")
                    : QStringLiteral(
                          "La cabecera cambió en Web mientras había cambios locales pendientes.");
                draft.insert(QStringLiteral("syncState"),
                             QString::fromLatin1(Conflict));
                draft.insert(QStringLiteral("syncError"), message);
                markOutboxState(QStringLiteral("rendition_update"),
                                draft.value(QStringLiteral("localId")).toString(), {},
                                QString::fromLatin1(Conflict), message);
            }
        }
        m_renditions[index] = draft;
        changed = true;
    }
    if (changed)
        persist();
}

void RenditionLocalStore::mergeRemoteExpenses(
    const QString &renditionLocalId, const QVariantList &remoteRows)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return;
    QVariantMap draft = m_renditions.at(index).toMap();
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    QSet<QString> remoteIds;
    if (draft.value(QStringLiteral("archived")).toBool()
        || (draft.value(QStringLiteral("status")).toString() == QLatin1String("PRESENTADA")
            && draft.value(QStringLiteral("expensesLoaded")).toBool())) return;
    for (const QVariant &value : remoteRows) {
        const QVariantMap remote = value.toMap();
        const QString id = remoteId(remote, QStringLiteral("expense"));
        if (id.isEmpty())
            continue;
        remoteIds.insert(id);
        int found = -1;
        for (int i = 0; i < expenses.size(); ++i) {
            if (expenses.at(i).toMap().value(QStringLiteral("remoteId")).toString() == id) {
                found = i;
                break;
            }
        }
        QVariantMap expense = found >= 0 ? expenses.at(found).toMap() : QVariantMap{};
        if (expense.value(QStringLiteral("archived")).toBool()) continue;
        const QString localState = stateOf(expense);
        const qint64 localVersion = expense.value(
            QStringLiteral("rowVersion")).toLongLong();
        const qint64 observedVersion = valueFor(
            remote, QStringLiteral("rowVersion"),
            QStringLiteral("row_version")).toLongLong();
        if (found < 0) {
            expense.insert(QStringLiteral("localId"), newUuid());
            expense.insert(QStringLiteral("remoteId"), id);
            expense.insert(QStringLiteral("attachments"), QVariantList{});
        }
        if (found >= 0 && localVersion > 0 && observedVersion < localVersion)
            continue;
        const QList<QPair<QString, QString>> keys{
            {QStringLiteral("projectId"), QStringLiteral("project_id")},
            {QStringLiteral("expenseDate"), QStringLiteral("expense_date")},
            {QStringLiteral("categoryCode"), QStringLiteral("category_code")},
            {QStringLiteral("categoryName"), QStringLiteral("category_name")},
            {QStringLiteral("concept"), QStringLiteral("concept")},
            {QStringLiteral("beneficiary"), QStringLiteral("beneficiary")},
            {QStringLiteral("paymentMethodCode"), QStringLiteral("payment_method_code")},
            {QStringLiteral("paymentMethodName"), QStringLiteral("payment_method_name")},
            {QStringLiteral("paymentMethodDetail"), QStringLiteral("payment_method_detail")},
            {QStringLiteral("supportTypeCode"), QStringLiteral("support_type_code")},
            {QStringLiteral("supportTypeName"), QStringLiteral("support_type_name")},
            {QStringLiteral("supportNumber"), QStringLiteral("support_number")},
            {QStringLiteral("supportDetail"), QStringLiteral("support_detail")},
            {QStringLiteral("currencyCode"), QStringLiteral("currency_code")},
            {QStringLiteral("amount"), QStringLiteral("amount")},
            {QStringLiteral("justification"), QStringLiteral("justification")},
            {QStringLiteral("reviewStatus"), QStringLiteral("review_status")},
            {QStringLiteral("rowVersion"), QStringLiteral("row_version")},
            {QStringLiteral("updatedAt"), QStringLiteral("updated_at")}
        };
        bool applied = found >= 0 && observedVersion > localVersion &&
            (localState == QLatin1String(NeedsReconciliation) || localState == QLatin1String(Conflict));
        for (const auto &key : keys) {
            if (key.first.endsWith("Name") || key.first == "rowVersion" ||
                key.first == "updatedAt" || key.first == "reviewStatus") continue;
            const auto observed = valueFor(remote, key.first, key.second);
            if (key.first == "amount") applied &= observed.isValid() && observed.toDouble() == expense.value(key.first).toDouble();
            else applied &= observed.toString() == expense.value(key.first).toString();
        }
        if (applied) {
            markOutboxState("expense_update", renditionLocalId,
                            expense.value("localId").toString(), QString::fromLatin1(Synced));
        }
        const bool serverOwnsValues = found < 0 || applied
            || localState == QLatin1String(Synced);
        if (serverOwnsValues) {
            for (const auto &key : keys)
                expense.insert(key.first, valueFor(remote, key.first, key.second));
            expense.insert(QStringLiteral("amount"),
                           valueFor(remote, QStringLiteral("amount"),
                                    QStringLiteral("amount")).toString());
            expense.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
            expense.remove(QStringLiteral("syncError"));
            expense.remove(QStringLiteral("serverSnapshot"));
            expense.remove(QStringLiteral("serverRowVersion"));
        } else {
            // El PULL nunca pisa una edición local pendiente. Conserva una
            // sombra remota para que el conflicto CAS pueda reconciliarse.
            expense.insert(QStringLiteral("serverSnapshot"), remote);
            expense.insert(QStringLiteral("serverRowVersion"), observedVersion);
            if (localState == QLatin1String(NeedsReconciliation)
                && localVersion > 0 && observedVersion == localVersion) {
                expense.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
                expense.remove(QStringLiteral("syncError"));
                markOutboxState(QStringLiteral("expense_update"), renditionLocalId,
                                expense.value(QStringLiteral("localId")).toString(),
                                QString::fromLatin1(PendingUpdate));
            }
            if (localVersion > 0 && observedVersion > 0
                && observedVersion != localVersion) {
                const QString message = QStringLiteral(
                    "Este gasto cambió en Web mientras había cambios locales pendientes.");
                expense.insert(QStringLiteral("syncState"),
                               QString::fromLatin1(Conflict));
                expense.insert(QStringLiteral("syncError"), message);
                for (const QString &operation : {
                         QStringLiteral("expense_create"),
                         QStringLiteral("expense_update"),
                         QStringLiteral("expense_delete")}) {
                    markOutboxState(operation, renditionLocalId,
                                    expense.value(QStringLiteral("localId")).toString(),
                                    QString::fromLatin1(Conflict), message);
                }
            }
        }
        if (found >= 0)
            expenses[found] = expense;
        else
            expenses.append(expense);
    }

    // La lista remota es autoritativa para filas ya sincronizadas. Una fila
    // que desapareció en Web se retira localmente sólo si no guarda trabajo
    // pendiente; de lo contrario queda en conflicto y conserva sus datos.
    for (int i = expenses.size() - 1; i >= 0; --i) {
        QVariantMap expense = expenses.at(i).toMap();
        const QString id = expense.value(QStringLiteral("remoteId")).toString();
        if (id.isEmpty() || remoteIds.contains(id)
            || expense.value(QStringLiteral("archived")).toBool()) {
            continue;
        }
        if (stateOf(expense) == QLatin1String(Synced)) {
            bool pendingAttachment = false;
            for (const auto &attachment : expense.value(QStringLiteral("attachments")).toList())
                pendingAttachment |= stateOf(attachment.toMap()) != QLatin1String(Synced);
            if (!pendingAttachment) {
                expense.insert(QStringLiteral("archived"), true);
                expenses[i] = expense;
                continue;
            }
        }
        const QString message = QStringLiteral(
            "El gasto ya no existe en Web y requiere reconciliación.");
        expense.insert(QStringLiteral("syncState"), QString::fromLatin1(Conflict));
        expense.insert(QStringLiteral("syncError"), message);
        expenses[i] = expense;
        for (const QString &operation : {QStringLiteral("expense_create"),
                                         QStringLiteral("expense_update"),
                                         QStringLiteral("expense_delete")}) {
            markOutboxState(operation, renditionLocalId,
                            expense.value(QStringLiteral("localId")).toString(),
                            QString::fromLatin1(Conflict), message);
        }
    }
    draft.insert(QStringLiteral("expenses"), expenses);
    draft.insert(QStringLiteral("expensesLoaded"), true);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    persist();
    if (draft.value(QStringLiteral("attachmentsLoaded")).toBool())
        mergeRemoteAttachments(renditionLocalId, draft.value(QStringLiteral("remoteAttachments")).toList());
}

void RenditionLocalStore::mergeRemoteAttachments(const QString &localId, const QVariantList &rows)
{
    const int index = renditionIndex(localId);
    if (index < 0) return;
    auto draft = m_renditions.at(index).toMap();
    auto expenses = draft.value(QStringLiteral("expenses")).toList();
    if (draft.value(QStringLiteral("archived")).toBool()
        || (draft.value(QStringLiteral("status")).toString() == QLatin1String("PRESENTADA")
            && draft.value(QStringLiteral("attachmentsLoaded")).toBool()
            && draft.value(QStringLiteral("expensesLoaded")).toBool())) return;
    for (int e = 0; e < expenses.size(); ++e) {
        auto expense = expenses[e].toMap();
        if (expense.value("archived").toBool()) continue;
        auto attachments = expense.value(QStringLiteral("attachments")).toList();
        for (const auto &value : rows) {
            const auto remote = value.toMap();
            if (remote.value(QStringLiteral("expense_id")) != expense.value(QStringLiteral("remoteId"))) continue;
            const QString id = remoteId(remote, QStringLiteral("attachment"));
            if (id.isEmpty()) continue;
            int found = -1;
            for (int a = 0; a < attachments.size(); ++a)
                if (attachments[a].toMap().value(QStringLiteral("remoteId")).toString() == id) { found = a; break; }
            auto attachment = found < 0 ? QVariantMap{{QStringLiteral("localId"), newUuid()}} : attachments[found].toMap();
            for (auto it = remote.cbegin(); it != remote.cend(); ++it) attachment.insert(it.key(), it.value());
            attachment.insert(QStringLiteral("remoteId"), id);
            attachment.insert(QStringLiteral("expenseLocalId"), expense.value(QStringLiteral("localId")));
            attachment.insert(QStringLiteral("phase"), QStringLiteral("READY")); // RPC returns READY rows only.
            attachment.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
            attachment.remove(QStringLiteral("syncError"));
            markOutboxState(QStringLiteral("attachment_reserve"), localId,
                            attachment.value(QStringLiteral("localId")).toString(), QString::fromLatin1(Synced));
            if (found < 0) attachments.append(attachment); else attachments[found] = attachment;
        }
        expense.insert(QStringLiteral("attachments"), attachments);
        expenses[e] = expense;
    }
    draft.insert(QStringLiteral("expenses"), expenses);
    draft.insert(QStringLiteral("attachmentsLoaded"), true);
    draft.insert(QStringLiteral("remoteAttachments"), rows);
    m_renditions[index] = draft;
    persist();
}

void RenditionLocalStore::adoptRemoteSummary(const QString &localId, const QVariantMap &summary)
{
    const int index = renditionIndex(localId);
    if (index < 0) return;
    auto draft = m_renditions.at(index).toMap();
    draft.insert(QStringLiteral("remoteSummary"), summary);
    m_renditions[index] = draft;
    persist();
}

QVariantMap RenditionLocalStore::syncStatus(const QString &localId, bool active) const
{
    const auto draft = rendition(localId);
    int pending = 0;
    QString state = QString::fromLatin1(Synced);
    QString error;
    auto inspect = [&](const QVariantMap &row, const QString &key) {
        const QString status = row.value(key).toString();
        if (status == QLatin1String(Conflict)) state = QString::fromLatin1(Conflict);
        else if (status == QLatin1String(NeedsReconciliation) && state != QLatin1String(Conflict)) state = QString::fromLatin1(NeedsReconciliation);
        else if (status == QLatin1String(Error) && state == QLatin1String(Synced)) state = QString::fromLatin1(Error);
        if (error.isEmpty()) error = row.value(QStringLiteral("syncError")).toString();
    };
    inspect(draft, QStringLiteral("syncState"));
    QSet<QString> counted;
    for (const auto &value : m_outbox) {
        const auto entry = value.toMap();
        if (entry.value(QStringLiteral("aggregateLocalId")).toString() != localId
            || entry.value(QStringLiteral("state")).toString() == QLatin1String(Synced)) continue;
        if (entry.value(QStringLiteral("operation")).toString() == QLatin1String("present")
            && entry.value(QStringLiteral("state")).toString() == QLatin1String(LocalOnly)) continue;
        ++pending;
        counted.insert(entry.value(QStringLiteral("childLocalId")).toString());
        inspect(entry, QStringLiteral("state"));
        if (error.isEmpty()) error = entry.value(QStringLiteral("lastError")).toString();
    }
    for (const auto &value : draft.value(QStringLiteral("expenses")).toList()) {
        const auto expense = value.toMap();
        if (expense.value(QStringLiteral("archived")).toBool()) continue;
        inspect(expense, QStringLiteral("syncState"));
        if (stateOf(expense) != QLatin1String(Synced)
            && !counted.contains(expense.value(QStringLiteral("localId")).toString())) ++pending;
        for (const auto &v : expense.value(QStringLiteral("attachments")).toList()) {
            const auto attachment = v.toMap();
            if (!attachment.value(QStringLiteral("archived_at")).toString().isEmpty()) continue;
            inspect(attachment, QStringLiteral("syncState"));
            if (attachment.value(QStringLiteral("phase")).toString() != QLatin1String("READY")
                && !counted.contains(attachment.value(QStringLiteral("localId")).toString())) ++pending;
        }
    }
    if (state == QLatin1String(Synced)) {
        if (active) state = QString::fromLatin1(Syncing);
        else if (pending > 0 || stateOf(draft) == QLatin1String(LocalOnly)) state = QString::fromLatin1(PendingUpdate);
        else {
            const auto summary = draft.value(QStringLiteral("remoteSummary")).toMap();
            if (!draft.value(QStringLiteral("expensesLoaded")).toBool()
                || !draft.value(QStringLiteral("attachmentsLoaded")).toBool()
                || summary.isEmpty()
                || summary.value(QStringLiteral("total_expenses")).toInt() != draft.value(QStringLiteral("expenseCount")).toInt()
                || qAbs(summary.value(QStringLiteral("total_declared_pen")).toDouble() - draft.value(QStringLiteral("totalPen")).toDouble()) > 0.005
                || qAbs(summary.value(QStringLiteral("total_declared_usd")).toDouble() - draft.value(QStringLiteral("totalUsd")).toDouble()) > 0.005
                || summary.value(QStringLiteral("rendition_row_version")).toLongLong() != draft.value(QStringLiteral("rowVersion")).toLongLong())
                state = QString::fromLatin1(NeedsReconciliation);
        }
    }
    return {{QStringLiteral("syncState"), state}, {QStringLiteral("pendingCount"), pending}, {QStringLiteral("syncError"), error}};
}

bool RenditionLocalStore::adoptDocumentLocation(
    const QString &renditionLocalId, const QVariantMap &location)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0 || location.isEmpty())
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    const QVariant parentId = valueFor(location,
        QStringLiteral("documentParentNodeId"),
        QStringLiteral("document_parent_node_id"));
    const QVariant nodeId = valueFor(location,
        QStringLiteral("documentNodeId"), QStringLiteral("document_node_id"));
    const QVariant nodeVersion = valueFor(location,
        QStringLiteral("documentNodeVersion"),
        QStringLiteral("document_node_version"));
    const QVariant spaceId = valueFor(location, QStringLiteral("spaceId"),
                                      QStringLiteral("space_id"));
    if (parentId.isValid())
        draft.insert(QStringLiteral("documentParentNodeId"), parentId);
    else if (location.value(QStringLiteral("parent_node_id")).isValid())
        draft.insert(QStringLiteral("documentParentNodeId"),
                     location.value(QStringLiteral("parent_node_id")));
    if (nodeId.isValid())
        draft.insert(QStringLiteral("documentNodeId"), nodeId);
    else if (location.value(QStringLiteral("node_id")).isValid())
        draft.insert(QStringLiteral("documentNodeId"),
                     location.value(QStringLiteral("node_id")));
    if (nodeVersion.isValid())
        draft.insert(QStringLiteral("documentNodeVersion"), nodeVersion);
    else if (location.value(QStringLiteral("node_version")).isValid())
        draft.insert(QStringLiteral("documentNodeVersion"),
                     location.value(QStringLiteral("node_version")));
    if (spaceId.isValid())
        draft.insert(QStringLiteral("spaceId"), spaceId);
    const QVariant parentName = valueFor(location,
        QStringLiteral("documentParentNodeName"),
        QStringLiteral("document_parent_node_name"));
    if (parentName.isValid())
        draft.insert(QStringLiteral("documentParentNodeName"), parentName);
    else if (location.value(QStringLiteral("parent_name")).isValid())
        draft.insert(QStringLiteral("documentParentNodeName"),
                     location.value(QStringLiteral("parent_name")));
    m_renditions[index] = draft;
    return persist();
}

QString RenditionLocalStore::newRequestId() const
{
    return newUuid();
}

QString RenditionLocalStore::ensurePresentationRequestId(const QString &localId)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return {};
    QVariantMap draft = m_renditions.at(index).toMap();
    if (!assertDraftStatus(draft))
        return {};
    QString requestId = draft.value(QStringLiteral("presentationRequestId")).toString();
    if (requestId.isEmpty()) {
        requestId = newUuid();
        draft.insert(QStringLiteral("presentationRequestId"), requestId);
        m_renditions[index] = draft;
        persist();
    }
    QVariantMap payload{
        {QStringLiteral("renditionLocalId"), localId},
        {QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId"))},
        {QStringLiteral("expectedRowVersion"), draft.value(QStringLiteral("rowVersion"))}
    };
    upsertOutbox(QStringLiteral("present"), localId,
                 draft.value(QStringLiteral("remoteId")).toString(), {},
                 requestId, payload, QString::fromLatin1(LocalOnly));
    persist();
    return requestId;
}

QString RenditionLocalStore::presentationBlocker(const QString &localId) const
{
    const QVariantMap draft = rendition(localId);
    if (syncStatus(localId).value(QStringLiteral("syncState")).toString() != QLatin1String(Synced))
        return QStringLiteral("Sincroniza los cambios pendientes antes de presentar.");
    if (draft.value(QStringLiteral("documentNodeId")).toString().isEmpty())
        return QStringLiteral("La rendición necesita su documento .rend canónico confirmado.");
    const auto invalid = RenditionValidation::header(draft.value(QStringLiteral("periodStart")).toString(),
        draft.value(QStringLiteral("periodEnd")).toString(), draft.value(QStringLiteral("projectIds")).toList(),
        draft.value(QStringLiteral("primaryProjectId")).toString(), draft.value(QStringLiteral("documentParentNodeId")).toString(),
        draft.value(QStringLiteral("spaceId")).toString());
    if (!invalid.isEmpty()) return invalid;
    int activeExpenses = 0;
    for (const auto &value : draft.value(QStringLiteral("expenses")).toList()) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("archived")).toBool()) continue;
        ++activeExpenses;
        const auto error = RenditionValidation::expense(draft, row);
        if (!error.isEmpty()) return error;
    }
    if (activeExpenses == 0) return QStringLiteral("Agrega al menos un gasto antes de presentar.");
    if (draft.isEmpty())
        return QStringLiteral("La rendición local ya no existe.");
    if (draft.value(QStringLiteral("status"), QStringLiteral("BORRADOR"))
            .toString().toUpper() != QLatin1String("BORRADOR")) {
        return QStringLiteral("Sólo una rendición BORRADOR puede presentarse.");
    }
    if (draft.value(QStringLiteral("remoteId")).toString().isEmpty()
        || draft.value(QStringLiteral("rowVersion")).toLongLong() <= 0) {
        return QStringLiteral("La cabecera todavía no fue confirmada por el servidor.");
    }

    for (const QVariant &value : m_outbox) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("aggregateLocalId")).toString() != localId
            || entry.value(QStringLiteral("operation")).toString()
                   == QLatin1String("present")) {
            continue;
        }
        if (entry.value(QStringLiteral("state")).toString()
            != QLatin1String(Synced)) {
            return QStringLiteral("Aún hay cambios pendientes, con error o en conflicto.");
        }
    }

    const QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    for (const QVariant &expenseValue : expenses) {
        const QVariantMap expense = expenseValue.toMap();
        if (expense.value(QStringLiteral("archived")).toBool())
            continue;
        if (expense.value(QStringLiteral("remoteId")).toString().isEmpty()
            || stateOf(expense) != QLatin1String(Synced)) {
            return QStringLiteral("Todos los gastos deben estar confirmados por el servidor.");
        }
        const QVariantList attachments = expense.value(
            QStringLiteral("attachments")).toList();
        for (const QVariant &attachmentValue : attachments) {
            const QVariantMap attachment = attachmentValue.toMap();
            if (!attachment.value(QStringLiteral("archived_at")).toString().isEmpty()) continue;
            if (attachment.value(QStringLiteral("remoteId")).toString().isEmpty()
                || attachment.value(QStringLiteral("phase")).toString()
                       != QLatin1String("READY")
                || stateOf(attachment) != QLatin1String(Synced)) {
                return QStringLiteral("Todos los sustentos deben terminar de sincronizarse.");
            }
        }
    }
    return {};
}

QVariantList RenditionLocalStore::pendingOperations() const
{
    QVariantList operations;
    for (const QVariant &value : m_outbox) {
        QVariantMap item = value.toMap();
        const QString state = item.value(QStringLiteral("state")).toString();
        const QString operation = item.value(QStringLiteral("operation")).toString();
        // La presentación nunca se ejecuta desde sync automático: sólo desde
        // la confirmación humana, reutilizando su request_id persistido.
        if (operation == QLatin1String("present"))
            continue;
        const bool idempotent = operation == QLatin1String("rendition_create")
            || operation == QLatin1String("rendition_delete")
            || operation == QLatin1String("expense_delete")
            || operation == QLatin1String("expense_create")
            || operation == QLatin1String("attachment_reserve")
            || operation == QLatin1String("present");
        if (state != QLatin1String(PendingCreate)
            && state != QLatin1String(PendingUpdate)
            && !(state == QLatin1String(Error) && idempotent)
            && !(state == QLatin1String(NeedsReconciliation)
                 && (operation == QLatin1String("attachment_reserve") || operation.endsWith(QLatin1String("_delete")))))
            continue;
        QVariantMap payload = item.value(QStringLiteral("payload")).toMap();
        const QString aggregateLocalId = item.value(QStringLiteral("aggregateLocalId")).toString();
        const QVariantMap draft = rendition(aggregateLocalId);
        if (draft.isEmpty() || (draft.value(QStringLiteral("archived")).toBool() && operation != QLatin1String("rendition_delete"))) continue;
        if (operation == QLatin1String("expense_update") || operation == QLatin1String("expense_delete")
            || operation.startsWith(QLatin1String("attachment_"))) {
            const QString expenseLocalId = operation.startsWith(QLatin1String("attachment_"))
                ? payload.value(QStringLiteral("expenseLocalId")).toString()
                : item.value(QStringLiteral("childLocalId")).toString();
            QString confirmedId;
            for (const auto &entry : draft.value(QStringLiteral("expenses")).toList()) {
                const auto expense = entry.toMap();
                if (expense.value(QStringLiteral("localId")).toString() == expenseLocalId)
                    confirmedId = expense.value(QStringLiteral("remoteId")).toString();
            }
            if (confirmedId.isEmpty() || confirmedId == draft.value(QStringLiteral("remoteId")).toString()) continue;
            payload.insert(QStringLiteral("expenseRemoteId"), confirmedId);
        }
        if ((draft.value(QStringLiteral("status")).toString() != QLatin1String("BORRADOR")
             || !draft.value(QStringLiteral("currentVersionId")).toString().isEmpty())
            && operation != QLatin1String("present"))
            continue;
        if ((operation == QLatin1String("expense_create")
             || operation.startsWith(QLatin1String("attachment_")))
            && draft.value(QStringLiteral("remoteId")).toString().isEmpty())
            continue;
        if (operation.startsWith(QLatin1String("attachment_"))
            && payload.value(QStringLiteral("expenseRemoteId")).toString().isEmpty())
            continue;
        for (auto it = item.cbegin(); it != item.cend(); ++it)
            payload.insert(it.key(), it.value());
        payload.insert(QStringLiteral("kind"), operation);
        payload.insert(QStringLiteral("localId"),
                       item.value(QStringLiteral("childLocalId")).toString().isEmpty()
                           ? aggregateLocalId
                           : item.value(QStringLiteral("childLocalId")));
        payload.insert(QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId")));
        operations.append(payload);
    }
    return operations;
}

bool RenditionLocalStore::markRenditionSyncing(const QString &localId)
{
    const QVariantMap draft = rendition(localId);
    const QString operation = draft.value(QStringLiteral("archived")).toBool() ? QStringLiteral("rendition_delete") : draft.value(QStringLiteral("remoteId")).toString().isEmpty()
        ? QStringLiteral("rendition_create") : QStringLiteral("rendition_update");
    markOutboxState(operation, localId, {}, QString::fromLatin1(Syncing));
    return markRenditionState(localId, QString::fromLatin1(Syncing));
}

bool RenditionLocalStore::markRenditionSynced(const QString &localId,
                                              const QVariantMap &remote)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    const QString id = remoteId(remote);
    const QString knownId = draft.value(QStringLiteral("remoteId")).toString();
    if (id.isEmpty() || (!knownId.isEmpty() && knownId != id)
        || remoteRowVersion(remote, 0) <= 0) {
        setLastError(QStringLiteral("El servidor no confirmó la identidad y versión de la rendición."));
        return false;
    }
    draft.insert(QStringLiteral("remoteId"), id);
    draft.insert(QStringLiteral("visibleCode"), valueFor(remote, QStringLiteral("visibleCode"), QStringLiteral("visible_code")));
    draft.insert(QStringLiteral("status"), remote.value(QStringLiteral("status"), draft.value(QStringLiteral("status"))));
    draft.insert(QStringLiteral("rowVersion"), remoteRowVersion(remote,
                 draft.value(QStringLiteral("rowVersion")).toLongLong()));
    draft.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    draft.remove(QStringLiteral("syncError"));
    m_renditions[index] = draft;
    markOutboxState(QStringLiteral("rendition_create"), localId, {},
                    QString::fromLatin1(Synced));
    markOutboxState(QStringLiteral("rendition_update"), localId, {},
                    QString::fromLatin1(Synced));
    for (int i = 0; i < m_outbox.size(); ++i) {
        QVariantMap entry = m_outbox.at(i).toMap();
        if (entry.value(QStringLiteral("aggregateLocalId")).toString() != localId)
            continue;
        entry.insert(QStringLiteral("remoteId"), draft.value(QStringLiteral("remoteId")));
        const QString operation = entry.value(
            QStringLiteral("operation")).toString();
        if (!operation.startsWith(QLatin1String("expense_"))
            && operation != QLatin1String("attachment_reserve")) {
            m_outbox[i] = entry;
            continue;
        }
        QVariantMap payload = entry.value(QStringLiteral("payload")).toMap();
        payload.insert(QStringLiteral("renditionRemoteId"), draft.value(QStringLiteral("remoteId")));
        if (operation.startsWith(QLatin1String("expense_"))) {
            payload.insert(QStringLiteral("expectedRenditionRowVersion"),
                           draft.value(QStringLiteral("rowVersion")));
        }
        entry.insert(QStringLiteral("payload"), payload);
        entry.insert(QStringLiteral("payloadHash"),
                     QString::fromLatin1(payloadHash(payload)));
        m_outbox[i] = entry;
    }
    return persist();
}

bool RenditionLocalStore::markRenditionState(const QString &localId,
                                             const QString &state,
                                             const QString &error)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    draft.insert(QStringLiteral("syncState"), state);
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    if (error.isEmpty())
        draft.remove(QStringLiteral("syncError"));
    else
        draft.insert(QStringLiteral("syncError"), error);
    m_renditions[index] = draft;
    const QString operation = draft.value(QStringLiteral("archived")).toBool() ? QStringLiteral("rendition_delete") : draft.value(QStringLiteral("remoteId")).toString().isEmpty()
        ? QStringLiteral("rendition_create") : QStringLiteral("rendition_update");
    markOutboxState(operation, localId, {}, state, error);
    return persist();
}

bool RenditionLocalStore::markPresentationState(const QString &localId,
                                                const QString &state,
                                                const QString &error)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    draft.insert(QStringLiteral("syncState"), state);
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    if (error.isEmpty())
        draft.remove(QStringLiteral("syncError"));
    else
        draft.insert(QStringLiteral("syncError"), error);
    m_renditions[index] = draft;
    markOutboxState(QStringLiteral("present"), localId, {}, state, error);
    return persist();
}

bool RenditionLocalStore::markRenditionPresented(const QString &localId,
                                                 const QVariantMap &remote)
{
    const int index = renditionIndex(localId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    if (remoteId(remote) != draft.value(QStringLiteral("remoteId")).toString()
        || remote.value(QStringLiteral("status")).toString() != QLatin1String("PRESENTADA")) {
        setLastError(QStringLiteral("La respuesta de presentación no corresponde a esta rendición."));
        return false;
    }
    draft.insert(QStringLiteral("status"), QStringLiteral("PRESENTADA"));
    draft.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    draft.insert(QStringLiteral("rowVersion"),
                 remoteRowVersion(remote, draft.value(QStringLiteral("rowVersion")).toLongLong()));
    QVariant versionId = valueFor(remote, QStringLiteral("versionId"),
                                  QStringLiteral("version_id"));
    if (!versionId.isValid())
        versionId = valueFor(remote, QStringLiteral("currentVersionId"),
                             QStringLiteral("current_version_id"));
    if (!versionId.isValid())
        versionId = remote.value(QStringLiteral("rendition_version_id"));
    if (!versionId.isValid())
        versionId = remote.value(QStringLiteral("id"));
    draft.insert(QStringLiteral("versionId"), versionId);
    draft.insert(QStringLiteral("currentVersionId"), versionId);
    draft.insert(QStringLiteral("submittedAt"), remote.value(QStringLiteral("submitted_at")));
    draft.insert(QStringLiteral("versionNumber"), valueFor(
                     remote, QStringLiteral("versionNumber"),
                     QStringLiteral("version_number")));
    QVariant snapshotHash = valueFor(remote, QStringLiteral("snapshotHash"),
                                     QStringLiteral("snapshot_hash"));
    if (!snapshotHash.isValid())
        snapshotHash = remote.value(QStringLiteral("snapshot_sha256"));
    draft.insert(QStringLiteral("snapshotHash"), snapshotHash);
    draft.insert(QStringLiteral("updatedAt"), nowUtc());
    draft.remove(QStringLiteral("syncError"));
    m_renditions[index] = draft;
    markOutboxState(QStringLiteral("present"), localId, {},
                    QString::fromLatin1(Synced));
    return persist();
}

bool RenditionLocalStore::markExpenseSyncing(const QString &renditionLocalId,
                                             const QString &expenseLocalId)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int child = expenseIndex(expenses, expenseLocalId);
    if (child < 0)
        return false;
    QVariantMap expense = expenses.at(child).toMap();
    const QString operation = expense.value(QStringLiteral("archived")).toBool() ? QStringLiteral("expense_delete") : expense.value(QStringLiteral("remoteId")).toString().isEmpty()
        ? QStringLiteral("expense_create") : QStringLiteral("expense_update");
    expense.insert(QStringLiteral("syncState"), QString::fromLatin1(Syncing));
    expenses[child] = expense;
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    markOutboxState(operation, renditionLocalId, expenseLocalId,
                    QString::fromLatin1(Syncing));
    return persist();
}

bool RenditionLocalStore::markExpenseSynced(const QString &renditionLocalId,
                                            const QString &expenseLocalId,
                                            const QVariantMap &remote)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int child = expenseIndex(expenses, expenseLocalId);
    if (child < 0)
        return false;
    QVariantMap expense = expenses.at(child).toMap();
    const QString id = remoteId(remote, QStringLiteral("expense"));
    const QString knownId = expense.value(QStringLiteral("remoteId")).toString();
    if (id.isEmpty() || id == draft.value(QStringLiteral("remoteId")).toString()
        || (!knownId.isEmpty() && id != knownId)) {
        setLastError(QStringLiteral("El servidor no confirmó un UUID válido para el gasto. Reintenta la misma operación."));
        return false;
    }
    if (!id.isEmpty())
        expense.insert(QStringLiteral("remoteId"), id);
    QVariant expenseVersion = valueFor(
                       remote, QStringLiteral("expenseRowVersion"),
                       QStringLiteral("expense_row_version"));
    if (!expenseVersion.isValid()) expenseVersion = remote.value(QStringLiteral("row_version"));
    if (expenseVersion.toLongLong() <= 0
        || expenseVersion.toLongLong() < expense.value(QStringLiteral("rowVersion")).toLongLong()) {
        setLastError(QStringLiteral("El servidor no confirmó la versión del gasto."));
        return false;
    }
    expense.insert(QStringLiteral("rowVersion"), expenseVersion);
    expense.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    expense.remove(QStringLiteral("syncError"));
    expenses[child] = expense;
    // An idempotent CREATE replay can meet a row already downloaded by PULL.
    // Retain the original local identity/intention and fold only the same UUID.
    for (int i = expenses.size() - 1; i >= 0; --i) {
        const auto other = expenses[i].toMap();
        if (i == child || other.value(QStringLiteral("remoteId")).toString() != id) continue;
        if (stateOf(other) != QLatin1String(Synced)) {
            setLastError(QStringLiteral("Dos intenciones locales corresponden al mismo gasto; requiere reconciliación."));
            return false;
        }
        auto attachments = expense.value(QStringLiteral("attachments")).toList();
        for (const auto &a : other.value(QStringLiteral("attachments")).toList()) {
            bool known = false;
            for (const auto &b : attachments)
                known |= a.toMap().value(QStringLiteral("localId")) == b.toMap().value(QStringLiteral("localId"))
                    || (!a.toMap().value(QStringLiteral("remoteId")).toString().isEmpty()
                        && a.toMap().value(QStringLiteral("remoteId")) == b.toMap().value(QStringLiteral("remoteId")));
            if (!known) attachments.append(a);
        }
        expense.insert(QStringLiteral("attachments"), attachments);
        expenses.removeAt(i);
    }
    expenses[expenseIndex(expenses, expenseLocalId)] = expense;
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    const QVariant headerVersion = valueFor(remote,
        QStringLiteral("renditionRowVersion"), QStringLiteral("rendition_row_version"));
    if (headerVersion.isValid())
        draft.insert(QStringLiteral("rowVersion"), qMax(headerVersion.toLongLong(),
                     draft.value(QStringLiteral("rowVersion")).toLongLong()));
    m_renditions[index] = draft;
    markOutboxState(QStringLiteral("expense_create"), renditionLocalId,
                    expenseLocalId, QString::fromLatin1(Synced));
    markOutboxState(QStringLiteral("expense_update"), renditionLocalId,
                    expenseLocalId, QString::fromLatin1(Synced));
    markOutboxState(QStringLiteral("expense_delete"), renditionLocalId,
                    expenseLocalId, QString::fromLatin1(Synced));
    for (int i = 0; i < m_outbox.size(); ++i) {
        QVariantMap entry = m_outbox.at(i).toMap();
        if (entry.value(QStringLiteral("aggregateLocalId")).toString()
                != renditionLocalId)
            continue;
        QVariantMap payload = entry.value(QStringLiteral("payload")).toMap();
        const QString operation = entry.value(
            QStringLiteral("operation")).toString();
        if (entry.value(QStringLiteral("state")).toString() == QLatin1String(Synced)
            && operation.startsWith(QLatin1String("expense_")))
            continue;
        if (operation.startsWith(QLatin1String("expense_")))
            payload.insert(QStringLiteral("expectedRenditionRowVersion"),
                           draft.value(QStringLiteral("rowVersion")));
        if (operation == QLatin1String("attachment_reserve")
            && payload.value(QStringLiteral("expenseLocalId")).toString()
                   == expenseLocalId) {
            payload.insert(QStringLiteral("expenseRemoteId"),
                           expense.value(QStringLiteral("remoteId")));
        }
        entry.insert(QStringLiteral("payload"), payload);
        entry.insert(QStringLiteral("payloadHash"),
                     QString::fromLatin1(payloadHash(payload)));
        m_outbox[i] = entry;
    }
    return persist();
}

bool RenditionLocalStore::markExpenseNeedsReconciliation(
    const QString &renditionLocalId, const QString &expenseLocalId,
    const QString &error)
{
    return markExpenseState(renditionLocalId, expenseLocalId,
                            QString::fromLatin1(NeedsReconciliation), error);
}

bool RenditionLocalStore::markExpenseState(
    const QString &renditionLocalId, const QString &expenseLocalId,
    const QString &state, const QString &error)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0)
        return false;
    QVariantMap draft = m_renditions.at(index).toMap();
    QVariantList expenses = draft.value(QStringLiteral("expenses")).toList();
    const int child = expenseIndex(expenses, expenseLocalId);
    if (child < 0)
        return false;
    QVariantMap expense = expenses.at(child).toMap();
    expense.insert(QStringLiteral("syncState"), state);
    if (error.isEmpty())
        expense.remove(QStringLiteral("syncError"));
    else
        expense.insert(QStringLiteral("syncError"), error);
    expenses[child] = expense;
    draft.insert(QStringLiteral("expenses"), expenses);
    RenditionValidation::totals(draft);
    m_renditions[index] = draft;
    // Only the active intention may change state. A confirmed CREATE must
    // never be revived when a later UPDATE/DELETE fails or is interrupted.
    const QString operation = expense.value(QStringLiteral("archived")).toBool()
        ? QStringLiteral("expense_delete")
        : expense.value(QStringLiteral("remoteId")).toString().isEmpty()
            ? QStringLiteral("expense_create") : QStringLiteral("expense_update");
    markOutboxState(operation, renditionLocalId, expenseLocalId, state, error);
    return persist();
}

int RenditionLocalStore::outboxIndex(const QString &operation,
                                     const QString &aggregateLocalId,
                                     const QString &childLocalId) const
{
    for (int i = 0; i < m_outbox.size(); ++i) {
        const QVariantMap entry = m_outbox.at(i).toMap();
        if (entry.value(QStringLiteral("operation")).toString() == operation
            && entry.value(QStringLiteral("aggregateLocalId")).toString() == aggregateLocalId
            && entry.value(QStringLiteral("childLocalId")).toString() == childLocalId)
            return i;
    }
    return -1;
}

void RenditionLocalStore::upsertOutbox(
    const QString &operation, const QString &aggregateLocalId,
    const QString &remoteIdValue, const QString &childLocalId,
    const QString &requestId, const QVariantMap &payload, const QString &state)
{
    int index = outboxIndex(operation, aggregateLocalId, childLocalId);
    QVariantMap entry = index >= 0 ? m_outbox.at(index).toMap() : QVariantMap{};
    if (index < 0) {
        entry.insert(QStringLiteral("id"), newUuid());
        entry.insert(QStringLiteral("sequence"), m_nextSequence++);
        entry.insert(QStringLiteral("attempts"), 0);
        entry.insert(QStringLiteral("createdAt"), nowUtc());
    }
    entry.insert(QStringLiteral("operation"), operation);
    entry.insert(QStringLiteral("accountScope"), m_accountScope);
    entry.insert(QStringLiteral("aggregateLocalId"), aggregateLocalId);
    entry.insert(QStringLiteral("childLocalId"), childLocalId);
    entry.insert(QStringLiteral("remoteId"), remoteIdValue);
    entry.insert(QStringLiteral("requestId"), requestId);
    entry.insert(QStringLiteral("payload"), payload);
    entry.insert(QStringLiteral("payloadHash"), QString::fromLatin1(payloadHash(payload)));
    entry.insert(QStringLiteral("state"), state);
    entry.insert(QStringLiteral("updatedAt"), nowUtc());
    entry.remove(QStringLiteral("lastSafeError"));
    if (index >= 0)
        m_outbox[index] = entry;
    else
        m_outbox.append(entry);
}

void RenditionLocalStore::markOutboxState(
    const QString &operation, const QString &aggregateLocalId,
    const QString &childLocalId, const QString &state, const QString &error)
{
    const int index = outboxIndex(operation, aggregateLocalId, childLocalId);
    if (index < 0)
        return;
    QVariantMap entry = m_outbox.at(index).toMap();
    entry.insert(QStringLiteral("state"), state);
    entry.insert(QStringLiteral("updatedAt"), nowUtc());
    if (state == QLatin1String(Syncing))
        entry.insert(QStringLiteral("attempts"),
                     entry.value(QStringLiteral("attempts")).toInt() + 1);
    if (error.isEmpty())
        entry.remove(QStringLiteral("lastSafeError"));
    else
        entry.insert(QStringLiteral("lastSafeError"), error.left(500));
    m_outbox[index] = entry;
}

void RenditionLocalStore::rebuildLegacyOutbox()
{
    for (const QVariant &value : m_renditions) {
        const QVariantMap draft = value.toMap();
        const QString localId = draft.value(QStringLiteral("localId")).toString();
        const bool localOnly = draft.value(QStringLiteral("remoteId")).toString().isEmpty();
        const QString state = stateOf(draft);
        if (state == QLatin1String(PendingCreate) || state == QLatin1String(PendingUpdate)
            || state == QLatin1String(Error)) {
            upsertOutbox(localOnly ? QStringLiteral("rendition_create")
                                   : QStringLiteral("rendition_update"),
                         localId, draft.value(QStringLiteral("remoteId")).toString(), {},
                         localOnly ? draft.value(QStringLiteral("requestId")).toString() : QString{},
                         canonicalDraftPayload(draft), state);
        }
    }
}

bool RenditionLocalStore::assertDraftStatus(const QVariantMap &rendition)
{
    if (!rendition.isEmpty() && !rendition.value(QStringLiteral("archived")).toBool()
        && rendition.value(QStringLiteral("currentVersionId")).toString().isEmpty()
        && rendition.value(QStringLiteral("status"), QStringLiteral("BORRADOR")).toString()
        == QLatin1String("BORRADOR"))
        return true;
    setLastError(QStringLiteral("Una rendición no BORRADOR es inmutable."));
    return false;
}

bool RenditionLocalStore::persist()
{
    const QString path = storagePath();
    if (path.isEmpty())
        return false;
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        setLastError(QStringLiteral("No se pudo crear el directorio local de rendiciones."));
        return false;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(QStringLiteral("No se pudo guardar la rendición local."));
        return false;
    }
    const QVariantMap root{
        {QStringLiteral("schemaVersion"), 2},
        {QStringLiteral("accountScope"), m_accountScope},
        {QStringLiteral("updatedAt"), nowUtc()},
        {QStringLiteral("nextSequence"), m_nextSequence},
        {QStringLiteral("renditions"), m_renditions},
        {QStringLiteral("outbox"), m_outbox}
        ,{QStringLiteral("editorDrafts"), m_editorDrafts}
    };
    const QByteArray bytes = QJsonDocument::fromVariant(root).toJson(QJsonDocument::Compact);
    if (file.write(bytes) != bytes.size()) {
        setLastError(QStringLiteral("No se pudo escribir el almacén local completo."));
        return false;
    }
    if (!file.commit()) {
        setLastError(QStringLiteral("No se pudo confirmar el guardado local."));
        return false;
    }
    setLastError({});
    emit renditionsChanged();
    emit outboxChanged();
    emit pendingCountChanged();
    return true;
}

void RenditionLocalStore::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
    if (!message.isEmpty())
        emit persistenceFailed(message);
}

bool RenditionLocalStore::saveEditorDraft(const QString &key, const QVariantMap &draft)
{
    if (key.isEmpty()) return false;
    const QString localId = draft.value(QStringLiteral("renditionLocalId")).toString();
    if (!draft.isEmpty() && !localId.isEmpty() && !assertDraftStatus(rendition(localId))) return false;
    if (draft.isEmpty()) m_editorDrafts.remove(key); else m_editorDrafts.insert(key, draft);
    return persist();
}

int RenditionLocalStore::renditionIndex(const QString &localId) const
{
    for (int i = 0; i < m_renditions.size(); ++i) {
        if (m_renditions.at(i).toMap().value(QStringLiteral("localId")).toString() == localId)
            return i;
    }
    return -1;
}

int RenditionLocalStore::renditionIndexByRemoteId(const QString &remoteIdValue) const
{
    for (int i = 0; i < m_renditions.size(); ++i) {
        if (m_renditions.at(i).toMap().value(QStringLiteral("remoteId")).toString()
            == remoteIdValue)
            return i;
    }
    return -1;
}

int RenditionLocalStore::expenseIndex(const QVariantList &expenses,
                                      const QString &localId) const
{
    for (int i = 0; i < expenses.size(); ++i) {
        if (expenses.at(i).toMap().value(QStringLiteral("localId")).toString() == localId)
            return i;
    }
    return -1;
}

QString RenditionLocalStore::nowUtc()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString RenditionLocalStore::newUuid()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QString RenditionLocalStore::remoteId(const QVariantMap &remote, const QString &entity)
{
    // Parent foreign keys are never the identity of a child row.
    for (const QString &key : {entity + QStringLiteral("_id"), QStringLiteral("id")}) {
        const QString id = remote.value(key).toString();
        if (!id.isEmpty())
            return id;
    }
    return {};
}

qint64 RenditionLocalStore::remoteRowVersion(const QVariantMap &remote,
                                             qint64 fallback)
{
    const QVariant direct = valueFor(remote, QStringLiteral("renditionRowVersion"),
                                     QStringLiteral("rendition_row_version"));
    if (direct.isValid())
        return direct.toLongLong();
    const QVariant value = remote.value(QStringLiteral("row_version"));
    return value.isValid() ? value.toLongLong() : fallback;
}

QVariantMap RenditionLocalStore::canonicalDraftPayload(const QVariantMap &draft)
{
    return {
        {QStringLiteral("periodStart"), draft.value(QStringLiteral("periodStart"))},
        {QStringLiteral("periodEnd"), draft.value(QStringLiteral("periodEnd"))},
        {QStringLiteral("projectIds"), draft.value(QStringLiteral("projectIds"))},
        {QStringLiteral("primaryProjectId"), draft.value(QStringLiteral("primaryProjectId"))},
        {QStringLiteral("documentParentNodeId"), draft.value(QStringLiteral("documentParentNodeId"))},
        {QStringLiteral("documentNodeId"), draft.value(QStringLiteral("documentNodeId"))},
        {QStringLiteral("documentNodeVersion"), draft.value(QStringLiteral("documentNodeVersion"))},
        {QStringLiteral("spaceId"), draft.value(QStringLiteral("spaceId"))},
        {QStringLiteral("expectedRowVersion"), draft.value(QStringLiteral("rowVersion"))}
    };
}

QByteArray RenditionLocalStore::payloadHash(const QVariantMap &payload)
{
    return QCryptographicHash::hash(
        QJsonDocument::fromVariant(payload).toJson(QJsonDocument::Compact),
        QCryptographicHash::Sha256).toHex();
}
