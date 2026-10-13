#include "renditionsynccontroller.h"

#include "renditionlocalstore.h"
#include "renditionrepository.h"
#include "renditionattachmentcontract.h"
#include <QDateTime>
#include <QGuiApplication>
#include <QNetworkInformation>
#include <QTimer>

namespace {
constexpr auto Conflict = "CONFLICT";
constexpr auto NeedsReconciliation = "NEEDS_RECONCILIATION";
constexpr auto Error = "ERROR";

QString field(const QVariantMap &map, const QString &camel, const QString &snake)
{
    const QVariant value = map.value(camel);
    return value.isValid() ? value.toString() : map.value(snake).toString();
}
}

RenditionSyncController::RenditionSyncController(
    RenditionLocalStore *store, RenditionRepository *repository, QObject *parent)
    : QObject(parent), m_store(store), m_repository(repository)
{
    // Reuse the existing persistent domain queue after reconnect/resume.
    if (auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
        connect(app, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
            if (state == Qt::ApplicationActive) synchronize();
        });
    QNetworkInformation::loadDefaultBackend();
    if (auto *network = QNetworkInformation::instance())
        connect(network, &QNetworkInformation::reachabilityChanged, this, [this](QNetworkInformation::Reachability state) {
            if (state == QNetworkInformation::Reachability::Online) synchronize();
        });
    connect(m_store, &RenditionLocalStore::accountIdChanged, this, [this] {
        QTimer::singleShot(0, this, &RenditionSyncController::synchronize);
    });
    QTimer::singleShot(0, this, &RenditionSyncController::synchronize);
    connect(m_repository, &RenditionRepository::receivedReset, this, [this]() {
        m_current.clear();
        m_locationRefreshLocalId.clear();
        setBusy(false);
        setLastError({});
    });
    connect(m_repository, &RenditionRepository::renditionCreated,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::renditionEdited,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::expenseAdded,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::expenseEdited,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::expenseDeleted,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::draftDeleted,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::documentLocationChanged, this,
            [this]() {
        if (m_locationRefreshLocalId.isEmpty())
            return;
        m_store->adoptDocumentLocation(m_locationRefreshLocalId,
                                       m_repository->documentLocation());
        m_locationRefreshLocalId.clear();
    });
    connect(m_repository, &RenditionRepository::attachmentReserved, this,
            [this](const QVariantMap &remote) {
        if (!m_busy || m_current.value(QStringLiteral("kind")).toString()
                != QLatin1String("attachment_reserve"))
            return;
        const QString renditionLocalId = m_current.value(
            QStringLiteral("aggregateLocalId")).toString();
        const QString expenseLocalId = m_current.value(
            QStringLiteral("expenseLocalId")).toString();
        const QString attachmentLocalId = m_current.value(
            QStringLiteral("localId")).toString();
        const QString path = RenditionAttachmentContract::objectPath(remote);
        const QString bucket = field(remote, QStringLiteral("bucket"), QStringLiteral("bucket_id"));
        const QString id = field(remote, QStringLiteral("attachmentId"), QStringLiteral("attachment_id"));
        if (!RenditionAttachmentContract::valid(bucket, path, id)) {
            failCurrent(QStringLiteral("RENDITION_ATTACHMENT_RESERVATION_INVALID"),
                        QStringLiteral("Reserva inválida: falta bucket, storage_path o identidad del sustento. El archivo sigue guardado localmente."));
            return;
        }
        const auto expiry = QDateTime::fromString(remote.value(QStringLiteral("expires_at")).toString(), Qt::ISODateWithMs);
        if (remote.value(QStringLiteral("result_code")).toString() != QLatin1String("IDEMPOTENT_READY")
            && (!expiry.isValid() || expiry <= QDateTime::currentDateTimeUtc())) {
            failCurrent(QStringLiteral("RENDITION_ATTACHMENT_RESERVATION_EXPIRED"),
                        QStringLiteral("La reserva no fue renovada por el servidor. El sustento queda pendiente para reintentar la sincronización."));
            return;
        }
        if (remote.value(QStringLiteral("result_code")).toString() == QLatin1String("IDEMPOTENT_READY")) {
            if (!m_store->updateAttachmentPhase(renditionLocalId, expenseLocalId, attachmentLocalId,
                                                QStringLiteral("READY"), remote)) {
                failCurrent(QStringLiteral("LOCAL_PERSISTENCE_FAILED"), m_store->lastError());
                return;
            }
            m_current.clear();
            processNext();
            return;
        }
        m_current.insert(QStringLiteral("phase"), QStringLiteral("UPLOAD"));
        if (!m_store->updateAttachmentPhase(renditionLocalId, expenseLocalId,
                                       attachmentLocalId,
                                       QStringLiteral("UPLOAD"), remote)) {
            failCurrent(QStringLiteral("LOCAL_PERSISTENCE_FAILED"), m_store->lastError());
            return;
        }
        m_repository->uploadReservedAttachment(
            m_current.value(QStringLiteral("localUri")).toString(),
            bucket,
            path,
            m_current.value(QStringLiteral("mimeType")).toString(),
            field(remote, QStringLiteral("attachmentId"), QStringLiteral("attachment_id")));
    });
    connect(m_repository, &RenditionRepository::attachmentUploaded, this,
            [this](const QString &attachmentId) {
        if (!m_busy || m_current.value(QStringLiteral("kind")).toString()
                != QLatin1String("attachment_reserve"))
            return;
        m_current.insert(QStringLiteral("confirmedAttachmentId"), attachmentId);
        if (!m_store->updateAttachmentPhase(
            m_current.value(QStringLiteral("aggregateLocalId")).toString(),
            m_current.value(QStringLiteral("expenseLocalId")).toString(),
            m_current.value(QStringLiteral("localId")).toString(),
            QStringLiteral("FINALIZE"),
            {{QStringLiteral("attachment_id"), attachmentId}})) {
            failCurrent(QStringLiteral("LOCAL_PERSISTENCE_FAILED"), m_store->lastError());
            return;
        }
        m_repository->finalizeAttachment(attachmentId);
    });
    connect(m_repository, &RenditionRepository::attachmentFinalized, this,
            [this](const QVariantMap &remote) {
        if (!m_busy || m_current.value(QStringLiteral("kind")).toString()
                != QLatin1String("attachment_reserve"))
            return;
        const auto attachmentId = field(remote, QStringLiteral("attachmentId"), QStringLiteral("attachment_id"));
        if (QUuid(attachmentId).isNull()
            || attachmentId != m_current.value(QStringLiteral("confirmedAttachmentId")).toString()) {
            failCurrent(QStringLiteral("INVALID_RESPONSE"), QStringLiteral("El servidor no confirmó la identidad del sustento."));
            return;
        }
        if (!m_store->updateAttachmentPhase(
            m_current.value(QStringLiteral("aggregateLocalId")).toString(),
            m_current.value(QStringLiteral("expenseLocalId")).toString(),
            m_current.value(QStringLiteral("localId")).toString(),
            QStringLiteral("READY"), remote)) {
            failCurrent(QStringLiteral("LOCAL_PERSISTENCE_FAILED"), m_store->lastError());
            return;
        }
        m_current.clear();
        processNext();
    });
    connect(m_repository, &RenditionRepository::operationFailed, this,
            [this](const QString &operation, const QString &code,
                   const QString &message) {
        if (operation == QLatin1String("get_location")) {
            m_locationRefreshLocalId.clear();
            return;
        }
        if (!m_busy || m_current.isEmpty())
            return;
        const QString kind = m_current.value(QStringLiteral("kind")).toString();
        const bool related = (kind == QLatin1String("rendition_create")
                              && operation == QLatin1String("create"))
            || (kind == QLatin1String("rendition_update")
                && operation == QLatin1String("edit"))
            || (kind == operation)
            || (kind == QLatin1String("attachment_reserve")
                && operation.startsWith(QLatin1String("attachment_")));
        if (!related)
            return;
        failCurrent(code, message);
    });
}

void RenditionSyncController::synchronize()
{
    if (m_busy || !m_store || !m_repository)
        return;
    setLastError({});
    setBusy(true);
    processNext();
}

void RenditionSyncController::processNext()
{
    const QVariantList pending = m_store->pendingOperations();
    if (pending.isEmpty()) {
        m_current.clear();
        setBusy(false);
        emit syncFinished(m_store->pendingCount());
        return;
    }

    m_current = pending.constFirst().toMap();
    const QString kind = m_current.value(QStringLiteral("kind")).toString();
    const QString localId = m_current.value(QStringLiteral("localId")).toString();
    const QString aggregateLocalId = m_current.value(
        QStringLiteral("aggregateLocalId"), localId).toString();
    if (kind == QLatin1String("rendition_delete")) {
        if (!m_store->markRenditionSyncing(aggregateLocalId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->deleteDraft(m_current.value(QStringLiteral("remoteId")).toString(),
                                  m_current.value(QStringLiteral("expectedRowVersion")).toLongLong());
        return;
    }
    if (kind == QLatin1String("rendition_create")) {
        if (!m_store->markRenditionSyncing(aggregateLocalId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->createRendition(
            m_current.value(QStringLiteral("requestId")).toString(),
            m_current.value(QStringLiteral("periodStart")).toString(),
            m_current.value(QStringLiteral("periodEnd")).toString(),
            m_current.value(QStringLiteral("projectIds")).toList(),
            m_current.value(QStringLiteral("primaryProjectId")).toString(),
            m_current.value(QStringLiteral("documentParentNodeId")).toString());
        return;
    }
    if (kind == QLatin1String("rendition_update")) {
        if (!m_store->markRenditionSyncing(aggregateLocalId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->editRendition(
            m_current.value(QStringLiteral("remoteId")).toString(),
            m_current.value(QStringLiteral("expectedRowVersion")).toLongLong(),
            m_current.value(QStringLiteral("periodStart")).toString(),
            m_current.value(QStringLiteral("periodEnd")).toString(),
            m_current.value(QStringLiteral("projectIds")).toList(),
            m_current.value(QStringLiteral("primaryProjectId")).toString(),
            m_current.value(QStringLiteral("documentParentNodeId")).toString(),
            m_current.value(QStringLiteral("documentNodeVersion")).toLongLong());
        return;
    }
    if (kind == QLatin1String("expense_create")) {
        if (!m_store->markExpenseSyncing(aggregateLocalId, localId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->addExpense(
            m_current.value(QStringLiteral("requestId")).toString(),
            m_current.value(QStringLiteral("renditionRemoteId")).toString(),
            m_current.value(QStringLiteral("expectedRenditionRowVersion")).toLongLong(),
            m_current.value(QStringLiteral("projectId")).toString(),
            m_current.value(QStringLiteral("expenseDate")).toString(),
            m_current.value(QStringLiteral("categoryCode")).toString(),
            m_current.value(QStringLiteral("concept")).toString(),
            m_current.value(QStringLiteral("beneficiary")).toString(),
            m_current.value(QStringLiteral("paymentMethodCode")).toString(),
            m_current.value(QStringLiteral("paymentMethodDetail")).toString(),
            m_current.value(QStringLiteral("supportTypeCode")).toString(),
            m_current.value(QStringLiteral("supportNumber")).toString(),
            m_current.value(QStringLiteral("supportDetail")).toString(),
            m_current.value(QStringLiteral("currencyCode"), QStringLiteral("PEN")).toString(),
            m_current.value(QStringLiteral("amount")).toString(),
            m_current.value(QStringLiteral("justification")).toString());
        return;
    }
    if (kind == QLatin1String("expense_update")) {
        if (!m_store->markExpenseSyncing(aggregateLocalId, localId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->updateExpense(
            m_current.value(QStringLiteral("expenseRemoteId")).toString(),
            m_current.value(QStringLiteral("renditionRemoteId")).toString(),
            m_current.value(QStringLiteral("rowVersion")).toLongLong(),
            m_current.value(QStringLiteral("expectedRenditionRowVersion")).toLongLong(),
            m_current);
        return;
    }
    if (kind == QLatin1String("expense_delete")) {
        if (!m_store->markExpenseSyncing(aggregateLocalId, localId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->deleteExpense(
            m_current.value(QStringLiteral("renditionRemoteId")).toString(),
            m_current.value(QStringLiteral("expenseRemoteId")).toString(),
            m_current.value(QStringLiteral("expectedExpenseRowVersion")).toLongLong(),
            m_current.value(QStringLiteral("expectedRenditionRowVersion")).toLongLong());
        return;
    }
    if (kind == QLatin1String("attachment_reserve")) {
        const auto draft = m_store->rendition(aggregateLocalId);
        const auto expenses = m_store->expensesFor(aggregateLocalId);
        QString projectId;
        for (const auto &entry : expenses) {
            const auto expense = entry.toMap();
            if (expense.value(QStringLiteral("localId")) == m_current.value(QStringLiteral("expenseLocalId")))
                projectId = expense.value(QStringLiteral("projectId")).toString();
        }
        if (projectId.isEmpty() || draft.value(QStringLiteral("remoteId")).toString().isEmpty()
            || m_current.value(QStringLiteral("expenseRemoteId")).toString().isEmpty()
            || m_current.value(QStringLiteral("fileName")).toString().trimmed().isEmpty()) {
            failCurrent(QStringLiteral("RENDITION_ATTACHMENT_SCOPE_REQUIRED"),
                        QStringLiteral("El sustento necesita proyecto, rendición, gasto y nombre de archivo válidos. Se conserva localmente."));
            return;
        }
        // Always replay the idempotent reservation before upload/finalization.
        // This renews an expired lease while retaining its UUID and object key.
        m_repository->reserveAttachment(
            m_current.value(QStringLiteral("renditionRemoteId")).toString(),
            m_current.value(QStringLiteral("expenseRemoteId")).toString(),
            m_current.value(QStringLiteral("requestId")).toString(),
            m_current.value(QStringLiteral("fileName")).toString(),
            m_current.value(QStringLiteral("mimeType")).toString(),
            m_current.value(QStringLiteral("sizeBytes")).toLongLong(),
            m_current.value(QStringLiteral("supportTypeCode")).toString(),
            m_current.value(QStringLiteral("documentNumber")).toString());
        return;
    }

    failCurrent(QStringLiteral("UNKNOWN_OPERATION"),
                QStringLiteral("No se pudo sincronizar un cambio pendiente. Revisa la rendición."));
}

void RenditionSyncController::finishCurrent(const QVariantMap &remote)
{
    if (!m_busy || m_current.isEmpty())
        return;
    const QString kind = m_current.value(QStringLiteral("kind")).toString();
    const QString localId = m_current.value(QStringLiteral("localId")).toString();
    const QString aggregateLocalId = m_current.value(
        QStringLiteral("aggregateLocalId"), localId).toString();
    if (kind == QLatin1String("rendition_delete")) {
        if (!m_store->markDraftDeleted(aggregateLocalId, remote)) { failCurrent("INVALID_RESPONSE", m_store->lastError()); return; }
    } else if (kind.startsWith(QLatin1String("expense_"))) {
        if (!m_store->markExpenseSynced(aggregateLocalId, localId, remote)) {
            failCurrent(QStringLiteral("INVALID_RESPONSE"), m_store->lastError());
            return;
        }
    } else {
        if (!m_store->markRenditionSynced(aggregateLocalId, remote)) {
            failCurrent(QStringLiteral("INVALID_RESPONSE"), m_store->lastError());
            return;
        }
        m_store->adoptDocumentLocation(aggregateLocalId, remote);
        if (m_repository->v02Enabled()) {
            const QString renditionRemoteId = m_store->rendition(
                aggregateLocalId).value(QStringLiteral("remoteId")).toString();
            if (!renditionRemoteId.isEmpty()) {
                m_locationRefreshLocalId = aggregateLocalId;
                m_repository->getDocumentLocation(renditionRemoteId);
            }
        }
    }
    m_current.clear();
    processNext();
}

void RenditionSyncController::failCurrent(const QString &code,
                                          const QString &message)
{
    if (!m_busy || m_current.isEmpty())
        return;
    const QString kind = m_current.value(QStringLiteral("kind")).toString();
    const QString localId = m_current.value(QStringLiteral("localId")).toString();
    const QString aggregateLocalId = m_current.value(
        QStringLiteral("aggregateLocalId"), localId).toString();
    const QString normalized = code.toUpper();
    const bool conflict = normalized.contains(QStringLiteral("CONFLICT"))
        || normalized.contains(QStringLiteral("ROW_VERSION"));
    const bool ambiguous = normalized.contains(QStringLiteral("NETWORK"))
        || normalized.contains(QStringLiteral("INVALID_RESPONSE"))
        || normalized.contains(QStringLiteral("TIMEOUT"))
        || normalized.contains(QStringLiteral("UPLOAD"));
    QString state = conflict ? QString::fromLatin1(Conflict)
                             : QString::fromLatin1(Error);

    if (kind == QLatin1String("rendition_update")
        || kind == QLatin1String("expense_update")
        || kind == QLatin1String("expense_delete")
        || kind == QLatin1String("attachment_reserve")) {
        state = ambiguous ? QString::fromLatin1(NeedsReconciliation) : state;
    }

    if (kind == QLatin1String("attachment_reserve")) {
        const QString phase = m_current.value(
            QStringLiteral("phase"), QStringLiteral("RESERVE")).toString();
        if (conflict)
            state = QString::fromLatin1(Conflict);
        else if (phase == QLatin1String("RESERVE") || phase == QLatin1String("ERROR"))
            state = QString::fromLatin1(Error);
        else
            state = QString::fromLatin1(NeedsReconciliation);
        m_store->updateAttachmentPhase(
            aggregateLocalId,
            m_current.value(QStringLiteral("expenseLocalId")).toString(),
            localId, state,
            {{QStringLiteral("syncError"), message}});
    } else if (kind == QLatin1String("expense_create")) {
        // CREATE V02 es idempotente: ERROR conserva el mismo request/payload
        // y permite retry seguro. Un conflicto de idempotencia sí se detiene.
        state = conflict ? QString::fromLatin1(Conflict)
                         : QString::fromLatin1(Error);
        m_store->markExpenseState(aggregateLocalId, localId, state, message);
    } else if (kind.startsWith(QLatin1String("expense_"))) {
        state = conflict ? QString::fromLatin1(Conflict)
                         : QString::fromLatin1(NeedsReconciliation);
        m_store->markExpenseState(aggregateLocalId, localId, state, message);
    } else {
        m_store->markRenditionState(aggregateLocalId, state, message);
    }
    const QString renditionRemoteId = m_current.value(
        QStringLiteral("renditionRemoteId"),
        m_current.value(QStringLiteral("remoteId"))).toString();
    m_current.clear();
    setLastError(message);
    setBusy(false);
    emit syncStopped(state, message);
    if (state == QLatin1String(NeedsReconciliation)
        || state == QLatin1String(Conflict)) {
        m_repository->listRenditions(50, {}, {});
        if (!renditionRemoteId.isEmpty()) {
            m_repository->getRendition(renditionRemoteId);
            m_repository->listExpenses(renditionRemoteId);
            m_repository->getExpenseSummary(renditionRemoteId);
            m_repository->listAttachments(renditionRemoteId);
            if (m_repository->v02Enabled())
                m_repository->getDocumentLocation(renditionRemoteId);
        }
    }
}

void RenditionSyncController::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void RenditionSyncController::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}
