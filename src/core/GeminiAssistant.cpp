#include "GeminiAssistant.h"
#include "authsession.h"
#include "supabaseclient.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif
namespace { QPointer<inge::core::GeminiAssistant> assistant; }
namespace inge::core {
GeminiAssistant::GeminiAssistant(SupabaseClient *api, AuthSession *auth, QObject *parent)
    : QObject(parent), m_api(api), m_auth(auth) {
    assistant = this;
    connect(auth, &AuthSession::loggedChanged, this, &GeminiAssistant::reset);
    connect(auth, &AuthSession::currentAccountChanged, this, &GeminiAssistant::reset);
    connect(auth, &AuthSession::accountSwitchStarted, this, [this]() {
        m_switching = true; close(); emit availableChanged();
    });
    connect(auth, &AuthSession::accountSwitchOk, this, [this]() { m_switching = false; reset(); });
    connect(auth, &AuthSession::accountSwitchFail, this, [this]() { m_switching = false; reset(); });
}
bool GeminiAssistant::available() const {
    return !m_switching && m_auth->logged() && !m_auth->devOffline() && !m_auth->accessToken().isEmpty();
}
void GeminiAssistant::reset() {
    const QString user = m_auth->userId();
    if (!available() || user != m_user) close();
    m_user = user; emit availableChanged();
}
void GeminiAssistant::open(const QVariantMap &visuals) {
    if (!available()) return;
    setActive(true);
#ifdef Q_OS_ANDROID
    const auto json = QJniObject::fromString(QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(visuals)).toJson(QJsonDocument::Compact)));
    const bool accepted = QJniObject::callStaticMethod<jboolean>("com/ingema/ingeplus/InGeQtActivity", "showAssistant", "(Ljava/lang/String;)Z", json.object<jstring>());
    if (!accepted) setActive(false);
#else
    setActive(false);
#endif
}
void GeminiAssistant::close() {
    setActive(false); ++m_epoch;
    const auto pending = m_replies; m_replies.clear();
    for (auto *reply : pending) reply->abort();
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity", "closeAssistant", "()V");
#endif
}
void GeminiAssistant::setActive(bool active) {
    if (m_active == active) return;
    m_active = active;
    emit activeChanged();
}
void GeminiAssistant::updateVisuals(const QVariantMap &visuals) {
    if (m_active) deliver(QJsonObject{{"event", "visuals"}, {"visuals", QJsonObject::fromVariantMap(visuals)}});
}
void GeminiAssistant::deliver(const QJsonObject &message) {
#ifdef Q_OS_ANDROID
    const auto json = QJniObject::fromString(QString::fromUtf8(QJsonDocument(message).toJson(QJsonDocument::Compact)));
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity", "assistantMessage", "(Ljava/lang/String;)V", json.object<jstring>());
#else
    Q_UNUSED(message);
#endif
}
void GeminiAssistant::receive(const QString &message) {
    if (message.size() > 32000) return;
    const auto body = QJsonDocument::fromJson(message.toUtf8()).object();
    const auto operation = body.value("operation").toString();
    if (operation == "closed") { close(); return; }
    if (!m_active || !available()) return;
    if (operation != "chat" && operation != "live-token") return;
    const auto id = body.value("id").toString();
    if (id.isEmpty() || id.size() > 64) return;
    if (m_replies.size() >= 2) {
        deliver(QJsonObject{{"id", id}, {"error", "Espera a que termine la consulta actual."}}); return;
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
        if (epoch != m_epoch || !m_active || user != m_auth->userId()) return;
        auto result = QJsonDocument::fromJson(bytes).object();
        if (status < 200 || status >= 300 || error != QNetworkReply::NoError) {
            result.remove("token");
            if (result.value("error").toString().isEmpty())
                result.insert("error", status == 401 ? "La sesión venció. Vuelve a iniciar sesión." : "No se pudo conectar con InGe+ IA.");
        }
        result.insert("id", id); deliver(result);
    });
}
}
#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL Java_com_ingema_ingeplus_InGeAssistantWebHost_nativeMessage(JNIEnv *env, jclass, jstring raw) {
    Q_UNUSED(env);
    const QString message = QJniObject(raw).toString();
    QMetaObject::invokeMethod(qApp, [message]() { if (assistant) assistant->receive(message); }, Qt::QueuedConnection);
}
#endif
