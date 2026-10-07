#pragma once

#include <QObject>
#include <QVariantMap>

class RenditionLocalStore;
class RenditionRepository;

class RenditionSyncController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit RenditionSyncController(RenditionLocalStore *store,
                                     RenditionRepository *repository,
                                     QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void synchronize();

signals:
    void busyChanged();
    void lastErrorChanged();
    void syncFinished(int remaining);
    void syncStopped(const QString &state, const QString &message);

private:
    void processNext();
    void finishCurrent(const QVariantMap &remote);
    void failCurrent(const QString &code, const QString &message);
    void setBusy(bool busy);
    void setLastError(const QString &message);

    RenditionLocalStore *m_store = nullptr;
    RenditionRepository *m_repository = nullptr;
    QVariantMap m_current;
    QString m_locationRefreshLocalId;
    bool m_busy = false;
    QString m_lastError;
};
