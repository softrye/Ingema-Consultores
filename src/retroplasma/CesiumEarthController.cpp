#include "RetroplasmaController.h"
#include "CesiumNativeView.h"
#include <QJsonArray>
#include <QSettings>
#include <QUuid>
#include <algorithm>

void RetroplasmaController::dispatchCesium(const QJsonObject &message){if(m_active)inge::earth::command(message);}
void RetroplasmaController::sendCesiumBudget(){dispatchCesium({{"op","budget"},{"value",QJsonObject{{"gpuMiB",qint64(m_budget.gpuBytes/1048576)},{"maxLevel",m_budget.maxLevel},{"pixelError",m_budget.pixelError},{"parallel",m_budget.parallel}}}});}
void RetroplasmaController::openCesium(){
    if(m_active)return;
    ++m_generation;m_active=true;m_cesiumReady=false;m_cesiumError.clear();m_manifestBusy=true;m_tick.stop();cancelJobs();m_cache.clear();m_renderTiles.clear();
    auto scene=std::make_shared<inge::rp::Scene>();scene->planetary=true;scene->imagery=m_preferredImagery;scene->title=QStringLiteral("InGe Earth · Cesium 1.147");m_scene=scene;
    m_camera.resetPlanet(true);m_status=QStringLiteral("Iniciando Cesium 1.147…");inge::earth::setController(this);
    if(!inge::earth::show()){m_manifestBusy=false;m_cesiumError=m_status=QStringLiteral("CESIUM_ANDROID_HOST_UNAVAILABLE");}
    emit changed();emit renderChanged();
}
void RetroplasmaController::closeCesium(){
    if(!m_active)return;
    dispatchCesium({{"op","visible"},{"value",false}});inge::earth::hide();inge::earth::setController(nullptr);
    ++m_generation;m_active=false;m_cesiumReady=false;m_manifestBusy=false;m_tick.stop();m_scene.reset();m_cesiumError.clear();m_cesiumBackdrop.clear();m_cesiumCamera.clear();m_cesiumStats.clear();m_status="CLOSED";emit changed();emit renderChanged();
}
void RetroplasmaController::setCesiumSource(const QString &layer,const QString &date){
    if(!m_active||(layer!="rocktree"&&layer!="sentinel"&&layer!="blue-marble"&&layer!="landsat"))return;
    m_preferredImagery=layer;QSettings().setValue(QStringLiteral("earth/imagery"),layer);m_cesiumError.clear();
    auto scene=std::make_shared<inge::rp::Scene>(*m_scene);scene->imagery=layer;scene->source=layer=="rocktree"?QStringLiteral("Google Earth / RockTree + base NASA / Natural Earth"):layer=="sentinel"?QStringLiteral("EOxCloudless 2016 + base Natural Earth"):QStringLiteral("NASA / USGS + base Natural Earth");m_scene=scene;
    dispatchCesium({{"op","source"},{"layer",layer},{"date",date}});emit changed();
}
void RetroplasmaController::sendCesiumLayers(){
    QJsonArray features;
    auto positions=[](const std::vector<inge::rp::GeoPoint> &points){QJsonArray result;for(auto p:points)result.append(QJsonObject{{"latitude",p.latitude},{"longitude",p.longitude},{"altitude",p.altitude}});return result;};
    auto add=[&](const inge::rp::GeoFeature &feature){if(!feature.visible)return;QJsonArray holes;for(const auto &ring:feature.holes)holes.append(positions(ring));
        features.append(QJsonObject{{"name",feature.name},{"kind",feature.kind},{"color",feature.color.name()},{"alpha",feature.color.alphaF()},{"points",positions(feature.points)},{"holes",holes}});};
    for(const auto &layer:m_geoLayers)if(layer.visible)for(const auto &feature:layer.document.features)add(feature);
    if(!m_measureLine.points.empty()){auto line=m_measureLine;if(line.points.size()==1)line.kind="Point";add(line);}
    dispatchCesium({{"op","features"},{"layers",features}});
}
void RetroplasmaController::acceptCesiumEvent(const QJsonObject &event){
    if(!m_active)return;const auto type=event.value("type").toString();
    if(type=="ready"){
        m_cesiumReady=true;m_manifestBusy=false;m_status=QStringLiteral("Cesium %1").arg(event.value("version").toString());
        sendCesiumBudget();setCesiumSource(m_preferredImagery);sendCesiumLayers();
        if(m_pendingTarget){auto p=*m_pendingTarget;m_pendingTarget.reset();goTo(p.latitude,p.longitude,p.altitude);}
    }else if(type=="error"){
        const auto code=event.value("code").toString();if(!code.startsWith(QLatin1String("CESIUM_"))||code.size()>100)return;
        m_cesiumError=m_status=code;m_manifestBusy=false;
        if(code==QLatin1String("CESIUM_RENDERER_GONE")||code==QLatin1String("CESIUM_WEBGL_INITIALIZATION_FAILED"))m_cesiumReady=false;
    }else if(type=="backdrop"){
        const auto uri=event.value("uri").toString();if(uri.size()>28000||!uri.startsWith(QLatin1String("data:image/jpeg;base64,")))return;m_cesiumBackdrop=uri;
    }else if(type=="state"){
        auto latitude=event.value("latitude").toDouble(999),longitude=event.value("longitude").toDouble(999),height=event.value("cameraAltitude").toDouble(-1);
        if(!std::isfinite(latitude)||!std::isfinite(longitude)||!std::isfinite(height)||std::abs(latitude)>90||std::abs(longitude)>180||height<0||height>1e9)return;
        m_cesiumCamera=event.toVariantMap();m_manifestBusy=event.value("pending").toInt()>0;
        m_camera.setPlanetView({latitude,longitude,0},height,event.value("heading").toDouble()*inge::rp::Radians);
        m_cesiumStats={{"backend","Cesium 1.147 / WebGL"},{"gpuMiB",event.value("gpuMiB").toDouble()},{"pending",event.value("pending").toInt()},{"renderError",m_cesiumError},{"decodeErrors",m_cesiumError.isEmpty()?0:1}};
        if(m_cesiumError.isEmpty())m_status=m_manifestBusy?QStringLiteral("Cesium · cargando detalle…"):QStringLiteral("Cesium · listo");
    }else if(type=="position"){
        inge::rp::GeoPoint p{event.value("latitude").toDouble(999),event.value("longitude").toDouble(999),event.value("altitude").toDouble()};
        if(!std::isfinite(p.latitude)||!std::isfinite(p.longitude)||!std::isfinite(p.altitude)||std::abs(p.latitude)>90||std::abs(p.longitude)>180||std::abs(p.altitude)>100000)return;
        const auto intent=event.value("intent").toString();
        if(intent=="measure"&&m_measuring){m_measureLine.points.push_back(p);if(m_measureLine.points.size()>=2){m_measurementKm=inge::rp::surfaceDistance(m_measureLine.points[0],p)/1000;m_measuring=false;m_documentMessage=QStringLiteral("Distancia geodésica: %1 km").arg(m_measurementKm,0,'f',3);}sendCesiumLayers();emit geoChanged();}
        else if(intent=="place"){
            std::size_t count=0;for(const auto &layer:m_geoLayers)count+=layer.document.features.size();if(count>=500||m_geoLayers.size()>=16){m_documentMessage=QStringLiteral("Máximo 500 geometrías / 16 capas.");emit geoChanged();return;}
            inge::rp::GeoDocument doc;doc.name=QStringLiteral("Lugar marcado");inge::rp::GeoFeature feature;feature.name=doc.name;feature.kind="Point";feature.points.push_back(p);doc.features.push_back(feature);m_geoLayers.push_back({QUuid::createUuid().toString(QUuid::WithoutBraces),doc,true});sendCesiumLayers();emit geoChanged();
        }else dispatchCesium({{"op","goto"},{"latitude",p.latitude},{"longitude",p.longitude},{"height",std::max(80.0,m_cesiumCamera.value("cameraAltitude",120000).toDouble()*.5)}});
    }
    emit changed();emit renderChanged();
}
