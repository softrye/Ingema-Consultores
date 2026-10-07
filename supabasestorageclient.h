#pragma once

#include <QObject>
#include <QStringList>
#include <QByteArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

class SupabaseStorageClient : public QObject {
    Q_OBJECT
public:
    explicit SupabaseStorageClient(QString supabaseUrl = {},
                                   QString anonKey = {},
                                   QObject* parent = nullptr);

    // ✅ setters
    void setBaseUrl(const QString& u);
    void setAnonKey(const QString& k);

    // ✅ helpers (ANTES eran private -> por eso tu error)
    static QString chopSlash(QString s);
    static QString normalizeBaseUrl(QString u);

    // Storage API
    void uploadFile(const QString& accessToken,
                    const QString& bucket,
                    const QString& objectPath,
                    const QString& localFilePath,
                    const QString& contentType,
                    bool upsert = true);

    // ✅ NUEVO: subir bytes (para crear marker de carpeta .ingep_dir)
    void uploadBytes(const QString& accessToken,
                     const QString& bucket,
                     const QString& objectPath,
                     const QByteArray& bytes,
                     const QString& contentType,
                     bool upsert = true);

    void downloadFile(const QString& accessToken,
                      const QString& bucket,
                      const QString& objectPath);

    void moveObject(const QString& accessToken,
                    const QString& bucketId,
                    const QString& sourceKey,
                    const QString& destKey);

    void deleteObjects(const QString& accessToken,
                       const QString& bucketName,
                       const QStringList& prefixes);

    void listObjects(const QString& accessToken,
                     const QString& bucketName,
                     const QString& prefix,
                     int limit = 1000,
                     int offset = 0);

signals:
    void uploadFinished(const QString& objectPath, bool ok, const QString& error);
    void downloadFinished(const QString& objectPath, bool ok, const QByteArray& data, const QString& error);

    void moveFinished(const QString& sourceKey, const QString& destKey, bool ok, const QString& error);
    void deleteFinished(const QStringList& prefixes, bool ok, const QString& error);
    void listFinished(const QString& prefix, bool ok, const QByteArray& rawJson, const QString& error);

private:
    QString m_base;      // https://xxxx.supabase.co
    QString m_anonKey;
    QNetworkAccessManager m_net;

    void ensureSettingsLoaded(QString* inoutBucket);
    QNetworkRequest makeRequest(const QUrl& url, const QString& accessToken) const;

    void uploadTryMethod(const QByteArray& method,
                         const QString& accessToken,
                         const QString& bucket,
                         const QString& objectPath,
                         const QString& localFilePath,
                         const QString& contentType,
                         bool upsert);
};
