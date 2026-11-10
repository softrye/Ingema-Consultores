#include "satellitetileproxy.h"

#include <QDir>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif

SatelliteTileProxy::SatelliteTileProxy(QObject *parent) : QObject(parent)
{
    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                             + QStringLiteral("/satellite-tiles");
    QDir().mkpath(cacheDir);
    auto *cache = new QNetworkDiskCache(this);
    cache->setCacheDirectory(cacheDir);
    cache->setMaximumCacheSize(150LL * 1024 * 1024);
    m_network.setCache(cache);
    connect(&m_server, &QTcpServer::newConnection, this, &SatelliteTileProxy::onNewConnection);
}

QString SatelliteTileProxy::cesiumIonToken()
{
#ifdef Q_OS_ANDROID
    const QJniObject token = QJniObject::callStaticObjectMethod(
        "com/ingema/ingeplus/InGeQtActivity", "cesiumIonToken", "()Ljava/lang/String;");
    return token.isValid() ? token.toString().trimmed() : QString();
#else
    return QString::fromLocal8Bit(qgetenv("CESIUM_ION_TOKEN")).trimmed();
#endif
}

QString SatelliteTileProxy::baseUrl() const
{
    if (!m_server.isListening()) return QString();
    return QStringLiteral("http://127.0.0.1:%1/sat/").arg(m_server.serverPort());
}

void SatelliteTileProxy::ensureStarted()
{
    if (!m_server.isListening() && !m_server.listen(QHostAddress::LocalHost, 0)) {
        fail("LISTEN_FAILED");
        return;
    }
    if (m_state == State::Idle || m_state == State::Failed) loadMetadata();
    emit stateChanged();
}

void SatelliteTileProxy::fail(const char *reason)
{
    qWarning() << "INGE_SATELLITE_PROXY_FAIL reason=" << reason;   // sin token ni URL
    m_state = State::Failed;
    for (const Pending &p : std::as_const(m_pending))
        if (p.socket) respond(p.socket, 502, "text/plain", "unavailable");
    m_pending.clear();
    emit stateChanged();
}

void SatelliteTileProxy::loadMetadata()
{
    const QString token = cesiumIonToken();
    if (token.isEmpty()) { fail("NO_TOKEN"); return; }
    m_state = State::Loading;

    // 1) Cesium ion: endpoint del asset 2 (Bing Maps Aerial) con su llave de Bing.
    QNetworkRequest ion(QUrl(QStringLiteral("https://api.cesium.com/v1/assets/2/endpoint")));
    ion.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    QNetworkReply *ionReply = m_network.get(ion);
    connect(ionReply, &QNetworkReply::finished, this, [this, ionReply]() {
        ionReply->deleteLater();
        const QJsonObject root = QJsonDocument::fromJson(ionReply->readAll()).object();
        const QJsonObject options = root.value(QStringLiteral("options")).toObject();
        const QString base = options.value(QStringLiteral("url")).toString();
        const QString key = options.value(QStringLiteral("key")).toString();
        QString style = options.value(QStringLiteral("mapStyle")).toString();
        if (ionReply->error() != QNetworkReply::NoError || base.isEmpty() || key.isEmpty()) {
            fail("ION_ENDPOINT");
            return;
        }
        if (style.isEmpty()) style = QStringLiteral("Aerial");

        // 2) Bing: plantilla de URL de cuadros (quadkey + subdominios).
        QUrl meta(base + QStringLiteral("/REST/v1/Imagery/Metadata/") + style);
        QUrlQuery q;
        q.addQueryItem(QStringLiteral("incl"), QStringLiteral("ImageryProviders"));
        q.addQueryItem(QStringLiteral("key"), key);
        q.addQueryItem(QStringLiteral("uriScheme"), QStringLiteral("https"));
        meta.setQuery(q);
        QNetworkReply *metaReply = m_network.get(QNetworkRequest(meta));
        connect(metaReply, &QNetworkReply::finished, this, [this, metaReply]() {
            metaReply->deleteLater();
            const QJsonObject doc = QJsonDocument::fromJson(metaReply->readAll()).object();
            const QJsonArray sets = doc.value(QStringLiteral("resourceSets")).toArray();
            const QJsonArray resources = sets.isEmpty() ? QJsonArray()
                : sets.first().toObject().value(QStringLiteral("resources")).toArray();
            if (metaReply->error() != QNetworkReply::NoError || resources.isEmpty()) {
                fail("BING_METADATA");
                return;
            }
            const QJsonObject res = resources.first().toObject();
            m_imageUrl = res.value(QStringLiteral("imageUrl")).toString();
            m_imageUrl.replace(QStringLiteral("{culture}"), QStringLiteral("en-US"));
            m_subdomains.clear();
            for (const QJsonValue &v : res.value(QStringLiteral("imageUrlSubdomains")).toArray())
                m_subdomains << v.toString();
            const int zoomMax = res.value(QStringLiteral("zoomMax")).toInt(19);
            m_maxZoom = qBound(10, zoomMax, 19);
            if (m_imageUrl.isEmpty() || m_subdomains.isEmpty()) { fail("BING_TEMPLATE"); return; }
            m_state = State::Ready;
            qInfo() << "INGE_SATELLITE_PROXY_READY maxZoom=" << m_maxZoom;
            const QList<Pending> queued = m_pending;
            m_pending.clear();
            for (const Pending &p : queued) serveTile(p);
            emit stateChanged();
        });
    });
}

QString SatelliteTileProxy::quadKey(int z, int x, int y)
{
    QString key;
    for (int i = z; i > 0; --i) {
        int digit = 0;
        const int mask = 1 << (i - 1);
        if (x & mask) digit += 1;
        if (y & mask) digit += 2;
        key += QChar('0' + digit);
    }
    return key;
}

void SatelliteTileProxy::onNewConnection()
{
    while (QTcpSocket *socket = m_server.nextPendingConnection()) {
        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() { onReadyRead(socket); });
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    }
}

void SatelliteTileProxy::onReadyRead(QTcpSocket *socket)
{
    const QByteArray data = socket->peek(2048);
    if (!data.contains("\r\n")) return;
    static const QRegularExpression re(QStringLiteral("^GET /sat/(\\d+)/(\\d+)/(\\d+)\\."));
    const QRegularExpressionMatch m = re.match(QString::fromLatin1(data.left(data.indexOf("\r\n"))));
    socket->readAll();
    if (!m.hasMatch()) { respond(socket, 400, "text/plain", "bad request"); return; }
    const Pending request{ m.captured(1).toInt(), m.captured(2).toInt(), m.captured(3).toInt(), socket };
    if (m_state == State::Failed) { respond(socket, 502, "text/plain", "unavailable"); return; }
    if (m_state != State::Ready) {
        m_pending.append(request);
        if (m_state == State::Idle) loadMetadata();
        return;
    }
    serveTile(request);
}

void SatelliteTileProxy::serveTile(const Pending &request)
{
    if (!request.socket) return;
    QString url = m_imageUrl;
    url.replace(QStringLiteral("{subdomain}"),
                m_subdomains.at(qAbs(request.x + request.y) % m_subdomains.size()));
    url.replace(QStringLiteral("{quadkey}"), quadKey(request.z, request.x, request.y));
    QNetworkRequest net{ QUrl(url) };
    net.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
    QNetworkReply *reply = m_network.get(net);
    const QPointer<QTcpSocket> socket = request.socket;
    connect(reply, &QNetworkReply::finished, this, [this, reply, socket]() {
        reply->deleteLater();
        if (!socket) return;
        if (reply->error() != QNetworkReply::NoError) {
            respond(socket, 404, "text/plain", "tile unavailable");
            return;
        }
        QByteArray type = reply->header(QNetworkRequest::ContentTypeHeader).toByteArray();
        respond(socket, 200, type.isEmpty() ? QByteArray("image/jpeg") : type, reply->readAll());
    });
}

void SatelliteTileProxy::respond(QTcpSocket *socket, int status, const QByteArray &contentType,
                                 const QByteArray &body)
{
    if (!socket || socket->state() != QAbstractSocket::ConnectedState) return;
    const char *text = status == 200 ? "OK" : status == 404 ? "Not Found" : status == 400 ? "Bad Request" : "Bad Gateway";
    socket->write("HTTP/1.1 " + QByteArray::number(status) + " " + text + "\r\nContent-Type: " + contentType
                  + "\r\nContent-Length: " + QByteArray::number(body.size())
                  + "\r\nConnection: close\r\n\r\n" + body);
    socket->disconnectFromHost();
}
