#include "InGeGraphicsCore.h"

#include "InGeEarthHostController.h"
#include "InGeGraphicsDiagnostics.h"

#include <QDebug>
#include <QGuiApplication>
#include <QMetaObject>
#include <QQuickWindow>
#include <QTimer>

InGeGraphicsCore::InGeGraphicsCore(QObject *parent)
    : QObject(parent)
{
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
    }
    emit stateChanged();
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
