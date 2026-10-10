#pragma once

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
    void updateConnectionState(const QString &code);
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
    QString m_connectionState = QStringLiteral("UNKNOWN");
    QSet<QString> m_pendingPullOperations;
    bool m_presentAfterSync = false;
    QTimer m_publishTimer;
};
