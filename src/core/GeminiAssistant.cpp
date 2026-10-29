#include "GeminiAssistant.h"
#include "authsession.h"
#include "supabaseclient.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
namespace inge::core {
GeminiAssistant::GeminiAssistant(SupabaseClient *api, AuthSession *auth, QObject *parent)
    : QObject(parent), m_api(api), m_auth(auth) {
    connect(auth, &AuthSession::loggedChanged, this, &GeminiAssistant::reset);
    connect(auth, &AuthSession::currentAccountChanged, this, &GeminiAssistant::reset);
    connect(auth, &AuthSession::accountSwitchStarted, this, [this]() {
        m_switching = true; cancelAll(); emit availableChanged();
    });
    connect(auth, &AuthSession::accountSwitchOk, this, [this]() { m_switching = false; reset(); });
    connect(auth, &AuthSession::accountSwitchFail, this, [this]() { m_switching = false; reset(); });
}
bool GeminiAssistant::available() const {
    return kEnabled && !m_switching && m_auth->logged() && !m_auth->devOffline() && !m_auth->accessToken().isEmpty();
}
void GeminiAssistant::reset() {
    const QString user = m_auth->userId();
    if (!available() || user != m_user) cancelAll();
    m_user = user; emit availableChanged();
}
void GeminiAssistant::cancelAll() {
    ++m_epoch;
    const auto pending = m_replies; m_replies.clear();
    for (auto *reply : pending) reply->abort();
}
bool GeminiAssistant::request(const QVariantMap &bodyMap) {
    if (!available()) return false;
    const QJsonObject body = QJsonObject::fromVariantMap(bodyMap);
    if (QJsonDocument(body).toJson(QJsonDocument::Compact).size() > 32000) return false;
    const auto operation = body.value("operation").toString();
    if (operation != "chat" && operation != "live-token") return false;
    const auto id = body.value("id").toString();
    if (id.isEmpty() || id.size() > 64) return false;
    if (m_replies.size() >= 2) {
        emit replyReady(QVariantMap{{"id", id}, {"error", QStringLiteral("Espera a que termine la consulta actual.")}});
        return false;
    }
    const auto epoch = m_epoch;
    const auto user = m_auth->userId();
    auto req = m_api->makeRequest(QUrl(m_api->projectUrl() + "/functions/v1/inge-ai-gemini"), m_auth->accessToken(), 45000);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    auto *reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    m_replies.insert(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, id, epoch, user]() {
        m_replies.remove(reply);
        const auto bytes = reply->readAll();
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error(); reply->deleteLater();
        if (epoch != m_epoch || user != m_auth->userId()) return;
        auto result = QJsonDocument::fromJson(bytes).object();
        if (status < 200 || status >= 300 || error != QNetworkReply::NoError) {
            result.remove("token");
            if (result.value("error").toString().isEmpty())
                result.insert("error", status == 401 ? "La sesión venció. Vuelve a iniciar sesión." : "No se pudo conectar con InGe+ IA.");
        }
        result.insert("id", id);
        emit replyReady(result.toVariantMap());
    });
    return true;
}
}
