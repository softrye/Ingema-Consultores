#include "betadiagnostics.h"

#include "authsession.h"
#include "supabaseclient.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QSet>
#include <QStandardPaths>
#include <QThread>
#include <QTimer>
#include <QUuid>

#include <algorithm>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#endif

namespace {
constexpr qint64 kMaximumSpoolBytes = 2 * 1024 * 1024;
constexpr qsizetype kMaximumSpoolEvents = 2000;
constexpr qsizetype kMaximumRpcEvents = 200;

QString normalizedSeverity(QString value)
{
    value = value.trimmed().toUpper();
    static const QSet<QString> allowed{
        QStringLiteral("DEBUG"), QStringLiteral("INFO"),
        QStringLiteral("WARNING"), QStringLiteral("ERROR"),
        QStringLiteral("FATAL")};
    return allowed.contains(value) ? value : QStringLiteral("INFO");
}

bool droppable(const QJsonObject &event)
{
    const QString severity = event.value(QStringLiteral("severity")).toString();
    return severity == QStringLiteral("DEBUG")
        || severity == QStringLiteral("INFO");
}
}

BetaDiagnostics *BetaDiagnostics::s_instance = nullptr;
QtMessageHandler BetaDiagnostics::s_previousMessageHandler = nullptr;

BetaDiagnostics::BetaDiagnostics(SupabaseClient *api, AuthSession *auth,
                                 QObject *parent)
    : QObject(parent), m_api(api), m_auth(auth)
{
    s_instance = this;
    loadLocalState();

#ifdef Q_OS_ANDROID
    const QJniObject snapshot = QJniObject::callStaticObjectMethod(
        "com/ingema/ingeplus/InGeQtActivity", "betaDeviceSnapshotJson",
        "()Ljava/lang/String;");
    if (snapshot.isValid()) {
        const QJsonDocument document = QJsonDocument::fromJson(
            snapshot.toString().toUtf8());
        if (document.isObject())
            m_device = sanitizeObject(document.object());
    }
#endif

    m_flushTimer = new QTimer(this);
    m_flushTimer->setInterval(60'000);
    connect(m_flushTimer, &QTimer::timeout, this, &BetaDiagnostics::flush);
    m_flushTimer->start();

    if (m_auth) {
        connect(m_auth, &AuthSession::loginOk, this, [this]() {
            record(QStringLiteral("AUTH"), QStringLiteral("INFO"),
                   QStringLiteral("AUTH_LOGIN_SUCCESS"));
            startAuthenticatedSession();
        });
        connect(m_auth, &AuthSession::loginFail, this,
                [this](const QString &) {
            record(QStringLiteral("AUTH"), QStringLiteral("WARNING"),
                   QStringLiteral("AUTH_LOGIN_FAILURE"), {}, {},
                   {{QStringLiteral("error_class"),
                     QStringLiteral("AUTH_REJECTED_OR_UNAVAILABLE")}});
        });
        connect(m_auth, &AuthSession::loggedChanged, this, [this]() {
            if (m_auth && m_auth->logged() && !m_auth->devOffline()
                && m_sessionId.isEmpty())
                startAuthenticatedSession();
        });
    }

    if (auto *guiApp = qobject_cast<QGuiApplication *>(
            QCoreApplication::instance())) {
        connect(guiApp, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
            const QString code = state == Qt::ApplicationActive
                ? QStringLiteral("QT_APP_ACTIVE")
                : QStringLiteral("QT_APP_BACKGROUND");
            record(QStringLiteral("LIFECYCLE"), QStringLiteral("INFO"), code);
            if (state != Qt::ApplicationActive)
                flush();
        });
    }
    connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() {
        finishSession(QStringLiteral("NORMAL"));
    });

    installQtMessageCapture();
    record(QStringLiteral("STARTUP"), QStringLiteral("INFO"),
           QStringLiteral("QT_RUNTIME_READY"));
}

BetaDiagnostics::~BetaDiagnostics()
{
    if (s_instance == this) {
        qInstallMessageHandler(s_previousMessageHandler);
        s_instance = nullptr;
    }
}

BetaDiagnostics *BetaDiagnostics::instance()
{
    return s_instance;
}

void BetaDiagnostics::loadLocalState()
{
    QSettings settings;
    m_installId = settings.value(
        QStringLiteral("betaDiagnostics/installId")).toString();
    if (QUuid(m_installId).isNull()) {
        m_installId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        settings.setValue(QStringLiteral("betaDiagnostics/installId"),
                          m_installId);
    }

    m_priorSessionId = settings.value(
        QStringLiteral("betaDiagnostics/activeSessionId")).toString();
    m_previousSessionUnclean = !m_priorSessionId.isEmpty();
    settings.remove(QStringLiteral("betaDiagnostics/activeSessionId"));
    settings.sync();

    const QString directory = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation) + QStringLiteral("/diagnostics");
    QDir().mkpath(directory);
    m_spoolPath = directory + QStringLiteral("/beta_diagnostics_v01.jsonl");
    const QList<QJsonObject> persisted = readSpool();
    m_localEventCount = persisted.size();
    m_localBytes = QFileInfo(m_spoolPath).size();
    for (const QJsonObject &event : persisted)
        m_nextSeq = qMax(m_nextSeq,
                         event.value(QStringLiteral("seq")).toInteger());
}

QString BetaDiagnostics::sanitizeString(QString value, int maximum) const
{
    static const QRegularExpression bearer(
        QStringLiteral("(?i)Bearer\\s+[A-Za-z0-9._~+\\-/=]+"));
    static const QRegularExpression jwt(
        QStringLiteral("[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"));
    static const QRegularExpression assignment(
        QStringLiteral("(?i)(access_token|refresh_token|password|authorization|apikey|secret)\\s*[:=]\\s*[^\\s,;}]+"));
    static const QRegularExpression email(
        QStringLiteral("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"),
        QRegularExpression::CaseInsensitiveOption);
    value.replace(bearer, QStringLiteral("<redacted-token>"));
    value.replace(jwt, QStringLiteral("<redacted-jwt>"));
    value.replace(assignment, QStringLiteral("<redacted-secret>"));
    value.replace(email, QStringLiteral("<redacted-email>"));
    value.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")),
                  QStringLiteral(" "));
    return value.trimmed().left(maximum);
}

QJsonObject BetaDiagnostics::sanitizeObject(const QJsonObject &value) const
{
    static const QSet<QString> excluded{
        QStringLiteral("password"), QStringLiteral("access_token"),
        QStringLiteral("refresh_token"), QStringLiteral("authorization"),
        QStringLiteral("headers"), QStringLiteral("apikey"),
        QStringLiteral("secret"), QStringLiteral("request_body"),
        QStringLiteral("response_body"), QStringLiteral("body"),
        QStringLiteral("email"), QStringLiteral("phone"),
        QStringLiteral("full_name"), QStringLiteral("typed_text"),
        QStringLiteral("clipboard"), QStringLiteral("latitude"),
        QStringLiteral("longitude"), QStringLiteral("exact_gps"),
        QStringLiteral("document_content"), QStringLiteral("file_content"),
        QStringLiteral("private_notes"), QStringLiteral("financial_amount"),
        QStringLiteral("amount")};
    QJsonObject result;
    for (auto it = value.constBegin(); it != value.constEnd(); ++it) {
        const QString key = it.key().trimmed().toLower();
        if (excluded.contains(key) || key.endsWith(QStringLiteral("_token")))
            continue;
        const QJsonValue item = it.value();
        if (item.isString())
            result.insert(it.key(), sanitizeString(item.toString()));
        else if (item.isObject())
            result.insert(it.key(), sanitizeObject(item.toObject()));
        else if (item.isArray()) {
            QJsonArray array;
            for (const QJsonValue &entry : item.toArray()) {
                if (entry.isString())
                    array.append(sanitizeString(entry.toString()));
                else if (entry.isObject())
                    array.append(sanitizeObject(entry.toObject()));
                else if (!entry.isArray())
                    array.append(entry);
            }
            result.insert(it.key(), array);
        } else {
            result.insert(it.key(), item);
        }
    }
    return result;
}

void BetaDiagnostics::record(const QString &category, const QString &severity,
                             const QString &code, const QString &message,
                             const QJsonObject &metrics,
                             const QJsonObject &context)
{
    if (QThread::currentThread() != thread()) {
        QMetaObject::invokeMethod(this, [=]() {
            record(category, severity, code, message, metrics, context);
        }, Qt::QueuedConnection);
        return;
    }
    QJsonObject event{
        {QStringLiteral("id"),
         QUuid::createUuid().toString(QUuid::WithoutBraces)},
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("seq"), ++m_nextSeq},
        {QStringLiteral("captured_at"),
         QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
        {QStringLiteral("category"),
         sanitizeString(category.toUpper(), 40)},
        {QStringLiteral("severity"), normalizedSeverity(severity)},
        {QStringLiteral("code"), sanitizeString(code.toUpper(), 100)},
        {QStringLiteral("metrics"), sanitizeObject(metrics)},
        {QStringLiteral("context"), sanitizeObject(context)}};
    if (!message.isEmpty())
        event.insert(QStringLiteral("message"), sanitizeString(message));
    appendLocal(event);
    if (m_localEventCount > 0 && m_localEventCount % 50 == 0)
        flush();
}

void BetaDiagnostics::appendLocal(QJsonObject event)
{
    QFile file(m_spoolPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append))
        return;
    const QByteArray line = QJsonDocument(event).toJson(QJsonDocument::Compact)
        + QByteArrayLiteral("\n");
    file.write(line);
    file.close();
    ++m_localEventCount;
    m_localBytes += line.size();
    enforceLocalLimit();
}

QList<QJsonObject> BetaDiagnostics::readSpool() const
{
    QList<QJsonObject> events;
    QFile file(m_spoolPath);
    if (!file.open(QIODevice::ReadOnly))
        return events;
    while (!file.atEnd()) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readLine());
        if (document.isObject())
            events.append(document.object());
    }
    return events;
}

void BetaDiagnostics::rewriteSpool(const QList<QJsonObject> &events)
{
    QSaveFile file(m_spoolPath);
    if (!file.open(QIODevice::WriteOnly))
        return;
    for (const QJsonObject &event : events) {
        const QByteArray line = QJsonDocument(event).toJson(QJsonDocument::Compact)
            + QByteArrayLiteral("\n");
        file.write(line);
    }
    if (file.commit()) {
        m_localEventCount = events.size();
        m_localBytes = QFileInfo(m_spoolPath).size();
    }
}

void BetaDiagnostics::enforceLocalLimit()
{
    if (m_localEventCount <= kMaximumSpoolEvents
        && m_localBytes <= kMaximumSpoolBytes)
        return;
    QList<QJsonObject> events = readSpool();
    auto serializedBytes = [&events]() {
        qint64 total = 0;
        for (const QJsonObject &event : events)
            total += QJsonDocument(event).toJson(QJsonDocument::Compact).size() + 1;
        return total;
    };
    qint64 bytes = serializedBytes();
    if (events.size() <= kMaximumSpoolEvents && bytes <= kMaximumSpoolBytes)
        return;
    while (!events.isEmpty()
           && (events.size() > kMaximumSpoolEvents
               || bytes > kMaximumSpoolBytes)) {
        auto candidate = std::find_if(events.begin(), events.end(), droppable);
        if (candidate == events.end())
            candidate = events.begin();
        events.erase(candidate);
        bytes = serializedBytes();
    }
    rewriteSpool(events);
}

void BetaDiagnostics::startAuthenticatedSession()
{
    if (!m_auth || !m_auth->logged() || m_auth->devOffline()
        || m_auth->accessToken().isEmpty() || !m_sessionId.isEmpty())
        return;
    m_sessionId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_sessionToken = m_auth->accessToken();
    if (!m_priorSessionId.isEmpty()) {
        const QString priorSession = m_priorSessionId;
        QList<QJsonObject> recovered = readSpool();
        bool changed = false;
        for (QJsonObject &event : recovered) {
            if (event.value(QStringLiteral("session_id")).toString()
                == m_priorSessionId) {
                event.insert(QStringLiteral("session_id"), m_sessionId);
                changed = true;
            }
        }
        if (changed)
            rewriteSpool(recovered);
        m_priorSessionId.clear();
        postRpc(QStringLiteral("finish_beta_diagnostic_session_v01"),
                {{QStringLiteral("p_session_id"), priorSession},
                 {QStringLiteral("p_end_reason"), QStringLiteral("UNKNOWN")}},
                [](bool, int) {});
    }
    QSettings settings;
    settings.setValue(QStringLiteral("betaDiagnostics/activeSessionId"),
                      m_sessionId);
    settings.sync();

    record(QStringLiteral("SESSION"), QStringLiteral("INFO"),
           QStringLiteral("SESSION_STARTED"));
    if (m_previousSessionUnclean) {
        record(QStringLiteral("SESSION"), QStringLiteral("WARNING"),
               QStringLiteral("PREVIOUS_SESSION_UNCLEAN"));
        m_previousSessionUnclean = false;
    }
    sendBegin();
}

void BetaDiagnostics::sendBegin()
{
    if (m_sessionId.isEmpty() || m_sessionToken.isEmpty()
        || m_remoteBegun || m_beginInFlight)
        return;
    m_beginInFlight = true;
    const QString build = m_device.value(QStringLiteral("app_build")).toString();
    const QJsonObject payload{
        {QStringLiteral("p_session_id"), m_sessionId},
        {QStringLiteral("p_install_id"), m_installId},
        {QStringLiteral("p_platform"), QStringLiteral("android")},
        {QStringLiteral("p_app_version"), QCoreApplication::applicationVersion()},
        {QStringLiteral("p_app_build"), build},
        {QStringLiteral("p_device"), m_device}};
    postRpc(QStringLiteral("begin_beta_diagnostic_session_v01"), payload,
            [this](bool ok, int) {
        m_beginInFlight = false;
        m_remoteBegun = ok;
        if (ok)
            flush();
    });
}

void BetaDiagnostics::flush()
{
    if (m_sessionId.isEmpty() || m_sessionToken.isEmpty())
        return;
    if (!m_remoteBegun) {
        sendBegin();
        return;
    }
    if (m_flushInFlight)
        return;

    QList<QJsonObject> events = readSpool();
    QList<QJsonObject> batch;
    QString batchSession;
    bool assignedSession = false;
    for (QJsonObject &event : events) {
        QString eventSession = event.value(QStringLiteral("session_id")).toString();
        if (eventSession.isEmpty()) {
            eventSession = m_sessionId;
            event.insert(QStringLiteral("session_id"), eventSession);
            assignedSession = true;
        }
        if (batchSession.isEmpty())
            batchSession = eventSession;
        if (eventSession == batchSession && batch.size() < kMaximumRpcEvents)
            batch.append(event);
    }
    if (assignedSession)
        rewriteSpool(events);
    if (batch.isEmpty()) {
        if (!m_finishReason.isEmpty())
            sendFinish();
        return;
    }

    QJsonArray payloadEvents;
    QSet<QString> ids;
    for (const QJsonObject &event : batch) {
        payloadEvents.append(event);
        ids.insert(event.value(QStringLiteral("id")).toString());
    }
    m_flushInFlight = true;
    postRpc(QStringLiteral("append_beta_diagnostic_events_v01"),
            {{QStringLiteral("p_session_id"), batchSession},
             {QStringLiteral("p_events"), payloadEvents}},
            [this, ids](bool ok, int) {
        m_flushInFlight = false;
        if (!ok)
            return;
        QList<QJsonObject> remaining;
        for (const QJsonObject &event : readSpool()) {
            if (!ids.contains(event.value(QStringLiteral("id")).toString()))
                remaining.append(event);
        }
        rewriteSpool(remaining);
        if (!remaining.isEmpty())
            QTimer::singleShot(0, this, &BetaDiagnostics::flush);
        else if (!m_finishReason.isEmpty())
            sendFinish();
    });
}

void BetaDiagnostics::finishSession(const QString &reason)
{
    if (m_sessionId.isEmpty())
        return;
    const QString normalized = reason.trimmed().toUpper();
    m_finishReason = normalized == QStringLiteral("LOGOUT")
        ? normalized : QStringLiteral("NORMAL");
    record(QStringLiteral("SESSION"), QStringLiteral("INFO"),
           QStringLiteral("SESSION_FINISH_REQUESTED"), {}, {},
           {{QStringLiteral("reason"), m_finishReason}});
    flush();
}

void BetaDiagnostics::sendFinish()
{
    if (!m_remoteBegun || m_finishInFlight || m_finishReason.isEmpty())
        return;
    m_finishInFlight = true;
    postRpc(QStringLiteral("finish_beta_diagnostic_session_v01"),
            {{QStringLiteral("p_session_id"), m_sessionId},
             {QStringLiteral("p_end_reason"), m_finishReason}},
            [this](bool ok, int) {
        m_finishInFlight = false;
        if (!ok)
            return;
        QSettings settings;
        settings.remove(QStringLiteral("betaDiagnostics/activeSessionId"));
        settings.sync();
        m_finishReason.clear();
        m_sessionId.clear();
        m_sessionToken.clear();
        m_remoteBegun = false;
    });
}

void BetaDiagnostics::postRpc(
    const QString &name, const QJsonObject &payload,
    const std::function<void(bool, int)> &done)
{
    if (!m_api || m_sessionToken.isEmpty()) {
        done(false, 0);
        return;
    }
    QNetworkRequest request = m_api->makeRequest(
        m_api->restUrl(QStringLiteral("rpc/") + name), m_sessionToken);
    QNetworkReply *reply = m_api->nam()->post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this,
            [reply, done]() {
        const int http = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = reply->error() == QNetworkReply::NoError
            && http >= 200 && http < 300;
        reply->deleteLater();
        done(ok, http);
    });
}

void BetaDiagnostics::recordAndroidJson(const QString &json)
{
    BetaDiagnostics *diagnostics = instance();
    if (!diagnostics)
        return;
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
    if (!document.isObject())
        return;
    const QJsonObject event = document.object();
    const QString code = event.value(QStringLiteral("code")).toString();
    const QJsonObject context = event.value(QStringLiteral("context")).toObject();
    if (code == QStringLiteral("DEVICE_SNAPSHOT"))
        diagnostics->m_device = diagnostics->sanitizeObject(context);
    diagnostics->record(
        event.value(QStringLiteral("category")).toString(),
        event.value(QStringLiteral("severity")).toString(), code,
        event.value(QStringLiteral("message")).toString(),
        event.value(QStringLiteral("metrics")).toObject(), context);
}

void BetaDiagnostics::installQtMessageCapture()
{
    s_previousMessageHandler = qInstallMessageHandler(qtMessageHandler);
}

void BetaDiagnostics::qtMessageHandler(QtMsgType type,
                                       const QMessageLogContext &context,
                                       const QString &message)
{
    if (type == QtWarningMsg || type == QtCriticalMsg || type == QtFatalMsg) {
        const QString severity = type == QtWarningMsg
            ? QStringLiteral("WARNING")
            : (type == QtCriticalMsg ? QStringLiteral("ERROR")
                                     : QStringLiteral("FATAL"));
        if (s_instance) {
            s_instance->record(QStringLiteral("QT"), severity,
                               QStringLiteral("QT_MESSAGE"), message, {},
                               {{QStringLiteral("category"),
                                 QString::fromUtf8(context.category
                                     ? context.category : "qt")}});
        }
    }
    if (s_previousMessageHandler)
        s_previousMessageHandler(type, context, message);
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeRecordBetaDiagnostic(
    JNIEnv *environment, jclass, jstring eventJson)
{
    if (!eventJson)
        return;
    const char *utf8 = environment->GetStringUTFChars(eventJson, nullptr);
    if (!utf8)
        return;
    const QString json = QString::fromUtf8(utf8);
    environment->ReleaseStringUTFChars(eventJson, utf8);
    BetaDiagnostics::recordAndroidJson(json);
}
#endif
