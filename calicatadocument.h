#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QVariantMap>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QImage>
#include <QtQml/qqmlregistration.h>

class CalicataDocument : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_DISABLE_COPY(CalicataDocument)

    Q_PROPERTY(QUrl fileUrl READ fileUrl NOTIFY fileUrlChanged)
    Q_PROPERTY(bool dirty READ dirty WRITE setDirty NOTIFY dirtyChanged)
    Q_PROPERTY(bool applyingCloudState READ applyingCloudState)
    Q_PROPERTY(QString displayName READ displayName NOTIFY displayNameChanged)
    Q_PROPERTY(QString instanceId READ instanceId NOTIFY instanceIdChanged)

    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    Q_PROPERTY(bool closed READ closed NOTIFY closedChanged)

    Q_PROPERTY(QVariantMap header READ header WRITE setHeader NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap uiState READ uiState WRITE setUiState NOTIFY dataChanged)
    Q_PROPERTY(QVariantList cortes READ cortes WRITE setCortes NOTIFY dataChanged)
    Q_PROPERTY(QString observaciones READ observaciones WRITE setObservaciones NOTIFY dataChanged)

    Q_PROPERTY(QVariantMap timestamp READ timestamp WRITE setTimestamp NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap images READ images WRITE setImages NOTIFY dataChanged)

    Q_PROPERTY(QString projectsFolderLabel READ projectsFolderLabel WRITE setProjectsFolderLabel NOTIFY projectsFolderLabelChanged)

    // Lifecycle shared with InGe+ Web (calicata_status) and cloud sync state
    // of this local mirror: LOCAL (never confirmed by the server), PENDING
    // (local changes not yet confirmed), SYNCING, SYNCED, CONFLICT (the
    // server row changed; row_version CAS rejected the write).
    Q_PROPERTY(QString status READ status NOTIFY dataChanged)
    Q_PROPERTY(QString syncState READ syncState NOTIFY dataChanged)

public:
    explicit CalicataDocument(QObject *parent = nullptr);
    ~CalicataDocument() override;

    QUrl fileUrl() const { return m_fileUrl; }
    bool dirty() const { return m_dirty; }
    bool applyingCloudState() const { return m_applyingCloudState; }
    QString displayName() const { return m_displayName; }
    QString instanceId() const { return m_instanceId; }

    QString errorString() const { return m_errorString; }
    bool closed() const { return m_closed; }

    QVariantMap header() const { return m_header; }
    void setHeader(const QVariantMap& value);

    QVariantMap uiState() const { return m_uiState; }
    void setUiState(const QVariantMap& value);

    QVariantList cortes() const { return m_cortes; }
    void setCortes(const QVariantList& value);

    QString observaciones() const { return m_observaciones; }
    void setObservaciones(const QString& value);

    QVariantMap timestamp() const { return m_timestamp; }
    void setTimestamp(const QVariantMap& value);

    QVariantMap images() const { return m_images; }
    void setImages(const QVariantMap& value);

    QString projectsFolderLabel() const { return m_projectsFolderLabel; }
    void setProjectsFolderLabel(const QString& value);

    Q_INVOKABLE bool load(const QUrl& url);
    Q_INVOKABLE bool selectProject(const QVariantMap &project);
    Q_INVOKABLE QVariantMap activeProject() const;
    Q_INVOKABLE bool transitionStatus(const QString &status);
    // Statuses reachable from the current one (single source of the rules).
    Q_INVOKABLE QStringList allowedStatusTransitions() const;
    // ARCHIVADO -> the status it was archived from (BORRADOR if unknown).
    Q_INVOKABLE bool restoreFromArchive();
    Q_INVOKABLE QString restoreTargetStatus() const;
    QString status() const;
    QString syncState() const;
    // Cloud state is owned by CalicataCloudService; it never marks the
    // document dirty.
    void setSyncState(const QString &state);
    Q_INVOKABLE QVariantList validationIssues(const QVariantMap &state) const;
    Q_INVOKABLE bool save();
    Q_INVOKABLE bool saveAsDefaultLocation(const QString& stem);
    Q_INVOKABLE bool saveAs(const QUrl& url, bool overwrite = false, bool copyPhotos = true);

    Q_INVOKABLE void markDirty();
    Q_INVOKABLE void setDirty(bool value);
    Q_INVOKABLE void resetNew();
    Q_INVOKABLE void prepareForClose();

    Q_INVOKABLE bool saveDraft();
    Q_INVOKABLE QVariantMap portableState(const QString &resourcesBase);
    Q_INVOKABLE bool restoreDraftIfNewer();
    Q_INVOKABLE void clearDraft();
    Q_INVOKABLE QVariantList listDrafts() const;
    Q_INVOKABLE QVariantList listDraftsForProject(const QString &projectId) const;
    // Local mirror of a project's calicatas, archived ones included on request.
    Q_INVOKABLE QVariantList listProjectDrafts(const QString &projectId, bool includeArchived) const;
    Q_INVOKABLE bool applyCloudSync(const QVariantMap &remoteRoot, const QVariantList &syncedCortes, bool fullSnapshot = false);
    void applyRemoteSnapshot(const QVariantMap &remoteRoot, const QVariantList &cortes);
    bool checkpointCloudRevision(const QString &projectId, const QString &remoteId, qint64 revision);
    // Live field change (CALICATA title/description) received from another person.
    // Not a user edit: no dirty, no draft write, no sync-state change (the
    // originating session persists it through its own sync).
    Q_INVOKABLE bool applyLiveHeaderField(const QString &key, const QVariant &value);
    Q_INVOKABLE bool loadDraftById(const QString& draftId);

    Q_INVOKABLE QUrl persistStampedPhotoToCache(int idx, const QUrl& sourceImageUrl);
    Q_INVOKABLE QUrl persistPhoto(int idx, const QUrl& sourceImageUrl, bool withStamp = false);
    Q_INVOKABLE QUrl cachedPhotoUrl(int idx) const;
    Q_INVOKABLE QUrl cachedPhotosFolderUrl(int idx) const;
    Q_INVOKABLE bool setPhotoFromCache(int idx, const QUrl& cachedFileUrl);
    Q_INVOKABLE bool copyPhotosFrom(CalicataDocument *source);
    Q_INVOKABLE void clearPhoto(int idx);

    // ===== Fotografías avanzadas (Web Media Cloud 02 contract) =====
    // foto<n>_original_path is immutable; foto<n>_path is the published
    // derivative. Rendering runs off the UI thread and answers with
    // derivedPhotoReady. Nothing here ever rewrites an original.
    Q_INVOKABLE QString photoCategoryCode(int idx) const;
    Q_INVOKABLE QUrl originalPhotoUrl(int idx) const;
    Q_INVOKABLE QVariantMap photoSlot(int idx) const;
    // Web CalicataPhotos "Descargar original" / "Descargar versión anotada":
    // copia exacta del archivo existente a la galería. "" = guardada.
    Q_INVOKABLE QString savePhotoToGallery(int idx, bool annotated);
    Q_INVOKABLE QVariantMap photoSheetMetadata() const;
    // Metadatos del rótulo de UNA foto: ficha + datos propios de su captura
    // (fecha/hora EXIF o de la app, altitud y posición de la foto).
    Q_INVOKABLE QVariantMap photoMetadata(int idx) const;
    // Fija una sola vez la hora de respaldo (sistema) de la foto idx si aún no
    // la tiene; las regeneraciones posteriores conservan esa hora.
    Q_INVOKABLE bool ensurePhotoSystemTime(int idx);
    // Instantánea opcional de la posición del dispositivo (lat/lon/altitud/
    // timestampMs) para la próxima foto: solo se usa si es fresca y la foto
    // acaba de tomarse; no activa el GPS.
    Q_INVOKABLE void setNextPhotoCaptureLocation(const QVariantMap &location) { m_nextCaptureLocation = location; }
    Q_INVOKABLE bool renderDerivedPhoto(int idx, const QVariantMap &edit);
    // Vista previa real del editor (mismo pipeline que la derivada); stage:
    // "result" | "annotate" | "geometry" | "source". Devuelve el token de la petición.
    Q_INVOKABLE int requestPhotoPreview(int idx, const QVariantMap &edit, const QString &stage = QStringLiteral("result"));
    Q_INVOKABLE QVariantMap suggestAutoWhiteBalance(int idx) const;
    Q_INVOKABLE bool savePhotoEditDraft(int idx, const QVariantMap &edit);
    // Logo de la ficha para la foto (PROJECT/ENTITY): misma resolución para vista previa,
    // derivada final y miniaturas del editor. "" = sin logo disponible.
    Q_INVOKABLE QString photoLogoUrl(const QString &source) const;
    // Raíz de Documentos del usuario: los logos se guardan relativos a ella.
    Q_INVOKABLE void setResourcesBase(const QString &base) { m_resourcesBase = base; }
    Q_INVOKABLE bool restorePhotoVersion(int idx, const QString &localVersionId);
    Q_INVOKABLE bool emptyPhotoSlot(int idx);
    // Cloud bookkeeping written by CalicataCloudService (never marks dirty by itself).
    Q_INVOKABLE void setPhotoCloudState(int idx, const QVariantMap &changes);
    bool bindStratumIdentity(const QString &localStratumId, const QString &remoteStratumId);
    // Web -> Android: adopt a downloaded cloud revision unless an unpublished
    // local edit of the slot exists (then false = conflict, nothing replaced).
    Q_INVOKABLE bool adoptRemotePhoto(int idx, const QVariantMap &remote);
    QString resolvedPhotoAbs(const QString &pathOrUrl) const { return resolveMaybeRelToAbs(pathOrUrl); }

    Q_INVOKABLE QString inferredProjectName() const;

signals:
    void fileUrlChanged();
    void dirtyChanged();
    void displayNameChanged();
    void errorStringChanged();
    void closedChanged();
    void dataChanged();
    void instanceIdChanged();
    void projectsFolderLabelChanged();
    void derivedPhotoReady(int idx, const QUrl &url, const QString &localVersionId, const QString &error);
    // persistPhoto(): la imagen publicable (con o sin rótulo) se genera fuera del hilo de UI;
    // este aviso confirma el commit local (url) o el fallo (error). La última importación gana.
    void photoPersisted(int idx, const QUrl &url, const QString &error);
    void photoPreviewReady(int idx, int token, const QUrl &url, const QString &error);
    void stratumIdentityBound(const QString &localStratumId, const QString &remoteStratumId);

private:
    bool m_applyingCloudState = false;
    void setErrorString(const QString& value);
    void clearError();

    QString defaultUserRootDir() const;
    QString defaultEditablesDir() const;

    QString absPathFromUrl(const QUrl& url) const;
    QUrl urlFromAbs(const QString& absPath) const;

    QVariantMap buildFullJson() const;
    bool applyFullJson(const QVariantMap& root);

    void updateDisplayName();

    bool hasSavedFile() const;
    QString baseDirAbs() const;
    QString calicataStem() const;

    QString photoTypeFolderName(int idx) const;
    QString photoPrefixForIdx(int idx) const;

    QString draftPhotosRootAbs() const;
    QString cachedPhotosTypeFolderAbs(int idx) const;
    QString photoAbsPath001(int idx) const;

    void ensurePhotosFolderStructure() const;
    void cleanupDraftPhotos();

    QImage readImageFromUrl(const QUrl& url) const;
    QVariantMap defaultPhotoEdit(bool withData) const;

    QString resolveMaybeRelToAbs(const QString& pathOrUrl) const;
    QString relFromAbsInBase(const QString& absPath) const;

    bool backupIfExists(const QString& destPath) const;
    bool isInsideDir(const QString& absFile, const QString& absDir) const;

    QString inferProjectNameFromPath() const;
    QString findProjectMetaAbs(const QString& startDirAbs) const;

    QString getDraftId() const;
    QString getDraftPath() const;
    QVariantList scanDrafts(bool includeArchived) const;
    void stampLocalAuthorship();
    bool writeDraftJson(const QString& path);
    bool commitPhotoImages(const QVariantMap &images);

private:
    QUrl m_fileUrl;
    bool m_dirty = false;
    bool m_loadedFromDisk = false;
    QVariantMap m_nextCaptureLocation;
    bool m_closed = false;
    // Local edits that happened while a sync was in flight: the confirmed
    // result then lands as PENDING, not SYNCED.
    bool m_changedWhileSyncing = false;

    QString m_displayName;
    QString m_errorString;
    QString m_instanceId;
    // Vista previa del editor de fotos (una en curso por slot; la última gana).
    void launchPhotoPreview(int idx, int token, const QVariantMap &edit);
    QString photoLogoPath(const QString &source) const;
    QString m_resourcesBase;
    int m_photoPreviewSerial = 0;
    QHash<int, int> m_photoPreviewLatest;
    QHash<int, QString> m_photoPreviewPath;
    QSet<int> m_photoPreviewRunning;
    QHash<int, QVariantMap> m_photoPreviewPending;
    QHash<int, int> m_photoPreviewPendingToken;
    int m_photoPersistSerial = 0;
    QHash<int, int> m_photoPersistLatest;

    QVariantMap m_header;
    QVariantMap m_extraRoot;
    QVariantMap m_uiState;
    QVariantList m_cortes;
    QString m_observaciones;

    QVariantMap m_timestamp;
    QVariantMap m_images;

    // Identidad estable del staging de fotos mientras la ficha no tiene fileUrl.
    // Cada CalicataDocument pertenece a una sola pestaña, por lo que este id evita
    // que dos borradores compartan imágenes pendientes.
    QString m_photoDraftId;

    QString m_projectsFolderLabel = QStringLiteral("InGePlusProyectos");
};
