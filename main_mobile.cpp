#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtQml/qqml.h>
#include <QtQml>
#include <QSslSocket>
#include <QLoggingCategory>
#include <QCoreApplication>
#include <QUrl>
#include <QFile>
#include <QLocationPermission>
#include <QPermission>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>
#include <QtQuick/QSGRendererInterface>

#include "docsops.h"
#include "appcontext.h"
#include "authsession.h"
#include "betadiagnostics.h"
#include "permissionhelper.h"
#include "src/fusionbridge/FusionBridgeController.h"
#include "docscontroller.h"
#include "calicatadocument.h"
#include "calicatacloudservice.h"
#include "fsutil.h"
#include "androidcalicataexporter.h"
#include "dropboxbridge.h"
#include "flowhaptics.h"
#include "src/dock/DockContextController.h"
#include "src/dock/DockCommandRouter.h"
#include <QPointer>
#include <QElapsedTimer>
#include <QVariant>
#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#endif
#include "src/cpp/renditionrepository.h"
#include "src/cpp/renditionlocalstore.h"
#include "src/cpp/renditionsynccontroller.h"
#include "src/cpp/renditionflutterbridge.h"
#include "src/cpp/renditionexportservice.h"
#include "src/graphics/InGeGraphicsCore.h"
#include "src/core/StartupInstrumentation.h"
#include "src/core/RemoteExecutor.h"
#include "src/core/GeminiAssistant.h"
#include "src/core/OnboardingState.h"

Q_LOGGING_CATEGORY(lcNet, "inge.net")


#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>

namespace {
// Back de Android sin consumir: Qt (QGuiApplicationPrivate::processKeyEvent)
// envía un cierre espontáneo a la ventana; al ser la última, la aplicación
// termina (main() retorna 0 -> Activity.finish() -> desmontaje con fallos
// nativos). El guardián convierte ese cierre en la navegación única de
// Main.qml (handleSystemBack) y, en la raíz, envía la tarea al fondo.
// No intercepta un cierre legítimo (Activity terminando o destruida).
class BackNavigationGuard final : public QObject
{
public:
    using QObject::QObject;

    void attach(QObject *root)
    {
        auto *window = qobject_cast<QQuickWindow *>(root);
        if (!window)
            return;
        if (m_window)
            m_window->removeEventFilter(this);
        m_window = window;
        m_root = root;
        window->installEventFilter(this);
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() != QEvent::Close || !event->spontaneous() || watched != m_window)
            return QObject::eventFilter(watched, event);
        if (activityFinishing())
            return QObject::eventFilter(watched, event);
        event->ignore();
        handleBack("close");
        return true;
    }

public:
    // Única entrada nativa: cierre de ventana de Qt o callback de Android.
    // Una pulsación que llega por ambas rutas se procesa una sola vez.
    void handleBack(const char *source)
    {
        if (m_lastBack.isValid() && m_lastBack.elapsed() < 300) {
            qInfo() << "INGE_NAV_BACK_SOURCE" << source << "ignored=duplicate";
            return;
        }
        m_lastBack.start();
        QVariant handled = false;
        if (m_root)
            QMetaObject::invokeMethod(m_root, "handleSystemBack", Q_RETURN_ARG(QVariant, handled));
        if (handled.toBool()) {
            qInfo() << "INGE_NAV_BACK_SOURCE" << source << "handled=qml";
            return;
        }
        qInfo() << "INGE_NAV_BACK_SOURCE" << source << "handled=background";
        moveTaskToBack();
    }

private:
    static bool activityFinishing()
    {
#ifdef Q_OS_ANDROID
        const jboolean finishing = QJniObject::callStaticMethod<jboolean>(
            "com/ingema/ingeplus/InGeQtActivity", "isAppFinishing", "()Z");
        QJniEnvironment env;
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            return true;
        }
        return finishing;
#else
        return true;
#endif
    }

    static void moveTaskToBack()
    {
#ifdef Q_OS_ANDROID
        QJniObject::callStaticMethod<void>(
            "com/ingema/ingeplus/InGeQtActivity", "moveAppToBackground", "()V");
        QJniEnvironment env;
        if (env->ExceptionCheck())
            env->ExceptionClear();
#endif
    }

    QPointer<QQuickWindow> m_window;
    QPointer<QObject> m_root;
    QElapsedTimer m_lastBack;
};
QPointer<BackNavigationGuard> g_backGuard;
} // namespace

#ifdef Q_OS_ANDROID
// InGeQtActivity.dispatchInGeBack (hilo de UI de Android): se encola al hilo de Qt.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeBackPressed(JNIEnv *, jclass)
{
    BackNavigationGuard *guard = g_backGuard.data();
    if (!guard)
        return JNI_FALSE;
    QMetaObject::invokeMethod(guard, [guard]() { guard->handleBack("activity"); }, Qt::QueuedConnection);
    return JNI_TRUE;
}
#endif

int main(int argc, char *argv[])
{
    // Native main entry is the process timing baseline (not Android JVM launch).
    inge::core::StartupInstrumentation startup;
    using StartupEvent = inge::core::StartupInstrumentation::Event;
#ifdef Q_OS_ANDROID
    qputenv("ANDROID_OPENSSL_SUFFIX", "_3");
#endif
    qputenv("QT_NETWORK_DISABLE_HTTP2", "1");

#ifdef Q_OS_ANDROID
    // P0 background: en Android priorizamos OpenGL ES para el scene graph Qt.
    // Evita QueuePresentKHR sobre una ANativeWindow ya destruida y mantiene
    // un backend estable para el host Qt mientras InGe Earth usa Cesium.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
#else
    // Let Qt select the supported native Desktop backend (D3D11 on Windows).
#endif

    // Editor original de Calicatas (Qt Quick Controls): estilo Basic, como antes.
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Basic");

    QCoreApplication::setOrganizationName("InGePlus");
    QCoreApplication::setOrganizationDomain("ingeplus.app");
    QCoreApplication::setApplicationName("InGePlusMobile");
    QCoreApplication::setApplicationVersion("1.1.13");

    qInfo() << "INGE_STARTUP_STAGE QT_APP_READY";
    // Antes que AuthSession y los demás servicios: la migración de instalaciones
    // anteriores distingue una instalación nueva por los datos que estos crean.
    OnboardingState onboarding;
    PermissionHelper perms;
    FusionBridgeController fusionBridge;
    FsUtil fs;
    // Auth subsystem initialization -> first completed authentication decision.
    startup.mark(StartupEvent::AUTH_START);
    auto* ctx = new AppContext(&app);
    const auto authReady = [&startup]() { startup.mark(StartupEvent::AUTH_READY); };
    QObject::connect(ctx->auth(), &AuthSession::loginOk, &app, authReady);
    QObject::connect(ctx->auth(), &AuthSession::loginFail, &app, authReady);
    QObject::connect(ctx->auth(), &AuthSession::autoLoginFinished, &app, authReady);
    AppContext::setInstance(ctx);
    inge::core::RemoteExecutor coreRemote(ctx->supabase(), ctx->auth(), &app);
    inge::core::GeminiAssistant geminiAssistant(ctx->supabase(), ctx->auth(), &coreRemote);
    new BetaDiagnostics(ctx->supabase(), ctx->auth(), &app);
    auto* renditions = new RenditionRepository(&app);
    auto* renditionLocalStore = new RenditionLocalStore(ctx->auth(), &app);
    auto* renditionSyncController = new RenditionSyncController(
        renditionLocalStore, renditions, &app);
    AndroidCalicataExporter excelExporter(&app);
    CalicataCloudService calicataCloud(&app);
    // Resume the durable export queue after process recreation; network work
    // remains deferred until its timer and a valid account are available.
    RenditionExportService::shared(ctx->supabase(), ctx->auth());
    auto *renditionFlutterBridge = new RenditionFlutterBridge(renditions, renditionLocalStore,
                               renditionSyncController, &excelExporter, &app);

    DropboxBridge dropboxBridge(&app);
    DocsOps docsOps(&app);
    InGeGraphicsCore graphicsCore(&app);
    FlowHaptics flowHaptics(&app);
    // Dock contextual: controladores originales; canal "qml" (sin vista nativa).
    DockContextController dockContextController(&app);
    DockCommandRouter dockCommandRouter(&dockContextController, &app);
    // Sesión: la gracia de 60 s la decide OnboardingState (única autoridad).
    QObject::connect(&app, &QGuiApplication::applicationStateChanged, &onboarding,
                     [&onboarding](Qt::ApplicationState state) { onboarding.handleApplicationState(state); });
    QObject::connect(&perms, &PermissionHelper::externalPhotoActivityStarted, &onboarding,
                     [&onboarding]() { onboarding.setExternalActivity(true); });
    QObject::connect(&perms, &PermissionHelper::externalPhotoActivityFinished, &onboarding,
                     [&onboarding]() { onboarding.setExternalActivity(false); });
    QObject::connect(&perms, &PermissionHelper::externalPhotoActivityStarted,
                     &graphicsCore, &InGeGraphicsCore::prepareForExternalActivity);
    QObject::connect(&perms, &PermissionHelper::externalPhotoActivityFinished,
                     &graphicsCore, &InGeGraphicsCore::completeExternalActivity);
    qmlRegisterSingletonInstance("InGe", 1, 0, "FS", &fs);
    qmlRegisterSingletonType<DocsController>("InGe", 1, 0, "Docs",
        [](QQmlEngine *qmlEngine, QJSEngine *) -> QObject * {
            return new DocsController(qmlEngine);
        });
    qmlRegisterSingletonInstance("InGe", 1, 0, "AppCtx", ctx);
    qmlRegisterSingletonInstance("InGe", 1, 0, "Auth", ctx->auth());
    qmlRegisterSingletonInstance("InGe", 1, 0, "ExcelExporter", &excelExporter);
    qmlRegisterSingletonInstance("InGe", 1, 0, "CalicataCloud", &calicataCloud);
    qmlRegisterSingletonInstance("InGe", 1, 0, "Dropbox", &dropboxBridge);
    qmlRegisterSingletonInstance("InGe", 1, 0, "GraphicsCore", &graphicsCore);
    qmlRegisterSingletonInstance("InGe", 1, 0, "FlowHaptics", &flowHaptics);
    // Editor original de Calicatas: motor global único InGe.CoreFlow 3.0.
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/InGeCoreFlow.qml")),
        "InGe.CoreFlow", 3, 0, "InGeCoreFlow");
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/FlowIcons.qml")),
        "InGe.CoreFlow", 3, 0, "FlowIcons");
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/InGeIconLibrary.qml")),
        "InGe.CoreFlow", 3, 0, "InGeIconLibrary");
    // Servicios expuestos a QML para la futura interfaz; los tipos de dominio
    // (CalicataDocument, DocsOps, NothingDocuments) se registran desde el
    // modulo QML real InGe.Mobile mediante QML_ELEMENT.

    qCDebug(lcNet) << "[InGe+ V122] SSL supportsSsl=" << QSslSocket::supportsSsl()
                   << "build=" << QSslSocket::sslLibraryBuildVersionString()
                   << "runtime=" << QSslSocket::sslLibraryVersionString();

    qInfo() << "INGE_STARTUP_STAGE SERVICES_READY";
    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("fusionbridge"), fusionBridge.createImageProvider());
    {
        class IdentifiedNetworkAccessManager final : public QNetworkAccessManager
        {
        public:
            using QNetworkAccessManager::QNetworkAccessManager;
        protected:
            QNetworkReply *createRequest(Operation op, const QNetworkRequest &request,
                                         QIODevice *data) override
            {
                QNetworkRequest identified(request);
                identified.setHeader(QNetworkRequest::UserAgentHeader,
                                     QStringLiteral("InGePlus-Android/1.0 (Ingema Consultores; com.ingema.ingeplus)"));
                return QNetworkAccessManager::createRequest(op, identified, data);
            }
        };
        class IdentifiedNetworkFactory final : public QQmlNetworkAccessManagerFactory
        {
        public:
            QNetworkAccessManager *create(QObject *parent) override
            {
                return new IdentifiedNetworkAccessManager(parent);
            }
        };
        static IdentifiedNetworkFactory identifiedNetworkFactory;
        engine.setNetworkAccessManagerFactory(&identifiedNetworkFactory);
    }
    // Al pasar a segundo plano (camara del OEM, otra app) Android decide que
    // proceso matar por su memoria. Qt bloquea su bucle poco despues de
    // ApplicationSuspended: liberar aqui los componentes QML sin uso y el
    // heap JS. No toca el scene graph ni los datos de la app.
    QObject::connect(&app, &QGuiApplication::applicationStateChanged, &engine,
                     [&engine](Qt::ApplicationState state) {
        if (state != Qt::ApplicationSuspended)
            return;
        engine.trimComponentCache();
        engine.collectGarbage();
        qInfo() << "INGE_QML_MEMORY_TRIMMED reason=suspended";
    });

#ifdef Q_OS_ANDROID
    auto *backGuard = new BackNavigationGuard(&app);
    g_backGuard = backGuard;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
                     [backGuard](QObject *object, const QUrl &) {
        if (object)
            backGuard->attach(object);
    });
#endif
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &graphicsCore,
        [&graphicsCore, &startup, &coreRemote, &app](QObject *object, const QUrl &) {
            if (!object)
                return;
            // Visual Zero no presenta fotogramas; no bloquear el motor remoto
            // esperando frameSwapped en una ventana intencionadamente vacia.
            if (auto *window = qobject_cast<QQuickWindow *>(object))
                graphicsCore.attachWindow(window);
            QTimer::singleShot(0, &app, [&startup, &coreRemote]() {
                startup.mark(StartupEvent::FIRST_UI); // hito de arranque compatible
                coreRemote.start();
            });
        });

    engine.rootContext()->setContextProperty("CoreRemote", &coreRemote);
    engine.rootContext()->setContextProperty("InGeAssistant", &geminiAssistant);
    renditionFlutterBridge->setCoreRemote(&coreRemote);
    engine.rootContext()->setContextProperty("FS", &fs);
    engine.rootContext()->setContextProperty("Perms", &perms);
    engine.rootContext()->setContextProperty("FusionBridge", &fusionBridge);
    engine.rootContext()->setContextProperty("appCtx", ctx);
    engine.rootContext()->setContextProperty("auth", static_cast<QObject*>(ctx->auth()));
    engine.rootContext()->setContextProperty("onboarding", &onboarding);
    engine.rootContext()->setContextProperty("renditions", renditions);
    engine.rootContext()->setContextProperty("renditionLocalStore", renditionLocalStore);
    engine.rootContext()->setContextProperty("renditionSyncController", renditionSyncController);
    engine.rootContext()->setContextProperty("renditionFlutterBridge", renditionFlutterBridge);
    engine.rootContext()->setContextProperty("excelExporter", &excelExporter);
    engine.rootContext()->setContextProperty("dropbox", &dropboxBridge);
    engine.rootContext()->setContextProperty("docsOps", &docsOps);
    engine.rootContext()->setContextProperty("dockContextController", &dockContextController);
    engine.rootContext()->setContextProperty("dockCommandRouter", &dockCommandRouter);

    QObject::connect(&engine, &QQmlEngine::warnings, [](const QList<QQmlError>& ws){
        for (const auto& w : ws)
            qWarning().noquote() << "[InGe+ V122 QML]" << w.toString();
    });

    // V35.2: InGe.Mobile remains packaged only once by qt_add_qml_module().
    // Main.qml is the application entry point, not a reusable QML type.
    // Loading the exact compiled resource avoids qmldir type lookup and keeps
    // the single-module architecture introduced in V35.1.
    const QUrl mainUrl(QStringLiteral("qrc:/InGe/Mobile/Main.qml"));
    qWarning().noquote() << "[InGe+ V122] Cargando entrada QML:" << mainUrl.toString();

    if (!QFile::exists(QStringLiteral(":/InGe/Mobile/Main.qml"))) {
        qCritical().noquote()
            << "[InGe+ V122] Recurso principal ausente: :/InGe/Mobile/Main.qml";
    } else {
        qInfo() << "INGE_STARTUP_STAGE QML_LOAD_BEGIN";
        engine.load(mainUrl);
        qInfo() << "INGE_STARTUP_STAGE QML_LOAD_END";
    }

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "INGE_STARTUP_FATAL Main.qml could not be created";
        return -1;
    }

    return app.exec();
}
