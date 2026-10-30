#pragma once

#include "renditionconnectivity.h"

#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantMap>
#include <QHash>

namespace inge::core { class RemoteExecutor; }
class RenditionLocalStore;
class RenditionRepository;
class RenditionSyncController;
class AndroidCalicataExporter;

// Adaptador de comandos JSON del dominio Renditions V02 (sin interfaz, Visual
// Zero 2026-10-10). No contiene reglas de negocio ni acceso a Supabase: traduce
// comandos JSON (submit) a las APIs existentes y publica estado y resultados
// como JSON mediante eventReady. Sin JNI: ningún consumidor visual conectado.
class RenditionFlutterBridge final : public QObject
{
    Q_OBJECT

public:
    explicit RenditionFlutterBridge(RenditionRepository *repository,
                                     RenditionLocalStore *store,
                                     RenditionSyncController *syncController,
                                     AndroidCalicataExporter *exporter,
                                     QObject *parent = nullptr);
    ~RenditionFlutterBridge() override;
    void setCoreRemote(inge::core::RemoteExecutor *core);

    Q_INVOKABLE void submit(const QString &requestJson);
    Q_INVOKABLE void openDocumentTarget(const QString &renditionId);
    Q_INVOKABLE void pickCalicataProject(const QString &documentId);

signals:
    void calicataProjectPickerRequested();
    void calicataProjectPicked(const QString &documentId, const QVariantMap &project);
    void globalActionRequested(const QString &action);
    void eventReady(const QString &eventJson);

private:
    void handleCommand(const QString &requestJson);
    void publishState();
    void publishStateNow();
    void refreshRemoteDetail();
    void startRemotePull(const QString &requestId = {},
                         const QString &reason = QStringLiteral("refresh"));
    void completeRemotePullOperation(const QString &operation);
    void failRemotePull(const QString &operation, const QString &code,
                        const QString &message);
    void continuePresentationAfterSync();
    void clearPendingPresentation();
    // Conectividad (fuente única): evidencia de red/transporte -> estado publicado.
    void applyConnectivity(bool changed);
    void scheduleRetry();
    void reconnect();
    void observeLocalCode(const QString &code);
    void sendEvent(const QVariantMap &event);
    void sendResult(const QString &requestId, const QVariantMap &result = {});
    void sendError(const QString &requestId, const QString &code,
                   const QString &message);

    inge::core::RemoteExecutor *m_core = nullptr;
    QSet<QString> m_coreRequests;
    RenditionRepository *m_repository = nullptr;
    RenditionLocalStore *m_store = nullptr;
    RenditionSyncController *m_syncController = nullptr;
    AndroidCalicataExporter *m_exporter = nullptr;
    QString m_selectedLocalId;
    QString m_calicataPickerDocument;
    QString m_documentTargetRemoteId;
    int m_documentOpenRevision = 0;
    bool m_documentTargetLoading = false;
    QVariantMap m_receivedSnapshot;
    QHash<QString, QVariantMap> m_receivedRequests;
    QString m_pendingPresentationRequestId;
    QString m_pendingPresentationLocalId;
    QString m_pendingSyncRequestId;
    QString m_pendingPullRequestId;
    QString m_pendingPullReason;
    QString m_pendingWorkspaceRequestId;
    QString m_pendingFoldersRequestId;
    QString m_lastPullAt;
    QString m_lastServerConfirmationAt;
    RenditionConnectivity::State m_link;
    QTimer m_retryTimer;                 // reintento controlado (sin sondeo continuo)
    // Working Document: UNKNOWN hasta la primera respuesta; UNAVAILABLE con PGRST202
    // (contrato no desplegado en este entorno: sin escrituras, borradores locales).
    QString m_workingContract = QStringLiteral("UNKNOWN");
    QTimer m_workingSyncTimer;           // agrupa guardados de borrador antes de enviarlos
    void scheduleWorkingSync(int delayMs);
    bool m_selectionPullPending = false; // detalle elegido durante otro pull
    int m_selectionSerial = 0;           // token de cada apertura de detalle (select)
    QSet<QString> m_pendingPullOperations;
    QTimer m_pullWatchdog;               // un pull sin todas sus respuestas no queda colgado
    bool m_presentAfterSync = false;
    QTimer m_publishTimer;
    QVariantMap m_lastPublishedState;
    QTimer m_renderDiagnosticsTimer;
    int m_publishRequests = 0;
    int m_publishEmissions = 0;
};
