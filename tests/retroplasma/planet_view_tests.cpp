#include "RetroplasmaController.h"
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QDateTime>
#include <QElapsedTimer>
#include <QThread>
#include <QtQml/qqmlextensionplugin.h>
#include <iostream>
#include <memory>
Q_IMPORT_QML_PLUGIN(InGeRetroplasmaPlugin)
int main(int argc,char **argv){
    QGuiApplication app(argc,argv);RetroplasmaController controller;QQmlEngine engine;
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
    std::unique_ptr<QObject> view(viewport.createWithInitialProperties({{"controller",QVariant::fromValue(&controller)},{"width",360}}));
    if(!view){for(const auto &error:viewport.errors())std::cerr<<error.toString().toStdString()<<'\n';return 1;}
    controller.open();QElapsedTimer deadline;deadline.start();while(!controller.ready()&&deadline.elapsed()<3000){QCoreApplication::processEvents();QThread::msleep(1);}
    if(!controller.ready()){std::cerr<<"default world scene not ready\n";return 1;}
    auto publishFix=[&](){service->setProperty("nativeHasFix",true);service->setProperty("nativeLatitude",-12.0464);service->setProperty("nativeLongitude",-77.0428);service->setProperty("nativeAltitude",153.0);service->setProperty("nativeTimestampMs",double(QDateTime::currentMSecsSinceEpoch()));QMetaObject::invokeMethod(service.get(),"nativeLocationChanged");QCoreApplication::processEvents();QCoreApplication::processEvents();};
    QMetaObject::invokeMethod(view.get(),"requestGps");publishFix();
    if(view->property("gpsRequested").toBool()||service->property("nativeTracking").toBool()){std::cerr<<"temporary Earth GPS tracking not released after fix\n";return 1;}
    service->setProperty("nativeTracking",true);QMetaObject::invokeMethod(view.get(),"requestGps");publishFix();
    if(!service->property("nativeTracking").toBool()){std::cerr<<"Earth stopped another client's GPS tracking\n";return 1;}
    std::cout<<"PLANET QML VIEW PASS: native registered type, controls, gesture signals and shared GPS boundary load\n";
}
