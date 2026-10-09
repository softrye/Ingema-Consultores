#include "InGeGraphicsCore.h"

#include "InGeEarthHostController.h"
#include "InGeGraphicsDiagnostics.h"

#include <QDebug>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>
#include <QQuickWindow>
#include <QTimer>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

namespace {
constexpr auto kPerformanceRuntimeClass = "com/ingema/ingeplus/InGePerformanceRuntime";
QPointer<InGeGraphicsCore> g_graphicsCore;
}

InGeGraphicsCore::InGeGraphicsCore(QObject *parent)
    : QObject(parent)
{
    g_graphicsCore = this;
    readInitialDeviceState();
    if (qGuiApp) {
        connect(qGuiApp, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
                    if (state == Qt::ApplicationActive)
                        restoreAfterExternalActivityIfReady();
                });
    }
}

QString InGeGraphicsCore::graphicsBackend() const { return m_graphicsBackend; }
QString InGeGraphicsCore::gpuName() const { return m_gpuName; }
bool InGeGraphicsCore::vulkanAvailable() const { return m_vulkanAvailable; }
bool InGeGraphicsCore::earthAvailable() const { return m_earthAvailable; }
bool InGeGraphicsCore::earthActive() const { return m_earthActive; }
QString InGeGraphicsCore::earthState() const { return m_earthState; }
QString InGeGraphicsCore::renderProfile() const { return m_renderProfile; }
QString InGeGraphicsCore::deviceTier() const { return m_deviceTier; }
QString InGeGraphicsCore::baseDeviceTier() const { return m_baseDeviceTier; }
bool InGeGraphicsCore::lowRamDevice() const { return m_lowRamDevice; }
int InGeGraphicsCore::totalMemoryMb() const { return m_totalMemoryMb; }
bool InGeGraphicsCore::powerSaveMode() const { return m_powerSaveMode; }
int InGeGraphicsCore::thermalStatus() const { return m_thermalStatus; }
bool InGeGraphicsCore::systemAnimationsEnabled() const { return m_systemAnimationsEnabled; }
qreal InGeGraphicsCore::systemFontScale() const { return m_systemFontScale; }
int InGeGraphicsCore::memoryTrimLevel() const { return m_memoryTrimLevel; }

// The Activity may initialize the runtime before or after Qt creates this
// object: read it here, and the runtime pushes every later change.
void InGeGraphicsCore::readInitialDeviceState()
{
#ifdef Q_OS_ANDROID
    const QJniObject json = QJniObject::callStaticObjectMethod(
        kPerformanceRuntimeClass, "stateJson", "()Ljava/lang/String;");
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return;
    }
    if (json.isValid())
        applyDevicePerformanceState(json.toString());
#endif
}

void InGeGraphicsCore::applyDevicePerformanceState(const QString &json)
{
    const QJsonObject state = QJsonDocument::fromJson(json.toUtf8()).object();
    if (state.isEmpty())
        return;
    const QString tier = state.value(QStringLiteral("tier")).toString(m_deviceTier);
    const QString baseTier = state.value(QStringLiteral("baseTier")).toString(m_baseDeviceTier);
    const bool lowRam = state.value(QStringLiteral("lowRam")).toBool(m_lowRamDevice);
    const int totalMemoryMb = state.value(QStringLiteral("totalMemoryMb")).toInt(m_totalMemoryMb);
    const bool powerSave = state.value(QStringLiteral("powerSave")).toBool(m_powerSaveMode);
    const int thermal = state.value(QStringLiteral("thermal")).toInt(m_thermalStatus);
    const bool animators = state.value(QStringLiteral("animatorsEnabled"))
                               .toBool(m_systemAnimationsEnabled);
    const qreal fontScale = state.value(QStringLiteral("fontScale")).toDouble(m_systemFontScale);
    const int trimLevel = state.value(QStringLiteral("trimLevel")).toInt(m_memoryTrimLevel);
    if (tier == m_deviceTier && baseTier == m_baseDeviceTier && lowRam == m_lowRamDevice
        && totalMemoryMb == m_totalMemoryMb && powerSave == m_powerSaveMode
        && thermal == m_thermalStatus && animators == m_systemAnimationsEnabled
        && qFuzzyCompare(fontScale, m_systemFontScale) && trimLevel == m_memoryTrimLevel)
        return;
    m_deviceTier = tier;
    m_baseDeviceTier = baseTier;
    m_lowRamDevice = lowRam;
    m_totalMemoryMb = totalMemoryMb;
    m_powerSaveMode = powerSave;
    m_thermalStatus = thermal;
    m_systemAnimationsEnabled = animators;
    m_systemFontScale = fontScale > 0.0 ? fontScale : 1.0;
    m_memoryTrimLevel = trimLevel;
    qInfo().noquote() << "INGE_DEVICE_PERFORMANCE tier=" << m_deviceTier
                      << " base=" << m_baseDeviceTier << " lowRam=" << m_lowRamDevice
                      << " ramMb=" << m_totalMemoryMb << " powerSave=" << m_powerSaveMode
                      << " thermal=" << m_thermalStatus
                      << " animators=" << m_systemAnimationsEnabled
                      << " fontScale=" << m_systemFontScale
                      << " trim=" << m_memoryTrimLevel;
    emit deviceStateChanged();
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGePerformanceRuntime_nativePerformanceStateChanged(
    JNIEnv *, jclass, jstring json)
{
    const QPointer<InGeGraphicsCore> core = g_graphicsCore;
    if (!core || !json)
        return;
    const QString payload = QJniObject(json).toString();
    if (payload.size() > 4096)
        return;
    QMetaObject::invokeMethod(core, [core, payload]() {
        if (core)
            core->applyDevicePerformanceState(payload);
    }, Qt::QueuedConnection);
}
#endif

void InGeGraphicsCore::setEarthHostController(
    InGeEarthHostController *controller)
{
    if (m_earthHostController == controller)
        return;
    if (m_earthHostController)
        disconnect(m_earthHostController, nullptr, this, nullptr);
    m_earthHostController = controller;
    m_earthAvailable = controller && controller->supported();
    if (controller) {
        connect(controller, &InGeEarthHostController::stateChanged, this,
                [this]() {
                    m_earthActive = m_earthHostController->active();
                    m_earthState = m_earthHostController->state();
                    if (m_earthState == QStringLiteral("CLOSED")) {
                        m_earthExitPending = true;
                        // CLOSED publicado por el host Android es la señal
                        // física de salida. Qt debe volver antes de que QML
                        // procese MapNativePage.requestExitMap().
                        setQtRenderingSuspended(false);
                    }
                    emit stateChanged();
                });
        connect(controller, &InGeEarthHostController::pickerPointSelected,
                this, &InGeGraphicsCore::earthPickerPointSelected);
        connect(controller, &InGeEarthHostController::pickerStateChanged,
                this, &InGeGraphicsCore::earthPickerStateChanged);
        connect(controller, &InGeEarthHostController::pickerSnapshot, this,
                [this](const QString &mapType, double latitude, double longitude,
                       const QString &dataUrl) {
                    m_pickerMapType = mapType;
                    m_pickerSnapshotUrl = dataUrl;
                    m_pickerSnapshotLat = latitude;
                    m_pickerSnapshotLon = longitude;
                    emit earthPickerSnapshotChanged();
                });
    }
    emit stateChanged();
}

bool InGeGraphicsCore::openEarthPicker(const QString &json, int left, int top,
                                       int width, int height)
{
    if (!m_earthAvailable || !m_earthHostController || width <= 0 || height <= 0)
        return false;
    return m_earthHostController->showPicker(json, left, top, width, height);
}

void InGeGraphicsCore::updateEarthPickerRect(int left, int top, int width, int height)
{
    if (m_earthHostController && width > 0 && height > 0)
        m_earthHostController->updatePickerRect(left, top, width, height);
}

void InGeGraphicsCore::setEarthPickerPoint(const QString &json)
{
    if (m_earthHostController)
        m_earthHostController->setPickerPoint(json);
}

void InGeGraphicsCore::setEarthPickerSuspended(bool suspended)
{
    if (m_earthHostController)
        m_earthHostController->setPickerSuspended(suspended);
}

QString InGeGraphicsCore::earthBaseMapUrl() const
{
    return m_earthHostController ? m_earthHostController->defaultMapUrl() : QString();
}

void InGeGraphicsCore::closeEarthPicker()
{
    if (m_earthHostController)
        m_earthHostController->hidePicker();
}

void InGeGraphicsCore::attachWindow(QQuickWindow *window)
{
    if (!window) {
        applyRuntimeState(QStringLiteral("UNAVAILABLE"),
                          QStringLiteral("UNAVAILABLE"), false);
        return;
    }

    m_window = window;
    // Earth hides this window instead of destroying it. Keep the existing QML
    // tree and graphics resources so the exact Home state can resume in place.
    window->setPersistentGraphics(true);
    window->setPersistentSceneGraph(true);

    connect(window, &QQuickWindow::sceneGraphInitialized, this,
            [this, window]() { inspectRuntime(window); },
            Qt::DirectConnection);
    connect(window, &QQuickWindow::beforeRendering, this,
            [this, window]() { inspectRuntime(window); },
            Qt::DirectConnection);
    connect(window, &QQuickWindow::sceneGraphError, this,
            [this](QQuickWindow::SceneGraphError, const QString &message) {
                applyRuntimeState(QStringLiteral("ERROR"), message, false);
            });
    connect(window, &QQuickWindow::sceneGraphInvalidated, this,
            [this]() {
                // La invalidación del scene graph no significa que el hardware
                // haya perdido soporte Vulkan. Solo habilita una nueva inspección
                // cuando Qt reconstruya su renderer.
                m_runtimeInspectionStarted.store(false);
            },
            Qt::DirectConnection);

    window->update();
}

void InGeGraphicsCore::prepareForExternalActivity()
{
    m_externalActivityInFlight = true;
    m_externalActivityRestorePending = false;
    m_externalRestoreAttempts = 0;

    QQuickWindow *window = m_window.data();
    if (!window)
        return;

    // Cámara/Galería reemplazan temporalmente la Surface de la QtActivity.
    // Ocultar primero la ventana detiene el render loop antes de que Android
    // retire la EGLSurface; después permitimos liberar el scene graph.
    m_externalWindowWasVisible = window->isVisible();
    if (m_externalWindowWasVisible)
        window->hide();
    window->setPersistentGraphics(false);
    window->setPersistentSceneGraph(false);
    window->releaseResources();
    qInfo().noquote()
        << "INGE_EXTERNAL_ACTIVITY_RENDER_PREPARED windowVisible="
        << window->isVisible();
}

void InGeGraphicsCore::completeExternalActivity()
{
    m_externalActivityInFlight = false;
    m_externalActivityRestorePending = true;
    m_externalRestoreAttempts = 0;
    restoreAfterExternalActivityIfReady();
}

void InGeGraphicsCore::restoreAfterExternalActivityIfReady()
{
    if (!m_externalActivityRestorePending || m_externalActivityInFlight || !qGuiApp
        || qGuiApp->applicationState() != Qt::ApplicationActive)
        return;

    QQuickWindow *window = m_window.data();
    if (!window) {
        m_externalActivityRestorePending = false;
        return;
    }

    window->setPersistentGraphics(true);
    window->setPersistentSceneGraph(true);
    if (m_externalWindowWasVisible && !window->isVisible())
        window->show();

    // ApplicationActive puede llegar unos milisegundos antes de que Android
    // publique de nuevo una Surface expuesta. Nunca pedir un frame sobre una
    // superficie todavía no lista: reintentar con intervalo fijo y positivo.
    if (!window->isExposed()) {
        ++m_externalRestoreAttempts;
        if (m_externalRestoreAttempts <= 12) {
            QTimer::singleShot(32, this, [this]() {
                restoreAfterExternalActivityIfReady();
            });
            return;
        }

        qWarning().noquote()
            << "INGE_EXTERNAL_ACTIVITY_RENDER_WAIT_TIMEOUT exposed=false";
        m_externalActivityRestorePending = false;
        m_externalRestoreAttempts = 0;
        return;
    }

    m_externalActivityRestorePending = false;
    m_externalRestoreAttempts = 0;
    window->update();
    qInfo().noquote()
        << "INGE_EXTERNAL_ACTIVITY_RENDER_RESTORED exposed="
        << window->isExposed();
}

void InGeGraphicsCore::inspectRuntime(QQuickWindow *window)
{
    if (m_runtimeInspectionStarted.exchange(true))
        return;

    const auto snapshot = InGeGraphicsDiagnostics::inspect(window);
    InGeGraphicsDiagnostics::logOnce(snapshot);
    QMetaObject::invokeMethod(
        this,
        [this, snapshot]() {
            applyRuntimeState(snapshot.graphicsApiName.toUpper(),
                              snapshot.gpuName,
                              snapshot.vulkanAvailable);
        },
        Qt::QueuedConnection);
}

bool InGeGraphicsCore::openEarth()
{
    // QML can deliver creation and activation in the same event turn. Opening
    // the direct Android host is idempotent.
    if (m_earthActive) {
        const bool opened = m_earthHostController
            && m_earthHostController->openEarth(
                QString(), 0.0, 0.0, QString());
        if (opened)
            setQtRenderingSuspended(false);
        return opened;
    }

    // CLOSED is delivered asynchronously after the direct host returns to Qt.
    if (m_earthExitPending)
        m_earthExitPending = false;

    if (!m_earthAvailable) {
        setEarthState(QStringLiteral("EARTH_HOST_PENDING"), false);
        return false;
    }

    if (!m_earthHostController
        || !m_earthHostController->openEarth(
            QString(), 0.0, 0.0, QString())) {
        setEarthState(QStringLiteral("ERROR"), false);
        return false;
    }

    // Earth is above Qt, but its apertures expose the single QML dock.
    // Hiding the Qt window would freeze/remove that dock as well.
    setQtRenderingSuspended(false);
    setEarthState(QStringLiteral("OPENING"), true);
    return true;
}

bool InGeGraphicsCore::focusEarthCoordinate(double latitude, double longitude,
                                             double altitude,
                                             const QString &label)
{
    return m_earthHostController
        && m_earthHostController->focusEarth(latitude, longitude, altitude,
                                             label);
}

void InGeGraphicsCore::closeEarth()
{
    // The page has become inactive. A later explicit entry may open a fresh
    // host, but transient component recreation during exit may not.
    m_earthExitPending = false;
    if (m_earthHostController && m_earthHostController->active())
        m_earthHostController->closeEarth();
    setQtRenderingSuspended(false);
    setEarthState(m_earthAvailable ? QStringLiteral("READY")
                                   : QStringLiteral("UNINITIALIZED"),
                  false);
}

void InGeGraphicsCore::setQtRenderingSuspended(bool suspended)
{
    if (m_qtRenderingSuspended == suspended)
        return;

    QQuickWindow *window = m_window.data();
    if (!window)
        return;

    if (suspended) {
        m_windowWasVisible = window->isVisible();
        m_qtRenderingSuspended = true;
        if (m_windowWasVisible)
            window->hide();
        qInfo().noquote()
            << "INGE_EARTH_QT_RENDER_SUSPENDED windowVisible="
            << window->isVisible();
        return;
    }

    m_qtRenderingSuspended = false;
    if (m_windowWasVisible) {
        window->show();
        window->requestUpdate();
    }
    qInfo().noquote()
        << "INGE_EARTH_QT_RENDER_RESUMED windowVisible="
        << window->isVisible();
}

bool InGeGraphicsCore::setRenderProfile(const QString &profile)
{
    const QString normalized = profile.trimmed().toUpper();
    if (normalized != QStringLiteral("QUALITY")
        && normalized != QStringLiteral("BALANCED")
        && normalized != QStringLiteral("PERFORMANCE")) {
        return false;
    }
    if (m_renderProfile == normalized)
        return true;
    m_renderProfile = normalized;
    emit stateChanged();
    return true;
}

void InGeGraphicsCore::applyRuntimeState(const QString &backend,
                                         const QString &gpuName,
                                         bool vulkanAvailable)
{
    m_graphicsBackend = backend;
    m_gpuName = gpuName;
    m_vulkanAvailable = vulkanAvailable;

    // La disponibilidad de Earth depende del host Android, no del backend
    // elegido por el scene graph Qt. Qt puede usar OpenGL mientras Earth o
    // Flutter usan Vulkan en el mismo dispositivo.
    if (!m_earthAvailable) {
        m_earthActive = false;
        m_earthState = QStringLiteral("EARTH_HOST_PENDING");
    } else if (!m_earthActive && m_earthState == QStringLiteral("UNINITIALIZED")) {
        m_earthState = QStringLiteral("READY");
    }

    emit stateChanged();
}

void InGeGraphicsCore::setEarthState(const QString &state, bool active)
{
    if (m_earthState == state && m_earthActive == active)
        return;
    m_earthState = state;
    m_earthActive = active;
    emit stateChanged();
}
