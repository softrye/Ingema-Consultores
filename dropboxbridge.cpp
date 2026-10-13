#include "dropboxbridge.h"

#include <QDesktopServices>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>

DropboxBridge::DropboxBridge(QObject *parent)
    : QObject(parent)
{
}

void DropboxBridge::setError(const QString& message)
{
    m_lastError = message;
    emit lastErrorChanged();
    qWarning() << "[DropboxBridge]" << message;
}

QString DropboxBridge::readablePath(const QString& localPathOrUrl) const
{
    QUrl u(localPathOrUrl);
    if (u.isValid() && u.isLocalFile())
        return u.toLocalFile();

    QString p = localPathOrUrl;
    if (p.startsWith(QStringLiteral("file://")))
        p = QUrl(p).toLocalFile();

    return p;
}

QString DropboxBridge::normalizeDropboxPath(const QString& path) const
{
    QString p = path.trimmed();
    if (p.isEmpty())
        p = QStringLiteral("/InGePlus");

    p.replace("\\", "/");
    while (p.contains("//"))
        p.replace("//", "/");

    if (!p.startsWith("/"))
        p.prepend("/");

    return p;
}

void DropboxBridge::connectWithToken(const QString& token)
{
    m_accessToken = token.trimmed();
    if (m_accessToken.isEmpty()) {
        m_accountLabel = QString();
        emit accountLabelChanged();
        emit connectedChanged();
        setError(QStringLiteral("Token Dropbox vacío."));
        return;
    }

    m_accountLabel = QStringLiteral("Dropbox INGEMA conectado");
    m_lastError.clear();
    emit accountLabelChanged();
    emit lastErrorChanged();
    emit connectedChanged();
    emit connectedOk();
}

void DropboxBridge::clearToken()
{
    m_accessToken.clear();
    m_accountLabel.clear();
    emit accountLabelChanged();
    emit connectedChanged();
}

void DropboxBridge::openOAuthUrl(const QString& appKey)
{
    const QString key = appKey.trimmed();
    if (key.isEmpty()) {
        setError(QStringLiteral("Falta Dropbox App Key. Pégala en Ajustes > Dropbox."));
        return;
    }

    QUrl url(QStringLiteral("https://www.dropbox.com/oauth2/authorize"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("client_id"), key);
    q.addQueryItem(QStringLiteral("response_type"), QStringLiteral("token"));
    q.addQueryItem(QStringLiteral("token_access_type"), QStringLiteral("online"));
    url.setQuery(q);

    QDesktopServices::openUrl(url);
    emit oauthUrlOpened(url.toString());
}

void DropboxBridge::uploadFile(const QString& localPathOrUrl, const QString& dropboxPath)
{
    if (!connected()) {
        emit uploadFail(QStringLiteral("Dropbox no conectado. Pega un token OAuth o conecta Dropbox."));
        return;
    }

    const QString localPath = readablePath(localPathOrUrl);
    QFile file(localPath);

    if (!file.open(QIODevice::ReadOnly)) {
        const QString msg = QStringLiteral("No se pudo leer archivo local: %1").arg(localPath);
        setError(msg);
        emit uploadFail(msg);
        return;
    }

    const QByteArray data = file.readAll();
    if (data.isEmpty()) {
        const QString msg = QStringLiteral("Archivo vacío o ilegible: %1").arg(localPath);
        setError(msg);
        emit uploadFail(msg);
        return;
    }

    QString dp = normalizeDropboxPath(dropboxPath);
    if (dp.endsWith("/")) {
        QFileInfo fi(localPath);
        dp += fi.fileName();
    }

    QJsonObject arg;
    arg.insert(QStringLiteral("path"), dp);
    arg.insert(QStringLiteral("mode"), QStringLiteral("overwrite"));
    arg.insert(QStringLiteral("autorename"), false);
    arg.insert(QStringLiteral("mute"), true);
    arg.insert(QStringLiteral("strict_conflict"), false);

    QNetworkRequest req(QUrl(QStringLiteral("https://content.dropboxapi.com/2/files/upload")));
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setRawHeader("Dropbox-API-Arg", QJsonDocument(arg).toJson(QJsonDocument::Compact));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/octet-stream"));
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    if (m_reply)
        m_reply->deleteLater();

    m_reply = m_nam.post(req, data);

    connect(m_reply, &QNetworkReply::finished, this, [this, dp]() {
        QNetworkReply* reply = m_reply;
        if (!reply)
            return;

        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();

        reply->deleteLater();
        m_reply = nullptr;

        if (http >= 200 && http < 300) {
            m_lastError.clear();
            emit lastErrorChanged();
            emit uploadOk(dp);
            return;
        }

        const QString msg = QStringLiteral("Dropbox upload falló HTTP %1: %2")
                .arg(http)
                .arg(QString::fromUtf8(body.left(500)));
        setError(msg);
        emit uploadFail(msg);
    });
}
