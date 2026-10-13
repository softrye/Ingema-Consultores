#pragma once

#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <QVariantMap>
#include <memory>

class QQuickImageProvider;
struct FusionFrameStore;

// A single context object. No QML_ELEMENT / singleton / second registration.
class FusionBridgeController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY stateChanged)
    Q_PROPERTY(bool earthInstalled READ earthInstalled NOTIFY stateChanged)
    Q_PROPERTY(QString earthVersion READ earthVersion NOTIFY stateChanged)
    Q_PROPERTY(bool probeSupported READ probeSupported NOTIFY stateChanged)
    Q_PROPERTY(bool interactive READ interactive CONSTANT)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString detail READ detail NOTIFY stateChanged)
    Q_PROPERTY(QString diagnostics READ diagnostics NOTIFY stateChanged)
    Q_PROPERTY(bool frameFresh READ frameFresh NOTIFY frameChanged)
    Q_PROPERTY(QString frameUrl READ frameUrl NOTIFY frameChanged)
    Q_PROPERTY(QVariantMap requestedTarget READ requestedTarget NOTIFY targetChanged)
public:
    explicit FusionBridgeController(QObject *parent = nullptr);
    ~FusionBridgeController() override;
    QQuickImageProvider *createImageProvider(); // ownership passes to QQmlEngine
    bool active() const { return m_active; }
    bool earthInstalled() const { return m_installed; }
    QString earthVersion() const { return m_version; }
    bool probeSupported() const { return m_probeSupported; }
    bool interactive() const { return false; } // no verified cooperative contract
    QString state() const { return m_state; }
    QString detail() const { return m_detail; }
    QString diagnostics() const { return m_diagnostics; }
    bool frameFresh() const { return m_frameFresh; }
    QString frameUrl() const;
    QVariantMap requestedTarget() const { return m_target; }
    Q_INVOKABLE void open();
    Q_INVOKABLE void close();
    Q_INVOKABLE void requestCaptureProbe();
    Q_INVOKABLE bool command(const QString &name);
    Q_INVOKABLE bool setTarget(double latitude, double longitude, const QString &label);
signals:
    void stateChanged();
    void frameChanged();
    void targetChanged();
private:
    void poll();
    void clearFrame();
    void fail(const QString &code);
    std::shared_ptr<FusionFrameStore> m_frames;
    QTimer m_poll;
    QElapsedTimer m_lastFrame;
    qint64 m_generation = 0;
    quint64 m_frameRevision = 0;
    quint64 m_observedRevision = 0;
    bool m_active = false;
    bool m_installed = false;
    bool m_probeSupported = false;
    bool m_frameFresh = false;
    QString m_version;
    QString m_state = QStringLiteral("CLOSED");
    QString m_detail;
    QString m_diagnostics;
    QVariantMap m_target;
};
