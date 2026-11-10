#include "supabaseclient.h"
#ifdef INGE_MOBILE
#include "betadiagnostics.h"
#endif
#include <QByteArray>
#include <QDateTime>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <QCoreApplication>
#include <QSysInfo>
#include <QRegularExpression>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif

namespace {
QString userAgentField(QString value, int limit = 96)
{
    value.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9 ._-]")), QStringLiteral(" "));
    return value.simplified().left(limit);
}

QByteArray applicationUserAgent()
{
    QString version = userAgentField(QCoreApplication::applicationVersion(), 32);
    if (version.isEmpty()) version = QStringLiteral("unknown");
#ifdef Q_OS_ANDROID
    QString maker = userAgentField(QJniObject::getStaticObjectField<jstring>("android/os/Build", "MANUFACTURER").toString(), 32);
    const QString model = userAgentField(QJniObject::getStaticObjectField<jstring>("android/os/Build", "MODEL").toString(), 60);
    if (maker.compare(QStringLiteral("samsung"), Qt::CaseInsensitive) == 0)
        maker = QStringLiteral("Samsung");
    QString device = model.startsWith(maker, Qt::CaseInsensitive) && !maker.isEmpty()
        ? model : (maker + QLatin1Char(' ') + model).simplified();
    if (device.isEmpty()) device = QStringLiteral("Dispositivo Android");
    QString release = userAgentField(QJniObject::getStaticObjectField<jstring>("android/os/Build$VERSION", "RELEASE").toString(), 32);
    if (release.isEmpty()) release = userAgentField(QSysInfo::productVersion(), 32);
    return QStringLiteral("InGePlus-Android/%1 (%2; Android %3)").arg(version, device, release).toLatin1();
#elif defined(Q_OS_IOS)
    return QStringLiteral("InGePlus-iOS/%1 (iPhone; iOS %2)").arg(version, userAgentField(QSysInfo::productVersion(),32)).toLatin1();
#else
    return QStringLiteral("InGePlus-Desktop/%1 (%2)").arg(version, userAgentField(QSysInfo::prettyProductName())).toLatin1();
#endif
}
}

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
    req.setRawHeader("User-Agent", applicationUserAgent());
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
