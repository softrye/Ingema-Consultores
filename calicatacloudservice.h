#pragma once

#include "calicatasyncpolicy.h"

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QSet>
#include <QStringList>
#include <functional>

class CalicataDocument;
class QJsonDocument;
class QNetworkReply;
class QUrl;
class QUrlQuery;
class QSslSocket;
class QTimer;

// Android bridge for the canonical Calicatas domain already used by InGe+ Web.
// It deliberately keeps local document UUIDs separate from remote calicatas.id.
class CalicataCloudService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    // Active (non archived) and archived calicatas of the last listed project.
    Q_PROPERTY(QVariantList projectCalicatas READ projectCalicatas NOTIFY projectCalicatasChanged)
    Q_PROPERTY(QVariantList archivedProjectCalicatas READ archivedProjectCalicatas NOTIFY projectCalicatasChanged)
    Q_PROPERTY(QString listedProjectId READ listedProjectId NOTIFY projectCalicatasChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(int pendingActivityCount READ pendingActivityCount NOTIFY pendingActivityChanged)
    Q_PROPERTY(int pendingMediaCount READ pendingMediaCount NOTIFY mediaQueueChanged)
    // P6 presence of the open ficha (Web presenceService contract).
    Q_PROPERTY(QVariantList presenceMembers READ presenceMembers NOTIFY presenceChanged)
    Q_PROPERTY(QString presenceState READ presenceState NOTIFY presenceChanged)

public:
    explicit CalicataCloudService(QObject *parent = nullptr);

    QVariantList projects() const { return m_projects; }
    QVariantList projectCalicatas() const { return m_projectCalicatas; }
    QVariantList archivedProjectCalicatas() const { return m_archivedProjectCalicatas; }
    QString listedProjectId() const { return m_listedProjectId; }
    bool busy() const { return m_pendingRequests > 0; }
    QString lastError() const { return m_lastError; }
    int pendingActivityCount() const;
    int pendingMediaCount() const { return m_mediaOutbox.size(); }
    QVariantList presenceMembers() const { return m_presenceMembers; }
    QString presenceState() const { return m_presenceState; }
    Q_INVOKABLE void joinPresence(CalicataDocument *document);
    Q_INVOKABLE void leavePresence();
    Q_INVOKABLE void setPresenceActive(bool active);     // app foreground/background
    Q_INVOKABLE void setPresenceField(const QString &field); // "" = viewing
    // Live field change (canonical Web contract, docs/CALICATAS_LIVE_COLLAB_V1.md):
    // durable RPC apply_calicata_field_change_v02 first; only the standing
    // change it returns is broadcast as "calicata-field-change". targetType:
    // CALICATA | STRATUM | LAB_RESULT (target id = stratum id). Returns false when the change
    // is not eligible for live (not joined, not draft, unknown field): the normal
    // full save carries it. The outcome arrives in fieldChangeSettled.
    Q_INVOKABLE bool applyFieldChange(CalicataDocument *document, const QString &targetType,
                                      const QString &targetId, const QString &field, const QVariant &value);

    // Cota del terreno vía Edge Function resolve-calicata-elevation (evidencias
    // geoespaciales + validación Gemini; la app nunca consulta proveedores
    // directamente). Resultado en elevationResolved(requestId, result).
    Q_INVOKABLE bool resolveElevation(const QString &requestId, const QVariantMap &input);

    Q_INVOKABLE void refreshProjects();
    Q_INVOKABLE void listProjectCalicatas(const QString &projectId);
    Q_INVOKABLE void resolveProjectWorkspace(const QString &projectId);
    Q_INVOKABLE void loadRemoteDocument(CalicataDocument *document, const QString &projectId,
                                        const QString &calicataId);
    // reason: "save" (explicit save, UPDATE_CALICATA) or "export" (system
    // sync before publishing, SYNC_CALICATA). The first creation is always
    // CREATE_CALICATA.
    Q_INVOKABLE QString syncDocument(CalicataDocument *document,
                                     const QString &reason = QStringLiteral("save"));
    Q_INVOKABLE QString archiveDocument(CalicataDocument *document);
    // Lifecycle transition validated by CalicataDocument. Confirmed with the
    // server when the calicata already has a cloud identity; offline it stays
    // local (sync_state PENDING) and travels with the next sync.
    Q_INVOKABLE QString changeStatus(CalicataDocument *document, const QString &status);
    // ARCHIVADO -> previous status. Synced calicatas need the server.
    Q_INVOKABLE QString restoreDocument(CalicataDocument *document);
    // Fast local check of UNIQUE(project_id, code) against the listed
    // project mirror and local drafts bound to other cloud rows. Empty when
    // no conflict is known; the backend (23505) stays authoritative.
    Q_INVOKABLE QString codeConflict(CalicataDocument *document) const;
    // Export events use the controlled idempotent RPC, platform ANDROID.
    // Domain changes are already audited server-side; the per-user outbox survives offline.
    Q_INVOKABLE bool logActivity(CalicataDocument *document, const QString &action,
                                 const QString &description, const QVariantMap &metadata);
    Q_INVOKABLE void flushActivity();

    // ===== Media Cloud (Web calicata_media contract, P1) =====
    // Photo slots: create -> reserve version -> upload original/derivative ->
    // finalize. Logos PROJECT/ENTITY: create -> reserve original -> upload ->
    // finalize. Every operation is persisted per user before touching the
    // network and survives closing the ficha, the app or the process.
    Q_INVOKABLE QString enqueuePhotoSync(CalicataDocument *document, int idx);
    Q_INVOKABLE QString enqueueLogoSync(CalicataDocument *document, const QString &categoryCode);
    // Fills project/calicata ids of entries queued before the ficha had a cloud row.
    Q_INVOKABLE void bindMediaIdentity(CalicataDocument *document);
    Q_INVOKABLE void flushMedia();
    // keepMine=true retries overriding the remote change; false drops the local op.
    Q_INVOKABLE bool resolveMediaConflict(const QString &entryId, bool keepMine);
    Q_INVOKABLE QVariantList mediaEntriesFor(const QString &localDocumentId) const;
    // Confirmed results for a ficha that was closed while syncing; applied once.
    Q_INVOKABLE QVariantList takeConfirmedMedia(const QString &localDocumentId);
    Q_INVOKABLE void loadPhotoHistory(CalicataDocument *document, int idx);
    // Web -> Android media: signed read of the slot's active revision (or versionId).
    Q_INVOKABLE void downloadRemotePhoto(CalicataDocument *document, int idx, const QString &versionId = QString());
    Q_INVOKABLE void activateCloudPhotoVersion(CalicataDocument *document, int idx, const QString &versionId);
    Q_INVOKABLE void discardCloudPhotoVersion(CalicataDocument *document, int idx, const QString &versionId, bool discarded);
    Q_INVOKABLE void loadRemoteLogos(CalicataDocument *document, const QString &resourcesDir);
    Q_INVOKABLE void restoreRemoteLogo(CalicataDocument *document, const QString &categoryCode,
                                       const QString &storagePath, const QString &resourcesDir);
    // activity_logs of this calicata, newest first, 30 per page.
    Q_INVOKABLE void loadActivity(CalicataDocument *document, int offset = 0);

    // InGeDrive: copia JSON versionada de la ficha (el Smart Document sigue siendo
    // la representación canónica). Destino por defecto: 06_GABINETE del espacio del
    // proyecto (se crea si falta); `targetFolderId` = "Guardar en…" (mismo proyecto).
    // Devuelve "" si el guardado arrancó o el motivo por el que no puede arrancar.
    Q_INVOKABLE QString saveJsonToDrive(CalicataDocument *document, const QString &resourcesBase,
                                        const QString &targetFolderId = QString());
    Q_INVOKABLE void listDriveFolders(const QString &projectId, const QString &parentNodeId = QString());
    Q_INVOKABLE void openDriveJson(const QString &spaceId, const QString &nodeId, const QString &versionId);

signals:
    void driveJsonSaved(const QString &localDocumentId, const QVariantMap &result);
    void driveJsonSaveFailed(const QString &localDocumentId, const QString &message);
    void driveFoldersListed(const QString &projectId, const QString &parentNodeId,
                            const QString &spaceId, const QVariantList &folders);
    void driveFoldersFailed(const QString &message);
    void driveJsonDownloaded(const QString &localPath);
    void driveJsonDownloadFailed(const QString &message);
    void projectsChanged();
    void projectCalicatasChanged();
    void busyChanged();
    void lastErrorChanged();

    void projectsLoadFailed(const QString &message);
    void projectCalicatasLoaded(const QString &projectId, const QVariantList &rows);
    void projectCalicatasLoadFailed(const QString &projectId, const QString &message);
    void workspaceResolved(const QString &projectId, const QString &spaceId);
    void workspaceResolveFailed(const QString &projectId, const QString &message);
    void remoteLoadSucceeded(const QString &localDocumentId, const QString &projectId,
                             const QString &calicataId);
    void remoteLoadFailed(const QString &localDocumentId, const QString &message);

    void elevationResolved(const QString &requestId, const QVariantMap &result);
    void syncSucceeded(const QString &localDocumentId, const QVariantMap &result);
    void syncFailed(const QString &localDocumentId, const QString &message);
    void archiveSucceeded(const QString &localDocumentId);
    void archiveFailed(const QString &localDocumentId, const QString &message);
    // confirmed=false: applied locally, pending the next sync (offline).
    void statusChangeSucceeded(const QString &localDocumentId, const QString &status, bool confirmed);
    void statusChangeFailed(const QString &localDocumentId, const QString &message);
    void restoreSucceeded(const QString &localDocumentId, const QString &status, bool confirmed);
    void restoreFailed(const QString &localDocumentId, const QString &message);
    void pendingActivityChanged();
    void mediaQueueChanged();
    void presenceChanged();
    // Canonical "calicata-field-change" from another person (validated, deduplicated).
    void fieldChangeReceived(const QString &calicataId, const QVariantMap &change);
    // Result of applyFieldChange: outcome APPLIED | SUPERSEDED (standing change
    // of someone else) | REFUSED (server decision) | UNAVAILABLE (network/server).
    void fieldChangeSettled(const QString &localDocumentId, const QVariantMap &result);
    // Rejoined after a disconnect: missed changes are not replayed; revalidate.
    void liveResyncRequested(const QString &calicataId);
    // state: PENDING | SYNCING | SYNCED | CONFLICT | FAILED. changes are the
    // CalicataDocument::setPhotoCloudState keys for photo slots (idx 1..3) or
    // {categoryCode, mediaId} for logos (idx 0).
    void mediaSyncChanged(const QString &localDocumentId, int idx, const QString &state,
                          const QString &message, const QVariantMap &changes);
    void photoHistoryLoaded(const QString &localDocumentId, int idx, const QVariantList &versions);
    void remoteLogoLoaded(const QString &localDocumentId, const QString &categoryCode,
                          const QString &localPath, const QVariantList &history);
    void remoteLogoRestored(const QString &localDocumentId, const QString &categoryCode,
                            const QString &localPath, const QString &error);
    void activityLoaded(const QString &localDocumentId, const QVariantList &rows, int offset, bool hasMore);

private:
    using JsonCallback = std::function<void(bool, const QJsonDocument &, const QString &, const QString &)>;
    using StatusCallback = std::function<void(bool confirmed, const QString &code, const QString &message)>;

    void beginRequest();
    void syncAccountContext();
    void endRequest();
    void setLastError(const QString &message);

    void getJson(const QUrl &url, JsonCallback callback);
    void postRpc(const QString &rpcName, const QVariantMap &arguments, JsonCallback callback);
    void patchRows(const QString &table, const QUrlQuery &query,
                   const QVariantMap &changes, JsonCallback callback);
    void insertRow(const QString &table, const QVariantMap &row, JsonCallback callback);

    // CAS status write (row_version) shared by status change, archive and restore.
    void patchRemoteStatus(CalicataDocument *document, const QString &status, StatusCallback done);
    void commitStatusChange(CalicataDocument *document, const QString &next);

    // Coordinador por ficha (CalicataSync::Lane): una escritura que mueva
    // calicatas.row_version en vuelo; al liberar arranca la siguiente.
    void releaseLane(const QString &localId);
    void noteConfirmedRevision(const QString &localId, const QString &remoteId, qint64 revision);
    // GET de la fila raíz (columnas de contenido + row_version) para atribuir revisiones.
    void probeRoot(const QString &projectId, const QString &remoteId,
                   std::function<void(bool ok, const QVariantMap &row)> done);
    // Cambio live de la FICHA (mueve row_version según el servidor) dentro del carril.
    // `send(after)` publica el cambio; after(1|0|2) = aplicado / no aplicado / desconocido.
    void runLiveCalicataChange(CalicataDocument *document, const QString &field, const QVariant &value,
                               std::function<void(std::function<void(int)>)> send);

    void enqueueActivity(const QString &projectId, const QString &calicataId,
                         const QString &action, const QString &description,
                         const QVariantMap &metadata);
    void ensureActivityOutbox();
    void saveActivityOutbox();
    void setPresenceState(const QString &state);
    void rtConnect();
    void rtDisconnect(bool leave);
    void rtScheduleRetry();
    void rtSendFrame(quint8 opcode, const QByteArray &payload);
    void rtSendJson(const QVariantMap &message);
    void rtOnReadyRead();
    void rtHandleMessage(const QByteArray &raw);
    void rtTrack();
    void rtRebuildMembers();
    void ensureMediaOutbox();
    void saveMediaOutbox();
    void processMediaEntry(int index);
    void finishMediaEntry(const QString &entryId, const QString &state, const QString &message,
                          const QVariantMap &changes);
    void downloadStorageObject(const QString &path, const QString &destAbs,
                               std::function<void(bool ok, const QString &message)> done);
    void uploadStorageObject(const QString &path, const QString &localFile, const QString &mimeType,
                             std::function<void(bool ok, const QString &message)> done,
                             const QString &bucket = QString());
    // Hijos directos de una carpeta de InGeDrive (paginación por defecto del servidor).
    // 04_PROYECTOS/<proyecto>/06_GABINETE (se crea si falta). done(ok, spaceId, folderId, error).
    void ensureProjectGabinete(const QString &projectId,
                               std::function<void(bool ok, const QString &spaceId, const QString &folderId,
                                                  const QString &error)> done);
    void listDriveChildren(const QString &spaceId, const QString &parentNodeId,
                           std::function<void(bool ok, const QVariantList &rows, const QString &error)> done);

    QVariantList m_projects;
    QString m_contextOwner;
    quint64 m_contextEpoch = 0;
    quint64 m_projectListRequest = 0;
    QVariantList m_projectCalicatas;
    QVariantList m_archivedProjectCalicatas;
    QVariantList m_allProjectCalicatas;
    QString m_listedProjectId;
    int m_pendingRequests = 0;
    QString m_lastError;
    QHash<QString, CalicataSync::Lane> m_lanes;             // por instanceId local
    QHash<QString, QPointer<CalicataDocument>> m_laneDocs;  // documento de cada carril
    QHash<QString, qint64> m_confirmedRevisions;            // por calicatas.id: confirmada en sesión
    QSet<QString> m_driveJsonOperations;

    QString m_activityUserId;
    QVariantList m_activityOutbox;
    bool m_activityFlushing = false;
    QString m_mediaUserId;
    QVariantList m_mediaOutbox;
    QVariantMap m_mediaConfirmed;
    bool m_mediaFlushing = false;
    QSslSocket *m_rtSocket = nullptr;
    QTimer *m_rtHeartbeat = nullptr;
    QTimer *m_rtRetry = nullptr;
    QByteArray m_rtBuffer;
    QByteArray m_rtFragment;
    bool m_rtHandshaken = false;
    bool m_rtActive = true;
    int m_rtRef = 0;
    int m_rtRetryStep = 0;
    qint64 m_rtJoinedAt = 0;
    QString m_rtCalicataId;
    QString m_rtJoinRef;
    QString m_rtToken;
    QString m_rtField;
    QVariantMap m_rtPresence;
    QVariantList m_presenceMembers;
    QString m_presenceState = QStringLiteral("OFF");
    // Live field changes: rejoin detection and local changeId dedup.
    bool m_rtEverJoined = false;
    QStringList m_liveSeenOrder;
    QSet<QString> m_liveSeen;
    void rtHandleBroadcast(const QVariantMap &broadcast);
};
