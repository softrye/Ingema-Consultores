#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

class DockContextController;

// Routes a tap on the single dock to the surface that published the action.
// Nested menu entries are dispatched by id exactly like capsule actions; the
// controller resolves them anywhere in the active tree.
// Adapters are per technology boundary (QML signal, Flutter channel, Earth
// WebView), never per subapp. One command is in flight at a time unless the
// action declares itself repeatable; the generation of the tap must match the
// active context or the tap is dropped as stale.
class DockCommandRouter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit DockCommandRouter(DockContextController *controller, QObject *parent = nullptr);
    ~DockCommandRouter() override;

    static DockCommandRouter *instance();

    bool busy() const { return !m_inFlightId.isEmpty(); }

    Q_INVOKABLE bool dispatch(const QString &actionId, int generation);
    Q_INVOKABLE bool dispatchGlobal(const QString &capabilityId);
    Q_INVOKABLE void complete(const QString &dispatchId);

    // Completion reported by Flutter / Earth: {"dispatchId": "...", "ok": bool}
    void completeJson(const QString &json);

signals:
    // QML adapter: the matching ContextPublisher executes and calls complete().
    void qmlCommand(const QString &ownerId, const QString &contextId,
                    const QString &commandId, const QString &dispatchId);
    void globalCapabilityRequested(const QString &capabilityId);
    void busyChanged();

private:
    bool deliverNative(const QString &channel, const QString &payload);
    void release(const QString &reason);

    DockContextController *m_controller = nullptr;
    QString m_inFlightId;
    QString m_inFlightCommand;
    quint64 m_sequence = 0;
    QTimer m_releaseTimer;
};
