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
#include <QtQuick/QSGRendererInterface>

#include "docsops.h"
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
#include "src/cpp/renditionrepository.h"
#include "src/cpp/renditionlocalstore.h"
#include "src/cpp/renditionsynccontroller.h"
#include "src/cpp/renditionflutterbridge.h"
#include "src/cpp/renditionexportservice.h"
#include "src/graphics/InGeGraphicsCore.h"
#include "src/core/StartupInstrumentation.h"
#include "src/core/RemoteExecutor.h"
#include "src/core/GeminiAssistant.h"

Q_LOGGING_CATEGORY(lcNet, "inge.net")


#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>

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

    QGuiApplication app(argc, argv);

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
    InGeGraphicsCore graphicsCore(&app);
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
    // Servicios expuestos a QML para la futura interfaz; los tipos de dominio
    // (CalicataDocument, DocsOps, NothingDocuments) se registran desde el
    // modulo QML real InGe.Mobile mediante QML_ELEMENT.

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
        [&graphicsCore, &startup, &coreRemote](QObject *object, const QUrl &) {
            // Ventana raiz minima (sin interfaz): primer fotograma = arranque listo.
            if (auto *window = qobject_cast<QQuickWindow *>(object)) {
                graphicsCore.attachWindow(window);
                QObject::connect(window, &QQuickWindow::frameSwapped, window,
                    [&startup, &coreRemote]() { startup.mark(StartupEvent::FIRST_UI); coreRemote.start(); },
                    static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::SingleShotConnection));
            }
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
    engine.rootContext()->setContextProperty("excelExporter", &excelExporter);
    engine.rootContext()->setContextProperty("dropbox", &dropboxBridge);
    engine.rootContext()->setContextProperty("docsOps", &docsOps);

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
