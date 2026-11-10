#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

#include <atomic>

class QQuickWindow;

// Servicio de estado gráfico y de dispositivo (sin interfaz, Visual Zero
// 2026-10-10): backend/GPU del scene graph, estado del dispositivo publicado
// por InGePerformanceRuntime (Android) y protección del render de Qt mientras
// la cámara o la galería sustituyen la Surface de la actividad.
class InGeGraphicsCore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString graphicsBackend READ graphicsBackend NOTIFY stateChanged)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY stateChanged)
    Q_PROPERTY(bool vulkanAvailable READ vulkanAvailable NOTIFY stateChanged)
    // Estado vivo del dispositivo calculado por InGePerformanceRuntime (Android).
    Q_PROPERTY(QString deviceTier READ deviceTier NOTIFY deviceStateChanged)
    Q_PROPERTY(QString baseDeviceTier READ baseDeviceTier NOTIFY deviceStateChanged)
    Q_PROPERTY(bool lowRamDevice READ lowRamDevice NOTIFY deviceStateChanged)
    Q_PROPERTY(int totalMemoryMb READ totalMemoryMb NOTIFY deviceStateChanged)
    Q_PROPERTY(bool powerSaveMode READ powerSaveMode NOTIFY deviceStateChanged)
    Q_PROPERTY(int thermalStatus READ thermalStatus NOTIFY deviceStateChanged)
    Q_PROPERTY(bool systemAnimationsEnabled READ systemAnimationsEnabled NOTIFY deviceStateChanged)
    Q_PROPERTY(qreal systemFontScale READ systemFontScale NOTIFY deviceStateChanged)
    Q_PROPERTY(int memoryTrimLevel READ memoryTrimLevel NOTIFY deviceStateChanged)
    // Selector «Calidad gráfica»: AUTO | LOW | HIGH | VERY_HIGH | EXTREME (persistido).
    Q_PROPERTY(QString qualityOverride READ qualityOverride NOTIFY deviceStateChanged)
    // Perfil de fidelidad efectivo: VERY_HIGH/EXTREME sólo por elección manual;
    // si no, el tier del dispositivo (Automática nunca los elige).
    Q_PROPERTY(QString fidelity READ fidelity NOTIFY deviceStateChanged)
    // Punto de enganche de las animaciones avanzadas (VERY_HIGH y EXTREME).
    Q_PROPERTY(bool advancedMotion READ advancedMotion NOTIFY deviceStateChanged)
    Q_PROPERTY(bool extremeGlass READ extremeGlass NOTIFY deviceStateChanged)
    // 0 normal, 1 alto (VERY_HIGH), 2 máximo (EXTREME): renderTypeQuality, layer.smooth/samples.
    Q_PROPERTY(int textSmoothing READ textSmoothing NOTIFY deviceStateChanged)
    // MSAA de la ventana sólo se fija al arrancar: true si la elección actual pide reiniciar.
    Q_PROPERTY(bool msaaRestartRequired READ msaaRestartRequired NOTIFY deviceStateChanged)

public:
    explicit InGeGraphicsCore(QObject *parent = nullptr);

    QString graphicsBackend() const;
    QString gpuName() const;
    bool vulkanAvailable() const;
    QString deviceTier() const;
    QString baseDeviceTier() const;
    bool lowRamDevice() const;
    int totalMemoryMb() const;
    bool powerSaveMode() const;
    int thermalStatus() const;
    bool systemAnimationsEnabled() const;
    qreal systemFontScale() const;
    int memoryTrimLevel() const;
    QString qualityOverride() const;
    QString fidelity() const;
    bool advancedMotion() const;
    bool extremeGlass() const;
    int textSmoothing() const;
    bool msaaRestartRequired() const;
    // Antes de crear la ventana: MSAA y render de texto según la fidelidad guardada.
    static void applyStartupFidelity();
    Q_INVOKABLE void setQualityOverride(const QString &value);

    // JSON from InGePerformanceRuntime.stateJson(); GUI thread only.
    void applyDevicePerformanceState(const QString &json);

    void attachWindow(QQuickWindow *window);
    void prepareForExternalActivity();
    void completeExternalActivity();

signals:
    void stateChanged();
    void deviceStateChanged();

private:
    void inspectRuntime(QQuickWindow *window);
    void applyRuntimeState(const QString &backend, const QString &gpuName,
                           bool vulkanAvailable);
    void restoreAfterExternalActivityIfReady();
    void readInitialDeviceState();

    QString m_graphicsBackend = QStringLiteral("PENDING_RUNTIME_INSPECTION");
    QString m_gpuName = QStringLiteral("PENDING");
    bool m_vulkanAvailable = false;
    QString m_deviceTier = QStringLiteral("UNKNOWN");
    QString m_baseDeviceTier = QStringLiteral("UNKNOWN");
    QString m_qualityOverride = QStringLiteral("AUTO");
    bool m_lowRamDevice = false;
    int m_totalMemoryMb = 0;
    bool m_powerSaveMode = false;
    int m_thermalStatus = -1;
    bool m_systemAnimationsEnabled = true;
    qreal m_systemFontScale = 1.0;
    int m_memoryTrimLevel = 0;
    QPointer<QQuickWindow> m_window;
    bool m_externalActivityInFlight = false;
    bool m_externalActivityRestorePending = false;
    bool m_externalWindowWasVisible = true;
    int m_externalRestoreAttempts = 0;
    std::atomic_bool m_runtimeInspectionStarted{false};
};
