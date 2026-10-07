#include "supabaseclient.h"
#ifdef INGE_MOBILE
#include "betadiagnostics.h"
#endif
#include <QByteArray>
#include <QDateTime>
#include <QNetworkReply>
#include <QNetworkProxy>

SupabaseClient::SupabaseClient(const QString& projectUrl,
                               const QString& anonKey,
                               QObject* parent)
    : QObject(parent),
    m_projectUrl(projectUrl),
    m_anonKey(anonKey)
{

    m_nam.setProxy(QNetworkProxy::NoProxy);
#ifdef INGE_MOBILE
    connect(&m_nam, &QNetworkAccessManager::finished, this,
            [](QNetworkReply *reply) {
        BetaDiagnostics *diagnostics = BetaDiagnostics::instance();
        if (!diagnostics || !reply)
            return;
        const QString path = reply->request().url().path();
        if (path.contains(QStringLiteral("beta_diagnostic")))
            return;

        QString operation;
        if (path.startsWith(QStringLiteral("/auth/v1/token")))
            operation = QStringLiteral("AUTH_LOGIN");
        else if (path.startsWith(QStringLiteral("/auth/v1/logout")))
            operation = QStringLiteral("AUTH_LOGOUT");
        else if (path.startsWith(QStringLiteral("/auth/v1/")))
            operation = QStringLiteral("AUTH_REQUEST");
        else if (path.startsWith(QStringLiteral("/rest/v1/rpc/")))
            operation = QStringLiteral("RPC_")
                + path.mid(QStringLiteral("/rest/v1/rpc/").size()).toUpper();
        else if (path.startsWith(QStringLiteral("/rest/v1/"))) {
            const QString table = path.mid(QStringLiteral("/rest/v1/").size())
                .section(QLatin1Char('/'), 0, 0).toUpper();
            operation = QStringLiteral("REST_") + table.left(80);
        } else if (path.startsWith(QStringLiteral("/storage/v1/")))
            operation = QStringLiteral("STORAGE_REQUEST");
        else
            return;

        const qint64 started = reply->request().attribute(
            static_cast<QNetworkRequest::Attribute>(QNetworkRequest::User + 1))
                .toLongLong();
        const qint64 duration = started > 0
            ? qMax<qint64>(0, QDateTime::currentMSecsSinceEpoch() - started) : 0;
        const int http = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QString errorClass = QStringLiteral("NONE");
        if (reply->error() == QNetworkReply::TimeoutError)
            errorClass = QStringLiteral("TIMEOUT");
        else if (reply->error() == QNetworkReply::HostNotFoundError)
            errorClass = QStringLiteral("HOST_NOT_FOUND");
        else if (reply->error() == QNetworkReply::SslHandshakeFailedError)
            errorClass = QStringLiteral("TLS");
        else if (reply->error() != QNetworkReply::NoError)
            errorClass = QStringLiteral("NETWORK");
        else if (http >= 500)
            errorClass = QStringLiteral("HTTP_5XX");
        else if (http >= 400)
            errorClass = QStringLiteral("HTTP_4XX");

        diagnostics->record(
            QStringLiteral("NETWORK"),
            errorClass == QStringLiteral("NONE")
                ? QStringLiteral("INFO") : QStringLiteral("WARNING"),
            QStringLiteral("NETWORK_REQUEST"), {},
            {{QStringLiteral("duration_ms"), duration},
             {QStringLiteral("http_status"), http}},
            {{QStringLiteral("operation"), operation},
             {QStringLiteral("error_class"), errorClass}});
    });
#endif
}

QUrl SupabaseClient::authUrl(const QString& path) const {
    return QUrl(m_projectUrl + "/auth/v1/" + path);
}

QUrl SupabaseClient::restUrl(const QString& path) const {
    return QUrl(m_projectUrl + "/rest/v1/" + path);
}

QNetworkRequest SupabaseClient::makeRequest(const QUrl& url,
                                            const QString& bearerToken,
                                            int transferTimeoutMs) const
{
    QNetworkRequest req(url);
    req.setAttribute(
        static_cast<QNetworkRequest::Attribute>(QNetworkRequest::User + 1),
        QDateTime::currentMSecsSinceEpoch());
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("apikey", m_anonKey.toUtf8());
#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
    if (transferTimeoutMs > 0)
        req.setTransferTimeout(transferTimeoutMs);
#endif

    // ✅ SOLO para JWT de usuario (access_token)
    if (!bearerToken.isEmpty()) {
        req.setRawHeader("Authorization", QByteArray("Bearer ") + bearerToken.toUtf8());
    }
    return req;
}
