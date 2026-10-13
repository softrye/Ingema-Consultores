#pragma once
#include "InGeCoreExecutor.h"
#include <QObject>
#include <QTimer>
#include <QHash>
#include <QJsonObject>
class AuthSession;
class SupabaseClient;

namespace inge::core {
class RemoteExecutor final : public QObject, public InGeCoreExecutor {
    Q_OBJECT
    Q_PROPERTY(bool online READ online NOTIFY healthChanged)
public:
    RemoteExecutor(SupabaseClient *api, AuthSession *auth, QObject *parent=nullptr);
    bool canExecute(const Request &request) const override;
    Response execute(const Request &request) override;
    Q_INVOKABLE bool cancel(const QString &id) override;
    ExecutorHealth health() const override;
    bool online() const { return m_online; }
    Q_INVOKABLE void start();
    Q_INVOKABLE QString reviewCalicata(const QVariantMap &snapshot);
    Q_INVOKABLE QString interpretCalicata(const QVariantMap &snapshot);
    void indexDocument(const QString &path,const QString &node,const QString &version,const QString &project);
    void analyzeEvidence(const QString &requestId, const QVariantList &attachments,
                         const QVariantMap &context = {});
signals:
    void completed(const QString &requestId, const QVariantMap &result, const QString &error);
    void healthChanged();
private:
    struct Pending { QJsonObject body; qint64 started=0; qint64 next=0; bool submitted=false; bool busy=false; };
    void tick();
    void selectAccount();
    void persist();
    void finish(const QString &id,const QVariantMap &result,const QString &error);
    SupabaseClient *m_api;
    AuthSession *m_auth;
    QTimer m_timer;
    QHash<QString,Pending> m_pending;
    QString m_user, m_journal;
    quint64 m_epoch=0;
    bool m_online=false, m_healthBusy=false;
    qint64 m_healthNext=0;
};
}
