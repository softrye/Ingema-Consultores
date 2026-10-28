#include "supabaserealtimechannel.h"

#include "appcontext.h"
#include "authsession.h"
#include "supabaseclient.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QSet>
#include <QUrl>

namespace {
const int kRetryMs[] = {1000, 2000, 4000, 8000, 15000, 30000};
}

SupabaseRealtimeChannel::SupabaseRealtimeChannel(QObject *parent) : QObject(parent)
{
    m_heartbeat.setInterval(25000);
    connect(&m_heartbeat, &QTimer::timeout, this, [this]() {
        if (!m_socket || !m_handshaken) return;
        sendJson({{QStringLiteral("topic"), QStringLiteral("phoenix")}, {QStringLiteral("event"), QStringLiteral("heartbeat")},
                  {QStringLiteral("payload"), QVariantMap()}, {QStringLiteral("ref"), QString::number(++m_ref)}});
        // Sesión renovada: el token nuevo se entrega al canal privado.
        auto *auth = appContext() ? appContext()->auth() : nullptr;
        if (auth && auth->logged() && !auth->accessToken().isEmpty() && auth->accessToken() != m_token) {
            m_token = auth->accessToken();
            sendJson({{QStringLiteral("topic"), fullTopic()}, {QStringLiteral("event"), QStringLiteral("access_token")},
                      {QStringLiteral("payload"), QVariantMap{{QStringLiteral("access_token"), m_token}}},
                      {QStringLiteral("ref"), QString::number(++m_ref)}, {QStringLiteral("join_ref"), m_joinRef}});
        }
    });
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, [this]() { connectSocket(); });
}

SupabaseRealtimeChannel::~SupabaseRealtimeChannel()
{
    disconnectSocket(true);
}

void SupabaseRealtimeChannel::setTopic(const QString &topic)
{
    const QString t = topic.trimmed();
    if (t == m_topic) return;
    disconnectSocket(true);
    m_topic = t;
    m_everJoined = false;
    m_retryStep = 0;
    emit topicChanged();
    if (m_topic.isEmpty()) setState(QStringLiteral("OFF"));
    else connectSocket();
}

void SupabaseRealtimeChannel::setActive(bool active)
{
    if (m_active == active) return;
    m_active = active;
    emit activeChanged();
    if (!active) { disconnectSocket(true); if (!m_topic.isEmpty()) setState(QStringLiteral("OFF")); }   // sin fantasmas
    else if (!m_topic.isEmpty()) { m_retryStep = 0; connectSocket(); }
}

void SupabaseRealtimeChannel::setTrackMeta(const QVariantMap &meta)
{
    if (meta == m_trackMeta) return;
    m_trackMeta = meta;
    emit trackMetaChanged();
    if (m_state == QLatin1String("JOINED")) track();
}

void SupabaseRealtimeChannel::broadcast(const QString &event, const QVariantMap &payload)
{
    if (m_state != QLatin1String("JOINED") || event.isEmpty()) return;
    sendJson({{QStringLiteral("topic"), fullTopic()}, {QStringLiteral("event"), QStringLiteral("broadcast")},
              {QStringLiteral("payload"), QVariantMap{{QStringLiteral("type"), QStringLiteral("broadcast")},
                                                       {QStringLiteral("event"), event},
                                                       {QStringLiteral("payload"), payload}}},
              {QStringLiteral("ref"), QString::number(++m_ref)}, {QStringLiteral("join_ref"), m_joinRef}});
}

QString SupabaseRealtimeChannel::selfId() const
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    return auth ? auth->userId().trimmed().toLower() : QString();
}

void SupabaseRealtimeChannel::setState(const QString &state)
{
    if (state == m_state) return;
    m_state = state;
    emit stateChanged();
}

void SupabaseRealtimeChannel::connectSocket()
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!m_active || m_topic.isEmpty()) return;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) { setState(QStringLiteral("UNAVAILABLE")); return; }
    const QUrl base(api->projectUrl());
    if (base.host().isEmpty()) { setState(QStringLiteral("UNAVAILABLE")); return; }
    disconnectSocket(false);
    auto *socket = new QSslSocket(this);
    m_socket = socket;
    m_buffer.clear();
    m_fragment.clear();
    m_handshaken = false;
    m_token = auth->accessToken();
    setState(m_everJoined ? QStringLiteral("RECONNECTING") : QStringLiteral("CONNECTING"));
    const QString host = base.host();
    const QByteArray anonKey = QUrl::toPercentEncoding(api->anonKey());
    connect(socket, &QSslSocket::encrypted, this, [this, socket, host, anonKey]() {
        if (socket != m_socket) return;
        QByteArray nonce(16, Qt::Uninitialized);
        for (char &c : nonce) c = char(QRandomGenerator::global()->bounded(256));
        socket->write("GET /realtime/v1/websocket?apikey=" + anonKey + "&vsn=1.0.0 HTTP/1.1\r\n"
                      "Host: " + host.toUtf8() + "\r\n"
                      "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Key: " + nonce.toBase64() + "\r\n"
                      "Sec-WebSocket-Version: 13\r\n\r\n");
    });
    connect(socket, &QSslSocket::readyRead, this, [this, socket]() { if (socket == m_socket) onReadyRead(); });
    connect(socket, &QSslSocket::disconnected, this, [this, socket]() {
        if (socket != m_socket) return;
        m_socket = nullptr;
        socket->deleteLater();
        m_heartbeat.stop();
        m_presence.clear();
        rebuildMembers();
        scheduleRetry();
    });
    connect(socket, &QSslSocket::errorOccurred, this, [this, socket](QAbstractSocket::SocketError) {
        if (socket == m_socket) socket->abort();
    });
    socket->connectToHostEncrypted(host, quint16(base.port(443)));
}

void SupabaseRealtimeChannel::scheduleRetry()
{
    if (!m_active || m_topic.isEmpty() || m_state == QLatin1String("UNAVAILABLE")) return;
    setState(QStringLiteral("RECONNECTING"));
    const int steps = int(sizeof(kRetryMs) / sizeof(kRetryMs[0]));
    m_retry.start(kRetryMs[qBound(0, m_retryStep, steps - 1)]);
    m_retryStep = qMin(m_retryStep + 1, steps - 1);
}

void SupabaseRealtimeChannel::disconnectSocket(bool leave)
{
    m_retry.stop();
    m_heartbeat.stop();
    QSslSocket *socket = m_socket;
    if (socket) {
        if (leave && m_handshaken && socket->state() == QAbstractSocket::ConnectedState) {
            sendJson({{QStringLiteral("topic"), fullTopic()}, {QStringLiteral("event"), QStringLiteral("phx_leave")},
                      {QStringLiteral("payload"), QVariantMap()}, {QStringLiteral("ref"), QString::number(++m_ref)},
                      {QStringLiteral("join_ref"), m_joinRef}});
            sendFrame(0x8, QByteArray::fromHex("03e8"));   // cierre 1000
            socket->flush();
        }
        m_socket = nullptr;
        socket->disconnect(this);
        socket->disconnectFromHost();
        socket->deleteLater();
    }
    m_handshaken = false;
    m_presence.clear();
    rebuildMembers();
}

void SupabaseRealtimeChannel::sendFrame(quint8 opcode, const QByteArray &payload)
{
    if (!m_socket) return;
    QByteArray frame;
    frame.append(char(0x80 | (opcode & 0x0F)));
    const qint64 size = payload.size();
    if (size < 126) frame.append(char(0x80 | size));
    else if (size <= 0xFFFF) { frame.append(char(0x80 | 126)); frame.append(char((size >> 8) & 0xFF)); frame.append(char(size & 0xFF)); }
    else { frame.append(char(0x80 | 127)); for (int shift = 56; shift >= 0; shift -= 8) frame.append(char((size >> shift) & 0xFF)); }
    char mask[4];
    for (char &c : mask) c = char(QRandomGenerator::global()->bounded(256));
    frame.append(mask, 4);
    QByteArray masked = payload;
    for (qsizetype i = 0; i < masked.size(); ++i) masked[i] = char(masked.at(i) ^ mask[i % 4]);   // tramas de cliente enmascaradas
    frame.append(masked);
    m_socket->write(frame);
}

void SupabaseRealtimeChannel::sendJson(const QVariantMap &message)
{
    sendFrame(0x1, QJsonDocument::fromVariant(message).toJson(QJsonDocument::Compact));
}

void SupabaseRealtimeChannel::onReadyRead()
{
    m_buffer.append(m_socket->readAll());
    if (!m_handshaken) {
        const qsizetype end = m_buffer.indexOf("\r\n\r\n");
        if (end < 0) return;
        const QByteArray status = m_buffer.left(m_buffer.indexOf("\r\n"));
        m_buffer.remove(0, end + 4);
        if (!status.contains(" 101")) { setState(QStringLiteral("UNAVAILABLE")); disconnectSocket(false); return; }
        m_handshaken = true;
        m_joinRef = QString::number(++m_ref);
        QVariantMap config;
        config[QStringLiteral("broadcast")] = QVariantMap{{QStringLiteral("ack"), false}, {QStringLiteral("self"), false}};
        config[QStringLiteral("presence")] = QVariantMap{{QStringLiteral("key"), selfId()}, {QStringLiteral("enabled"), true}};
        config[QStringLiteral("postgres_changes")] = QVariantList();
        config[QStringLiteral("private")] = true;
        sendJson({{QStringLiteral("topic"), fullTopic()}, {QStringLiteral("event"), QStringLiteral("phx_join")},
                  {QStringLiteral("payload"), QVariantMap{{QStringLiteral("config"), config}, {QStringLiteral("access_token"), m_token}}},
                  {QStringLiteral("ref"), m_joinRef}, {QStringLiteral("join_ref"), m_joinRef}});
        m_heartbeat.start();
    }
    for (;;) {
        if (m_buffer.size() < 2 || !m_socket) return;
        const quint8 b0 = quint8(m_buffer.at(0)), b1 = quint8(m_buffer.at(1));
        const bool fin = b0 & 0x80, masked = b1 & 0x80;
        const quint8 opcode = b0 & 0x0F;
        qint64 length = b1 & 0x7F;
        qsizetype offset = 2;
        if (length == 126) {
            if (m_buffer.size() < 4) return;
            length = (quint8(m_buffer.at(2)) << 8) | quint8(m_buffer.at(3));
            offset = 4;
        } else if (length == 127) {
            if (m_buffer.size() < 10) return;
            length = 0;
            for (int i = 2; i < 10; ++i) length = (length << 8) | quint8(m_buffer.at(i));
            offset = 10;
        }
        if (length < 0 || length > 16 * 1024 * 1024) { disconnectSocket(false); scheduleRetry(); return; }
        const qsizetype maskOffset = offset;
        if (masked) offset += 4;
        if (m_buffer.size() < offset + length) return;
        QByteArray payload = m_buffer.mid(offset, length);
        if (masked) for (qsizetype i = 0; i < payload.size(); ++i) payload[i] = char(payload.at(i) ^ m_buffer.at(maskOffset + i % 4));
        m_buffer.remove(0, offset + length);
        if (opcode == 0x9) { sendFrame(0xA, payload); continue; }
        if (opcode == 0xA) continue;
        if (opcode == 0x8) { if (m_socket) m_socket->disconnectFromHost(); return; }
        if (opcode == 0x1 || opcode == 0x0) {
            m_fragment.append(payload);
            if (!fin) continue;
            const QByteArray message = m_fragment;
            m_fragment.clear();
            handleMessage(message);
        }
    }
}

void SupabaseRealtimeChannel::handleMessage(const QByteArray &raw)
{
    const QVariantMap message = QJsonDocument::fromJson(raw).toVariant().toMap();
    const QString event = message.value(QStringLiteral("event")).toString();
    const QVariantMap payload = message.value(QStringLiteral("payload")).toMap();
    if (event == QLatin1String("phx_reply") && message.value(QStringLiteral("ref")).toString() == m_joinRef) {
        if (payload.value(QStringLiteral("status")).toString() == QLatin1String("ok")) {
            m_retryStep = 0;
            setState(QStringLiteral("JOINED"));
            track();
            if (m_everJoined) emit rejoined();
            m_everJoined = true;
        } else {
            setState(QStringLiteral("UNAVAILABLE"));          // rechazado por RLS: sin reintentos en bucle
            disconnectSocket(false);
        }
        return;
    }
    if (event == QLatin1String("phx_error") || event == QLatin1String("phx_close")) {
        if (m_socket) m_socket->abort();
        return;
    }
    if (event == QLatin1String("broadcast")) {
        emit broadcastReceived(payload.value(QStringLiteral("event")).toString(), payload.value(QStringLiteral("payload")).toMap());
        return;
    }
    if (event == QLatin1String("presence_state")) {
        m_presence = payload;
        rebuildMembers();
        return;
    }
    if (event == QLatin1String("presence_diff")) {
        const QVariantMap joins = payload.value(QStringLiteral("joins")).toMap();
        const QVariantMap leaves = payload.value(QStringLiteral("leaves")).toMap();
        for (auto it = leaves.cbegin(); it != leaves.cend(); ++it) {
            QSet<QString> gone;
            for (const QVariant &meta : it.value().toMap().value(QStringLiteral("metas")).toList())
                gone.insert(meta.toMap().value(QStringLiteral("phx_ref")).toString());
            QVariantList kept;
            for (const QVariant &meta : m_presence.value(it.key()).toMap().value(QStringLiteral("metas")).toList())
                if (!gone.contains(meta.toMap().value(QStringLiteral("phx_ref")).toString())) kept << meta;
            if (kept.isEmpty()) m_presence.remove(it.key());
            else m_presence[it.key()] = QVariantMap{{QStringLiteral("metas"), kept}};
        }
        for (auto it = joins.cbegin(); it != joins.cend(); ++it) {
            QVariantList metas = m_presence.value(it.key()).toMap().value(QStringLiteral("metas")).toList();
            metas += it.value().toMap().value(QStringLiteral("metas")).toList();
            m_presence[it.key()] = QVariantMap{{QStringLiteral("metas"), metas}};
        }
        rebuildMembers();
    }
}

void SupabaseRealtimeChannel::track()
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    if (!auth || !m_socket) return;
    QVariantMap meta = m_trackMeta;
    if (!meta.contains(QStringLiteral("userId"))) meta[QStringLiteral("userId")] = selfId();
    if (!meta.contains(QStringLiteral("name"))) {
        QString name = auth->fullName().trimmed();
        if (name.isEmpty()) name = auth->email().section(QLatin1Char('@'), 0, 0);
        meta[QStringLiteral("name")] = name.left(60);
    }
    sendJson({{QStringLiteral("topic"), fullTopic()}, {QStringLiteral("event"), QStringLiteral("presence")},
              {QStringLiteral("payload"), QVariantMap{{QStringLiteral("type"), QStringLiteral("presence")},
                                                       {QStringLiteral("event"), QStringLiteral("track")},
                                                       {QStringLiteral("payload"), meta}}},
              {QStringLiteral("ref"), QString::number(++m_ref)}, {QStringLiteral("join_ref"), m_joinRef}});
}

void SupabaseRealtimeChannel::rebuildMembers()
{
    const QString self = selfId();
    QVariantList members;
    // Una entrada por persona (clave = userId); la meta más reciente la representa.
    for (auto it = m_presence.cbegin(); it != m_presence.cend(); ++it) {
        const QVariantList metas = it.value().toMap().value(QStringLiteral("metas")).toList();
        if (metas.isEmpty()) continue;
        const QVariantMap meta = metas.last().toMap();
        const QString userId = meta.value(QStringLiteral("userId"), it.key()).toString().trimmed().toLower();
        if (userId.isEmpty() || userId == self) continue;
        const QString name = meta.value(QStringLiteral("name")).toString().trimmed().left(60);
        const QStringList parts = name.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        QString initials;
        for (int i = 0; i < parts.size() && initials.size() < 2; ++i) initials += parts.at(i).left(1).toUpper();
        members << QVariantMap{{QStringLiteral("userId"), userId},
                               {QStringLiteral("name"), name.isEmpty() ? QStringLiteral("Usuario") : name},
                               {QStringLiteral("initials"), initials.isEmpty() ? QStringLiteral("?") : initials}};
    }
    if (members == m_members) return;
    m_members = members;
    emit membersChanged();
}
