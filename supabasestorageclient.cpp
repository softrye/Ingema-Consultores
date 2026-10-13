#include "supabasestorageclient.h"
#include "settingshelper.h"

#include <QSettings>
#include <QDebug>
#include <QFile>
#include <QUrl>
#include <QRegularExpression>

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QBuffer>

static QString firstNonEmpty(QSettings& s, const QStringList& keys)
{
    for (const auto& k : keys) {
        const QString v = s.value(k).toString().trimmed();
        if (!v.isEmpty()) return v;
    }
    return {};
}



QString SupabaseStorageClient::chopSlash(QString s)
{
    s = s.trimmed();
    while (s.endsWith('/')) s.chop(1);
    return s;
}

QString SupabaseStorageClient::normalizeBaseUrl(QString u)
{
    u = u.trimmed();
    if (u.endsWith('/')) u.chop(1);
    if (!u.startsWith("http://") && !u.startsWith("https://"))
        u = "https://" + u;
    return u;
}

static QString percentDecodeRepeated(QString s, int maxRounds = 3)
{
    for (int i = 0; i < maxRounds; ++i) {
        const QString before = s;
        const QByteArray out = QByteArray::fromPercentEncoding(s.toUtf8());
        s = QString::fromUtf8(out.constData(), out.size());
        if (s == before) break;
    }
    return s;
}

static QString stripDiacritics(QString s)
{
    const QString n = s.normalized(QString::NormalizationForm_D);
    QString out;
    out.reserve(n.size());

    for (const QChar c : n) {
        switch (c.category()) {
        case QChar::Mark_NonSpacing:
        case QChar::Mark_SpacingCombining:
        case QChar::Mark_Enclosing:
            continue;
        default:
            out.append(c);
        }
    }
    return out;
}

static QString toSafeStoragePath(QString objectPath)
{
    objectPath.replace('\\', '/');

    // Si llega "CT-0%2B000.xlsx" => "CT-0+000.xlsx"
    objectPath = percentDecodeRepeated(objectPath);

    QStringList parts = objectPath.split('/', Qt::SkipEmptyParts);

    // Permitimos '+'
    static const QRegularExpression bad(QStringLiteral("[^A-Za-z0-9._+\\-]"));
    static const QRegularExpression multi(QStringLiteral("_+"));

    for (QString &seg : parts) {
        seg = stripDiacritics(seg);
        seg.replace(' ', '_');
        seg.replace('%', '_');          // neutraliza % literal
        seg.replace(bad, "_");
        seg.replace(multi, "_");
        if (seg.isEmpty()) seg = "_";
    }

    return parts.join('/');
}

static QString hardenStoragePath(QString s)
{
    s = percentDecodeRepeated(s);
    s.replace(QRegularExpression("%[0-9A-Fa-f]{2}"), "_"); // por si quedó algo raro
    s.replace('%', '_');
    return s;
}

static QUrl buildStorageObjectUrl(const QString& base,
                                  const QString& routePrefix,
                                  const QString& bucket,
                                  const QString& safePath)
{
    const QString baseNoSlash = SupabaseStorageClient::chopSlash(base);
    const QString prefix = baseNoSlash + routePrefix + bucket + "/";

    // Mantenemos '/' como separador
    // ✅ Permitimos '+' SIN que se convierta en %2B
    const QByteArray encPath = QUrl::toPercentEncoding(safePath, "/._-+");


    return QUrl::fromEncoded(prefix.toUtf8() + encPath);
}

static QUrl buildStorageApiUrl(const QString& base, const QString& path)
{
    QString b = base;
    if (b.endsWith('/')) b.chop(1);
    return QUrl(b + path);
}

static void loadSupabaseFromSettings(QString* url, QString* anon, QString* bucket)
{
    QSettings s = appSettings();
    qDebug() << "[StorageClient] where:" << s.fileName();

    // URL
    if (url) {
        QString u = firstNonEmpty(s, {
                                         "supabase/url",
                                         "supabase/base_url",
                                         "base_url"
                                     });
        u = SupabaseStorageClient::normalizeBaseUrl(u);
        *url = SupabaseStorageClient::chopSlash(u);
    }

    // ✅ ANON: soporta tu key "supabase/anon_key" + compat
    if (anon) {
        *anon = firstNonEmpty(s, {
                                     "supabase/anon_key",
                                     "supabase/anon",
                                     "supabase/anon-key",
                                     "anon_key",
                                     "supabase/anonKey"
                                 });
    }

    // Bucket
    if (bucket) {
        *bucket = firstNonEmpty(s, {
                                       "supabase/bucket",
                                       "bucket"
                                   });
    }
}

SupabaseStorageClient::SupabaseStorageClient(QString supabaseUrl,
                                             QString anonKey,
                                             QObject* parent)
    : QObject(parent),
    m_base(std::move(supabaseUrl)),
    m_anonKey(std::move(anonKey))
{
    m_base = normalizeBaseUrl(m_base);
    m_base = chopSlash(m_base);
    m_anonKey = m_anonKey.trimmed();
}

void SupabaseStorageClient::setBaseUrl(const QString& u)
{
    m_base = normalizeBaseUrl(u);
    m_base = chopSlash(m_base);
}

void SupabaseStorageClient::setAnonKey(const QString& k)
{
    m_anonKey = k.trimmed();
}

void SupabaseStorageClient::ensureSettingsLoaded(QString* inoutBucket)
{
    QString bucketUse = inoutBucket ? inoutBucket->trimmed() : QString();

    if (!m_base.trimmed().isEmpty() && !m_anonKey.trimmed().isEmpty() && !bucketUse.isEmpty())
        return;

    QString url = m_base;
    QString anon = m_anonKey;
    QString bucket = bucketUse;

    loadSupabaseFromSettings(&url, &anon, &bucket);

    if (m_base.trimmed().isEmpty())    m_base    = url;
    if (m_anonKey.trimmed().isEmpty()) m_anonKey = anon;
    if (bucketUse.isEmpty())           bucketUse = bucket;

    if (inoutBucket) *inoutBucket = bucketUse.trimmed();
}

QNetworkRequest SupabaseStorageClient::makeRequest(const QUrl& url, const QString& accessToken) const
{
    QNetworkRequest req(url);

#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
#endif

    req.setRawHeader("apikey", m_anonKey.toUtf8());

    if (!accessToken.trimmed().isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken.toUtf8());
    }

    return req;
}

void SupabaseStorageClient::uploadFile(const QString& accessToken,
                                       const QString& bucket,
                                       const QString& objectPath,
                                       const QString& localFilePath,
                                       const QString& contentType,
                                       bool upsert)
{
    uploadTryMethod("POST", accessToken, bucket, objectPath, localFilePath, contentType, upsert);
}

void SupabaseStorageClient::uploadTryMethod(const QByteArray& method,
                                            const QString& accessToken,
                                            const QString& bucket,
                                            const QString& objectPath,
                                            const QString& localFilePath,
                                            const QString& contentType,
                                            bool upsert)
{
    QString bucketUse = bucket.trimmed();
    ensureSettingsLoaded(&bucketUse);

    if (m_base.trimmed().isEmpty() || m_anonKey.trimmed().isEmpty() || bucketUse.isEmpty()) {
        emit uploadFinished(objectPath, false, "Falta configuración Supabase (url/anon/bucket).");
        return;
    }

    QFile* f = new QFile(localFilePath);
    if (!f->open(QIODevice::ReadOnly)) {
        emit uploadFinished(objectPath, false, QString("No se pudo abrir archivo: %1").arg(localFilePath));
        delete f;
        return;
    }

    QString safePath = toSafeStoragePath(objectPath);
    safePath = hardenStoragePath(safePath);

    const QUrl url = buildStorageObjectUrl(m_base,
                                           "/storage/v1/object/",
                                           bucketUse,
                                           safePath);

    qDebug().noquote() << "\n========== SUPABASE UPLOAD ==========";
    qDebug().noquote() << "[UPLOAD] objectPath:" << objectPath;
    qDebug().noquote() << "[UPLOAD] safePath  :" << safePath;
    qDebug().noquote() << "[UPLOAD] url enc   :" << url.toString(QUrl::FullyEncoded);
    qDebug().noquote() << "=====================================\n";

    QNetworkRequest req = makeRequest(url, accessToken);

    const QString ct = contentType.trimmed().isEmpty() ? "application/octet-stream" : contentType.trimmed();
    req.setHeader(QNetworkRequest::ContentTypeHeader, ct);

    req.setRawHeader("x-upsert", upsert ? "true" : "false");

    QNetworkReply* reply = m_net.sendCustomRequest(req, method, f);
    f->setParent(reply);

    // ✅ IMPORTANTE: reintento debe usar bucketUse (resuelto), no el "bucket" original
    const QString resolvedBucket = bucketUse;

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, method, accessToken, resolvedBucket, objectPath, localFilePath, ct, upsert]() {

                const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                const QByteArray body = reply->readAll();

                qDebug().noquote() << "[UPLOAD] reply.url:" << reply->url().toString(QUrl::FullyEncoded);
                qDebug() << "[UPLOAD] HTTP" << status << "QtErr" << reply->error() << reply->errorString();
                if (!body.isEmpty())
                    qDebug().noquote() << "[UPLOAD] body:" << QString::fromUtf8(body);

                if (status == 405 && method == "POST") {
                    reply->deleteLater();
                    uploadTryMethod("PUT", accessToken, resolvedBucket, objectPath, localFilePath, ct, upsert);
                    return;
                }

                const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

                if (!ok) {
                    const QString err = QString("Upload falló (HTTP %1): %2")
                                            .arg(status)
                                            .arg(QString::fromUtf8(body.isEmpty()
                                                                       ? reply->errorString().toUtf8()
                                                                       : body));
                    emit uploadFinished(objectPath, false, err);
                } else {
                    emit uploadFinished(objectPath, true, {});
                }

                reply->deleteLater();
            });
}

void SupabaseStorageClient::downloadFile(const QString& accessToken,
                                         const QString& bucket,
                                         const QString& objectPath)
{
    QString bucketUse = bucket.trimmed();
    ensureSettingsLoaded(&bucketUse);

    if (m_base.trimmed().isEmpty() || m_anonKey.trimmed().isEmpty() || bucketUse.isEmpty()) {
        emit downloadFinished(objectPath, false, {}, "Falta configuración Supabase (url/anon/bucket).");
        return;
    }

    QString safePath = toSafeStoragePath(objectPath);
    safePath = hardenStoragePath(safePath);

    const QUrl url = buildStorageObjectUrl(m_base,
                                           "/storage/v1/object/authenticated/",
                                           bucketUse,
                                           safePath);

    QNetworkRequest req = makeRequest(url, accessToken);

    qDebug().noquote() << "\n========== SUPABASE DOWNLOAD ==========";
    qDebug().noquote() << "[DOWN] objectPath:" << objectPath;
    qDebug().noquote() << "[DOWN] safePath  :" << safePath;
    qDebug().noquote() << "[DOWN] url enc   :" << url.toString(QUrl::FullyEncoded);
    qDebug().noquote() << "======================================\n";

    QNetworkReply* reply = m_net.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, objectPath]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();

        const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

        if (ok) {
            emit downloadFinished(objectPath, true, data, {});
        } else {
            const QString err = QString("Download falló (HTTP %1): %2")
                                    .arg(status)
                                    .arg(QString::fromUtf8(data.isEmpty()
                                                               ? reply->errorString().toUtf8()
                                                               : data));
            emit downloadFinished(objectPath, false, {}, err);
        }
        reply->deleteLater();
    });
}

void SupabaseStorageClient::moveObject(const QString& accessToken,
                                       const QString& bucketId,
                                       const QString& sourceKey,
                                       const QString& destKey)
{
    const QUrl url = buildStorageApiUrl(m_base, "/storage/v1/object/move");

    QJsonObject body;
    body["bucketId"] = bucketId;
    body["sourceKey"] = hardenStoragePath(toSafeStoragePath(sourceKey));
    body["destinationKey"] = hardenStoragePath(toSafeStoragePath(destKey));

    const QByteArray json = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkRequest req = makeRequest(url, accessToken);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply* reply = m_net.post(req, json);

    connect(reply, &QNetworkReply::finished, this, [this, reply, sourceKey, destKey]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

        if (!ok) {
            emit moveFinished(sourceKey, destKey, false,
                              QString("MOVE falló (HTTP %1): %2")
                                  .arg(status)
                                  .arg(QString::fromUtf8(data.isEmpty()
                                                             ? reply->errorString().toUtf8()
                                                             : data)));
        } else {
            emit moveFinished(sourceKey, destKey, true, {});
        }
        reply->deleteLater();
    });
}

void SupabaseStorageClient::deleteObjects(const QString& accessToken,
                                          const QString& bucketName,
                                          const QStringList& prefixes)
{
    const QUrl url = buildStorageApiUrl(m_base, "/storage/v1/object/" + bucketName);

    QJsonArray arr;
    for (const auto& p : prefixes) {
        arr.append(hardenStoragePath(toSafeStoragePath(p)));
    }

    QJsonObject body;
    body["prefixes"] = arr;

    const QByteArray json = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkRequest req = makeRequest(url, accessToken);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QBuffer* buf = new QBuffer;
    buf->setData(json);
    buf->open(QIODevice::ReadOnly);

    QNetworkReply* reply = m_net.sendCustomRequest(req, "DELETE", buf);
    buf->setParent(reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply, prefixes]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

        if (!ok) {
            emit deleteFinished(prefixes, false,
                                QString("DELETE falló (HTTP %1): %2")
                                    .arg(status)
                                    .arg(QString::fromUtf8(data.isEmpty()
                                                               ? reply->errorString().toUtf8()
                                                               : data)));
        } else {
            emit deleteFinished(prefixes, true, {});
        }
        reply->deleteLater();
    });
}

void SupabaseStorageClient::listObjects(const QString& accessToken,
                                        const QString& bucketName,
                                        const QString& prefix,
                                        int limit,
                                        int offset)
{
    const QUrl url = buildStorageApiUrl(m_base, "/storage/v1/object/list/" + bucketName);

    QJsonObject body;
    QString safePrefix = hardenStoragePath(toSafeStoragePath(prefix));
    if (prefix.endsWith('/') && !safePrefix.endsWith('/'))
        safePrefix += '/';
    body["prefix"] = safePrefix;

    body["limit"] = limit;
    body["offset"] = offset;

    const QByteArray json = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkRequest req = makeRequest(url, accessToken);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply* reply = m_net.post(req, json);

    connect(reply, &QNetworkReply::finished, this, [this, reply, prefix]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

        if (!ok) {
            emit listFinished(prefix, false, {},
                              QString("LIST falló (HTTP %1): %2")
                                  .arg(status)
                                  .arg(QString::fromUtf8(data.isEmpty()
                                                             ? reply->errorString().toUtf8()
                                                             : data)));
        } else {
            emit listFinished(prefix, true, data, {});
        }
        reply->deleteLater();
    });
}


void SupabaseStorageClient::uploadBytes(const QString& accessToken,
                                        const QString& bucket,
                                        const QString& objectPath,
                                        const QByteArray& bytes,
                                        const QString& contentType,
                                        bool upsert)
{
    QString bucketUse = bucket.trimmed();
    ensureSettingsLoaded(&bucketUse);

    if (m_base.trimmed().isEmpty() || m_anonKey.trimmed().isEmpty() || bucketUse.isEmpty()) {
        emit uploadFinished(objectPath, false, "Falta configuración Supabase (url/anon/bucket).");
        return;
    }

    QString safePath = hardenStoragePath(toSafeStoragePath(objectPath));
    const QUrl url = buildStorageObjectUrl(m_base, "/storage/v1/object/", bucketUse, safePath);

    QNetworkRequest req = makeRequest(url, accessToken);
    const QString ct = contentType.trimmed().isEmpty() ? "application/octet-stream" : contentType.trimmed();
    req.setHeader(QNetworkRequest::ContentTypeHeader, ct);
    req.setRawHeader("x-upsert", upsert ? "true" : "false");

    auto* buf = new QBuffer;
    buf->setData(bytes);
    buf->open(QIODevice::ReadOnly);

    QNetworkReply* reply = m_net.sendCustomRequest(req, "POST", buf);
    buf->setParent(reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply, objectPath]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        const bool ok = (reply->error() == QNetworkReply::NoError) && (status >= 200 && status < 300);

        if (!ok) {
            emit uploadFinished(objectPath, false,
                                QString("UploadBytes falló (HTTP %1): %2").arg(status).arg(QString::fromUtf8(body)));
        } else {
            emit uploadFinished(objectPath, true, {});
        }
        reply->deleteLater();
    });
}
