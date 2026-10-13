#include "renditionflutterbridge.h"
#include "../core/RemoteExecutor.h"

#include "../../androidcalicataexporter.h"
#include "renditionlocalstore.h"
#include "renditionrepository.h"
#include "renditionsynccontroller.h"
#include "renditionsnapshotexporter.h"

#include <QJsonDocument>
#include <QDateTime>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>

namespace {
QString value(const QVariantMap &map, const QString &camel,
              const QString &snake = {})
{
    const QVariant direct = map.value(camel);
    if (direct.isValid() && !direct.isNull())
        return direct.toString();
    return snake.isEmpty() ? QString() : map.value(snake).toString();
}
}

RenditionFlutterBridge::RenditionFlutterBridge(
    RenditionRepository *repository, RenditionLocalStore *store,
    RenditionSyncController *syncController, AndroidCalicataExporter *exporter,
    QObject *parent)
    : QObject(parent),
      m_repository(repository),
      m_store(store),
      m_syncController(syncController),
      m_exporter(exporter)
{
    connect(m_repository, &RenditionRepository::receivedReset, this, [this]() {
        const auto picker = m_calicataPickerDocument;
        m_calicataPickerDocument.clear();
        if (!picker.isEmpty()) emit calicataProjectPicked(picker, {});
        m_selectedLocalId.clear();
        m_documentTargetRemoteId.clear();
        m_documentTargetLoading = false;
        m_pendingPullOperations.clear();
        m_pendingPullRequestId.clear();
        m_pendingSyncRequestId.clear();
        clearPendingPresentation();
        m_receivedSnapshot.clear();
        const auto requests = m_receivedRequests.keys();
        m_receivedRequests.clear();
        for (const auto &id : requests)
            sendError(id, QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió; vuelve a abrir la consulta."));
        sendEvent({{QStringLiteral("type"), QStringLiteral("receivedReset")}});
    });
    connect(m_repository, &RenditionRepository::receivedResult, this,
            [this](const QString &id, const QString &operation, const QVariant &payload) {
        if (!m_receivedRequests.contains(id)) return;
        const QVariantMap expected = m_receivedRequests.take(id);
        const QVariantList rows = payload.metaType().id() == QMetaType::QVariantList
            ? payload.toList() : QVariantList{payload};
        if (operation == QLatin1String("folderCapabilities")) {
            sendResult(id, rows.isEmpty() ? QVariantMap{} : rows.first().toMap());
            return;
        }
        if (operation == QLatin1String("receivedQuery")) {
            const QVariantMap row = rows.isEmpty() ? QVariantMap{} : rows.first().toMap();
            if (row.value(QStringLiteral("rendition_id")) != expected.value(QStringLiteral("renditionId"))
                || row.value(QStringLiteral("rendition_version_id")) != expected.value(QStringLiteral("versionId"))
                || row.value(QStringLiteral("version_number")).toInt() != expected.value(QStringLiteral("versionNumber")).toInt()
                || row.value(QStringLiteral("snapshot_hash")).toString().isEmpty()
                || row.value(QStringLiteral("snapshot_payload")).toMap().isEmpty()) {
                sendError(id, QStringLiteral("SNAPSHOT_CHANGED"), QStringLiteral("La versión presentada cambió. Actualiza la bandeja y vuelve a seleccionarla."));
                return;
            }
            SnapshotExportModel model;
            QString validationError;
            if (!SnapshotExportModel::fromReceived(row, &model, &validationError)
                || (!expected.value(QStringLiteral("hash")).toString().isEmpty()
                    && expected.value(QStringLiteral("hash")) != row.value(QStringLiteral("snapshot_hash")))) {
                sendError(id, QStringLiteral("SNAPSHOT_INVALID"), validationError.isEmpty()
                    ? QStringLiteral("El hash de la versión no coincide.") : validationError);
                return;
            }
            m_receivedSnapshot = row;
        }
        sendResult(id, {{QStringLiteral("rows"), rows}});
    });
    m_publishTimer.setSingleShot(true);
    m_publishTimer.setInterval(24);
    connect(&m_publishTimer, &QTimer::timeout, this,
            &RenditionFlutterBridge::publishStateNow);

    connect(m_repository, &RenditionRepository::renditionsChanged, this,
            [this]() {
        m_store->mergeRemoteRenditions(m_repository->renditions());
        m_store->reconcileCompleteRenditionList(m_repository->renditions());
        publishState();
    });
    const auto localForRemote = [this](const QString &id) {
        for (const auto &entry : m_store->renditions()) {
            const auto row = entry.toMap();
            if (row.value(QStringLiteral("remoteId")).toString() == id)
                return row.value(QStringLiteral("localId")).toString();
        }
        return QString{};
    };
    connect(m_repository, &RenditionRepository::expensesLoaded, this,
            [this, localForRemote](const QString &id, const QVariantList &rows) {
        m_store->mergeRemoteExpenses(localForRemote(id), rows);
    });
    connect(m_repository, &RenditionRepository::attachmentsLoaded, this,
            [this, localForRemote](const QString &id, const QVariantList &rows) {
        m_store->mergeRemoteAttachments(localForRemote(id), rows);
    });
    connect(m_repository, &RenditionRepository::summaryLoaded, this,
            [this, localForRemote](const QString &id, const QVariantMap &summary) {
        m_store->adoptRemoteSummary(localForRemote(id), summary);
    });
    connect(m_repository, &RenditionRepository::documentLocationLoaded, this,
            [this, localForRemote](const QString &id, const QVariantMap &location) {
        m_store->adoptDocumentLocation(localForRemote(id), location);
        publishState();
    });
    connect(m_repository, &RenditionRepository::documentWorkspaceChanged, this,
            [this]() {
        const QVariantMap workspace = m_repository->documentWorkspace();
        const QString spaceId = value(workspace, QStringLiteral("spaceId"),
                                      QStringLiteral("space_id"));
        if (!spaceId.isEmpty()) {
            m_repository->getDocumentSpace(spaceId);
            m_repository->getDocumentCapabilities(spaceId, {});
        }
        if (!m_pendingWorkspaceRequestId.isEmpty()) {
            sendResult(m_pendingWorkspaceRequestId, workspace);
            m_pendingWorkspaceRequestId.clear();
        }
        publishState();
    });
    connect(m_repository, &RenditionRepository::documentFoldersChanged, this,
            [this]() {
        if (!m_pendingFoldersRequestId.isEmpty()) {
            sendResult(m_pendingFoldersRequestId,
                       {{QStringLiteral("folders"), m_repository->documentFolders()},
                        {QStringLiteral("count"),
                         m_repository->documentFolders().size()}});
            m_pendingFoldersRequestId.clear();
        }
    });
    connect(m_repository, &RenditionRepository::renditionPresented, this,
            [this](const QVariantMap &result) {
        const QString localId = m_pendingPresentationLocalId.isEmpty()
            ? m_selectedLocalId : m_pendingPresentationLocalId;
        if (localId.isEmpty() || !m_store->markRenditionPresented(localId, result)) {
            sendError(m_pendingPresentationRequestId, QStringLiteral("PRESENT_INVALID_RESPONSE"), m_store->lastError());
            clearPendingPresentation();
            return;
        }
        m_lastServerConfirmationAt = QDateTime::currentDateTimeUtc()
            .toString(Qt::ISODateWithMs);
        const QString requestId = m_pendingPresentationRequestId;
        clearPendingPresentation();
        startRemotePull(requestId, QStringLiteral("present"));
    });
    connect(m_repository, &RenditionRepository::operationSucceeded, this,
            &RenditionFlutterBridge::completeRemotePullOperation);
    connect(m_repository, &RenditionRepository::attachmentAccessReady, this,
            [this](const QVariantMap &result) {
        sendEvent({{QStringLiteral("type"), QStringLiteral("attachmentAccess")},
                   {QStringLiteral("result"), result}});
    });
    connect(m_repository, &RenditionRepository::attachmentArchived, this,
            [this](const QVariantMap &) {
        const QVariantMap draft = m_store->rendition(m_selectedLocalId);
        const QString remoteId = draft.value(QStringLiteral("remoteId")).toString();
        if (!remoteId.isEmpty())
            m_repository->listAttachments(remoteId);
    });
    connect(m_repository, &RenditionRepository::operationFailed, this,
            [this](const QString &operation, const QString &code,
                   const QString &message) {
        if (operation.startsWith(QLatin1String("received/"))) {
            const QString id = operation.mid(9);
            m_receivedRequests.remove(id);
            sendError(id, code, message);
            return;
        }
        if (m_pendingPullOperations.contains(operation)) {
            failRemotePull(operation, code, message);
            return;
        }
        QString requestId;
        if (operation == QLatin1String("present")) {
            requestId = m_pendingPresentationRequestId;
            const QString localId = m_pendingPresentationLocalId.isEmpty()
                ? m_selectedLocalId : m_pendingPresentationLocalId;
            if (!localId.isEmpty()) {
                const QString normalized = code.toUpper();
                const QString state = normalized.contains(QStringLiteral("CONFLICT"))
                        || normalized.contains(QStringLiteral("ROW_VERSION"))
                    ? QStringLiteral("CONFLICT")
                    : (normalized.contains(QStringLiteral("NETWORK"))
                           || normalized.contains(QStringLiteral("TIMEOUT"))
                       ? QStringLiteral("NEEDS_RECONCILIATION")
                       : QStringLiteral("ERROR"));
                m_store->markPresentationState(localId, state, message);
            }
            clearPendingPresentation();
        } else if (operation == QLatin1String("project_workspace")) {
            requestId = m_pendingWorkspaceRequestId;
            m_pendingWorkspaceRequestId.clear();
        } else if (operation == QLatin1String("document_folders")) {
            requestId = m_pendingFoldersRequestId;
            m_pendingFoldersRequestId.clear();
        }
        sendError(requestId, code, message);
        publishState();
    });

    const auto publish = [this]() { publishState(); };
    connect(m_store, &RenditionLocalStore::renditionsChanged, this, publish);
    connect(m_store, &RenditionLocalStore::pendingCountChanged, this, publish);
    connect(m_repository, &RenditionRepository::projectsChanged, this, publish);
    connect(m_repository, &RenditionRepository::currentRenditionChanged,
            this, [this]() {
        const QVariantMap remote = m_repository->currentRendition();
        if (!remote.isEmpty()) m_store->mergeRemoteRenditions({remote});
        if (m_documentTargetLoading && !m_documentTargetRemoteId.isEmpty()
            && value(remote, QStringLiteral("id"), QStringLiteral("rendition_id")) == m_documentTargetRemoteId) {
            for (const auto &entry : m_store->renditions()) {
                const auto row = entry.toMap();
                if (row.value(QStringLiteral("remoteId")).toString() == m_documentTargetRemoteId) {
                    m_selectedLocalId = row.value(QStringLiteral("localId")).toString();
                    m_documentTargetLoading = false;
                    m_repository->listExpenses(m_documentTargetRemoteId);
                    m_repository->listAttachments(m_documentTargetRemoteId);
                    m_repository->listVersions(m_documentTargetRemoteId);
                    break;
                }
            }
        }
        publishState();
    });
    connect(m_repository, &RenditionRepository::expenseCatalogsChanged, this, publish);
    connect(m_repository, &RenditionRepository::expenseSummaryChanged, this, publish);
    connect(m_repository, &RenditionRepository::versionsChanged, this, publish);
    connect(m_repository, &RenditionRepository::attachmentsChanged, this, publish);
    connect(m_repository, &RenditionRepository::documentFoldersChanged, this, publish);
    connect(m_repository, &RenditionRepository::documentCapabilitiesChanged, this, publish);
    connect(m_repository, &RenditionRepository::busyChanged, this, publish);
    connect(m_syncController, &RenditionSyncController::busyChanged, this, publish);
    connect(m_syncController, &RenditionSyncController::syncFinished, this,
            [this](int) {
        if (m_presentAfterSync) {
            startRemotePull({}, QStringLiteral("present_preflight"));
            return;
        }
        const QString requestId = m_pendingSyncRequestId;
        m_pendingSyncRequestId.clear();
        startRemotePull(requestId, QStringLiteral("sync"));
    });
    connect(m_syncController, &RenditionSyncController::syncStopped, this,
            [this](const QString &state, const QString &message) {
        if (m_presentAfterSync && !m_pendingPresentationRequestId.isEmpty()) {
            const QString requestId = m_pendingPresentationRequestId;
            clearPendingPresentation();
            sendError(requestId, state, message);
        }
        if (!m_pendingSyncRequestId.isEmpty()) {
            sendError(m_pendingSyncRequestId, state, message);
            m_pendingSyncRequestId.clear();
        }
        updateConnectionState(state);
        publishState();
    });
}

void RenditionFlutterBridge::setCoreRemote(inge::core::RemoteExecutor *core) {
    m_core=core;
    connect(core,&inge::core::RemoteExecutor::completed,this,
        [this](const QString &id,const QVariantMap &result,const QString &error){
            if(!m_coreRequests.remove(id)) return;
            if(error.isEmpty()) sendResult(id,result);
            else sendError(id,error,QStringLiteral("Análisis no disponible. Conserva los documentos y revisa los campos manualmente."));
        });
}

RenditionFlutterBridge::~RenditionFlutterBridge() = default;

void RenditionFlutterBridge::submit(const QString &requestJson)
{
    const QPointer<RenditionFlutterBridge> bridge = this;
    QMetaObject::invokeMethod(this, [bridge, requestJson]() {
        if (bridge)
            bridge->handleCommand(requestJson);
    }, Qt::QueuedConnection);
}

void RenditionFlutterBridge::pickCalicataProject(const QString &documentId)
{
    if (documentId.isEmpty()) return;
    m_calicataPickerDocument = documentId;
    m_repository->listProjects();
    publishState();
    emit calicataProjectPickerRequested();
}

void RenditionFlutterBridge::openDocumentTarget(const QString &renditionId)
{
    if (renditionId.isEmpty()) return;
    if (m_repository->busy() || m_syncController->busy()) {
        sendError({}, QStringLiteral("DETAIL_BUSY"), QStringLiteral("Espera a que termine la sincronización y vuelve a abrir el documento."));
        return;
    }
    m_documentTargetRemoteId = renditionId;
    m_documentTargetLoading = true;
    ++m_documentOpenRevision;
    m_selectedLocalId.clear();
    m_repository->getRendition(renditionId);
}

void RenditionFlutterBridge::handleCommand(const QString &requestJson)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(
        requestJson.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        sendError({}, QStringLiteral("INVALID_COMMAND"),
                  QStringLiteral("Solicitud Flutter de rendiciones inválida."));
        return;
    }

    const QVariantMap request = document.object().toVariantMap();
    const QString requestId = request.value(QStringLiteral("requestId")).toString();
    const QString operation = request.value(QStringLiteral("operation")).toString();
    const QVariantMap arguments = request.value(QStringLiteral("arguments")).toMap();

    if (operation == QLatin1String("saveEditorDraft")) {
        if (m_store->saveEditorDraft(arguments.value(QStringLiteral("key")).toString(),
                                     arguments.value(QStringLiteral("draft")).toMap())) sendResult(requestId);
        else sendError(requestId, QStringLiteral("AUTOSAVE_FAILED"), m_store->lastError());
        return;
    }

    if (operation == QLatin1String("calicataProjectPicked")) {
        const auto document = arguments.value(QStringLiteral("documentId")).toString();
        if (document.isEmpty() || document != m_calicataPickerDocument) {
            sendError(requestId, QStringLiteral("STALE_PICKER"), QStringLiteral("La ficha cambió. Abre de nuevo el selector."));
            return;
        }
        const auto selection = arguments.value(QStringLiteral("selection")).toMap();
        if (!selection.isEmpty()) {
            bool found = false;
            for (const auto &value : m_repository->projects())
                if (value.toMap().value(QStringLiteral("id")) == selection.value(QStringLiteral("projectId"))) found = true;
            if (!found || selection.value(QStringLiteral("documentParentNodeId")).toString().isEmpty()
                || selection.value(QStringLiteral("spaceId")).toString().isEmpty()) {
                sendError(requestId, QStringLiteral("INVALID_PROJECT"), QStringLiteral("Selecciona un proyecto y una carpeta autorizados."));
                return;
            }
        }
        m_calicataPickerDocument.clear();
        sendResult(requestId);
        publishState();
        emit calicataProjectPicked(document, selection);
        return;
    }
    if (operation == QLatin1String("globalAction")) {
        const QString action = arguments.value(QStringLiteral("action")).toString();
        if (action != QLatin1String("home") && action != QLatin1String("create") && action != QLatin1String("documents")) {
            sendError(requestId, QStringLiteral("INVALID_ACTION"), QStringLiteral("Acción no reconocida."));
            return;
        }
        emit globalActionRequested(action);
        sendResult(requestId);
        return;
    }
    if (operation == QLatin1String("receivedClose")) {
        m_receivedSnapshot.clear();
        // Invalidate query responses after Back, without cancelling unrelated work.
        const auto pending = m_receivedRequests.keys();
        for (const auto &id : pending) {
            m_receivedRequests.remove(id);
            sendError(id, QStringLiteral("QUERY_CLOSED"), QStringLiteral("Consulta cerrada."));
        }
        sendResult(requestId);
        return;
    }
    if (operation == QLatin1String("folderCapabilities")) {
        if (arguments.value(QStringLiteral("nodeId")).toString().isEmpty()
            || arguments.value(QStringLiteral("spaceId")).toString().isEmpty()) {
            sendError(requestId, QStringLiteral("ROOT_NOT_SELECTABLE"), QStringLiteral("Selecciona una carpeta dentro del proyecto."));
            return;
        }
        m_receivedRequests.insert(requestId, arguments);
        m_repository->receivedCommand(requestId, operation, arguments);
        return;
    }
    if (operation == QLatin1String("receivedList") || operation == QLatin1String("receivedQuery")
        || operation == QLatin1String("receivedNotes") || operation == QLatin1String("receivedActivity")
        || operation == QLatin1String("receivedAddNote")) {
        if (operation == QLatin1String("receivedQuery")) m_receivedSnapshot.clear();
        if (operation != QLatin1String("receivedList") && operation != QLatin1String("receivedQuery")
            && (m_receivedSnapshot.isEmpty()
                || arguments.value(QStringLiteral("renditionId")) != m_receivedSnapshot.value(QStringLiteral("rendition_id"))
                || arguments.value(QStringLiteral("versionId")) != m_receivedSnapshot.value(QStringLiteral("rendition_version_id")))) {
            sendError(requestId, QStringLiteral("SNAPSHOT_REQUIRED"), QStringLiteral("Abre una versión autorizada antes de consultar su administración."));
            return;
        }
        m_receivedRequests.insert(requestId, arguments);
        m_repository->receivedCommand(requestId, operation, arguments);
        return;
    }
    if (operation == QLatin1String("receivedExport") || operation == QLatin1String("receivedAttachment")) {
        if (m_receivedSnapshot.isEmpty()
            || arguments.value(QStringLiteral("versionId")) != m_receivedSnapshot.value(QStringLiteral("rendition_version_id"))
            || arguments.value(QStringLiteral("hash")) != m_receivedSnapshot.value(QStringLiteral("snapshot_hash"))) {
            sendError(requestId, QStringLiteral("SNAPSHOT_REQUIRED"), QStringLiteral("La consulta ya no corresponde a esta versión."));
            return;
        }
        if (operation == QLatin1String("receivedAttachment")) {
            const QString attachmentId = arguments.value(QStringLiteral("attachmentId")).toString();
            const auto attachments = m_receivedSnapshot.value(QStringLiteral("snapshot_payload")).toMap()
                .value(QStringLiteral("attachments")).toList();
            bool found = false;
            for (const auto &entry : attachments)
                found |= entry.toMap().value(QStringLiteral("id")).toString() == attachmentId;
            if (!found || attachmentId.isEmpty()) {
                sendError(requestId, QStringLiteral("ATTACHMENT_NOT_IN_SNAPSHOT"), QStringLiteral("El sustento no pertenece al snapshot."));
                return;
            }
            m_receivedRequests.insert(requestId, arguments);
            m_repository->accessReceivedAttachment(requestId, attachmentId);
            return;
        }
        const QString output = m_exporter ? m_exporter->exportReceivedSnapshot(
            m_receivedSnapshot, arguments.value(QStringLiteral("format")).toString()) : QString();
        if (output.isEmpty()) {
            sendError(requestId, QStringLiteral("EXPORT_FAILED"), m_exporter ? m_exporter->lastError() : QStringLiteral("Exportador no disponible."));
        } else {
            sendResult(requestId, {{QStringLiteral("output"), output}, {QStringLiteral("warning"), m_exporter->lastError()}});
        }
        return;
    }

    if (operation == QLatin1String("bootstrap")
        || operation == QLatin1String("refresh")) {
        publishState();
        startRemotePull(requestId, operation);
        return;
    }

    if (operation == QLatin1String("select")) {
        const QString localId = arguments.value(QStringLiteral("localId")).toString();
        const QVariantMap selected = m_store->rendition(localId);
        if (selected.isEmpty()) {
            sendError(requestId, QStringLiteral("NOT_FOUND"),
                      QStringLiteral("La rendición no existe en la cuenta actual."));
            return;
        }
        // Keep responses for the previous selection from entering another record.
        if (m_repository->busy() || m_syncController->busy()) {
            sendError(requestId, QStringLiteral("DETAIL_BUSY"),
                      QStringLiteral("Espera a que termine la sincronización para abrir la rendición."));
            return;
        }
        m_selectedLocalId = localId;
        publishStateNow();
        sendResult(requestId, {{QStringLiteral("current"), selected}});
        if (!selected.value(QStringLiteral("remoteId")).toString().isEmpty())
            startRemotePull({}, QStringLiteral("select"));
        return;
    }

    if (operation == QLatin1String("closeDetail")) {
        m_selectedLocalId.clear();
        publishState();
        sendResult(requestId);
        return;
    }

    if (operation == QLatin1String("create")) {
        const bool synchronize = arguments.value(
            QStringLiteral("synchronize"), true).toBool();
        const QString localId = m_store->createDraft(
            arguments.value(QStringLiteral("periodStart")).toString(),
            arguments.value(QStringLiteral("periodEnd")).toString(),
            arguments.value(QStringLiteral("projectIds")).toList(),
            arguments.value(QStringLiteral("primaryProjectId")).toString(),
            arguments.value(QStringLiteral("documentParentNodeId")).toString(),
            arguments.value(QStringLiteral("spaceId")).toString(),
            synchronize);
        if (localId.isEmpty()) {
            sendError(requestId, QStringLiteral("CREATE_LOCAL_FAILED"),
                      m_store->lastError());
            return;
        }
        m_selectedLocalId = localId;
        publishStateNow();
        sendResult(requestId, {{QStringLiteral("current"), m_store->rendition(localId)},
                               {QStringLiteral("localId"), localId},
                               {QStringLiteral("pendingSync"), true}});
        publishState();
        if (synchronize)
            m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("update")) {
        const bool synchronize = arguments.value(
            QStringLiteral("synchronize"), true).toBool();
        const QString localId = arguments.value(QStringLiteral("localId")).toString();
        const QVariantMap draft = m_store->rendition(localId);
        if (arguments.contains(QStringLiteral("expectedRowVersion"))
            && arguments.value(QStringLiteral("expectedRowVersion")).toLongLong()
                != draft.value(QStringLiteral("rowVersion")).toLongLong()) {
            sendError(requestId, QStringLiteral("ROW_VERSION_CONFLICT"),
                      QStringLiteral("La rendición cambió. Vuelve a abrirla antes de guardar."));
            return;
        }
        const bool saved = m_store->saveDraft(
            localId,
            arguments.value(QStringLiteral("periodStart")).toString(),
            arguments.value(QStringLiteral("periodEnd")).toString(),
            arguments.value(QStringLiteral("projectIds")).toList(),
            arguments.value(QStringLiteral("primaryProjectId")).toString(),
            draft.value(QStringLiteral("rowVersion")).toLongLong(),
            arguments.value(QStringLiteral("documentParentNodeId")).toString(),
            draft.value(QStringLiteral("documentNodeId")).toString(),
            draft.value(QStringLiteral("documentNodeVersion")).toLongLong(),
            arguments.value(QStringLiteral("spaceId")).toString(),
            synchronize);
        if (!saved) {
            sendError(requestId, QStringLiteral("UPDATE_LOCAL_FAILED"),
                      m_store->lastError());
            return;
        }
        publishStateNow();
        sendResult(requestId, {{QStringLiteral("pendingSync"), true},
                              {QStringLiteral("current"), m_store->rendition(localId)}});
        if (synchronize)
            m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("saveExpense")) {
        const QString localId = arguments.value(QStringLiteral("localId")).toString();
        const QString expenseLocalId = arguments.value(
            QStringLiteral("expenseLocalId")).toString();
        const QVariantMap expense = arguments.value(QStringLiteral("expense")).toMap();
        if (!expenseLocalId.isEmpty() && arguments.contains(QStringLiteral("expectedExpenseRowVersion"))) {
            for (const auto &entry : m_store->expensesFor(localId)) {
                const auto row = entry.toMap();
                if (row.value(QStringLiteral("localId")).toString() == expenseLocalId
                    && row.value(QStringLiteral("rowVersion")).toLongLong() != arguments.value(QStringLiteral("expectedExpenseRowVersion")).toLongLong()) {
                    sendError(requestId, QStringLiteral("EXPENSE_CONFLICT"), QStringLiteral("El gasto cambió desde que abriste el editor. Actualiza antes de guardar."));
                    return;
                }
            }
        }
        const bool synchronize = arguments.value(
            QStringLiteral("synchronize"), true).toBool();
        const QString savedLocalId = expenseLocalId.isEmpty()
            ? m_store->addLocalExpense(localId, expense, synchronize)
            : (m_store->saveLocalExpense(localId, expenseLocalId, expense,
                                         synchronize)
                   ? expenseLocalId : QString{});
        const bool saved = !savedLocalId.isEmpty();
        if (!saved) {
            sendError(requestId, QStringLiteral("EXPENSE_LOCAL_FAILED"),
                      m_store->lastError());
            return;
        }
        publishStateNow();
        sendResult(requestId, {{QStringLiteral("localId"), savedLocalId},
                               {QStringLiteral("pendingSync"), true}});
        if (synchronize)
            m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("deleteDraft")) {
        if (m_syncController->busy() || m_repository->busy()) { sendError(requestId, "SYNC_BUSY", "Espera a que termine la sincronización."); return; }
        const QString localId = arguments.value(QStringLiteral("localId")).toString();
        if (!m_store->removeDraft(localId)) { sendError(requestId, "DRAFT_DELETE_FAILED", m_store->lastError()); return; }
        if (m_selectedLocalId == localId) m_selectedLocalId.clear();
        sendResult(requestId, {{QStringLiteral("pendingSync"), true}});
        publishState(); m_syncController->synchronize(); return;
    }
    if (operation == QLatin1String("deleteExpense")) {
        if (m_syncController->busy() || m_repository->busy()) { sendError(requestId, "SYNC_BUSY", "Espera a que termine la sincronización."); return; }
        const bool removed = m_store->removeLocalExpense(
            arguments.value(QStringLiteral("localId")).toString(),
            arguments.value(QStringLiteral("expenseLocalId")).toString());
        if (!removed) {
            sendError(requestId, QStringLiteral("EXPENSE_DELETE_LOCAL_FAILED"),
                      m_store->lastError());
            return;
        }
        sendResult(requestId, {{QStringLiteral("pendingSync"), true}});
        m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("coreAnalyze")) {
        if (!m_core) { sendError(requestId,"AI_UNAVAILABLE","InGe Core no disponible"); return; }
        m_coreRequests.insert(requestId);
        m_core->analyzeEvidence(requestId,arguments.value("attachments").toList(),
                               arguments.value("context").toMap());
        return;
    }

    if (operation == QLatin1String("attachSupport")) {
        const QString localId = arguments.value(QStringLiteral("localId")).toString();
        const QString expenseLocalId = arguments.value(
            QStringLiteral("expenseLocalId")).toString();
        QVariantMap attachment = arguments.value(QStringLiteral("attachment")).toMap();
        const QString attachmentLocalId = m_store->addLocalAttachment(
            localId, expenseLocalId, attachment);
        if (attachmentLocalId.isEmpty()) {
            sendError(requestId, QStringLiteral("ATTACHMENT_LOCAL_FAILED"),
                      m_store->lastError());
            return;
        }
        sendResult(requestId, {{QStringLiteral("pendingSync"), true}});
        m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("present")) {
        if (!m_pendingPresentationRequestId.isEmpty()) {
            sendError(requestId, QStringLiteral("PRESENT_BUSY"),
                      QStringLiteral("Ya hay una presentación en curso."));
            return;
        }
        const QVariantMap draft = m_store->rendition(m_selectedLocalId);
        if (draft.isEmpty()
            || draft.value(QStringLiteral("status")).toString()
                   != QLatin1String("BORRADOR")) {
            sendError(requestId, QStringLiteral("PRESENT_NOT_ALLOWED"),
                      QStringLiteral("Sólo una rendición BORRADOR puede presentarse."));
            return;
        }
        if (m_repository->busy() || m_syncController->busy()
            || !m_store->presentationBlocker(m_selectedLocalId).isEmpty()) {
            sendError(requestId, QStringLiteral("PRESENT_NOT_READY"),
                      QStringLiteral("Sincroniza los cambios pendientes antes de presentar."));
            return;
        }
        m_pendingPresentationRequestId = requestId;
        m_pendingPresentationLocalId = m_selectedLocalId;
        m_presentAfterSync = true;
        publishState();
        startRemotePull({}, QStringLiteral("present_preflight"));
        return;
    }

    if (operation == QLatin1String("sync")) {
        if (!m_pendingSyncRequestId.isEmpty() || m_syncController->busy()
            || !m_pendingPullOperations.isEmpty() || m_repository->busy()) {
            sendError(requestId, QStringLiteral("SYNC_BUSY"),
                      QStringLiteral("Ya hay una sincronización solicitada."));
            return;
        }
        if (!m_store->stageLocalOnlyChanges(m_repository->v02Enabled())) {
            sendError(requestId, QStringLiteral("SYNC_STAGE_FAILED"),
                      m_store->lastError());
            return;
        }
        m_pendingSyncRequestId = requestId;
        m_syncController->synchronize();
        return;
    }

    if (operation == QLatin1String("projectWorkspace")) {
        if (!m_pendingWorkspaceRequestId.isEmpty()) {
            sendError(requestId, QStringLiteral("WORKSPACE_BUSY"),
                      QStringLiteral("Ya se está consultando el espacio documental."));
            return;
        }
        m_pendingWorkspaceRequestId = requestId;
        m_repository->getProjectWorkspace(
            arguments.value(QStringLiteral("projectId")).toString());
        return;
    }

    if (operation == QLatin1String("listFolders")) {
        if (!m_pendingFoldersRequestId.isEmpty()) {
            sendError(requestId, QStringLiteral("FOLDERS_BUSY"),
                      QStringLiteral("Ya se está consultando esta carpeta."));
            return;
        }
        m_pendingFoldersRequestId = requestId;
        const QString spaceId = arguments.value(QStringLiteral("spaceId")).toString();
        const QString parentId = arguments.value(QStringLiteral("parentId")).toString();
        m_repository->getDocumentCapabilities(spaceId, parentId);
        m_repository->listDocumentFolders(spaceId, parentId);
        return;
    }

    if (operation == QLatin1String("attachmentAccess")) {
        m_receivedRequests.insert(requestId, arguments);
        m_repository->accessReceivedAttachment(requestId,
            arguments.value(QStringLiteral("attachmentId")).toString());
        return;
    }

    if (operation == QLatin1String("ownerExport")) {
        const auto draft = m_store->rendition(m_selectedLocalId);
        const auto remoteId = draft.value(QStringLiteral("remoteId")).toString();
        const auto versionId = draft.value(QStringLiteral("currentVersionId")).toString();
        if (draft.value(QStringLiteral("status")).toString() != QLatin1String("PRESENTADA")
            || remoteId.isEmpty() || versionId.isEmpty()) {
            sendError(requestId, QStringLiteral("SNAPSHOT_REQUIRED"), QStringLiteral("Abre una rendición presentada con versión confirmada."));
            return;
        }
        for (const auto &entry : m_repository->versions()) {
            auto row = entry.toMap();
            if (row.value(QStringLiteral("id")).toString() != versionId
                || row.value(QStringLiteral("rendition_id")).toString() != remoteId) continue;
            row.insert(QStringLiteral("rendition_version_id"), versionId);
            const auto header = row.value(QStringLiteral("snapshot_payload")).toMap().value(QStringLiteral("rendition")).toMap();
            row.insert(QStringLiteral("visible_code"), header.value(QStringLiteral("visible_code")));
            row.insert(QStringLiteral("owner_name"), header.value(QStringLiteral("owner_user_id")));
            const QString output = m_exporter ? m_exporter->exportReceivedSnapshot(row,
                arguments.value(QStringLiteral("format")).toString()) : QString();
            if (output.isEmpty()) sendError(requestId, QStringLiteral("EXPORT_FAILED"),
                m_exporter ? m_exporter->lastError() : QStringLiteral("Exportador no disponible."));
            else sendResult(requestId, {{QStringLiteral("output"), output}});
            return;
        }
        sendError(requestId, QStringLiteral("SNAPSHOT_REQUIRED"), QStringLiteral("Sincroniza para cargar la versión inmutable antes de exportar."));
        return;
    }

    if (operation == QLatin1String("archiveAttachment")) {
        m_repository->archiveAttachment(
            arguments.value(QStringLiteral("attachmentId")).toString(),
            arguments.value(QStringLiteral("rowVersion")).toLongLong());
        sendResult(requestId);
        return;
    }

    if (operation == QLatin1String("export")) {
        if (!m_exporter) {
            sendError(requestId, QStringLiteral("EXPORT_UNAVAILABLE"),
                      QStringLiteral("El exportador nativo no está disponible."));
            return;
        }
        const QString format = arguments.value(QStringLiteral("format"))
                                   .toString().toLower();
        const QVariantMap state = arguments.value(QStringLiteral("state")).toMap();
        const QString baseName = arguments.value(QStringLiteral("fileBaseName")).toString();
        const QString output = format == QLatin1String("pdf")
            ? m_exporter->exportRenditionToPdf(state, baseName)
            : m_exporter->exportRenditionToXlsx(state, baseName);
        if (output.isEmpty()) {
            sendError(requestId, QStringLiteral("EXPORT_FAILED"),
                      m_exporter->lastError().isEmpty()
                          ? QStringLiteral("No se pudo crear el archivo.")
                          : m_exporter->lastError());
            return;
        }
        sendResult(requestId, {{QStringLiteral("format"), format},
                               {QStringLiteral("output"), output},
                               {QStringLiteral("warning"), m_exporter->lastError()}});
        return;
    }

    sendError(requestId, QStringLiteral("UNKNOWN_COMMAND"),
              QStringLiteral("Operación Flutter de rendiciones no soportada."));
}

void RenditionFlutterBridge::refreshRemoteDetail()
{
    if (m_selectedLocalId.isEmpty())
        return;
    const QVariantMap draft = m_store->rendition(m_selectedLocalId);
    const QString remoteId = draft.value(QStringLiteral("remoteId")).toString();
    if (remoteId.isEmpty())
        return;
    m_repository->getRendition(remoteId);
    m_repository->listExpenses(remoteId);
    m_repository->getExpenseSummary(remoteId);
    m_repository->listVersions(remoteId);
    m_repository->listAttachments(remoteId);
    if (m_repository->v02Enabled())
        m_repository->getDocumentLocation(remoteId);
}

void RenditionFlutterBridge::startRemotePull(const QString &requestId,
                                             const QString &reason)
{
    if (!m_pendingPullOperations.isEmpty()) {
        if (!requestId.isEmpty()) {
            sendError(requestId, QStringLiteral("PULL_BUSY"),
                      QStringLiteral("Ya hay una actualización remota en curso."));
        }
        return;
    }

    m_pendingPullRequestId = requestId;
    m_pendingPullReason = reason;
    m_pendingPullOperations = {
        QStringLiteral("list"),
        QStringLiteral("projects"),
        QStringLiteral("expense_catalogs")
    };
    const QVariantMap draft = m_store->rendition(m_selectedLocalId);
    const QString remoteId = draft.value(QStringLiteral("remoteId")).toString();
    if (!remoteId.isEmpty()) {
        m_pendingPullOperations.unite({
            QStringLiteral("get"),
            QStringLiteral("expenses"),
            QStringLiteral("expense_summary"),
            QStringLiteral("versions"),
            QStringLiteral("attachments")
        });
        if (m_repository->v02Enabled())
            m_pendingPullOperations.insert(QStringLiteral("get_location"));
    }
    publishState();

    m_repository->listProjects();
    m_repository->listExpenseCatalogs();
    m_repository->listRenditions(50, {}, {});
    if (!remoteId.isEmpty()) {
        m_repository->getRendition(remoteId);
        m_repository->listExpenses(remoteId);
        m_repository->getExpenseSummary(remoteId);
        m_repository->listVersions(remoteId);
        m_repository->listAttachments(remoteId);
        if (m_repository->v02Enabled())
            m_repository->getDocumentLocation(remoteId);
    }
}

void RenditionFlutterBridge::completeRemotePullOperation(
    const QString &operation)
{
    if (!m_pendingPullOperations.remove(operation))
        return;
    if (!m_pendingPullOperations.isEmpty())
        return;

    const QString requestId = m_pendingPullRequestId;
    const QString reason = m_pendingPullReason;
    m_pendingPullRequestId.clear();
    m_pendingPullReason.clear();
    m_lastPullAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    m_connectionState = QStringLiteral("ONLINE");
    if (reason == QLatin1String("sync"))
        m_lastServerConfirmationAt = m_lastPullAt;
    if (reason == QLatin1String("present_preflight")) {
        continuePresentationAfterSync();
        return;
    }
    publishStateNow();
    if (!requestId.isEmpty()) {
        sendResult(requestId, {
            {QStringLiteral("pulled"), true},
            {QStringLiteral("reason"), reason},
            {QStringLiteral("lastPullAt"), m_lastPullAt},
            {QStringLiteral("pendingCount"), m_store->pendingCount()}
        });
    }
    publishState();
}

void RenditionFlutterBridge::failRemotePull(const QString &operation,
                                            const QString &code,
                                            const QString &message)
{
    Q_UNUSED(operation)
    const QString requestId = m_pendingPullRequestId;
    if (m_pendingPullReason == QLatin1String("present_preflight")) {
        sendError(m_pendingPresentationRequestId, code, message);
        clearPendingPresentation();
    }
    m_pendingPullOperations.clear();
    m_pendingPullRequestId.clear();
    m_pendingPullReason.clear();
    updateConnectionState(code);
    if (!requestId.isEmpty())
        sendError(requestId, code, message);
    publishState();
}

void RenditionFlutterBridge::continuePresentationAfterSync()
{
    if (!m_presentAfterSync || m_pendingPresentationRequestId.isEmpty())
        return;
    const QString blocker = m_store->presentationBlocker(
        m_pendingPresentationLocalId);
    if (!blocker.isEmpty()) {
        const QString requestId = m_pendingPresentationRequestId;
        clearPendingPresentation();
        sendError(requestId, QStringLiteral("PRESENT_NOT_READY"), blocker);
        publishState();
        return;
    }

    const QVariantMap draft = m_store->rendition(m_pendingPresentationLocalId);
    const QString idempotencyId = m_store->ensurePresentationRequestId(
        m_pendingPresentationLocalId);
    if (idempotencyId.isEmpty()) {
        const QString requestId = m_pendingPresentationRequestId;
        const QString message = m_store->lastError().isEmpty()
            ? QStringLiteral("No se pudo reservar la presentación.")
            : m_store->lastError();
        clearPendingPresentation();
        sendError(requestId, QStringLiteral("PRESENT_REQUEST_FAILED"), message);
        publishState();
        return;
    }

    m_presentAfterSync = false;
    m_store->markPresentationState(m_pendingPresentationLocalId,
                                   QStringLiteral("SYNCING"));
    m_repository->presentRendition(
        draft.value(QStringLiteral("remoteId")).toString(),
        draft.value(QStringLiteral("rowVersion")).toLongLong(),
        idempotencyId);
    publishState();
}

void RenditionFlutterBridge::clearPendingPresentation()
{
    m_pendingPresentationRequestId.clear();
    m_pendingPresentationLocalId.clear();
    m_presentAfterSync = false;
}

void RenditionFlutterBridge::updateConnectionState(const QString &code)
{
    const QString normalized = code.toUpper();
    if (normalized.contains(QStringLiteral("NETWORK"))
        || normalized.contains(QStringLiteral("TIMEOUT"))) {
        m_connectionState = QStringLiteral("OFFLINE");
    } else if (normalized.contains(QStringLiteral("AUTH"))
               || normalized.contains(QStringLiteral("401"))
               || normalized.contains(QStringLiteral("403"))) {
        m_connectionState = QStringLiteral("AUTH_REQUIRED");
    } else if (normalized.contains(QStringLiteral("CONFLICT"))
               || normalized.contains(QStringLiteral("ROW_VERSION"))) {
        m_connectionState = QStringLiteral("CONFLICT");
    } else {
        m_connectionState = QStringLiteral("ERROR");
    }
}

void RenditionFlutterBridge::publishState()
{
    if (!m_publishTimer.isActive())
        m_publishTimer.start();
}

void RenditionFlutterBridge::publishStateNow()
{
    QVariantMap current;
    QVariantList expenses;
    QVariantList localAttachments;
    if (!m_selectedLocalId.isEmpty()) {
        current = m_store->rendition(m_selectedLocalId);
        expenses = m_store->expensesFor(m_selectedLocalId);
        for (const QVariant &expenseValue : expenses) {
            const QVariantMap expense = expenseValue.toMap();
            const QVariantList rows = m_store->attachmentsFor(
                m_selectedLocalId,
                expense.value(QStringLiteral("localId")).toString());
            for (const QVariant &row : rows)
                localAttachments.append(row);
        }
    }

    const QString selectedRemoteId = current.value(
        QStringLiteral("remoteId")).toString();
    const QVariantMap repositoryCurrent = m_repository->currentRendition();
    const QString repositoryRemoteId = value(
        repositoryCurrent, QStringLiteral("id"),
        QStringLiteral("rendition_id"));
    const bool detailMatches = !selectedRemoteId.isEmpty()
        && selectedRemoteId == repositoryRemoteId;

    const bool active = m_repository->busy() || m_syncController->busy();
    QVariantList publishedRenditions;
    for (const auto &entry : m_store->renditions()) {
        auto row = entry.toMap();
        const auto status = m_store->syncStatus(row.value(QStringLiteral("localId")).toString(), active);
        for (auto it = status.cbegin(); it != status.cend(); ++it) row.insert(it.key(), it.value());
        if (row.value(QStringLiteral("localId")).toString() == m_selectedLocalId) current = row;
        publishedRenditions.append(row);
    }

    sendEvent({
        {QStringLiteral("type"), QStringLiteral("state")},
        {QStringLiteral("contractMode"), m_repository->contractMode()},
        {QStringLiteral("busy"), m_repository->busy()
             || m_syncController->busy()},
        // Operation errors are persisted on their owning row/outbox. Command
        // failures go to their request's caller, never a global sticky banner.
        {QStringLiteral("lastError"), QString()},
        {QStringLiteral("connectionState"), m_connectionState},
        {QStringLiteral("syncPhase"), m_presentAfterSync
             || !m_pendingPresentationRequestId.isEmpty()
                 ? QStringLiteral("PRESENTING")
                 : (m_syncController->busy()
                        ? QStringLiteral("PUSHING")
                        : (!m_pendingPullOperations.isEmpty()
                               ? QStringLiteral("PULLING")
                               : QStringLiteral("IDLE")))},
        {QStringLiteral("lastPullAt"), m_lastPullAt},
        {QStringLiteral("lastServerConfirmationAt"),
         m_lastServerConfirmationAt},
        {QStringLiteral("pendingCount"), m_store->pendingCount()},
        {QStringLiteral("editorDrafts"), m_store->editorDrafts()},
        {QStringLiteral("renditions"), publishedRenditions},
        {QStringLiteral("projects"), m_repository->projects()},
        {QStringLiteral("catalogs"), m_repository->expenseCatalogs()},
        {QStringLiteral("selectedLocalId"), m_selectedLocalId},
        {QStringLiteral("documentTargetId"), m_documentTargetRemoteId},
        {QStringLiteral("documentOpenRevision"), m_documentOpenRevision},
        {QStringLiteral("calicataPickerDocument"), m_calicataPickerDocument},
        {QStringLiteral("current"), current},
        {QStringLiteral("remoteCurrent"), detailMatches
             ? repositoryCurrent : QVariantMap{}},
        {QStringLiteral("expenses"), expenses},
        {QStringLiteral("summary"), current.value(QStringLiteral("remoteSummary"))},
        {QStringLiteral("versions"), detailMatches
             ? m_repository->versions() : QVariantList{}},
        {QStringLiteral("attachments"), current.value(QStringLiteral("remoteAttachments"))},
        {QStringLiteral("localAttachments"), localAttachments},
        {QStringLiteral("documentWorkspace"), m_repository->documentWorkspace()},
        {QStringLiteral("documentSpace"), m_repository->documentSpace()},
        {QStringLiteral("documentFolders"), m_repository->documentFolders()},
        {QStringLiteral("documentCapabilities"), m_repository->documentCapabilities()}
    });
}

void RenditionFlutterBridge::sendResult(const QString &requestId,
                                        const QVariantMap &result)
{
    sendEvent({{QStringLiteral("type"), QStringLiteral("commandResult")},
               {QStringLiteral("requestId"), requestId},
               {QStringLiteral("ok"), true},
               {QStringLiteral("result"), result}});
}

void RenditionFlutterBridge::sendError(const QString &requestId,
                                       const QString &code,
                                       const QString &message)
{
    sendEvent({{QStringLiteral("type"), QStringLiteral("commandResult")},
               {QStringLiteral("requestId"), requestId},
               {QStringLiteral("ok"), false},
               {QStringLiteral("code"), code},
               {QStringLiteral("message"), message}});
}

void RenditionFlutterBridge::sendEvent(const QVariantMap &event)
{
    emit eventReady(QString::fromUtf8(
        QJsonDocument::fromVariant(event).toJson(QJsonDocument::Compact)));
}
