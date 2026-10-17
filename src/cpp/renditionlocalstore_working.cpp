// Working Document de Rendiciones (rendition_cloud_working_rows_v01, Web PR #6)
// dentro del MISMO almacén local y del MISMO outbox que el resto del dominio.
//
// Cada borrador guarda dos cosas separadas:
//   - la intención DESEADA (form + sustentos) que el usuario editó, y
//   - el intento EN VUELO (inflight: argumentos exactos del último envío).
// Si la respuesta se pierde (timeout, sin red, 5xx) el inflight se reenvía
// byte a byte con el mismo request_id: el servidor responde con su recibo o lo
// aplica; nunca se produce un conflicto CAS falso ni una doble escritura. Sólo
// después se envía la intención deseada sobre la versión confirmada.
//
// Los conflictos reales (rechazo CAS) se conservan como CONFLICT con la intención
// local intacta; nunca se sobrescribe el servidor en silencio.
#include "renditionlocalstore.h"

#include "renditionconnectivity.h"
#include "renditioncontract.h"
#include "renditionvalidation.h"
#include "renditionworkingcontract.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QUrl>
#include <QUuid>

#include <iterator>

namespace W = RenditionWorkingContract;

namespace {
constexpr auto PendingUpdate = "PENDING_UPDATE";
constexpr auto Syncing = "SYNCING";
constexpr auto Synced = "SYNCED";
constexpr auto Conflict = "CONFLICT";
constexpr auto Error = "ERROR";
constexpr auto LocalOnly = "LOCAL_ONLY";

QString hashOf(const QVariant &value)
{
    // Firma por VALOR (claves ordenadas por QJsonDocument): no depende del orden de inserción.
    return QString::fromLatin1(QCryptographicHash::hash(
        QJsonDocument::fromVariant(value).toJson(QJsonDocument::Compact),
        QCryptographicHash::Sha256).toHex());
}
bool retryable(const QVariantMap &entry)
{
    const QString state = entry.value(QStringLiteral("state")).toString();
    return state == QLatin1String(PendingUpdate) || state == QLatin1String("PENDING_CREATE")
        || (state == QLatin1String(Error)
            && entry.value(QStringLiteral("lastSafeError")).toString() == RenditionConnectivity::transportMarker());
}
QString isoNow() { return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs); }
}

int RenditionLocalStore::workingIndex(const QString &workingId) const
{
    for (int i = 0; i < m_workingRows.size(); ++i)
        if (m_workingRows.at(i).toMap().value(QStringLiteral("id")).toString() == workingId)
            return i;
    return -1;
}

QVariantMap RenditionLocalStore::workingRow(const QString &workingId) const
{
    const int index = workingIndex(workingId);
    return index < 0 ? QVariantMap{} : m_workingRows.at(index).toMap();
}

QVariantMap RenditionLocalStore::workingDocument(const QVariantMap &row) const
{
    return W::payload(row.value(QStringLiteral("form")).toMap(), row.value(QStringLiteral("baseline")).toMap(),
                      row.value(QStringLiteral("sources")).toList(),
                      row.value(QStringLiteral("expenseRequestId")).toString());
}

static bool activeRow(const QVariantMap &row)
{
    const QString cloud = row.value(QStringLiteral("cloudState")).toString();
    return cloud != QLatin1String("PROMOTED") && cloud != QLatin1String("ARCHIVED");
}

int RenditionLocalStore::activeWorkingCount(const QString &renditionLocalId) const
{
    int count = 0;
    for (const auto &value : m_workingRows) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("renditionLocalId")).toString() == renditionLocalId && activeRow(row)) ++count;
    }
    return count;
}

int RenditionLocalStore::workingConflictCount(const QString &renditionLocalId) const
{
    int count = 0;
    for (const auto &value : m_workingRows) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("renditionLocalId")).toString() == renditionLocalId && activeRow(row)
            && row.value(QStringLiteral("syncState")).toString() == QLatin1String(Conflict)) ++count;
    }
    return count;
}

QStringList RenditionLocalStore::promotedWorkingIds(const QString &renditionLocalId) const
{
    QStringList ids;
    for (const auto &value : m_workingRows) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("renditionLocalId")).toString() == renditionLocalId
            && row.value(QStringLiteral("cloudState")).toString() == QLatin1String("PROMOTED"))
            ids.append(row.value(QStringLiteral("id")).toString());
    }
    return ids;
}

// Vista para la UI: sólo borradores activos, sin rutas locales ni URLs.
QVariantList RenditionLocalStore::workingRowsFor(const QString &renditionLocalId) const
{
    QVariantList out;
    for (const auto &value : m_workingRows) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("renditionLocalId")).toString() != renditionLocalId || !activeRow(row)) continue;
        const auto files = row.value(QStringLiteral("sourceFiles")).toMap();
        const auto ready = row.value(QStringLiteral("readySourceIds")).toStringList();
        int missing = 0, waiting = 0;
        QVariantList sources;
        for (const auto &s : row.value(QStringLiteral("sources")).toList()) {
            auto source = s.toMap();
            const QString id = source.value(QStringLiteral("id")).toString();
            const bool isReady = ready.contains(id);
            const bool hasBytes = files.contains(id) && QFileInfo::exists(files.value(id).toString());
            source.insert(QStringLiteral("ready"), isReady);
            source.insert(QStringLiteral("local"), hasBytes);
            // Bytes que nunca llegaron al servidor desde otro dispositivo: no se pueden recrear.
            if (!isReady && !hasBytes) ++missing;
            else if (!isReady) ++waiting;
            sources.append(source);
        }
        QVariantMap view{
            {QStringLiteral("id"), row.value(QStringLiteral("id"))},
            {QStringLiteral("kind"), row.value(QStringLiteral("kind"))},
            {QStringLiteral("expenseLocalId"), row.value(QStringLiteral("expenseLocalId"))},
            {QStringLiteral("expenseId"), row.value(QStringLiteral("expenseId"))},
            {QStringLiteral("form"), row.value(QStringLiteral("form"))},
            {QStringLiteral("sources"), sources},
            {QStringLiteral("missingSources"), missing},
            {QStringLiteral("waitingSources"), waiting},
            {QStringLiteral("cloudVersion"), row.value(QStringLiteral("cloudVersion"))},
            {QStringLiteral("inCloud"), row.value(QStringLiteral("cloudVersion")).toLongLong() > 0},
            {QStringLiteral("syncState"), row.value(QStringLiteral("syncState"))},
            {QStringLiteral("syncError"), row.value(QStringLiteral("syncError"))},
            {QStringLiteral("promoteRequested"), row.value(QStringLiteral("promoteRequested")).toBool()},
            {QStringLiteral("archiveRequested"), row.value(QStringLiteral("archiveRequested")).toBool()},
            {QStringLiteral("serverSnapshot"), row.value(QStringLiteral("serverSnapshot"))},
            {QStringLiteral("updatedAt"), row.value(QStringLiteral("updatedAt"))}};
        out.append(view);
    }
    return out;
}

QString RenditionLocalStore::saveWorkingDraft(const QString &renditionLocalId, const QString &workingId,
                                              const QVariantMap &form, const QVariantList &files,
                                              const QString &expenseLocalId)
{
    const QVariantMap draft = rendition(renditionLocalId);
    if (!assertDraftStatus(draft)) return {};
    int index = workingId.isEmpty() ? -1 : workingIndex(workingId);
    if (!workingId.isEmpty() && index < 0) { setLastError(QStringLiteral("El borrador ya no existe en este equipo.")); return {}; }
    QVariantMap row = index >= 0 ? m_workingRows.at(index).toMap() : QVariantMap{};
    if (index >= 0) {
        if (!activeRow(row)) { setLastError(QStringLiteral("El borrador ya fue registrado o descartado.")); return {}; }
        if (row.value(QStringLiteral("promoteRequested")).toBool() || row.value(QStringLiteral("archiveRequested")).toBool()) {
            setLastError(QStringLiteral("El borrador está en registro o descarte; espera la confirmación del servidor.")); return {};
        }
    } else {
        // Nuevo borrador. EDIT parte de un gasto ya confirmado por el servidor.
        const QString id = W::newUuid();
        row.insert(QStringLiteral("id"), id);
        row.insert(QStringLiteral("renditionLocalId"), renditionLocalId);
        row.insert(QStringLiteral("expenseRequestId"), W::newUuid());   // identidad financiera estable
        row.insert(QStringLiteral("cloudVersion"), 0);
        row.insert(QStringLiteral("cloudState"), QString());
        row.insert(QStringLiteral("sources"), QVariantList{});
        row.insert(QStringLiteral("sourceFiles"), QVariantMap{});
        row.insert(QStringLiteral("readySourceIds"), QStringList{});
        row.insert(QStringLiteral("createdAt"), isoNow());
        QVariantMap baseline = W::formFrom({});
        if (!expenseLocalId.isEmpty()) {
            QVariantMap expense;
            for (const auto &entry : draft.value(QStringLiteral("expenses")).toList())
                if (entry.toMap().value(QStringLiteral("localId")).toString() == expenseLocalId) expense = entry.toMap();
            if (expense.isEmpty() || expense.value(QStringLiteral("remoteId")).toString().isEmpty()
                || expense.value(QStringLiteral("rowVersion")).toLongLong() < 1) {
                setLastError(QStringLiteral("El gasto aún no está confirmado por el servidor."));
                return {};
            }
            row.insert(QStringLiteral("kind"), QStringLiteral("EDIT"));
            row.insert(QStringLiteral("expenseLocalId"), expenseLocalId);
            row.insert(QStringLiteral("expenseId"), expense.value(QStringLiteral("remoteId")));
            row.insert(QStringLiteral("expenseRowVersion"), expense.value(QStringLiteral("rowVersion")));
            baseline = W::formFrom(expense);
        } else {
            row.insert(QStringLiteral("kind"), QStringLiteral("NEW"));
        }
        row.insert(QStringLiteral("baseline"), baseline);
    }
    const QString id = row.value(QStringLiteral("id")).toString();
    const QVariantMap normalizedForm = W::formFrom(form);
    if (!W::validateForm(normalizedForm).isEmpty()) {
        setLastError(QStringLiteral("Un campo del borrador supera el tamaño permitido."));
        return {};
    }

    // Sustentos: se conservan los existentes indicados y se materializan los nuevos
    // en un mirror persistente (los permisos de URI del selector no sobreviven).
    QVariantList previous = row.value(QStringLiteral("sources")).toList();
    QVariantMap sourceFiles = row.value(QStringLiteral("sourceFiles")).toMap();
    QVariantList sources;
    QStringList keep;
    for (const auto &value : files) {
        const auto file = value.toMap();
        const QString existing = file.value(QStringLiteral("id")).toString();
        if (!existing.isEmpty()) { keep.append(existing); continue; }
    }
    for (const auto &value : previous)
        if (keep.contains(value.toMap().value(QStringLiteral("id")).toString())) sources.append(value);
    for (const auto &value : files) {
        const auto file = value.toMap();
        if (!file.value(QStringLiteral("id")).toString().isEmpty()) continue;
        const qint64 size = file.value(QStringLiteral("sizeBytes")).toLongLong();
        const QUrl url(file.value(QStringLiteral("localUri")).toString());
        QFile input(url.isLocalFile() ? url.toLocalFile() : file.value(QStringLiteral("localUri")).toString());
        if (size <= 0 || size > W::MaxFileBytes || !input.open(QIODevice::ReadOnly) || input.size() != size) {
            setLastError(QStringLiteral("No se pudo conservar un sustento (inexistente o mayor a 20 MiB)."));
            return {};
        }
        const QByteArray bytes = input.readAll();
        const QString sha = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
        bool duplicate = false;
        for (const auto &s : sources) duplicate |= s.toMap().value(QStringLiteral("contentHash")).toString() == sha;
        if (duplicate) continue;                           // mismo comprobante: sin duplicados
        const QString sourceId = W::newUuid();
        const QString name = QFileInfo(file.value(QStringLiteral("fileName")).toString()).fileName().trimmed();
        if (name.isEmpty() || name == QLatin1String(".") || name == QLatin1String("..")) {
            setLastError(QStringLiteral("El sustento no tiene un nombre válido.")); return {};
        }
        const QString dir = storagePath() + QStringLiteral(".working/") + id + QLatin1Char('/') + sourceId;
        if (!QDir().mkpath(dir)) { setLastError(QStringLiteral("No se pudo preparar el sustento para uso offline.")); return {}; }
        const QString mirrorPath = QDir(dir).filePath(name);
        QSaveFile mirror(mirrorPath);
        if (!mirror.open(QIODevice::WriteOnly) || mirror.write(bytes) != bytes.size() || !mirror.commit()) {
            setLastError(QStringLiteral("No se pudo guardar el sustento para uso offline.")); return {};
        }
        const QString mime = file.value(QStringLiteral("mimeType")).toString().trimmed().toLower();
        QVariantMap source{{QStringLiteral("id"), sourceId}, {QStringLiteral("name"), name},
                           {QStringLiteral("size"), size},
                           {QStringLiteral("lastModified"), qMax<qint64>(0, QFileInfo(mirrorPath).lastModified().toMSecsSinceEpoch())},
                           {QStringLiteral("type"), mime.isEmpty() ? QStringLiteral("application/octet-stream") : mime},
                           {QStringLiteral("uploadRequestId"), W::newUuid()},
                           {QStringLiteral("contentHash"), sha}};
        sources.append(source);
        sourceFiles.insert(sourceId, mirrorPath);
    }
    if (sources.size() > W::MaxSources) { setLastError(QStringLiteral("Máximo 100 sustentos por borrador.")); return {}; }
    for (auto it = sourceFiles.begin(); it != sourceFiles.end();) {
        bool used = false;
        for (const auto &s : sources) used |= s.toMap().value(QStringLiteral("id")).toString() == it.key();
        it = used ? std::next(it) : sourceFiles.erase(it);
    }
    row.insert(QStringLiteral("form"), normalizedForm);
    row.insert(QStringLiteral("sources"), sources);
    row.insert(QStringLiteral("sourceFiles"), sourceFiles);
    const QVariantMap document = workingDocument(row);
    const QString invalid = W::validatePayload(document);
    if (!invalid.isEmpty()) { setLastError(QStringLiteral("El borrador no cumple el contrato del servidor (") + invalid + QLatin1Char(')')); return {}; }

    const bool conflicted = row.value(QStringLiteral("syncState")).toString() == QLatin1String(Conflict);
    const QString desiredHash = hashOf(document);
    row.insert(QStringLiteral("desiredHash"), desiredHash);
    row.insert(QStringLiteral("updatedAt"), isoNow());
    if (!conflicted) {
        row.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
        row.remove(QStringLiteral("syncError"));
    }
    const int existingOp = outboxIndex(QStringLiteral("working_save"), renditionLocalId, id);
    const QVariantMap oldEntry = existingOp >= 0 ? m_outbox.at(existingOp).toMap() : QVariantMap{};
    // request_id del guardado: estable mientras la intención no cambia (reintentos).
    const QString requestId = oldEntry.value(QStringLiteral("payloadHash")).toString().isEmpty()
            || oldEntry.value(QStringLiteral("payload")).toMap().value(QStringLiteral("desiredHash")) != desiredHash
        ? W::newUuid() : oldEntry.value(QStringLiteral("requestId")).toString();

    const auto oldRows = m_workingRows; const auto oldOutbox = m_outbox;
    if (index >= 0) m_workingRows[index] = row; else m_workingRows.append(row);
    upsertOutbox(QStringLiteral("working_save"), renditionLocalId, draft.value(QStringLiteral("remoteId")).toString(), id,
                 requestId, {{QStringLiteral("desiredHash"), desiredHash}},
                 conflicted ? QString::fromLatin1(Conflict) : QString::fromLatin1(PendingUpdate));
    if (!persist()) { m_workingRows = oldRows; m_outbox = oldOutbox; return {}; }
    return id;
}

bool RenditionLocalStore::requestWorkingPromotion(const QString &renditionLocalId, const QString &workingId)
{
    const QVariantMap draft = rendition(renditionLocalId);
    if (!assertDraftStatus(draft)) return false;
    const int index = workingIndex(workingId);
    if (index < 0) { setLastError(QStringLiteral("El borrador ya no existe en este equipo.")); return false; }
    QVariantMap row = m_workingRows.at(index).toMap();
    if (!activeRow(row)) { setLastError(QStringLiteral("El borrador ya fue registrado o descartado.")); return false; }
    if (row.value(QStringLiteral("syncState")).toString() == QLatin1String(Conflict)) {
        setLastError(QStringLiteral("Resuelve el conflicto del borrador antes de registrarlo.")); return false;
    }
    // Mismas validaciones del gasto que el alta normal (sin IA ni autocompletado).
    const QString invalid = RenditionValidation::expense(draft, row.value(QStringLiteral("form")).toMap());
    if (!invalid.isEmpty()) { setLastError(invalid); return false; }
    const auto files = row.value(QStringLiteral("sourceFiles")).toMap();
    const auto ready = row.value(QStringLiteral("readySourceIds")).toStringList();
    int missing = 0;
    for (const auto &s : row.value(QStringLiteral("sources")).toList()) {
        const QString id = s.toMap().value(QStringLiteral("id")).toString();
        if (!ready.contains(id) && !(files.contains(id) && QFileInfo::exists(files.value(id).toString()))) ++missing;
    }
    if (missing > 0) {
        setLastError(QStringLiteral("Faltan %1 sustentos por volver a adjuntar en este equipo.").arg(missing));
        return false;
    }
    const auto oldRows = m_workingRows; const auto oldOutbox = m_outbox;
    row.insert(QStringLiteral("promoteRequested"), true);
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
    row.remove(QStringLiteral("syncError"));
    row.insert(QStringLiteral("updatedAt"), isoNow());
    m_workingRows[index] = row;
    upsertOutbox(QStringLiteral("working_promote"), renditionLocalId, draft.value(QStringLiteral("remoteId")).toString(),
                 workingId, W::newUuid(), {{QStringLiteral("workingId"), workingId}}, QString::fromLatin1(PendingUpdate));
    if (!persist()) { m_workingRows = oldRows; m_outbox = oldOutbox; return false; }
    return true;
}

bool RenditionLocalStore::requestWorkingArchive(const QString &renditionLocalId, const QString &workingId)
{
    const QVariantMap draft = rendition(renditionLocalId);
    if (!assertDraftStatus(draft)) return false;
    const int index = workingIndex(workingId);
    if (index < 0) return true;                            // ya no existe: idempotente
    QVariantMap row = m_workingRows.at(index).toMap();
    if (!activeRow(row)) return true;
    if (row.value(QStringLiteral("promoteRequested")).toBool()) {
        setLastError(QStringLiteral("El borrador ya se está registrando como gasto.")); return false;
    }
    const auto oldRows = m_workingRows; const auto oldOutbox = m_outbox;
    const bool reachedServer = row.value(QStringLiteral("cloudVersion")).toLongLong() > 0
        || row.contains(QStringLiteral("inflight"));
    if (!reachedServer) {
        // Nunca llegó al servidor: se descarta sólo en este equipo.
        for (int i = m_outbox.size() - 1; i >= 0; --i) {
            const auto entry = m_outbox.at(i).toMap();
            if (entry.value(QStringLiteral("childLocalId")).toString() == workingId
                && entry.value(QStringLiteral("operation")).toString().startsWith(QLatin1String("working_")))
                m_outbox.removeAt(i);
        }
        m_workingRows.removeAt(index);
        if (!persist()) { m_workingRows = oldRows; m_outbox = oldOutbox; return false; }
        QDir(storagePath() + QStringLiteral(".working/") + workingId).removeRecursively();
        return true;
    }
    row.insert(QStringLiteral("archiveRequested"), true);
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
    row.remove(QStringLiteral("syncError"));
    m_workingRows[index] = row;
    // Una intención no enviada se descarta; un envío en vuelo se confirma antes de archivar.
    if (!row.contains(QStringLiteral("inflight")))
        markOutboxState(QStringLiteral("working_save"), renditionLocalId, workingId, QString::fromLatin1(Synced));
    upsertOutbox(QStringLiteral("working_archive"), renditionLocalId, draft.value(QStringLiteral("remoteId")).toString(),
                 workingId, W::newUuid(), {{QStringLiteral("workingId"), workingId}}, QString::fromLatin1(PendingUpdate));
    if (!persist()) { m_workingRows = oldRows; m_outbox = oldOutbox; return false; }
    return true;
}

bool RenditionLocalStore::resolveWorkingConflict(const QString &renditionLocalId, const QString &workingId,
                                                 bool keepLocal, const QVariantMap &serverRow)
{
    const QVariantMap draft = rendition(renditionLocalId);
    const int index = workingIndex(workingId);
    if (draft.isEmpty() || index < 0) { setLastError(QStringLiteral("El borrador ya no existe en este equipo.")); return false; }
    const auto record = W::normalize(serverRow, draft.value(QStringLiteral("remoteId")).toString());
    if (!record.error.isEmpty() || record.id != workingId) {
        setLastError(QStringLiteral("La versión del servidor no corresponde a este borrador.")); return false;
    }
    QVariantMap row = m_workingRows.at(index).toMap();
    const auto oldRows = m_workingRows; const auto oldOutbox = m_outbox;
    row.remove(QStringLiteral("inflight"));
    row.remove(QStringLiteral("serverSnapshot"));
    row.remove(QStringLiteral("syncError"));
    row.insert(QStringLiteral("cloudVersion"), record.rowVersion);
    row.insert(QStringLiteral("cloudState"), record.state);
    row.insert(QStringLiteral("readySourceIds"), record.readySourceIds);
    if (!keepLocal || record.state != QLatin1String("ACTIVE")) {
        // Usar la versión del servidor: la intención local se descarta explícitamente.
        row.insert(QStringLiteral("form"), record.form);
        row.insert(QStringLiteral("baseline"), record.baseline);
        row.insert(QStringLiteral("sources"), record.sources);
        row.insert(QStringLiteral("expenseRequestId"), record.expenseRequestId);
        row.insert(QStringLiteral("expenseId"), record.expenseId);
        row.insert(QStringLiteral("expenseRowVersion"), record.expenseRowVersion);
        const QString synced = hashOf(workingDocument(row));
        row.insert(QStringLiteral("syncedHash"), synced);
        row.insert(QStringLiteral("desiredHash"), synced);
        row.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
        for (const auto &operation : {QStringLiteral("working_save"), QStringLiteral("working_promote"), QStringLiteral("working_archive")})
            markOutboxState(operation, renditionLocalId, workingId, QString::fromLatin1(Synced));
    } else {
        // Aplicar mis cambios sobre la versión vigente: CAS con la versión del servidor
        // y, en EDIT, con la versión actual del gasto base.
        if (row.value(QStringLiteral("kind")).toString() == QLatin1String("EDIT")) {
            for (const auto &entry : draft.value(QStringLiteral("expenses")).toList())
                if (entry.toMap().value(QStringLiteral("remoteId")) == row.value(QStringLiteral("expenseId")))
                    row.insert(QStringLiteral("expenseRowVersion"), entry.toMap().value(QStringLiteral("rowVersion")));
        }
        row.insert(QStringLiteral("syncedHash"), QString());
        row.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingUpdate));
        upsertOutbox(QStringLiteral("working_save"), renditionLocalId, draft.value(QStringLiteral("remoteId")).toString(),
                     workingId, W::newUuid(), {{QStringLiteral("desiredHash"), row.value(QStringLiteral("desiredHash"))}},
                     QString::fromLatin1(PendingUpdate));
    }
    m_workingRows[index] = row;
    if (!persist()) { m_workingRows = oldRows; m_outbox = oldOutbox; return false; }
    return true;
}

void RenditionLocalStore::mergeRemoteWorkingRows(const QString &renditionLocalId, const QVariantList &rows)
{
    const QVariantMap draft = rendition(renditionLocalId);
    const QString remote = draft.value(QStringLiteral("remoteId")).toString();
    if (draft.isEmpty() || remote.isEmpty()) return;
    bool changed = false;
    for (const auto &value : rows) {
        const auto record = W::normalize(value, remote);
        if (!record.error.isEmpty()) continue;               // fuera de contrato: no se adivina
        const int index = workingIndex(record.id);
        if (index < 0) {
            if (record.state != QLatin1String("ACTIVE")) continue;
            // Borrador creado en otra sesión/dispositivo: metadatos y sustentos del servidor.
            QVariantMap row{{QStringLiteral("id"), record.id}, {QStringLiteral("renditionLocalId"), renditionLocalId},
                {QStringLiteral("kind"), record.kind}, {QStringLiteral("expenseId"), record.expenseId},
                {QStringLiteral("expenseRowVersion"), record.expenseRowVersion},
                {QStringLiteral("form"), record.form}, {QStringLiteral("baseline"), record.baseline},
                {QStringLiteral("sources"), record.sources}, {QStringLiteral("sourceFiles"), QVariantMap{}},
                {QStringLiteral("readySourceIds"), record.readySourceIds},
                {QStringLiteral("expenseRequestId"), record.expenseRequestId},
                {QStringLiteral("cloudVersion"), record.rowVersion}, {QStringLiteral("cloudState"), record.state},
                {QStringLiteral("syncState"), QString::fromLatin1(Synced)}, {QStringLiteral("origin"), QStringLiteral("REMOTE")},
                {QStringLiteral("createdAt"), isoNow()}, {QStringLiteral("updatedAt"), record.updatedAt}};
            if (!record.expenseId.isEmpty()) {
                for (const auto &entry : draft.value(QStringLiteral("expenses")).toList())
                    if (entry.toMap().value(QStringLiteral("remoteId")).toString() == record.expenseId)
                        row.insert(QStringLiteral("expenseLocalId"), entry.toMap().value(QStringLiteral("localId")));
            }
            const QString hash = hashOf(workingDocument(row));
            row.insert(QStringLiteral("syncedHash"), hash);
            row.insert(QStringLiteral("desiredHash"), hash);
            m_workingRows.append(row);
            changed = true;
            continue;
        }
        QVariantMap row = m_workingRows.at(index).toMap();
        const bool pending = row.value(QStringLiteral("desiredHash")) != row.value(QStringLiteral("syncedHash"))
            || row.contains(QStringLiteral("inflight")) || row.value(QStringLiteral("promoteRequested")).toBool()
            || row.value(QStringLiteral("archiveRequested")).toBool();
        // Una respuesta tardía nunca retrocede una versión ya confirmada.
        if (record.rowVersion < row.value(QStringLiteral("cloudVersion")).toLongLong()) continue;
        if (!pending && row.value(QStringLiteral("syncState")).toString() != QLatin1String(Conflict)) {
            row.insert(QStringLiteral("form"), record.form);
            row.insert(QStringLiteral("baseline"), record.baseline);
            row.insert(QStringLiteral("sources"), record.sources);
            row.insert(QStringLiteral("readySourceIds"), record.readySourceIds);
            row.insert(QStringLiteral("cloudVersion"), record.rowVersion);
            row.insert(QStringLiteral("cloudState"), record.state);
            row.insert(QStringLiteral("expenseRowVersion"), record.expenseRowVersion);
            const QString hash = hashOf(workingDocument(row));
            row.insert(QStringLiteral("syncedHash"), hash);
            row.insert(QStringLiteral("desiredHash"), hash);
            row.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
        } else if (record.rowVersion > row.value(QStringLiteral("cloudVersion")).toLongLong()
                   || record.state != QLatin1String("ACTIVE")) {
            // Cambió en otra sesión mientras hay cambios locales: sombra del servidor
            // para el panel de conflicto; el CAS del guardado decide.
            row.insert(QStringLiteral("serverSnapshot"), value.toMap());
            if (record.state != QLatin1String("ACTIVE") && !row.value(QStringLiteral("promoteRequested")).toBool()
                && !row.value(QStringLiteral("archiveRequested")).toBool()) {
                row.insert(QStringLiteral("syncState"), QString::fromLatin1(Conflict));
                row.insert(QStringLiteral("syncError"), QStringLiteral("Este borrador fue registrado o descartado en otra sesión mientras tenías cambios."));
                markOutboxState(QStringLiteral("working_save"), renditionLocalId, record.id, QString::fromLatin1(Conflict));
            }
        }
        m_workingRows[index] = row;
        changed = true;
    }
    if (changed) persist();
}

// ------------------------------------------------------------- Cola (outbox)
QVariantMap RenditionLocalStore::workingOperation(const QVariantMap &entry) const
{
    const QString operation = entry.value(QStringLiteral("operation")).toString();
    const QString workingId = entry.value(QStringLiteral("childLocalId")).toString();
    const QString aggregate = entry.value(QStringLiteral("aggregateLocalId")).toString();
    const QVariantMap row = workingRow(workingId);
    const QVariantMap draft = rendition(aggregate);
    const QString remote = draft.value(QStringLiteral("remoteId")).toString();
    if (row.isEmpty() || draft.isEmpty() || remote.isEmpty() || !retryable(entry)
        || !RenditionContract::canEditWorkingCopy(draft))
        return {};
    QVariantMap op{{QStringLiteral("kind"), operation}, {QStringLiteral("localId"), workingId},
                   {QStringLiteral("workingId"), workingId}, {QStringLiteral("aggregateLocalId"), aggregate},
                   {QStringLiteral("renditionRemoteId"), remote}, {QStringLiteral("requestId"), entry.value(QStringLiteral("requestId"))}};
    const bool inflight = row.contains(QStringLiteral("inflight"));
    const auto pendingSources = workingPendingSources(workingId);
    if (operation == QLatin1String("working_save")) {
        if (row.value(QStringLiteral("archiveRequested")).toBool() && !inflight) return {};
        QVariantMap args;
        if (inflight) {
            args = row.value(QStringLiteral("inflight")).toMap();        // replay exacto
        } else if (row.value(QStringLiteral("desiredHash")) != row.value(QStringLiteral("syncedHash"))) {
            args = W::saveArguments(remote, workingId, row.value(QStringLiteral("cloudVersion")).toLongLong(),
                                    entry.value(QStringLiteral("requestId")).toString(), workingDocument(row),
                                    row.value(QStringLiteral("expenseId")).toString(),
                                    row.value(QStringLiteral("expenseRowVersion")).toLongLong());
        }
        op.insert(QStringLiteral("saveArguments"), args);
        op.insert(QStringLiteral("pendingSources"), pendingSources);
        return op;
    }
    // Promoción y archivo esperan a que el guardado y los sustentos estén confirmados.
    const int saveOp = outboxIndex(QStringLiteral("working_save"), aggregate, workingId);
    const bool saveDone = saveOp < 0 || m_outbox.at(saveOp).toMap().value(QStringLiteral("state")).toString() == QLatin1String(Synced);
    if (inflight) return {};
    if (operation == QLatin1String("working_promote")) {
        if (!saveDone || !pendingSources.isEmpty() || row.value(QStringLiteral("cloudVersion")).toLongLong() < 1) return {};
        op.insert(QStringLiteral("promoteArguments"), W::promoteArguments(workingId, row.value(QStringLiteral("cloudVersion")).toLongLong(),
                                                                         draft.value(QStringLiteral("rowVersion")).toLongLong()));
        return op;
    }
    if (operation == QLatin1String("working_archive")) {
        if (row.value(QStringLiteral("cloudVersion")).toLongLong() < 1) return {};
        op.insert(QStringLiteral("archiveArguments"), W::archiveArguments(workingId, row.value(QStringLiteral("cloudVersion")).toLongLong()));
        return op;
    }
    return {};
}

bool RenditionLocalStore::markWorkingSending(const QString &workingId, const QVariantMap &saveArguments)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    if (!saveArguments.isEmpty()) row.insert(QStringLiteral("inflight"), saveArguments);   // durable antes de enviar
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(Syncing));
    m_workingRows[index] = row;
    markOutboxState(QStringLiteral("working_save"), row.value(QStringLiteral("renditionLocalId")).toString(),
                    workingId, QString::fromLatin1(Syncing));
    return persist();
}

bool RenditionLocalStore::markWorkingSaved(const QString &workingId, const QVariantMap &serverRow)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    const QVariantMap draft = rendition(row.value(QStringLiteral("renditionLocalId")).toString());
    const auto record = W::normalize(serverRow, draft.value(QStringLiteral("remoteId")).toString());
    const QVariantMap inflight = row.value(QStringLiteral("inflight")).toMap();
    if (!record.error.isEmpty() || record.id != workingId || inflight.isEmpty()) {
        setLastError(QStringLiteral("RENDITION_INVALID_RESPONSE: el servidor no confirmó la identidad del borrador."));
        return false;
    }
    // Lo confirmado es exactamente lo enviado en el inflight.
    row.insert(QStringLiteral("syncedHash"), hashOf(inflight.value(QStringLiteral("p_payload"))));
    row.insert(QStringLiteral("cloudVersion"), record.rowVersion);
    row.insert(QStringLiteral("cloudState"), record.state);
    QStringList ready = row.value(QStringLiteral("readySourceIds")).toStringList();
    for (const auto &id : record.readySourceIds) if (!ready.contains(id)) ready.append(id);
    row.insert(QStringLiteral("readySourceIds"), ready);
    if (!record.expenseId.isEmpty()) row.insert(QStringLiteral("expenseRowVersion"), record.expenseRowVersion);
    row.remove(QStringLiteral("inflight"));
    row.remove(QStringLiteral("serverSnapshot"));
    row.remove(QStringLiteral("syncError"));
    m_workingRows[index] = row;
    return persist();
}

QVariantList RenditionLocalStore::workingPendingSources(const QString &workingId) const
{
    const QVariantMap row = workingRow(workingId);
    const auto files = row.value(QStringLiteral("sourceFiles")).toMap();
    const auto ready = row.value(QStringLiteral("readySourceIds")).toStringList();
    const auto phases = row.value(QStringLiteral("sourcePhases")).toMap();
    QVariantList out;
    for (const auto &value : row.value(QStringLiteral("sources")).toList()) {
        auto source = value.toMap();
        const QString id = source.value(QStringLiteral("id")).toString();
        if (ready.contains(id) || !files.contains(id) || !QFileInfo::exists(files.value(id).toString())) continue;
        source.insert(QStringLiteral("localUri"), files.value(id));
        source.insert(QStringLiteral("phase"), phases.value(id, QStringLiteral("RESERVE")));
        out.append(source);
    }
    return out;
}

bool RenditionLocalStore::markWorkingSourcePhase(const QString &workingId, const QString &sourceId,
                                                 const QString &phase, const QVariantMap &file)
{
    Q_UNUSED(file)
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    QVariantMap phases = row.value(QStringLiteral("sourcePhases")).toMap();
    if (phase == QLatin1String("READY")) {
        QStringList ready = row.value(QStringLiteral("readySourceIds")).toStringList();
        if (!ready.contains(sourceId)) ready.append(sourceId);
        row.insert(QStringLiteral("readySourceIds"), ready);
        phases.remove(sourceId);
    } else {
        phases.insert(sourceId, phase);
    }
    row.insert(QStringLiteral("sourcePhases"), phases);
    m_workingRows[index] = row;
    return persist();
}

bool RenditionLocalStore::finishWorkingSave(const QString &workingId)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    const QString aggregate = row.value(QStringLiteral("renditionLocalId")).toString();
    const bool done = !row.contains(QStringLiteral("inflight"))
        && row.value(QStringLiteral("desiredHash")) == row.value(QStringLiteral("syncedHash"))
        && workingPendingSources(workingId).isEmpty();
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(done && !row.value(QStringLiteral("promoteRequested")).toBool()
                                                                && !row.value(QStringLiteral("archiveRequested")).toBool()
                                                                ? Synced : PendingUpdate));
    m_workingRows[index] = row;
    markOutboxState(QStringLiteral("working_save"), aggregate, workingId,
                    QString::fromLatin1(done ? Synced : PendingUpdate));
    return persist();
}

void RenditionLocalStore::adoptOwnRenditionVersion(const QString &renditionLocalId, qint64 version)
{
    const int index = renditionIndex(renditionLocalId);
    if (index < 0 || version <= 0) return;
    auto draft = m_renditions.at(index).toMap();
    draft.insert(QStringLiteral("rowVersion"), qMax(version, draft.value(QStringLiteral("rowVersion")).toLongLong()));
    m_renditions[index] = draft;
    // Sólo intenciones nunca enviadas siguen la versión confirmada por NUESTRA escritura.
    for (int i = 0; i < m_outbox.size(); ++i) {
        auto entry = m_outbox.at(i).toMap();
        if (entry.value(QStringLiteral("aggregateLocalId")).toString() != renditionLocalId
            || entry.value(QStringLiteral("state")).toString() == QLatin1String(Synced)
            || entry.value(QStringLiteral("attempts")).toInt() != 0) continue;
        auto payload = entry.value(QStringLiteral("payload")).toMap();
        if (payload.contains(QStringLiteral("expectedRowVersion"))) payload.insert(QStringLiteral("expectedRowVersion"), draft.value(QStringLiteral("rowVersion")));
        if (payload.contains(QStringLiteral("expectedRenditionRowVersion"))) payload.insert(QStringLiteral("expectedRenditionRowVersion"), draft.value(QStringLiteral("rowVersion")));
        entry.insert(QStringLiteral("payload"), payload);
        entry.insert(QStringLiteral("payloadHash"), QString::fromLatin1(payloadHash(payload)));
        m_outbox[i] = entry;
    }
}

bool RenditionLocalStore::markWorkingPromoted(const QString &workingId, const QVariantMap &result)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    if (!W::canonicalUuid(result.value(QStringLiteral("expense_id")))
        || result.value(QStringLiteral("rendition_row_version")).toLongLong() < 1) {
        setLastError(QStringLiteral("RENDITION_INVALID_RESPONSE: el servidor no confirmó el gasto registrado."));
        return false;
    }
    QVariantMap row = m_workingRows.at(index).toMap();
    const QString aggregate = row.value(QStringLiteral("renditionLocalId")).toString();
    row.insert(QStringLiteral("cloudState"), QStringLiteral("PROMOTED"));
    row.insert(QStringLiteral("promotedExpenseId"), result.value(QStringLiteral("expense_id")));
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    row.remove(QStringLiteral("syncError"));
    row.remove(QStringLiteral("promoteRequested"));
    m_workingRows[index] = row;
    for (const auto &operation : {QStringLiteral("working_save"), QStringLiteral("working_promote")})
        markOutboxState(operation, aggregate, workingId, QString::fromLatin1(Synced));
    adoptOwnRenditionVersion(aggregate, result.value(QStringLiteral("rendition_row_version")).toLongLong());
    if (!persist()) return false;
    // Los bytes ya son sustentos del gasto en el servidor: el mirror ya no es necesario.
    QDir(storagePath() + QStringLiteral(".working/") + workingId).removeRecursively();
    return true;
}

bool RenditionLocalStore::markWorkingArchived(const QString &workingId, const QVariantMap &serverRow)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    const QString aggregate = row.value(QStringLiteral("renditionLocalId")).toString();
    if (serverRow.value(QStringLiteral("id")).toString() != workingId
        || serverRow.value(QStringLiteral("state")).toString() != QLatin1String("ARCHIVED")) {
        setLastError(QStringLiteral("RENDITION_INVALID_RESPONSE: el servidor no confirmó el descarte."));
        return false;
    }
    row.insert(QStringLiteral("cloudState"), QStringLiteral("ARCHIVED"));
    row.insert(QStringLiteral("cloudVersion"), serverRow.value(QStringLiteral("row_version")));
    row.insert(QStringLiteral("syncState"), QString::fromLatin1(Synced));
    row.remove(QStringLiteral("archiveRequested"));
    m_workingRows[index] = row;
    for (const auto &operation : {QStringLiteral("working_save"), QStringLiteral("working_archive"), QStringLiteral("working_promote")})
        markOutboxState(operation, aggregate, workingId, QString::fromLatin1(Synced));
    if (!persist()) return false;
    QDir(storagePath() + QStringLiteral(".working/") + workingId).removeRecursively();
    return true;
}

bool RenditionLocalStore::markWorkingFailed(const QString &operation, const QString &workingId,
                                            const QString &state, const QString &error)
{
    const int index = workingIndex(workingId);
    if (index < 0) return false;
    QVariantMap row = m_workingRows.at(index).toMap();
    const QString aggregate = row.value(QStringLiteral("renditionLocalId")).toString();
    const bool transport = error == RenditionConnectivity::transportMarker();
    // Rechazo definitivo: el servidor no aplicó el intento (CAS/validación);
    // un fallo de transporte conserva el inflight para reenviarlo idéntico.
    if (!transport) row.remove(QStringLiteral("inflight"));
    if (operation == QLatin1String("working_promote") && !transport) row.remove(QStringLiteral("promoteRequested"));
    if (operation == QLatin1String("working_archive") && !transport) row.remove(QStringLiteral("archiveRequested"));
    row.insert(QStringLiteral("syncState"), state);
    if (error.isEmpty()) row.remove(QStringLiteral("syncError")); else row.insert(QStringLiteral("syncError"), error);
    m_workingRows[index] = row;
    markOutboxState(operation, aggregate, workingId, state, error);
    if (operation == QLatin1String("working_promote") && state == QLatin1String(Conflict))
        markOutboxState(QStringLiteral("working_save"), aggregate, workingId, QString::fromLatin1(Conflict));
    if (state == QLatin1String(LocalOnly)) {
        // Contrato no desplegado en este entorno: el borrador queda sólo en el equipo.
        for (const auto &op : {QStringLiteral("working_save"), QStringLiteral("working_promote"), QStringLiteral("working_archive")})
            markOutboxState(op, aggregate, workingId, QString::fromLatin1(LocalOnly));
    }
    return persist();
}
