#include "RetroplasmaController.h"
#include <QGuiApplication>
#include <QAbstractListModel>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QDateTime>
#include <QElapsedTimer>
#include <QThread>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QFile>
#include <QtQml/qqmlextensionplugin.h>
#include <iostream>
#include <memory>
Q_IMPORT_QML_PLUGIN(InGeRetroplasmaPlugin)
// Document service boundary only: validates the adapter's QML construction and
// navigation dispatch without network credentials or modifying production Drive.
class DocumentFixture : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString rootPath MEMBER rootPath NOTIFY changed)
    Q_PROPERTY(QString folder MEMBER folder NOTIFY changed)
    Q_PROPERTY(QString route MEMBER route NOTIFY changed)
    Q_PROPERTY(QString error MEMBER error NOTIFY changed)
    Q_PROPERTY(QString uploadTargetLabel MEMBER uploadTargetLabel NOTIFY changed)
    Q_PROPERTY(QString location READ location NOTIFY changed)
    Q_PROPERTY(bool moreRemote MEMBER moreRemote NOTIFY changed)
public:
    QString rootPath=QStringLiteral("."),folder=QStringLiteral("."),route=QStringLiteral("home"),error,uploadTargetLabel;bool moreRemote=false;
    bool busy()const{return false;}
    QString location()const{return route+":"+folder;}
    int rowCount(const QModelIndex &p={})const override{return p.isValid()?0:0;}
    QVariant data(const QModelIndex &,int)const override{return {};}
    QHash<int,QByteArray> roleNames()const override{return {{Qt::UserRole+1,"entry"}};}
    Q_INVOKABLE QString breadcrumb()const{return folder;}
    Q_INVOKABLE void navigate(QString r,QString path={}){route=r;if(r=="files")folder=path;emit changed();}
    Q_INVOKABLE bool back(){return false;}
    Q_INVOKABLE void refresh(){}
    Q_INVOKABLE void loadMore(){}
    Q_INVOKABLE void download(QVariantMap){}
    Q_INVOKABLE void upload(QString,QString,QString){}
    Q_INVOKABLE void open(QVariantMap,bool,bool){}
signals:
    void changed();void completed(QString message,QString path);
};
int main(int argc,char **argv){
    QGuiApplication app(argc,argv);qmlRegisterType<DocumentFixture>("InGe.Mobile",1,0,"NothingDocuments");RetroplasmaController controller;QQmlEngine engine;
    // The shared GPS service is represented only at its QObject boundary; no GPS is started.
    QQmlComponent permissions(&engine);permissions.setData(R"(
        import QtQml
        QtObject {
            property bool nativeTracking: false
            property bool nativePermissionGranted: true
            property bool nativeHasFix: false
            property double nativeTimestampMs: 0
            property double nativeLatitude: 0
            property double nativeLongitude: 0
            property double nativeAltitude: 0
            property double nativeAccuracy: 0
            property string nativeLocationError: ""
            signal nativePermissionChanged()
            signal nativeLocationChanged()
            function hasLocationPermission() { return nativePermissionGranted }
            function requestLocationPermission() {}
            function requestImmediateLocationUpdate() { nativeTracking = true; return true }
            function stopNativeLocationUpdates() { nativeTracking = false }
        })",QUrl());
    std::unique_ptr<QObject> service(permissions.create());if(!service){std::cerr<<"GPS QObject fixture failed\n";return 1;}
    engine.rootContext()->setContextProperty("Perms",service.get());
    QQmlComponent viewport(&engine,QUrl::fromLocalFile(QStringLiteral(RP_VIEW_SOURCE)));
    std::unique_ptr<QObject> view(viewport.createWithInitialProperties({{"controller",QVariant::fromValue(&controller)},{"width",360},{"height",780}}));
    if(!view){for(const auto &error:viewport.errors())std::cerr<<error.toString().toStdString()<<'\n';return 1;}
    if(view->metaObject()->indexOfMethod("handleBack()")<0||!view->property("safeTop").isValid()){std::cerr<<"fullscreen Earth safe area / Back interface missing\n";return 1;}
    auto *native=view->findChild<QQuickItem *>(QStringLiteral("earthFullViewport"));if(!native||native->width()!=360||native->height()!=780){std::cerr<<"native globe fails to fill Earth viewport\n";return 1;}
    controller.open();QElapsedTimer deadline;deadline.start();while(!controller.ready()&&deadline.elapsed()<3000){QCoreApplication::processEvents();QThread::msleep(1);}
    if(!controller.ready()){std::cerr<<"default world scene not ready\n";return 1;}
    QTemporaryDir documents;QString input=documents.path()+"/lima.kml";QFile file(input);file.open(QIODevice::WriteOnly);file.write("<kml><Placemark><name>Lima</name><Point><coordinates>-77,-12,0</coordinates></Point></Placemark></kml>");file.close();
    if(!controller.importDocument(input)||controller.geoLayers().size()!=1){std::cerr<<"controller import failed\n";return 1;}
    QString complexPath=documents.path()+"/complex.kml";QFile complexity(complexPath);complexity.open(QIODevice::WriteOnly);complexity.write("<kml>");
    for(int i=0;i<100;++i){complexity.write("<Placemark><LineString><coordinates>");for(int j=0;j<35;++j)complexity.write(j%2?"2,0 ":"0,0 ");complexity.write("</coordinates></LineString></Placemark>");}complexity.write("</kml>");complexity.close();
    if(controller.importDocument(complexPath)||controller.geoLayers().size()!=1){std::cerr<<"excessive tessellation not rejected before render work\n";return 1;}
    auto id=controller.geoLayers()[0].toMap().value("id").toString();
    bool nativeGeometry=false;for(auto &tile:controller.renderTiles())nativeGeometry|=tile.key.startsWith("geo:");if(!nativeGeometry){std::cerr<<"KML layer not connected to native renderer\n";return 1;}
    controller.setLayerVisible(id,false);for(auto &tile:controller.renderTiles())if(tile.key.startsWith("geo:")){std::cerr<<"hidden layer still rendered\n";return 1;}
    controller.setLayerVisible(id,true);if(controller.exportDocument(documents.path(),"earth",true).isEmpty()){std::cerr<<"controller KMZ export failed\n";return 1;}
    view->setProperty("sheet","places");QCoreApplication::processEvents();QVariant back;QMetaObject::invokeMethod(view.get(),"handleBack",Q_RETURN_ARG(QVariant,back));
    if(!back.toBool()||!view->property("sheet").toString().isEmpty()){std::cerr<<"Back fails to close Earth sheet\n";return 1;}
    view->setProperty("sheet","files");deadline.restart();while(!view->findChild<DocumentFixture *>()&&deadline.elapsed()<3000){QCoreApplication::processEvents();QThread::msleep(1);}
    if(!view->findChild<DocumentFixture *>()){std::cerr<<"Earth document adapter not constructed; sheet="<<view->property("sheet").toString().toStdString()<<" initialized="<<view->property("filesInitialized").toBool()<<'\n';for(auto *o:view->findChildren<QObject *>())if(o->property("source").isValid())std::cerr<<o->metaObject()->className()<<" source="<<o->property("source").toString().toStdString()<<" active="<<o->property("active").toBool()<<" status="<<o->property("status").toInt()<<'\n';return 1;}
    view->setProperty("sheet","");controller.clearGeoLayers();if(!controller.geoLayers().empty()){std::cerr<<"account geography not cleared\n";return 1;}
    auto publishFix=[&](){service->setProperty("nativeHasFix",true);service->setProperty("nativeLatitude",-12.0464);service->setProperty("nativeLongitude",-77.0428);service->setProperty("nativeAltitude",153.0);service->setProperty("nativeTimestampMs",double(QDateTime::currentMSecsSinceEpoch()));QMetaObject::invokeMethod(service.get(),"nativeLocationChanged");QCoreApplication::processEvents();QCoreApplication::processEvents();};
    QMetaObject::invokeMethod(view.get(),"requestGps");publishFix();
    if(view->property("gpsRequested").toBool()||service->property("nativeTracking").toBool()){std::cerr<<"temporary Earth GPS tracking not released after fix\n";return 1;}
    service->setProperty("nativeTracking",true);QMetaObject::invokeMethod(view.get(),"requestGps");publishFix();
    if(!service->property("nativeTracking").toBool()){std::cerr<<"Earth stopped another client's GPS tracking\n";return 1;}
    std::cout<<"PLANET QML VIEW PASS: native registered type, controls, gesture signals and shared GPS boundary load\n";
    if(qEnvironmentVariableIsSet("RP_EARTH_CAPTURE")){
        controller.command("reset");
        QQuickWindow window;window.resize(360,780);qobject_cast<QQuickItem *>(view.get())->setParentItem(window.contentItem());window.show();
        deadline.restart();while(deadline.elapsed()<2500){QCoreApplication::processEvents();QThread::msleep(10);}
        auto shot=window.grabWindow();if(!shot.save(qEnvironmentVariable("RP_EARTH_CAPTURE"))){std::cerr<<"Host capture unavailable\n";return 1;}
        qobject_cast<QQuickItem *>(view.get())->setParentItem(nullptr);
    }
}
#include "planet_view_tests.moc"
