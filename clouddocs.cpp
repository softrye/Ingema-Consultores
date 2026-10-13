#include "clouddocs.h"
#include "supabaseclient.h"
#include "authsession.h"

#include <QFile>
#include <QSaveFile>
#include <QTimer>
#include <QUuid>
#include <utility>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QMimeDatabase>
#include <QDirIterator>

QString CloudDocs::toFolderKey(QString s)
{
    s = s.trimmed();
    s.replace('\\','/');
    // Solo el último segmento si vino como ruta
    if (s.contains('/')) s = s.section('/', -1);

    // estilo que tú quieres: espacios -> _
    s.replace(' ', '_');

    // elimina cosas raras
    s.remove(QRegularExpression(R"(^_+|_+$)"));
    s.replace("..", "_");
    s.replace(':', '_');

    // deja caracteres seguros
    s.replace(QRegularExpression("[^A-Za-z0-9._\\-]"), "_");
    s.replace(QRegularExpression("_+"), "_");
    if (s.isEmpty()) s = "_";
    return s;
}

void CloudDocs::setUserFolderAlias(const QString& alias)
{
    m_userFolderAlias = toFolderKey(alias);
}

void CloudDocs::setProjectFolderAlias(const QString& projectId, const QString& alias)
{
    const QString pid = cleanSegment(projectId);
    if (pid.isEmpty()) return;
    m_projectFolderAlias.insert(pid, toFolderKey(alias));
}

QString CloudDocs::userFolderKey() const
{
    if (!m_userFolderAlias.trimmed().isEmpty())
        return m_userFolderAlias;

    // fallback viejo
    return userPrefix();
}

QString CloudDocs::projectFolderKey(const QString& projectId) const
{
    const QString pid = cleanSegment(projectId);
    const QString alias = m_projectFolderAlias.value(pid).trimmed();
    if (!alias.isEmpty())
        return alias;

    // fallback viejo (si no seteas alias)
    return cleanSegment(projectId);
}


CloudDocs::CloudDocs(SupabaseClient* api, AuthSession* auth, QObject* parent)
    : QObject(parent), m_api(api), m_auth(auth)
{
    if (m_auth) {
        connect(m_auth, &AuthSession::loggedChanged, this, [this] { ++m_accountEpoch; });
        connect(m_auth, &AuthSession::currentAccountChanged, this, [this] { ++m_accountEpoch; });
    }
}

bool CloudDocs::ensureReadyAndLogged(QString* whyNot) const
{
    if (!m_api || !m_auth) {
        if (whyNot) *whyNot = "CloudDocs no inicializado (api/auth null).";
        return false;
    }
    if (!m_auth->logged() || m_auth->accessToken().isEmpty()) {
        if (whyNot) *whyNot = "Debes iniciar sesión (token vacío).";
        return false;
    }
    return true;
}

QString CloudDocs::userPrefix() const
{
    if (!m_auth || m_auth->userId().isEmpty())
        return "anon";
    return m_auth->userId();
}

QString CloudDocs::cleanSegment(const QString& s) const
{
    QString out = s.trimmed();
    out.replace('\\', '/');
    out.remove(QRegularExpression(R"(^/+|/+$)"));
    out.replace("..", "_");
    out.replace(':', '_');
    return out;
}

QString CloudDocs::projectPrefix(const QString& projectId) const
{
    const QString uidFolder = userFolderKey();
    const QString projFolder = projectFolderKey(projectId);
    return QString("%1/%2/").arg(uidFolder, projFolder);
}


QString CloudDocs::objectKeyFor(const QString& projectId, const QString& relativePath) const
{
    const QString uidFolder = userFolderKey();
    const QString projFolder = projectFolderKey(projectId);

    QString rel = cleanSegment(relativePath);

    // Si ya viene con "Edit/..." u otra ruta completa, la respetamos
    // (puedes ajustar esta regla si quieres)
    if (!rel.isEmpty() && (rel.startsWith(uidFolder + "/") || rel.startsWith("anon/")))
        return rel;

    if (rel.isEmpty())
        return QString("%1/%2").arg(uidFolder, projFolder);

    return QString("%1/%2/%3").arg(uidFolder, projFolder, rel);
}


QString CloudDocs::inferProjectIdFromLocalPath(const QString& localPath) const
{
    const QString p = QDir::fromNativeSeparators(localPath);
    QStringList parts = p.split('/', Qt::SkipEmptyParts);

    int idxCal = parts.indexOf("Calicatas");
    if (idxCal > 0) {
        return cleanSegment(parts.at(idxCal - 1));
    }

    QFileInfo fi(localPath);
    const QString parentDir = fi.dir().dirName(); // ej "Edit"
    if (parentDir.compare("Edit", Qt::CaseInsensitive) == 0) {
        QDir d = fi.dir();
        d.cdUp(); // Calicatas
        d.cdUp(); // Proyecto
        const QString proj = d.dirName();
        if (!proj.isEmpty())
            return cleanSegment(proj);
    }

    return "sin_proyecto";
}

QString CloudDocs::ensureObjectKeyForUploadLegacy(const QString& localPath,
                                                  const QString& projectId,
                                                  const QString& remoteDir) const
{
    const QFileInfo fi(localPath);
    const QString fileName = fi.fileName().isEmpty() ? "document.json" : fi.fileName();

    const QString dir = cleanSegment(remoteDir.isEmpty() ? "Edit" : remoteDir);
    const QString rel = dir.isEmpty() ? fileName : (dir + "/" + fileName);

    return objectKeyFor(projectId, rel);
}

QUrl CloudDocs::storageObjectUrl(const QString& objectKey) const
{
    const QString base = m_api->projectUrl() + "/storage/v1/object/" + m_bucket + "/";
    const QByteArray encodedKey = QUrl::toPercentEncoding(objectKey, "/");
    return QUrl::fromEncoded(base.toUtf8() + encodedKey);
}

QUrl CloudDocs::storageListUrl() const
{
    return QUrl(m_api->projectUrl() + "/storage/v1/object/list/" + m_bucket);
}

QString CloudDocs::guessContentType(const QString& localPath)
{
    QMimeDatabase db;
    const auto mt = db.mimeTypeForFile(localPath, QMimeDatabase::MatchExtension);
    const QString ct = mt.isValid() ? mt.name() : QString();
    return ct.isEmpty() ? QString("application/octet-stream") : ct;
}

// ==========================
// NUEVO: listProjectTree(projectId, remoteDir)
// ==========================
void CloudDocs::listPage(const QString& projectId, const QString& remoteDir, int offset, int limit)
{
    QString prefix = projectId.isEmpty() ? userFolderKey() + "/" : projectPrefix(projectId);
    const QString dir = cleanSegment(remoteDir);
    if (!dir.isEmpty()) prefix += dir + "/";
    listByPrefix(prefix, projectId, qMax(0, offset), limit);
}

void CloudDocs::listProjectTree(const QString& projectId, const QString& remoteDir)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit listFail(why); return; }

    const QString dir = cleanSegment(remoteDir);
    QString prefix = projectPrefix(projectId); // userId/projectId/
    if (!dir.isEmpty())
        prefix += dir + "/";

    prefix = cleanSegment(prefix);
    if (!prefix.endsWith('/')) prefix += '/';

    listByPrefix(prefix, projectId);
}

// ==========================
// Interno: listByPrefix
// Devuelve CloudDocItem.relativePath SIEMPRE relativo a userId/projectId/
// ==========================
void CloudDocs::listByPrefix(const QString& prefixObjectKey,
                             const QString& projectIdForRelative, int offset, int limit)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit listFail(why); return; }

    QNetworkRequest req = m_api->makeRequest(storageListUrl(), m_auth->accessToken());
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject body;
    body["prefix"] = prefixObjectKey;
    if (offset >= 0) {
        body["offset"] = offset;
        body["limit"] = qBound(1, limit, 1000);
        body["sortBy"] = QJsonObject{{"column", "name"}, {"order", "asc"}};
    }

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply, prefixObjectKey, projectIdForRelative]() {
        const QByteArray raw = reply->readAll();
        const auto err = reply->error();
        const QString errStr = reply->errorString();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || httpStatus >= 400) {
            QString msg = QString("Error al listar (HTTP %1): %2").arg(httpStatus).arg(errStr);
            if (!raw.isEmpty()) msg += "\n" + QString::fromUtf8(raw);
            emit listFail(msg);
            return;
        }

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isArray()) {
            emit listFail("Respuesta inválida al listar (no es array).");
            return;
        }

        const QString projPrefix = projectPrefix(projectIdForRelative); // userId/projectId/
        QVector<CloudDocItem> items;
        const auto arr = doc.array();
        items.reserve(arr.size());

        for (const auto& v : arr) {
            const auto o = v.toObject();

            CloudDocItem it;
            it.name = o.value("name").toString();

            // objectKey completo (evita duplicar prefix)
            QString fullKey;
            if (it.name.startsWith(prefixObjectKey))
                fullKey = it.name;
            else
                fullKey = prefixObjectKey + it.name;

            it.objectKey = cleanSegment(fullKey);

            // metadata
            const QJsonObject md = o.value("metadata").toObject();
            const QString id = o.value("id").toString();

            // Heurísticas de folder:
            // - md vacío y sin id suele ser folder
            // - o name termina en "/" también puede ser folder
            it.isFolder = (md.isEmpty() && id.isEmpty()) || it.name.endsWith('/');

            if (!md.isEmpty()) {
                it.size = (qint64)md.value("size").toDouble();
                it.etag = md.value("eTag").toString();
                it.mimeType = md.value("mimetype").toString();
            }

            it.updatedAt = o.value("updated_at").toString();

            // relativePath SIEMPRE relativo a userId/projectId/
            if (!projPrefix.isEmpty() && it.objectKey.startsWith(projPrefix)) {
                it.relativePath = cleanSegment(it.objectKey.mid(projPrefix.size()));
            } else {
                // fallback (por si listaste algo fuera de proyecto)
                it.relativePath = cleanSegment(it.name);
            }

            items.push_back(it);
        }

        emit listOk(items);
    });
}

// ==========================
// NUEVO: uploadFile
// ==========================
void CloudDocs::uploadExact(const QString& localPath, const QString& bucket, const QString& objectKey,
                            const QString& contentType, std::function<void(bool, const QString&)> done)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { done(false, why); return; }
    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) { done(false, QStringLiteral("LOCAL_FILE_MISSING")); return; }
    const QByteArray data = f.readAll();
    f.close();
    const QByteArray encodedKey = QUrl::toPercentEncoding(objectKey, "/");
    const QUrl url = QUrl::fromEncoded((m_api->projectUrl() + "/storage/v1/object/" + bucket + "/").toUtf8() + encodedKey);
    QNetworkRequest req = m_api->makeRequest(url, m_auth->accessToken());
    req.setHeader(QNetworkRequest::ContentTypeHeader,
                  contentType.isEmpty() ? guessContentType(localPath) : contentType);
    req.setRawHeader("x-upsert", "false");   // objeto inmutable, igual que Web
    req.setRawHeader("x-ingeplus-platform", "ANDROID");
    QNetworkReply* reply = m_api->nam()->post(req, data);
    connect(reply, &QNetworkReply::finished, this, [reply, done]() {
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = reply->error() == QNetworkReply::NoError && http >= 200 && http < 300;
        reply->deleteLater();
        done(ok, ok ? QString() : QStringLiteral("NETWORK"));
    });
}

void CloudDocs::uploadFile(const QString& localPath,
                           const QString& projectId,
                           const QString& relativePath,
                           const QString& contentType,
                           bool upsert)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit uploadFail(why); return; }

    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) {
        emit uploadFail("No se pudo abrir el archivo local: " + localPath);
        return;
    }
    const QByteArray data = f.readAll();
    f.close();

    QString rel = cleanSegment(relativePath);
    if (rel.isEmpty()) {
        rel = cleanSegment(QFileInfo(localPath).fileName());
    } else if (rel.endsWith('/')) {
        rel += cleanSegment(QFileInfo(localPath).fileName());
    }

    const QString objectKey = objectKeyFor(projectId, rel);
    const QUrl url = storageObjectUrl(objectKey);

    QNetworkRequest req = m_api->makeRequest(url, m_auth->accessToken());
    req.setHeader(QNetworkRequest::ContentTypeHeader,
                  contentType.isEmpty() ? guessContentType(localPath) : contentType);
    req.setRawHeader("x-upsert", upsert ? "true" : "false");

    auto* reply = m_api->nam()->put(req, data);

    connect(reply, &QNetworkReply::finished, this, [this, reply, objectKey]() {
        const QByteArray raw = reply->readAll();
        const auto err = reply->error();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || httpStatus >= 400) {
            QString msg = QString("Error al subir (HTTP %1): %2").arg(httpStatus).arg(errStr);
            if (!raw.isEmpty()) msg += "\n" + QString::fromUtf8(raw);
            emit uploadFail(msg);
            return;
        }

        emit uploadOk(objectKey);
    });
}

// ==========================
// NUEVO: downloadFile
// ==========================
void CloudDocs::downloadFile(const QString& projectId,
                             const QString& relativePath,
                             const QString& savePath)
{
    const QString objectKey = objectKeyFor(projectId, relativePath);
    downloadJson(objectKey, savePath);
}

// ==========================
// LEGACY: UploadJson
// ==========================
void CloudDocs::uploadJson(const QString& localPath)
{
    const QString pid = inferProjectIdFromLocalPath(localPath);
    uploadJson(localPath, pid, "Edit");
}

void CloudDocs::uploadJson(const QString& localPath, const QString& projectId, const QString& remoteDir)
{
    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) {
        emit uploadFail("No se pudo abrir el archivo local: " + localPath);
        return;
    }
    const QByteArray data = f.readAll();
    f.close();

    {
        QJsonParseError pe{};
        QJsonDocument::fromJson(data, &pe);
        if (pe.error != QJsonParseError::NoError) {
            emit uploadFail("El archivo no es JSON válido: " + pe.errorString());
            return;
        }
    }

    const QString objectKey = ensureObjectKeyForUploadLegacy(localPath, projectId, remoteDir);

    // relativo al proyecto (strip userId/projectId/)
    QString rel = objectKey;
    const QString pp = projectPrefix(projectId);
    if (rel.startsWith(pp)) rel = rel.mid(pp.size());
    rel = cleanSegment(rel);

    uploadFile(localPath, projectId, rel, "application/json", true);
}

// ==========================
// LEGACY: List
// ==========================
void CloudDocs::listMyJson()
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit listFail(why); return; }

    QString prefix = userPrefix();
    prefix = cleanSegment(prefix);
    if (!prefix.endsWith('/')) prefix += '/';

    // aquí projectIdForRelative vacío => relativePath fallback a name
    listByPrefix(prefix, QString());
}

void CloudDocs::listMyJson(const QString& projectId, const QString& remoteDir)
{
    // ahora esto lista bien debajo del proyecto (y relativePath sale consistente)
    listProjectTree(projectId, remoteDir);
}

// ==========================
// LEGACY: Download por objectKey
// ==========================
void CloudDocs::downloadJson(const QString& objectKey, const QString& savePath)
{
    downloadObject(m_bucket, objectKey, savePath, -1, [this, savePath](bool ok, const QString& error) {
        if (ok) emit downloadOk(savePath);
        else emit downloadFail(error);
    });
}

void CloudDocs::downloadExact(const QString& bucket, const QString& objectKey, const QString& savePath,
                             qint64 expectedSize, DownloadCompletion done)
{
    const auto parts = objectKey.split('/');
    if (bucket != "project-files" || parts.size() != 7 || parts.value(0) != "spaces"
            || parts.value(2) != "nodes" || parts.value(4) != "versions"
            || QUuid(parts.value(1)).isNull() || QUuid(parts.value(3)).isNull() || QUuid(parts.value(5)).isNull()
            || parts.contains("..") || parts.contains(".") || parts.contains("") || objectKey.contains('\\')
            || expectedSize < 0) {
        done(false, QStringLiteral("La versión devuelta por InGeDrive tiene un destino o tamaño inválido."));
        return;
    }
    downloadObject(bucket, objectKey, savePath, expectedSize, std::move(done));
}

void CloudDocs::downloadObject(const QString& bucket, const QString& objectKey, const QString& savePath,
                              qint64 expectedSize, DownloadCompletion done)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { done(false, why); return; }

    const QUrl url = QUrl::fromEncoded((m_api->projectUrl() + "/storage/v1/object/" + bucket + "/").toUtf8()
                                      + QUrl::toPercentEncoding(objectKey, "/"));
    const auto epoch = m_accountEpoch;
    const auto owner = m_auth->userId();

    QNetworkRequest req = m_api->makeRequest(url, m_auth->accessToken());
    req.setTransferTimeout(60000);
    auto* reply = m_api->nam()->get(req);
    QTimer::singleShot(65000, reply, [reply] { if (reply->isRunning()) reply->abort(); });

    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath, expectedSize, epoch, owner, done=std::move(done)]() {
        const QByteArray raw = reply->readAll();
        const auto err = reply->error();
        const QString errStr = reply->errorString();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if (epoch != m_accountEpoch || !m_auth->logged() || m_auth->userId() != owner) {
            done(false, QStringLiteral("ACCOUNT_CHANGED"));
            return;
        }
        if (err != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300) {
            QString msg = QString("Error al descargar (HTTP %1): %2").arg(httpStatus).arg(errStr);
            if (!raw.isEmpty()) msg += "\n" + QString::fromUtf8(raw);
            done(false, msg);
            return;
        }

        if (expectedSize >= 0 && raw.size() != expectedSize) {
            done(false, QStringLiteral("La descarga está incompleta. Reintenta; la copia anterior se conserva."));
            return;
        }
        if (!QDir().mkpath(QFileInfo(savePath).absolutePath())) {
            done(false, QStringLiteral("No se pudo crear la carpeta de descarga."));
            return;
        }

        QSaveFile f(savePath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            done(false, QStringLiteral("No se pudo guardar el archivo descargado."));
            return;
        }
        if (f.write(raw) != raw.size() || !f.commit()) {
            done(false, QStringLiteral("No se pudo completar el archivo descargado. La copia anterior se conserva."));
            return;
        }
        done(true, {});
    });
}

QString CloudDocs::inferRelativePathFromLocalPath(const QString& localPath, const QString& projectId) const
{
    const QString p = QDir::fromNativeSeparators(localPath);
    const QString pid = cleanSegment(projectId);

    const QString needle = "/" + pid + "/";
    const int pos = p.indexOf(needle);
    if (pos >= 0) {
        return cleanSegment(p.mid(pos + needle.size())); // ej: "Calicatas/Edit/xxx.json"
    }

    return cleanSegment(QFileInfo(localPath).fileName());
}

void CloudDocs::uploadLocalAuto(const QString& localPath, bool upsert)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit uploadFail(why); return; }

    const QString projectId = inferProjectIdFromLocalPath(localPath);
    const QString relativePath = inferRelativePathFromLocalPath(localPath, projectId);
    const QString contentType = guessContentType(localPath);

    uploadFile(localPath, projectId, relativePath, contentType, upsert);
}

void CloudDocs::uploadProjectTree(const QString& projectRoot, bool upsert)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit uploadFail(why); return; }

    QFileInfo rootFi(projectRoot);
    if (!rootFi.exists() || !rootFi.isDir()) {
        emit uploadFail("projectRoot no es carpeta válida: " + projectRoot);
        return;
    }

    const QString projectId = cleanSegment(rootFi.fileName());
    QDir root(projectRoot);

    QDirIterator it(projectRoot,
                    QDir::Files | QDir::NoSymLinks,
                    QDirIterator::Subdirectories);

    while (it.hasNext()) {
        const QString absPath = it.next();

        const QString base = QFileInfo(absPath).fileName();
        if (base == "Thumbs.db" || base == ".DS_Store")
            continue;

        QString rel = root.relativeFilePath(absPath);
        rel = QDir::fromNativeSeparators(rel);
        rel = cleanSegment(rel);

        const QString ct = guessContentType(absPath);
        uploadFile(absPath, projectId, rel, ct, upsert);
    }
}


void CloudDocs::removeFile(const QString& projectId, const QString& relativePath)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit removeFail(why); return; }

    const QString objectKey = objectKeyFor(projectId, relativePath);

    // Endpoint alternativo muy usado:
    // POST /storage/v1/object/remove  { bucketId, paths:[key] }
    QUrl url(m_api->projectUrl() + "/storage/v1/object/remove");

    QNetworkRequest req = m_api->makeRequest(url, m_auth->accessToken());
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject body;
    body["bucketId"] = m_bucket;
    body["paths"] = QJsonArray{ objectKey };

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply, objectKey]() {
        const QByteArray raw = reply->readAll();
        const auto err = reply->error();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || httpStatus >= 400) {
            QString msg = QString("Error al borrar (HTTP %1): %2").arg(httpStatus).arg(errStr);
            if (!raw.isEmpty()) msg += "\n" + QString::fromUtf8(raw);
            emit removeFail(msg);
            return;
        }
        emit removeOk(objectKey);
    });
}

void CloudDocs::moveFile(const QString& projectId, const QString& fromRel, const QString& toRel)
{
    QString why;
    if (!ensureReadyAndLogged(&why)) { emit moveFail(why); return; }

    const QString fromKey = objectKeyFor(projectId, fromRel);
    const QString toKey   = objectKeyFor(projectId, toRel);

    QUrl url(m_api->projectUrl() + "/storage/v1/object/move");

    QNetworkRequest req = m_api->makeRequest(url, m_auth->accessToken());
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject body;
    body["bucketId"] = m_bucket;
    body["sourceKey"] = fromKey;
    body["destinationKey"] = toKey;

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply, fromKey, toKey]() {
        const QByteArray raw = reply->readAll();
        const auto err = reply->error();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || httpStatus >= 400) {
            QString msg = QString("Error al mover (HTTP %1): %2").arg(httpStatus).arg(errStr);
            if (!raw.isEmpty()) msg += "\n" + QString::fromUtf8(raw);
            emit moveFail(msg);
            return;
        }
        emit moveOk(fromKey, toKey);
    });
}
