#pragma once

#include <QObject>
#include <QPointer>
#include <QSslSocket>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Canal privado de Supabase Realtime (protocolo Phoenix sobre WebSocket) para
// QML: presencia de quién tiene abierto un documento y avisos «broadcast».
// Mismo contrato que la Web (supabase-js): topic "realtime:<topic>",
// presence keyed por userId, broadcast sin eco propio y RLS de canal privado.
// La presencia es una indicación, nunca una autorización: los datos siempre se
// vuelven a pedir por RPC al recibir un aviso.
class SupabaseRealtimeChannel : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString topic READ topic WRITE setTopic NOTIFY topicChanged)          // p. ej. "rendition:<uuid>"; "" = apagado
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)          // false en segundo plano
    Q_PROPERTY(QVariantMap trackMeta READ trackMeta WRITE setTrackMeta NOTIFY trackMetaChanged)
    Q_PROPERTY(QVariantList members READ members NOTIFY membersChanged)               // otras personas (sin mí)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)                          // OFF | CONNECTING | JOINED | RECONNECTING | UNAVAILABLE
public:
    explicit SupabaseRealtimeChannel(QObject *parent = nullptr);
    ~SupabaseRealtimeChannel() override;

    QString topic() const { return m_topic; }
    void setTopic(const QString &topic);
    bool active() const { return m_active; }
    void setActive(bool active);
    QVariantMap trackMeta() const { return m_trackMeta; }
    void setTrackMeta(const QVariantMap &meta);
    QVariantList members() const { return m_members; }
    QString state() const { return m_state; }

    Q_INVOKABLE void broadcast(const QString &event, const QVariantMap &payload = {});

signals:
    void topicChanged();
    void activeChanged();
    void trackMetaChanged();
    void membersChanged();
    void stateChanged();
    void broadcastReceived(const QString &event, const QVariantMap &payload);
    void rejoined();                                      // reconexión: lo enviado mientras tanto no se repite

private:
    void connectSocket();
    void disconnectSocket(bool leave);
    void scheduleRetry();
    void sendFrame(quint8 opcode, const QByteArray &payload);
    void sendJson(const QVariantMap &message);
    void onReadyRead();
    void handleMessage(const QByteArray &raw);
    void track();
    void rebuildMembers();
    void setState(const QString &state);
    QString fullTopic() const { return QStringLiteral("realtime:") + m_topic; }
    QString selfId() const;

    QString m_topic;
    bool m_active = true;
    QVariantMap m_trackMeta;
    QVariantList m_members;
    QString m_state = QStringLiteral("OFF");

    QPointer<QSslSocket> m_socket;
    QByteArray m_buffer;
    QByteArray m_fragment;
    bool m_handshaken = false;
    bool m_everJoined = false;
    QString m_token;
    QString m_joinRef;
    int m_ref = 0;
    int m_retryStep = 0;
    QTimer m_heartbeat;
    QTimer m_retry;
    QVariantMap m_presence;
};
