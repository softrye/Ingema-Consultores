#include "InGeGraphicsCore.h"

#include "InGeGraphicsDiagnostics.h"

#include <QDebug>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>
#include <QQuickWindow>
#include <QSettings>
#include <QSurfaceFormat>
#include <QTimer>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

namespace {
constexpr auto kPerformanceRuntimeClass = "com/ingema/ingeplus/InGePerformanceRuntime";
constexpr auto kFidelityKey = "graphics/fidelityChoice";
QPointer<InGeGraphicsCore> g_graphicsCore;
int g_startupSamples = 0;

bool validQualityChoice(const QString &value)
{
    return value == QLatin1String("AUTO") || value == QLatin1String("LOW") || value == QLatin1String("HIGH")
        || value == QLatin1String("VERY_HIGH") || value == QLatin1String("EXTREME");
}

// EXTREME: MSAA 8 (EGL/RHI reducen a lo que admita el dispositivo); VERY_HIGH: 4.
int samplesForChoice(const QString &choice)
{
    return choice == QLatin1String("EXTREME") ? 8 : choice == QLatin1String("VERY_HIGH") ? 4 : 0;
}
}

void InGeGraphicsCore::applyStartupFidelity()
{
    const QString choice = QSettings().value(QLatin1String(kFidelityKey)).toString();
    g_startupSamples = samplesForChoice(choice);
    if (g_startupSamples > 0) {
        QSurfaceFormat format = QSurfaceFormat::defaultFormat();
        format.setSamples(g_startupSamples);
        QSurfaceFormat::setDefaultFormat(format);
        QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);
    }
    qInfo().noquote() << "INGE_GRAPHICS_FIDELITY_STARTUP choice=" << (choice.isEmpty() ? QStringLiteral("AUTO") : choice)
                      << " msaa=" << g_startupSamples;
}

InGeGraphicsCore::InGeGraphicsCore(QObject *parent)
    : QObject(parent)
{
    g_graphicsCore = this;
    readInitialDeviceState();
    if (qGuiApp) {
        connect(qGuiApp, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
                    if (state == Qt::ApplicationActive) {
                        // Android's surface may still be changing during this signal.
                        // Showing the QQuickWindow here can re-enter Qt's JNI lifecycle.
                        QTimer::singleShot(0, this, [this]() {
                            restoreAfterExternalActivityIfReady();
                        });
                    }
                });
    }
}

QString InGeGraphicsCore::graphicsBackend() const { return m_graphicsBackend; }
QString InGeGraphicsCore::gpuName() const { return m_gpuName; }
bool InGeGraphicsCore::vulkanAvailable() const { return m_vulkanAvailable; }
QString InGeGraphicsCore::deviceTier() const { return m_deviceTier; }
QString InGeGraphicsCore::baseDeviceTier() const { return m_baseDeviceTier; }
bool InGeGraphicsCore::lowRamDevice() const { return m_lowRamDevice; }
int InGeGraphicsCore::totalMemoryMb() const { return m_totalMemoryMb; }
bool InGeGraphicsCore::powerSaveMode() const { return m_powerSaveMode; }
int InGeGraphicsCore::thermalStatus() const { return m_thermalStatus; }
bool InGeGraphicsCore::systemAnimationsEnabled() const { return m_systemAnimationsEnabled; }
qreal InGeGraphicsCore::systemFontScale() const { return m_systemFontScale; }
int InGeGraphicsCore::memoryTrimLevel() const { return m_memoryTrimLevel; }
QString InGeGraphicsCore::qualityOverride() const { return m_qualityOverride; }
QString InGeGraphicsCore::fidelity() const
{
    return m_qualityOverride == QLatin1String("VERY_HIGH") || m_qualityOverride == QLatin1String("EXTREME")
        ? m_qualityOverride : m_deviceTier;
}
bool InGeGraphicsCore::advancedMotion() const
{
    const QString value = fidelity();
    return value == QLatin1String("VERY_HIGH") || value == QLatin1String("EXTREME");
}
bool InGeGraphicsCore::extremeGlass() const { return fidelity() == QLatin1String("EXTREME"); }
int InGeGraphicsCore::textSmoothing() const
{
    const QString value = fidelity();
    return value == QLatin1String("EXTREME") ? 2 : value == QLatin1String("VERY_HIGH") ? 1 : 0;
}
bool InGeGraphicsCore::msaaRestartRequired() const
{
    return samplesForChoice(m_qualityOverride) != g_startupSamples;
}

void InGeGraphicsCore::setQualityOverride(const QString &value)
{
    const QString mode = validQualityChoice(value) ? value : QStringLiteral("AUTO");
    // Persistida también aquí: el MSAA del siguiente arranque se lee antes de la ventana.
    QSettings().setValue(QLatin1String(kFidelityKey), mode);
#ifdef Q_OS_ANDROID
    // The runtime saves the choice, reclassifies and pushes the new state back.
    QJniObject::callStaticMethod<void>(kPerformanceRuntimeClass, "setUserOverride",
                                       "(Ljava/lang/String;)V",
                                       QJniObject::fromString(mode).object<jstring>());
    QJniEnvironment env;
    if (env->ExceptionCheck())
        env->ExceptionClear();
#else
    if (mode == m_qualityOverride)
        return;
    m_qualityOverride = mode;
    emit deviceStateChanged();
#endif
}

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
    const QString qualityOverride = state.value(QStringLiteral("override")).toString(m_qualityOverride);
    if (qualityOverride == m_qualityOverride && tier == m_deviceTier && baseTier == m_baseDeviceTier && lowRam == m_lowRamDevice
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
    m_qualityOverride = qualityOverride;
    qInfo().noquote() << "INGE_DEVICE_PERFORMANCE tier=" << m_deviceTier
                      << " override=" << m_qualityOverride
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

void InGeGraphicsCore::attachWindow(QQuickWindow *window)
{
    if (!window) {
        applyRuntimeState(QStringLiteral("UNAVAILABLE"),
                          QStringLiteral("UNAVAILABLE"), false);
        return;
    }

    m_window = window;
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
    // Defer window restoration until Qt has finished dispatching the return
    // from Android's camera/gallery Activity (no nested state transitions).
    QTimer::singleShot(0, this, [this]() {
        restoreAfterExternalActivityIfReady();
    });
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

void InGeGraphicsCore::applyRuntimeState(const QString &backend,
                                         const QString &gpuName,
                                         bool vulkanAvailable)
{
    m_graphicsBackend = backend;
    m_gpuName = gpuName;
    m_vulkanAvailable = vulkanAvailable;
    emit stateChanged();
}
