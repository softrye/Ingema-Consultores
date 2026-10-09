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
    // Último tipo de mapa elegido en el selector y su miniatura (memoria).
    Q_PROPERTY(QString earthPickerMapType READ earthPickerMapType NOTIFY earthPickerSnapshotChanged)
    Q_PROPERTY(QString earthPickerSnapshotUrl READ earthPickerSnapshotUrl NOTIFY earthPickerSnapshotChanged)
    Q_PROPERTY(double earthPickerSnapshotLatitude READ earthPickerSnapshotLatitude NOTIFY earthPickerSnapshotChanged)
    Q_PROPERTY(double earthPickerSnapshotLongitude READ earthPickerSnapshotLongitude NOTIFY earthPickerSnapshotChanged)
    // Live device state computed by InGePerformanceRuntime (Android). One
    // source for InGeCoreFlow, Flutter (via the QML profile) and Cesium.
    Q_PROPERTY(QString deviceTier READ deviceTier NOTIFY deviceStateChanged)
    // INGE_PERFORMANCE_BARE_UI: lo decide el host Android (InGeQtActivity.BARE_UI).
    Q_PROPERTY(bool bareUiEnabled READ bareUiEnabled CONSTANT)
    Q_PROPERTY(QString baseDeviceTier READ baseDeviceTier NOTIFY deviceStateChanged)
    Q_PROPERTY(bool lowRamDevice READ lowRamDevice NOTIFY deviceStateChanged)
    Q_PROPERTY(int totalMemoryMb READ totalMemoryMb NOTIFY deviceStateChanged)
    Q_PROPERTY(bool powerSaveMode READ powerSaveMode NOTIFY deviceStateChanged)
    Q_PROPERTY(int thermalStatus READ thermalStatus NOTIFY deviceStateChanged)
    Q_PROPERTY(bool systemAnimationsEnabled READ systemAnimationsEnabled NOTIFY deviceStateChanged)
    Q_PROPERTY(qreal systemFontScale READ systemFontScale NOTIFY deviceStateChanged)
    Q_PROPERTY(int memoryTrimLevel READ memoryTrimLevel NOTIFY deviceStateChanged)

public:
    explicit InGeGraphicsCore(QObject *parent = nullptr);

    QString graphicsBackend() const;
    QString gpuName() const;
    bool vulkanAvailable() const;
    bool earthAvailable() const;
    bool earthActive() const;
    QString earthState() const;
    QString renderProfile() const;
    QString earthPickerMapType() const { return m_pickerMapType; }
    QString earthPickerSnapshotUrl() const { return m_pickerSnapshotUrl; }
    double earthPickerSnapshotLatitude() const { return m_pickerSnapshotLat; }
    double earthPickerSnapshotLongitude() const { return m_pickerSnapshotLon; }
    QString deviceTier() const;
    bool bareUiEnabled() const;
    QString baseDeviceTier() const;
    bool lowRamDevice() const;
    int totalMemoryMb() const;
    bool powerSaveMode() const;
    int thermalStatus() const;
    bool systemAnimationsEnabled() const;
    qreal systemFontScale() const;
    int memoryTrimLevel() const;

    // JSON from InGePerformanceRuntime.stateJson(); GUI thread only.
    void applyDevicePerformanceState(const QString &json);

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

    // Selector de coordenadas de Calicatas sobre el WebView de InGe Earth
    // (un solo motor Cesium). Rect en píxeles físicos de pantalla.
    Q_INVOKABLE bool openEarthPicker(const QString &json, int left, int top,
                                     int width, int height);
    Q_INVOKABLE void updateEarthPickerRect(int left, int top, int width, int height);
    Q_INVOKABLE void setEarthPickerPoint(const QString &json);
    Q_INVOKABLE void setEarthPickerSuspended(bool suspended);
    Q_INVOKABLE void closeEarthPicker();
    // Plantilla XYZ del mapa base de Earth ("" si no está configurada).
    Q_INVOKABLE QString earthBaseMapUrl() const;

signals:
    void stateChanged();
    void earthPickerPointSelected(double latitude, double longitude);
    void earthPickerStateChanged(const QString &state);
    void earthPickerSnapshotChanged();
    void deviceStateChanged();

private:
    void inspectRuntime(QQuickWindow *window);
    void applyRuntimeState(const QString &backend, const QString &gpuName,
                           bool vulkanAvailable);
    void setEarthState(const QString &state, bool active);
    void setQtRenderingSuspended(bool suspended);
    void restoreAfterExternalActivityIfReady();
    void readInitialDeviceState();

    QString m_graphicsBackend = QStringLiteral("PENDING_RUNTIME_INSPECTION");
    QString m_gpuName = QStringLiteral("PENDING");
    bool m_vulkanAvailable = false;
    bool m_earthAvailable = false;
    bool m_earthActive = false;
    bool m_earthExitPending = false;
    QString m_earthState = QStringLiteral("UNINITIALIZED");
    QString m_renderProfile = QStringLiteral("BALANCED");
    QString m_deviceTier = QStringLiteral("UNKNOWN");
    QString m_baseDeviceTier = QStringLiteral("UNKNOWN");
    bool m_lowRamDevice = false;
    int m_totalMemoryMb = 0;
    bool m_powerSaveMode = false;
    int m_thermalStatus = -1;
    bool m_systemAnimationsEnabled = true;
    qreal m_systemFontScale = 1.0;
    int m_memoryTrimLevel = 0;
    InGeEarthHostController *m_earthHostController = nullptr;
    QString m_pickerMapType = QStringLiteral("DEFAULT");
    QString m_pickerSnapshotUrl;
    double m_pickerSnapshotLat = 0.0;
    double m_pickerSnapshotLon = 0.0;
    QPointer<QQuickWindow> m_window;
    bool m_qtRenderingSuspended = false;
    bool m_windowWasVisible = true;
    bool m_externalActivityInFlight = false;
    bool m_externalActivityRestorePending = false;
    bool m_externalWindowWasVisible = true;
    int m_externalRestoreAttempts = 0;
    std::atomic_bool m_runtimeInspectionStarted{false};
};
