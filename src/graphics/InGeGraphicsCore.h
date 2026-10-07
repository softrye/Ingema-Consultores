#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

#include <atomic>

class QQuickWindow;
class InGeEarthHostController;

class InGeGraphicsCore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString graphicsBackend READ graphicsBackend NOTIFY stateChanged)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY stateChanged)
    Q_PROPERTY(bool vulkanAvailable READ vulkanAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool earthAvailable READ earthAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool earthActive READ earthActive NOTIFY stateChanged)
    Q_PROPERTY(QString earthState READ earthState NOTIFY stateChanged)
    Q_PROPERTY(QString renderProfile READ renderProfile NOTIFY stateChanged)

public:
    explicit InGeGraphicsCore(QObject *parent = nullptr);

    QString graphicsBackend() const;
    QString gpuName() const;
    bool vulkanAvailable() const;
    bool earthAvailable() const;
    bool earthActive() const;
    QString earthState() const;
    QString renderProfile() const;

    void attachWindow(QQuickWindow *window);
    void setEarthHostController(InGeEarthHostController *controller);
    void prepareForExternalActivity();
    void completeExternalActivity();

    Q_INVOKABLE bool openEarth();
    Q_INVOKABLE bool focusEarthCoordinate(double latitude, double longitude,
                                          double altitude,
                                          const QString &label);
    Q_INVOKABLE void closeEarth();
    Q_INVOKABLE bool setRenderProfile(const QString &profile);

signals:
    void stateChanged();

private:
    void inspectRuntime(QQuickWindow *window);
    void applyRuntimeState(const QString &backend, const QString &gpuName,
                           bool vulkanAvailable);
    void setEarthState(const QString &state, bool active);
    void setQtRenderingSuspended(bool suspended);
    void restoreAfterExternalActivityIfReady();

    QString m_graphicsBackend = QStringLiteral("PENDING_RUNTIME_INSPECTION");
    QString m_gpuName = QStringLiteral("PENDING");
    bool m_vulkanAvailable = false;
    bool m_earthAvailable = false;
    bool m_earthActive = false;
    bool m_earthExitPending = false;
    QString m_earthState = QStringLiteral("UNINITIALIZED");
    QString m_renderProfile = QStringLiteral("BALANCED");
    InGeEarthHostController *m_earthHostController = nullptr;
    QPointer<QQuickWindow> m_window;
    bool m_qtRenderingSuspended = false;
    bool m_windowWasVisible = true;
    bool m_externalActivityInFlight = false;
    bool m_externalActivityRestorePending = false;
    bool m_externalWindowWasVisible = true;
    int m_externalRestoreAttempts = 0;
    std::atomic_bool m_runtimeInspectionStarted{false};
};
