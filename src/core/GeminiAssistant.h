#pragma once
#include <QObject>
#include <QVariantMap>
#include <QPointer>
#include <QSet>
#include <QJsonObject>
class AuthSession;
class SupabaseClient;
class QNetworkReply;
namespace inge::core {
// Transport owned by CoreRemote. Auth remains native; this is not another engine.
class GeminiAssistant final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // Estado real del asistente (WebView aceptado y abierto); lo usa la UI para
    // ocultar el Dock global y el halo perimetral, sin booleano paralelo.
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
public:
    GeminiAssistant(SupabaseClient *, AuthSession *, QObject *parent);
    bool available() const;
    bool active() const { return m_active; }
    Q_INVOKABLE void open(const QVariantMap &visuals);
    Q_INVOKABLE void close();
    Q_INVOKABLE void updateVisuals(const QVariantMap &visuals);
    void receive(const QString &message);
signals:
    void openingRequested();
    void availableChanged();
    void activeChanged();
private:
    void reset();
    void deliver(const QJsonObject &message);
    void setActive(bool active);
    SupabaseClient *m_api;
    AuthSession *m_auth;
    QSet<QNetworkReply *> m_replies;
    quint64 m_epoch = 0;
    bool m_active = false;
    QString m_user;
    bool m_switching = false;
};
}
