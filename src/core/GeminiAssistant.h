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
// InGe+ IA sin interfaz (Visual Zero, 2026-10-10): servicio DESHABILITADO.
// Conserva la regla de disponibilidad (sesión real, sin modo DEV ni cambio de
// cuenta en curso) y el transporte autenticado a la Edge Function
// inge-ai-gemini, con sus validaciones, para la futura interfaz. No abre
// WebViews ni muestra nada. Auth sigue siendo nativa.
class GeminiAssistant final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled CONSTANT)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
public:
    // Interruptor del servicio: mientras no exista la nueva interfaz, deshabilitado.
    static constexpr bool kEnabled = false;
    GeminiAssistant(SupabaseClient *, AuthSession *, QObject *parent);
    bool enabled() const { return kEnabled; }
    bool available() const;
    // Consulta {operation: "chat" | "live-token", id, ...}. Devuelve false si se
    // rechaza sin enviar (servicio deshabilitado, sin sesión, petición inválida
    // o dos consultas en curso); la respuesta llega por replyReady.
    Q_INVOKABLE bool request(const QVariantMap &body);
    // Cancela las consultas en curso (cierre de sesión o cambio de cuenta).
    Q_INVOKABLE void cancelAll();
signals:
    void availableChanged();
    void replyReady(const QVariantMap &result);
private:
    void reset();
    SupabaseClient *m_api;
    AuthSession *m_auth;
    QSet<QNetworkReply *> m_replies;
    quint64 m_epoch = 0;
    QString m_user;
    bool m_switching = false;
};
}
