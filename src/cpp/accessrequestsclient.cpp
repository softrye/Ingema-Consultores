#include "accessrequestsclient.h"

#include "appcontext.h"
#include "authsession.h"
#include "supabaseclient.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QUuid>

AccessRequestsClient::AccessRequestsClient(QObject *parent)
    : QObject(parent)
{
}

void AccessRequestsClient::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

// Mensajes legibles para los códigos del servidor; el resto se muestra tal cual.
QString AccessRequestsClient::friendlyError(const QString &raw)
{
    if (raw.contains(QLatin1String("USER_ADMIN_INSTITUTIONAL_ROLE_REQUIRED")))
        return QStringLiteral("Elige un rol válido para la cuenta.");
    if (raw.contains(QLatin1String("42501")) || raw.contains(QLatin1String("FORBIDDEN"), Qt::CaseInsensitive))
        return QStringLiteral("Tu cuenta no tiene permiso para administrar solicitudes.");
    if (raw.contains(QLatin1String("CONFLICT"), Qt::CaseInsensitive) || raw.contains(QLatin1String("40001")))
        return QStringLiteral("La solicitud cambió en otro dispositivo. Actualiza la lista.");
    return raw.isEmpty() ? QStringLiteral("No se pudo completar la operación.") : raw;
}

void AccessRequestsClient::callRpc(const QString &name, const QVariantMap &params, Done done)
{
    AppContext *ctx = AppContext::instance();
    if (!ctx || !ctx->supabase() || !ctx->auth() || ctx->auth()->accessToken().isEmpty()) {
        done(false, {}, QStringLiteral("Inicia sesión para administrar solicitudes."));
        return;
    }
    SupabaseClient *api = ctx->supabase();
    QNetworkRequest request = api->makeRequest(api->restUrl(QStringLiteral("rpc/") + name),
                                               ctx->auth()->accessToken());
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    const QByteArray body = QJsonDocument(QJsonObject::fromVariantMap(params)).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = api->nam()->post(request, body);
    if (m_pending++ == 0)
        emit busyChanged();
    connect(reply, &QNetworkReply::finished, this, [this, reply, done]() {
        reply->deleteLater();
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QVariant result = QJsonDocument::fromJson(data).toVariant();
        if (--m_pending == 0)
            emit busyChanged();
        if (reply->error() != QNetworkReply::NoError || status >= 400) {
            const QVariantMap map = result.toMap();
            QString message = map.value(QStringLiteral("message")).toString();
            if (message.isEmpty())
                message = reply->errorString();
            // Sin secretos en logs: solo nombre de la RPC y estado HTTP.
            qWarning() << "[AccessRequests] RPC failed" << status;
            done(false, {}, friendlyError(message + QLatin1Char(' ') + map.value(QStringLiteral("code")).toString()).trimmed());
            return;
        }
        done(true, result, {});
    });
}

void AccessRequestsClient::refresh()
{
    setError({});
    callRpc(QStringLiteral("list_profiles_for_administration_v02"),
            {{QStringLiteral("p_status"), QStringLiteral("PENDIENTE")},
             {QStringLiteral("p_deleted"), false},
             {QStringLiteral("p_limit"), 100},
             {QStringLiteral("p_cursor"), QVariant()}},
            [this](bool ok, const QVariant &result, const QString &error) {
                if (!ok) {
                    setError(error);
                    return;
                }
                QVariantList list;
                for (const QVariant &row : result.toList()) {
                    const QVariantMap r = row.toMap();
                    list.append(QVariantMap{
                        {QStringLiteral("profileId"), r.value(QStringLiteral("profile_id"))},
                        {QStringLiteral("fullName"), r.value(QStringLiteral("full_name"))},
                        {QStringLiteral("email"), r.value(QStringLiteral("email"))},   // tal cual
                        {QStringLiteral("registeredAt"), r.value(QStringLiteral("registered_at"))},
                        {QStringLiteral("updatedAt"), r.value(QStringLiteral("updated_at"))}});
                }
                m_requests = list;
                emit requestsChanged();
            });
    callRpc(QStringLiteral("list_assignable_institutional_roles_v01"), {},
            [this](bool ok, const QVariant &result, const QString &error) {
                if (!ok) {
                    setError(error);
                    return;
                }
                m_roles = result.toList();   // [{code, label}]
                emit rolesChanged();
            });
}

void AccessRequestsClient::approve(const QString &profileId, const QString &expectedUpdatedAt,
                                   const QString &roleCode, const QString &projectId,
                                   const QString &projectRole, const QString &accessLevel)
{
    setError({});
    callRpc(QStringLiteral("approve_profile_with_role_controlled_v01"),
            {{QStringLiteral("p_profile_id"), profileId},
             {QStringLiteral("p_expected_updated_at"), expectedUpdatedAt},
             {QStringLiteral("p_institutional_role_code"), roleCode},
             {QStringLiteral("p_global_role"), QVariant()},
             {QStringLiteral("p_administrative_notes"), QVariant()}},
            [=](bool ok, const QVariant &, const QString &error) {
                if (!ok) {
                    setError(error);
                    emit actionFinished(false, error);
                    return;
                }
                const auto finish = [this, profileId](bool fully, const QString &message) {
                    for (int i = 0; i < m_requests.size(); ++i) {
                        if (m_requests.at(i).toMap().value(QStringLiteral("profileId")).toString() == profileId) {
                            m_requests.removeAt(i);
                            emit requestsChanged();
                            break;
                        }
                    }
                    emit actionFinished(fully, message);
                };
                if (projectId.isEmpty()) {
                    finish(true, QStringLiteral("Cuenta aprobada."));
                    return;
                }
                const QString level = accessLevel.isEmpty() ? QStringLiteral("READ") : accessLevel;
                callRpc(QStringLiteral("create_project_team_member_with_access_v01"),
                        {{QStringLiteral("p_project_id"), projectId},
                         {QStringLiteral("p_profile_id"), profileId},
                         {QStringLiteral("p_role"), projectRole},
                         {QStringLiteral("p_access_level"), level},
                         {QStringLiteral("p_request_id"), level == QLatin1String("NONE") ? QVariant()
                              : QVariant(QUuid::createUuid().toString(QUuid::WithoutBraces))},
                         {QStringLiteral("p_node_id"), QVariant()},
                         {QStringLiteral("p_starts_at"), QVariant()},
                         {QStringLiteral("p_approval_reference"), QVariant()},
                         {QStringLiteral("p_notes"), QVariant()}},
                        [this, finish](bool ok2, const QVariant &, const QString &error2) {
                            if (!ok2) {
                                setError(error2);
                                finish(false, QStringLiteral("Cuenta aprobada, pero no se pudo dar acceso al proyecto: ") + error2);
                                return;
                            }
                            finish(true, QStringLiteral("Cuenta aprobada con acceso al proyecto."));
                        });
            });
}

void AccessRequestsClient::reject(const QString &)
{
    // [PENDIENTE SERVIDOR] No hay RPC de rechazo; no se inventa una.
    const QString message = QStringLiteral("Rechazar aún no está disponible en el servidor.");
    setError(message);
    emit actionFinished(false, message);
}
