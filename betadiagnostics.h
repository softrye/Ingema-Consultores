#pragma once

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QtLogging>

#include <functional>

class AuthSession;
class QNetworkReply;
class QTimer;
class SupabaseClient;

class BetaDiagnostics final : public QObject
{
    Q_OBJECT

public:
    explicit BetaDiagnostics(SupabaseClient *api, AuthSession *auth,
                             QObject *parent = nullptr);
    ~BetaDiagnostics() override;

    static BetaDiagnostics *instance();
    static void recordAndroidJson(const QString &json);

    void record(const QString &category, const QString &severity,
                const QString &code, const QString &message = {},
                const QJsonObject &metrics = {},
                const QJsonObject &context = {});
    void flush();
    void finishSession(const QString &reason);

private:
    void loadLocalState();
    void startAuthenticatedSession();
    void sendBegin();
    void sendFinish();
    void appendLocal(QJsonObject event);
    void enforceLocalLimit();
    void rewriteSpool(const QList<QJsonObject> &events);
    QList<QJsonObject> readSpool() const;
    void postRpc(const QString &name, const QJsonObject &payload,
                 const std::function<void(bool, int)> &done);
    QJsonObject sanitizeObject(const QJsonObject &value) const;
    QString sanitizeString(QString value, int maximum = 1000) const;
    void installQtMessageCapture();

    static void qtMessageHandler(QtMsgType type,
                                 const QMessageLogContext &context,
                                 const QString &message);

    static BetaDiagnostics *s_instance;
    static QtMessageHandler s_previousMessageHandler;

    SupabaseClient *m_api = nullptr;
    AuthSession *m_auth = nullptr;
    QTimer *m_flushTimer = nullptr;
    QString m_installId;
    QString m_sessionId;
    QString m_priorSessionId;
    QString m_sessionToken;
    QString m_spoolPath;
    QJsonObject m_device;
    qint64 m_nextSeq = 0;
    qint64 m_localBytes = 0;
    qsizetype m_localEventCount = 0;
    bool m_previousSessionUnclean = false;
    bool m_remoteBegun = false;
    bool m_beginInFlight = false;
    bool m_flushInFlight = false;
    bool m_finishInFlight = false;
    QString m_finishReason;
};
