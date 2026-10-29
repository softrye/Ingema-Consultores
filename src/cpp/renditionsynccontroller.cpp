#include "renditionsynccontroller.h"

#include "renditionlocalstore.h"
#include "renditionrepository.h"
#include "renditionattachmentcontract.h"
#include "renditionconnectivity.h"
#include "renditionworkingcontract.h"
#include <QDateTime>
#include <QDebug>
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
    connect(m_repository, &RenditionRepository::financialSaved, this, &RenditionSyncController::finishCurrent);
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
    connect(m_repository, &RenditionRepository::draftTrashed,
            this, &RenditionSyncController::finishCurrent);
    connect(m_repository, &RenditionRepository::renditionArchived,
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
        if (kind.startsWith(QLatin1String("working_"))) {
            if (!operation.startsWith(QLatin1String("working_")) && operation != QLatin1String("attachment_upload"))
                return;
            if (operation == QLatin1String("working_list"))
                return;                                       // lectura del pull, no de la cola
            // El objeto aún no existe: subir y volver a confirmar (flujo Web exacto).
            if (operation == QLatin1String("working_confirm") && code == QLatin1String("RENDITION_ATTACHMENT_OBJECT_MISSING")
                && m_current.value(QStringLiteral("phase")).toString() == QLatin1String("CONFIRM")) {
                const QVariantMap source = m_current.value(QStringLiteral("source")).toMap();
                const QString workingId = m_current.value(QStringLiteral("workingId")).toString();
                m_current.insert(QStringLiteral("phase"), QStringLiteral("UPLOAD"));
                m_store->markWorkingSourcePhase(workingId, source.value(QStringLiteral("id")).toString(), QStringLiteral("UPLOAD"));
                m_repository->uploadReservedAttachment(source.value(QStringLiteral("localUri")).toString(),
                                                       QStringLiteral("project-files"),
                                                       m_current.value(QStringLiteral("storagePath")).toString(),
                                                       m_current.value(QStringLiteral("mimeType")).toString(),
                                                       source.value(QStringLiteral("uploadRequestId")).toString());
                return;
            }
            failWorking(code, message);
            return;
        }
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

    // ---- Working Document: respuestas de la cola.
    const auto isWorking = [this](const char *kind) {
        return m_busy && m_current.value(QStringLiteral("kind")).toString() == QLatin1String(kind);
    };
    connect(m_repository, &RenditionRepository::workingSaved, this, [this, isWorking](const QVariantMap &row) {
        if (!isWorking("working_save") || m_current.value(QStringLiteral("phase")) != QLatin1String("SAVE")) return;
        if (!m_store->markWorkingSaved(m_current.value(QStringLiteral("workingId")).toString(), row)) {
            failWorking(QStringLiteral("RENDITION_INVALID_RESPONSE"), m_store->lastError());
            return;
        }
        nextWorkingSource();
    });
    connect(m_repository, &RenditionRepository::workingFileReserved, this, [this, isWorking](const QVariantMap &file) {
        if (!isWorking("working_save") || m_current.value(QStringLiteral("phase")) != QLatin1String("RESERVE")) return;
        const QVariantMap source = m_current.value(QStringLiteral("source")).toMap();
        const QString workingId = m_current.value(QStringLiteral("workingId")).toString();
        // La ruta la asigna el servidor; sólo se acepta la esperada para este borrador.
        if (file.value(QStringLiteral("id")) != source.value(QStringLiteral("uploadRequestId"))
            || !RenditionWorkingContract::reservedPathValid(file, m_current.value(QStringLiteral("renditionRemoteId")).toString(), workingId)) {
            failWorking(QStringLiteral("RENDITION_WORKING_INVALID_FILE"), QStringLiteral("El servidor devolvió una reserva que no corresponde a este sustento."));
            return;
        }
        if (file.value(QStringLiteral("status")).toString() == QLatin1String("READY")) {
            m_store->markWorkingSourcePhase(workingId, source.value(QStringLiteral("id")).toString(), QStringLiteral("READY"), file);
            nextWorkingSource();
            return;
        }
        // Un intento previo pudo subir los bytes: se confirma primero.
        m_current.insert(QStringLiteral("phase"), QStringLiteral("CONFIRM"));
        m_current.insert(QStringLiteral("storagePath"), file.value(QStringLiteral("storage_path")));
        m_current.insert(QStringLiteral("mimeType"), file.value(QStringLiteral("mime_type")));
        m_store->markWorkingSourcePhase(workingId, source.value(QStringLiteral("id")).toString(), QStringLiteral("CONFIRM"));
        m_repository->confirmWorkingFile(source.value(QStringLiteral("uploadRequestId")).toString());
    });
    connect(m_repository, &RenditionRepository::attachmentUploaded, this, [this, isWorking](const QString &fileId) {
        if (!isWorking("working_save") || m_current.value(QStringLiteral("phase")) != QLatin1String("UPLOAD")) return;
        if (fileId != m_current.value(QStringLiteral("source")).toMap().value(QStringLiteral("uploadRequestId")).toString()) return;
        m_current.insert(QStringLiteral("phase"), QStringLiteral("CONFIRM_UPLOADED"));
        m_repository->confirmWorkingFile(fileId);
    });
    connect(m_repository, &RenditionRepository::workingFileConfirmed, this, [this, isWorking](const QVariantMap &file) {
        const QString phase = m_current.value(QStringLiteral("phase")).toString();
        if (!isWorking("working_save") || (phase != QLatin1String("CONFIRM") && phase != QLatin1String("CONFIRM_UPLOADED"))) return;
        const QVariantMap source = m_current.value(QStringLiteral("source")).toMap();
        if (file.value(QStringLiteral("id")) != source.value(QStringLiteral("uploadRequestId"))
            || file.value(QStringLiteral("status")).toString() != QLatin1String("READY")) {
            failWorking(QStringLiteral("RENDITION_WORKING_INVALID_FILE"), QStringLiteral("El servidor no confirmó el sustento."));
            return;
        }
        m_store->markWorkingSourcePhase(m_current.value(QStringLiteral("workingId")).toString(),
                                        source.value(QStringLiteral("id")).toString(), QStringLiteral("READY"), file);
        nextWorkingSource();
    });
    connect(m_repository, &RenditionRepository::workingPromoted, this, [this, isWorking](const QVariantMap &result) {
        if (!isWorking("working_promote")) return;
        if (!m_store->markWorkingPromoted(m_current.value(QStringLiteral("workingId")).toString(), result)) {
            failWorking(QStringLiteral("RENDITION_INVALID_RESPONSE"), m_store->lastError());
            return;
        }
        continueQueue();
    });
    connect(m_repository, &RenditionRepository::workingArchived, this, [this, isWorking](const QVariantMap &row) {
        if (!isWorking("working_archive")) return;
        if (!m_store->markWorkingArchived(m_current.value(QStringLiteral("workingId")).toString(), row)) {
            failWorking(QStringLiteral("RENDITION_INVALID_RESPONSE"), m_store->lastError());
            return;
        }
        continueQueue();
    });
}

// ------------------------------------------------------- Working Document
void RenditionSyncController::processWorking()
{
    const QString kind = m_current.value(QStringLiteral("kind")).toString();
    const QString workingId = m_current.value(QStringLiteral("workingId")).toString();
    if (kind == QLatin1String("working_save")) {
        const QVariantMap args = m_current.value(QStringLiteral("saveArguments")).toMap();
        // El intento se registra ANTES de enviarlo: si el proceso muere o la respuesta
        // se pierde, se reenvía idéntico (mismo request_id, misma versión esperada).
        if (!m_store->markWorkingSending(workingId, args)) {
            failWorking(QStringLiteral("LOCAL_PERSISTENCE_FAILED"), m_store->lastError());
            return;
        }
        if (!args.isEmpty()) {
            m_current.insert(QStringLiteral("phase"), QStringLiteral("SAVE"));
            m_repository->saveWorkingRow(args);
            return;
        }
        nextWorkingSource();
        return;
    }
    if (kind == QLatin1String("working_promote")) {
        // Promoción atómica en el servidor; un reintento devuelve el mismo resultado.
        m_current.insert(QStringLiteral("phase"), QStringLiteral("PROMOTE"));
        m_repository->promoteWorkingRow(m_current.value(QStringLiteral("promoteArguments")).toMap());
        return;
    }
    if (kind == QLatin1String("working_archive")) {
        m_current.insert(QStringLiteral("phase"), QStringLiteral("ARCHIVE"));
        m_repository->archiveWorkingRow(m_current.value(QStringLiteral("archiveArguments")).toMap());
        return;
    }
    failWorking(QStringLiteral("UNKNOWN_OPERATION"), QStringLiteral("Operación de borrador desconocida."));
}

void RenditionSyncController::nextWorkingSource()
{
    const QString workingId = m_current.value(QStringLiteral("workingId")).toString();
    const QVariantList sources = m_store->workingPendingSources(workingId);
    if (sources.isEmpty()) {
        m_store->finishWorkingSave(workingId);
        continueQueue();
        return;
    }
    const QVariantMap source = sources.constFirst().toMap();
    m_current.insert(QStringLiteral("source"), source);
    m_current.insert(QStringLiteral("phase"), QStringLiteral("RESERVE"));
    // Reserva idempotente (renueva la concesión con la misma identidad y ruta).
    m_repository->reserveWorkingFile(RenditionWorkingContract::reserveArguments(workingId, source));
}

void RenditionSyncController::continueQueue()
{
    m_current.clear();
    processNext();
}

void RenditionSyncController::failWorking(const QString &code, const QString &message)
{
    if (!m_busy || m_current.isEmpty())
        return;
    const QString kind = m_current.value(QStringLiteral("kind")).toString();
    const QString workingId = m_current.value(QStringLiteral("workingId")).toString();
    const QString normalized = code.toUpper();
    if (RenditionConnectivity::isTransportFailure(normalized) || normalized == QLatin1String("AUTH_REQUIRED")) {
        // Sin servidor: el intento queda en vuelo y se reenviará idéntico. Silencioso.
        qInfo() << "INGE_RENDITIONS_SYNC working_transport_retry" << kind << normalized;
        m_store->markWorkingFailed(kind, workingId, QStringLiteral("ERROR"), RenditionConnectivity::transportMarker());
        m_current.clear();
        setBusy(false);
        emit syncStopped(QStringLiteral("ERROR"), code, QString());
        return;
    }
    if (normalized == QLatin1String("PGRST202")) {
        // Contrato Working no desplegado en este entorno: nada se escribe; el borrador
        // se conserva sólo en este equipo.
        m_store->markWorkingFailed(kind, workingId, QStringLiteral("LOCAL_ONLY"), QString());
        emit workingContractMissing();
        continueQueue();
        return;
    }
    if (RenditionWorkingContract::conflict(normalized)) {
        // Conflicto CAS REAL de esta fila: se conserva la intención local; la
        // resolución es explícita (panel de conflicto). Las demás filas siguen.
        m_store->markWorkingFailed(kind, workingId, QStringLiteral("CONFLICT"), RenditionWorkingContract::message(normalized));
        continueQueue();
        return;
    }
    // Rechazo definitivo del servidor (validación, permisos, sustentos pendientes,
    // versión de la rendición): visible en la fila, sin reintento automático.
    const QString text = RenditionWorkingContract::message(normalized).isEmpty()
        ? message : RenditionWorkingContract::message(normalized);
    m_store->markWorkingFailed(kind, workingId, QStringLiteral("ERROR"), text.isEmpty() ? normalized : text);
    continueQueue();
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

    if (kind.startsWith(QLatin1String("working_"))) {
        processWorking();
        return;
    }
    if (kind=="funding_set" || kind=="exchange_set") {
        if (!m_store->markFinancialState(aggregateLocalId,kind,m_current.value("requestId").toString(),"SYNCING")) {
            failCurrent("LOCAL_PERSISTENCE_FAILED",m_store->lastError());return;
        }
        m_repository->setFinancial(kind,m_current);return;
    }
    if (kind == QLatin1String("rendition_delete")) {
        if (!m_store->markRenditionSyncing(aggregateLocalId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        m_repository->deleteDraft(m_current.value(QStringLiteral("remoteId")).toString(),
                                  m_current.value(QStringLiteral("expectedRowVersion")).toLongLong());
        return;
    }
    if (kind == QLatin1String("rendition_trash") || kind == QLatin1String("rendition_archive")) {
        if (!m_store->markRenditionSyncing(aggregateLocalId)) { failCurrent("LOCAL_PERSISTENCE_FAILED", m_store->lastError()); return; }
        const auto remoteId=m_current.value(QStringLiteral("remoteId")).toString();
        const auto version=m_current.value(QStringLiteral("expectedRowVersion")).toLongLong();
        const auto requestId=m_current.value(QStringLiteral("requestId")).toString();
        if (kind == QLatin1String("rendition_archive")) m_repository->archiveRendition(remoteId,version,requestId);
        else m_repository->trashDraft(remoteId,version,requestId);
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
            m_current.value(QStringLiteral("documentParentNodeId")).toString(),
            m_current.value(QStringLiteral("displayName")).toString());
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

    if (kind=="funding_set" || kind=="exchange_set") {
        if (!m_store->markFinancialSynced(aggregateLocalId,kind,m_current.value("requestId").toString(),remote)) {
            failCurrent("INVALID_RESPONSE",m_store->lastError());return;
        }
    } else if (kind == QLatin1String("rendition_delete")) {
        if (!m_store->markDraftDeleted(aggregateLocalId, remote)) { failCurrent("INVALID_RESPONSE", m_store->lastError()); return; }
    } else if (kind == QLatin1String("rendition_trash")) {
        if (!m_store->markDraftTrashed(aggregateLocalId, remote)) { failCurrent("INVALID_RESPONSE", m_store->lastError()); return; }
    } else if (kind == QLatin1String("rendition_archive")) {
        if (!m_store->markRenditionArchived(aggregateLocalId, remote)) { failCurrent("INVALID_RESPONSE", m_store->lastError()); return; }
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
    // Sin respuesta del servidor (sin red, timeout, 5xx): NO es un conflicto ni un
    // error de datos. La operación conserva su intención (mismo request_id/CAS) y su
    // estado de reintento/reconciliación, sin texto visible: lo comunica el aura.
    // Sesión expirada (401): el servidor no ejecutó la operación; espera intacta a
    // que se renueve la sesión. No es un rechazo de datos: sin texto en la ficha
    // (lo comunica el aura y el panel "Estado de Rendiciones").
    const bool authWait = normalized == QLatin1String("AUTH_REQUIRED")
        || normalized == QLatin1String("HTTP_401");
    const bool transport = RenditionConnectivity::isTransportFailure(normalized) || authWait;
    const bool conflict = !transport
        && (normalized.contains(QStringLiteral("CONFLICT"))
            || normalized.contains(QStringLiteral("ROW_VERSION")));
    const bool ambiguous = transport
        || normalized.contains(QStringLiteral("INVALID_RESPONSE"))
        || normalized.contains(QStringLiteral("UPLOAD"));
    const QString shown = transport ? RenditionConnectivity::transportMarker() : message;
    if (transport)
        qInfo() << "INGE_RENDITIONS_SYNC transport_retry" << kind << normalized;
    QString state = conflict ? QString::fromLatin1(Conflict)
                             : QString::fromLatin1(Error);

    if (kind == QLatin1String("rendition_update")
        || kind == QLatin1String("expense_update")
        || kind == QLatin1String("expense_delete")
        || kind == QLatin1String("attachment_reserve")) {
        state = ambiguous ? QString::fromLatin1(NeedsReconciliation) : state;
    }


    if (kind=="funding_set" || kind=="exchange_set") {
        // Both financial RPCs deduplicate BEFORE CAS. Ambiguous failures replay
        // the original request, not a rebased or newly generated intention.
        state=conflict ? QString::fromLatin1(Conflict) : QString::fromLatin1(Error);
        m_store->markFinancialState(aggregateLocalId,kind,m_current.value("requestId").toString(),state,shown);
    } else if (kind == QLatin1String("attachment_reserve")) {
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
            {{QStringLiteral("syncError"), shown}});
    } else if (kind == QLatin1String("expense_create")) {
        // CREATE V02 es idempotente: ERROR conserva el mismo request/payload
        // y permite retry seguro. Un conflicto de idempotencia sí se detiene.
        state = conflict ? QString::fromLatin1(Conflict)
                         : QString::fromLatin1(Error);
        m_store->markExpenseState(aggregateLocalId, localId, state, shown);
    } else if ((kind == QLatin1String("rendition_trash") || kind == QLatin1String("rendition_archive")) && !ambiguous) {
        const bool persisted=kind==QLatin1String("rendition_archive")
            ? m_store->rejectRenditionArchive(aggregateLocalId, shown) : m_store->rejectDraftTrash(aggregateLocalId, shown);
        if (!persisted)
            m_store->markRenditionState(aggregateLocalId, QString::fromLatin1(Error), m_store->lastError());
    } else if (kind.startsWith(QLatin1String("expense_"))) {
        state = conflict ? QString::fromLatin1(Conflict)
                         : QString::fromLatin1(NeedsReconciliation);
        m_store->markExpenseState(aggregateLocalId, localId, state, shown);
    } else {
        m_store->markRenditionState(aggregateLocalId, state, shown);
    }
    const QString renditionRemoteId = m_current.value(
        QStringLiteral("renditionRemoteId"),
        m_current.value(QStringLiteral("remoteId"))).toString();
    m_current.clear();
    setLastError(transport ? QString() : message);
    setBusy(false);
    emit syncStopped(state, code, transport ? QString() : message);
    // Sin servidor no se relanzan consultas: la reconexión (evento de red o
    // reintento controlado) ejecuta sync + pull y resuelve la reconciliación.
    if (!transport && (state == QLatin1String(NeedsReconciliation)
        || state == QLatin1String(Conflict))) {
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
