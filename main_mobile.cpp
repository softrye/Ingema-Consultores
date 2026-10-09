#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
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
#include <QFontDatabase>
#include <QtQuick/QSGRendererInterface>

#include "docsops.h"
#include "src/documents/nothingvideoprovider.h"
#include "appcontext.h"
#include "authsession.h"
#include "betadiagnostics.h"
#include "permissionhelper.h"
#include "docscontroller.h"
#include "calicatadocument.h"
#include "calicatacloudservice.h"
#include "fsutil.h"
#include "androidcalicataexporter.h"
#include "dropboxbridge.h"
#include "firstexperiencecontroller.h"
#include "ingenarrator.h"
#include "ingeexperienceaudio.h"
#include "flowhaptics.h"
#include "mapworkspacecontroller.h"
#include "src/cpp/renditionrepository.h"
#include "src/cpp/renditionlocalstore.h"
#include "src/cpp/renditionsynccontroller.h"
#include "src/cpp/renditionflutterbridge.h"
#include "src/cpp/renditionexportservice.h"
#include "src/graphics/InGeGraphicsCore.h"
#include "src/graphics/InGeEarthHostController.h"
#include "src/dock/DockContextController.h"
#include "src/dock/DockCommandRouter.h"
#include "src/core/StartupInstrumentation.h"
#include "src/core/RemoteExecutor.h"
#include "src/core/GeminiAssistant.h"

Q_LOGGING_CATEGORY(lcNet, "inge.net")


#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QPointer>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>
static QPointer<QObject> globalBackRoot;

extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeRequestGlobalBack(JNIEnv *, jclass)
{
    // No blocking Android/Qt cross-thread invocation: QML decides on its thread.
    QMetaObject::invokeMethod(qApp, []() {
        if (!globalBackRoot) {
            qCritical() << "INGE_BACK_ROUTER_UNAVAILABLE";
            return;
        }
        QVariant decision;
        if (!QMetaObject::invokeMethod(globalBackRoot, "routeAndroidBack",
                                      Q_RETURN_ARG(QVariant, decision))) {
            qCritical() << "INGE_BACK_ROUTER_INVOKE_FAILED";
            return;
        }
        const QJniObject action = QJniObject::fromString(decision.toString());
        QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity",
                "completeGlobalBack", "(Ljava/lang/String;)V", action.object<jstring>());
    }, Qt::QueuedConnection);
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
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

#ifdef Q_OS_ANDROID
    // P0 background: en Android priorizamos OpenGL ES para el scene graph Qt.
    // Evita QueuePresentKHR sobre una ANativeWindow ya destruida y mantiene
    // un backend estable para el host Qt mientras InGe Earth usa Cesium.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
#else
    // Let Qt select the supported native Desktop backend (D3D11 on Windows).
#endif
    QQuickStyle::setStyle("Basic");

    QGuiApplication app(argc, argv);

    // Tipografia corporativa INGEMA (Manual Corporativo Ingema 2025): Rubik
    // Light/Regular/SemiBold. Se registra antes de crear el motor QML para que
    // todo Text sin familia explicita herede Rubik. FreeType agrupa los tres
    // archivos bajo la familia tipografica "Rubik" (pesos 300/400/600).
    {
        QString rubikFamily;
        const char *const rubikWeights[] = { "Light", "Regular", "SemiBold" };
        for (const char *weight : rubikWeights) {
            const QString path = QStringLiteral(":/ui/v2/fonts/rubik/Rubik-%1.ttf")
                                     .arg(QLatin1String(weight));
            const int fontId = QFontDatabase::addApplicationFont(path);
            if (fontId < 0) {
                qWarning() << "INGE_BRAND_FONT_MISSING" << path;
                continue;
            }
            const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
            if (rubikFamily.isEmpty() || qstrcmp(weight, "Regular") == 0)
                rubikFamily = families.value(0, rubikFamily);
        }
        if (!rubikFamily.isEmpty()) {
            QFont brandFont = QGuiApplication::font();
            brandFont.setFamily(rubikFamily);
            QGuiApplication::setFont(brandFont);
            qInfo() << "INGE_BRAND_FONT_READY" << rubikFamily;
        }
    }

// Los permisos se solicitan de forma contextual desde Mapa/Cámara,
// después de que la Primera Experiencia explique su propósito.



    QCoreApplication::setOrganizationName("InGePlus");
    QCoreApplication::setOrganizationDomain("ingeplus.app");
    QCoreApplication::setApplicationName("InGePlusMobile");
    QCoreApplication::setApplicationVersion("1.1.13");

    qInfo() << "INGE_STARTUP_STAGE QT_APP_READY";
    PermissionHelper perms;
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
    FirstExperienceController firstExperience(&app);
    // INGE_PERF_120HZ_V1: mobile startup stays silent; no eager TTS/SFX decoders.
    FlowHaptics flowHaptics(&app);
    InGeEarthHostController earthHost(&app);
    InGeGraphicsCore graphicsCore(&app);
    graphicsCore.setEarthHostController(&earthHost);
    // One host-owned dock context and one command router for every surface.
    DockContextController dockContextController(&app);
    DockCommandRouter dockCommandRouter(&dockContextController, &app);
    // The dedicated assistant shares Auth and the global remote owner.
    const auto updateAssistantAvailability = [&]() {
        dockContextController.setIngeCoreAvailable(geminiAssistant.available());
    };
    QObject::connect(&dockContextController, &DockContextController::contextChanged,
                     &app, updateAssistantAvailability);
    QObject::connect(&geminiAssistant, &inge::core::GeminiAssistant::availableChanged,
                     &app, updateAssistantAvailability);
    QObject::connect(&dockCommandRouter, &DockCommandRouter::globalCapabilityRequested,
                     &geminiAssistant, [&geminiAssistant](const QString &capability) {
        if (capability == QStringLiteral("inge.core")) emit geminiAssistant.openingRequested();
    });
    updateAssistantAvailability();
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
    qmlRegisterSingletonInstance("InGe", 1, 0, "FlowHaptics", &flowHaptics);
    qmlRegisterSingletonInstance("InGe", 1, 0, "GraphicsCore", &graphicsCore);
    qmlRegisterSingletonInstance("InGe.Experience", 1, 0, "FirstExperience", &firstExperience);
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/InGeCoreFlow.qml")),
        "InGe.CoreFlow", 3, 0, "InGeCoreFlow");
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/FlowIcons.qml")),
        "InGe.CoreFlow", 3, 0, "FlowIcons");
    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/InGeIconLibrary.qml")),
        "InGe.CoreFlow", 3, 0, "InGeIconLibrary");

    // desde el modulo QML real InGe.Mobile mediante QML_ELEMENT.
    // No usar submodulos dinamicos InGe.Docs / InGe.Calicata.

    qCDebug(lcNet) << "[InGe+ V122] SSL supportsSsl=" << QSslSocket::supportsSsl()
                   << "build=" << QSslSocket::sslLibraryBuildVersionString()
                   << "runtime=" << QSslSocket::sslLibraryVersionString();

    qInfo() << "INGE_STARTUP_STAGE SERVICES_READY";
    QQmlApplicationEngine engine;
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
    engine.addImageProvider("nothingvideo",new NothingVideoProvider);
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

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &graphicsCore,
        [&graphicsCore, &earthHost, &startup, &coreRemote](QObject *object, const QUrl &) {
            if (auto *window = qobject_cast<QQuickWindow *>(object)) {
                graphicsCore.attachWindow(window);
                QObject::connect(window, &QQuickWindow::frameSwapped, window,
                    [&startup, &coreRemote]() { startup.mark(StartupEvent::FIRST_UI); coreRemote.start(); },
                    static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::SingleShotConnection));
            }
            if (!object)
                return;
            // Existing flag becomes true only after Flutter reports Home ready.
            if (!startup.watchReadyProperty(object, "flutterHomeActiveV60", StartupEvent::HOME_READY))
                qWarning() << "INGE_STARTUP HOME_READY observer unavailable";
            QObject::connect(
                &earthHost,
                &InGeEarthHostController::coordinateForCalicata,
                object,
                [object](double latitude, double longitude, double altitude,
                         double accuracy, const QString &timestamp,
                         const QString &source) {
                    QMetaObject::invokeMethod(
                        object, "useEarthPointInCalicataM0809",
                        Q_ARG(QVariant, latitude),
                        Q_ARG(QVariant, longitude),
                        Q_ARG(QVariant, altitude),
                        Q_ARG(QVariant, accuracy),
                        Q_ARG(QVariant, timestamp),
                        Q_ARG(QVariant, source));
                });
        });

    engine.rootContext()->setContextProperty("CoreRemote", &coreRemote);
    engine.rootContext()->setContextProperty("InGeAssistant", &geminiAssistant);
    renditionFlutterBridge->setCoreRemote(&coreRemote);
    engine.rootContext()->setContextProperty("FS", &fs);
    engine.rootContext()->setContextProperty("Perms", &perms);
    engine.rootContext()->setContextProperty("appCtx", ctx);
    engine.rootContext()->setContextProperty("auth", static_cast<QObject*>(ctx->auth()));
    engine.rootContext()->setContextProperty("renditions", renditions);
    engine.rootContext()->setContextProperty("renditionLocalStore", renditionLocalStore);
    engine.rootContext()->setContextProperty("renditionSyncController", renditionSyncController);
    engine.rootContext()->setContextProperty("renditionFlutterBridge", renditionFlutterBridge);
    engine.rootContext()->setContextProperty("dockContextController", &dockContextController);
    engine.rootContext()->setContextProperty("dockCommandRouter", &dockCommandRouter);
    engine.rootContext()->setContextProperty("excelExporter", &excelExporter);
    engine.rootContext()->setContextProperty("dropbox", &dropboxBridge);
    engine.rootContext()->setContextProperty("docsOps", &docsOps);
    engine.rootContext()->setContextProperty("firstExperience", &firstExperience);
    engine.rootContext()->setContextProperty("narrator", static_cast<QObject*>(nullptr));
    engine.rootContext()->setContextProperty("experienceAudio", static_cast<QObject*>(nullptr));

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

#ifdef Q_OS_ANDROID
    globalBackRoot = engine.rootObjects().constFirst();
#endif
    return app.exec();
}
