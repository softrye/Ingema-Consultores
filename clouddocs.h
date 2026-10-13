#pragma once
#include <QObject>
#include <QString>
#include <QVector>
#include <QUrl>
#include <QHash>
#include <QMetaType>
#include <functional>


class SupabaseClient;
class AuthSession;

struct CloudDocItem {
    QString name;         // nombre devuelto por list (relativo al prefix)
    QString objectKey;    // key completo: userId/projectId/relativePath...
    QString relativePath; // relativo al proyecto: "Calicatas/Edit/xxx.json", "Resources/a.png", etc.
    bool    isFolder = false;

    qint64  size = 0;
    QString updatedAt;    // ISO string si viene
    QString etag;         // (si viene en metadata)
    QString mimeType;     // (si viene en metadata)
};

Q_DECLARE_METATYPE(CloudDocItem)
Q_DECLARE_METATYPE(QVector<CloudDocItem>)

class CloudDocs : public QObject {
    Q_OBJECT
public:
    explicit CloudDocs(SupabaseClient* api, AuthSession* auth, QObject* parent=nullptr);

    void setBucket(const QString& bucket) { m_bucket = bucket; }
    QString bucket() const { return m_bucket; }

    // objectKey = userId/projectId/relativePath
    QString projectPrefix(const QString& projectId) const; // userId/projectId/
    QString objectKeyFor(const QString& projectId, const QString& relativePath) const;

    // ==========================
    // NUEVO (OneDrive-like)
    // ==========================
    // Lista TODO debajo de userId/projectId/(remoteDir opcional)
    // remoteDir puede ser "" (raíz del proyecto) o "Calicatas", "Calicatas/Edit", etc.
    void listProjectTree(const QString& projectId, const QString& remoteDir);
    void listProjectTree(const QString& projectId) { listProjectTree(projectId, QString()); }

    // Documents browser pagination. Empty projectId lists the current user's root.
    void listPage(const QString& projectId, const QString& remoteDir, int offset, int limit = 100);




    // Alias (si quieres seguir usando el nombre "listFolder")
    void listFolder(const QString& projectId, const QString& remoteDir = QString()) { listProjectTree(projectId, remoteDir); }

    // Subir cualquier archivo (json, pdf, jpg, etc.)
    void uploadFile(const QString& localPath,
                    const QString& projectId,
                    const QString& relativePath,
                    const QString& contentType = QString(),
                    bool upsert = true);

    // Descargar por (projectId + relativePath)
    void downloadFile(const QString& projectId,
                      const QString& relativePath,
                      const QString& savePath);

    // Borrar remoto (útil para "delete" del plan de sync)
    void removeFile(const QString& projectId,
                    const QString& relativePath);

    // ==========================
    // LEGACY (tus métodos)
    // ==========================
    void uploadJson(const QString& localPath);
    void uploadJson(const QString& localPath, const QString& projectId, const QString& remoteDir = "Edit");

    void listMyJson();
    void listMyJson(const QString& projectId, const QString& remoteDir = "Edit");

    void downloadJson(const QString& objectKey, const QString& savePath);
    using DownloadCompletion = std::function<void(bool, const QString&)>;
    // Canonical binary downloads use the bucket/path returned by Files Core.
    void downloadExact(const QString& bucket, const QString& objectKey, const QString& savePath,
                       qint64 expectedSize, DownloadCompletion done);
    // Files Core 01E: sube al bucket/path EXACTOS que reservó el servidor
    // (reserve_binary_document_*), sin upsert. No emite uploadOk/uploadFail.
    void uploadExact(const QString& localPath, const QString& bucket, const QString& objectKey,
                     const QString& contentType, std::function<void(bool ok, const QString& error)> done);
    void uploadLocalAuto(const QString& localPath, bool upsert = true);
    void uploadProjectTree(const QString& projectRoot, bool upsert = true);
    void moveFile(const QString& projectId, const QString& fromRel, const QString& toRel);
    void setUserFolderAlias(const QString& alias);
    void setProjectFolderAlias(const QString& projectId, const QString& alias);

signals:
    void uploadOk(const QString& objectKey);
    void uploadFail(const QString& msg);

    void listOk(const QVector<CloudDocItem>& items);
    void listFail(const QString& msg);

    void downloadOk(const QString& savePath);
    void downloadFail(const QString& msg);

    void removeOk(const QString& objectKey);
    void removeFail(const QString& msg);

    void moveOk(const QString& fromKey, const QString& toKey);
    void moveFail(const QString& msg);

private:
    bool ensureReadyAndLogged(QString* whyNot = nullptr) const;

    QString inferProjectIdFromLocalPath(const QString& localPath) const;

    QString userPrefix() const; // userId
    QString cleanSegment(const QString& s) const;

    QString ensureObjectKeyForUploadLegacy(const QString& localPath,
                                           const QString& projectId,
                                           const QString& remoteDir) const;

    QUrl storageObjectUrl(const QString& objectKey) const;
    QUrl storageListUrl() const;

    // IMPORTANTE: aquí ya “normalizamos” relativePath como:
    // objectKey - (userId/projectId/)
    void listByPrefix(const QString& prefixObjectKey,
                      const QString& projectIdForRelative,
                      int offset = -1, int limit = 100); // <-- clave para OneDrive

    static QString guessContentType(const QString& localPath);

    QString m_userFolderAlias;
    QHash<QString, QString> m_projectFolderAlias;

    QString userFolderKey() const;
    QString projectFolderKey(const QString& projectId) const;

    static QString toFolderKey(QString s);

private:
    SupabaseClient* m_api = nullptr;
    AuthSession* m_auth = nullptr;
    quint64 m_accountEpoch = 0;
    void downloadObject(const QString& bucket, const QString& objectKey, const QString& savePath,
                        qint64 expectedSize, DownloadCompletion done);

    QString inferRelativePathFromLocalPath(const QString& localPath, const QString& projectId) const;

    QString m_bucket = "IngePlus"; // debe coincidir con AppContext/Supabase
};
