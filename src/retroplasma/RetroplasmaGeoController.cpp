#include "RetroplasmaController.h"
#include "RetroplasmaPlanet.h"
#include <QDir>
#include <QFileInfo>
#include <QUuid>
#include <QRegularExpression>
#include <algorithm>

QVariantList RetroplasmaController::geoLayers()const{
    QVariantList result;
    for(auto &layer:m_geoLayers){QVariantList features;for(std::size_t i=0;i<layer.document.features.size();++i){auto &f=layer.document.features[i];features.append(QVariantMap{{"name",f.name},{"kind",f.kind},{"index",int(i)}});}
        result.append(QVariantMap{{"id",layer.id},{"name",layer.document.name},{"visible",layer.visible},{"count",int(layer.document.features.size())},{"features",features},{"warnings",layer.document.warnings.join('\n')}});
    }return result;
}
bool RetroplasmaController::importDocument(const QString &input){
    if(m_geoLayers.size()>=16){m_documentMessage=QStringLiteral("Máximo 16 capas; elimina una antes de importar.");emit geoChanged();return false;}
    auto url=QUrl(input);QString path=url.isLocalFile()?url.toLocalFile():input;inge::rp::GeoDocument doc;QString error;
    if(!inge::rp::readGeoDocument(path,doc,error)){m_documentMessage=error;emit geoChanged();return false;}
    std::size_t positions=0,features=0,vertices=0;
    auto account=[&](const auto &f){++features;vertices+=inge::rp::geoFeatureVertexCost(f);positions+=f.points.size();for(auto &h:f.holes)positions+=h.size();};
    for(auto &l:m_geoLayers)for(auto &f:l.document.features)account(f);
    for(auto &f:doc.features)account(f);
    if(features>500||vertices>180000){m_documentMessage=QStringLiteral("Capas demasiado complejas: máximo 500 geometrías y 180000 vértices estimados. Simplifica o elimina capas antes de importar.");emit geoChanged();return false;}
    if(positions>20000){m_documentMessage=QStringLiteral("Límite total de 20000 posiciones cargadas.");emit geoChanged();return false;}
    auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);m_documentMessage=QStringLiteral("Cargado: ")+doc.name;if(!doc.warnings.isEmpty())m_documentMessage+='\n'+doc.warnings.join('\n');
    m_geoLayers.push_back({id,std::move(doc),true});rebuildGeoTiles();centerGeoLayer(id);emit geoChanged();return true;
}
QString RetroplasmaController::exportDocument(const QString &folder,const QString &name,bool kmz){
    const QString stem=name.trimmed();if(stem.isEmpty()||stem==QLatin1String(".")||stem==QLatin1String("..")||stem.contains('/')||stem.contains('\\')||stem.contains(':')||stem.contains(QChar::Null)) {m_documentMessage=QStringLiteral("Nombre de archivo inválido.");emit geoChanged();return {};}
    if(!QFileInfo(folder).isDir()){m_documentMessage=QStringLiteral("Selecciona una carpeta local en Documentos.");emit geoChanged();return {};}
    inge::rp::GeoDocument doc;doc.name=stem;for(auto &l:m_geoLayers){for(auto f:l.document.features){f.visible=f.visible&&l.visible;doc.features.push_back(std::move(f));}}
    if(m_measureLine.points.size()>1)doc.features.push_back(m_measureLine);
    if(doc.features.empty()){m_documentMessage=QStringLiteral("Agrega lugares o importa una capa antes de guardar.");emit geoChanged();return {};}
    QString base=stem;base.remove(QRegularExpression(QStringLiteral("\\.(kml|kmz)$"),QRegularExpression::CaseInsensitiveOption));QString path=QDir(folder).filePath(base+(kmz?".kmz":".kml"));
    for(int n=1;QFileInfo::exists(path);++n)path=QDir(folder).filePath(base+QStringLiteral(" (%1)").arg(n)+(kmz?".kmz":".kml"));
    QString error;if(!inge::rp::saveGeoDocument(path,doc,error)){m_documentMessage=error;emit geoChanged();return {};}
    m_documentMessage=QStringLiteral("Guardado: ")+path;emit geoChanged();return path;
}
void RetroplasmaController::setLayerVisible(const QString &id,bool visible){for(auto &l:m_geoLayers)if(l.id==id){l.visible=visible;rebuildGeoTiles();emit geoChanged();return;}}
void RetroplasmaController::removeGeoLayer(const QString &id){m_geoLayers.erase(std::remove_if(m_geoLayers.begin(),m_geoLayers.end(),[&](auto &l){return l.id==id;}),m_geoLayers.end());rebuildGeoTiles();emit geoChanged();}
void RetroplasmaController::clearGeoLayers(){m_geoLayers.clear();m_measureLine={};m_measuring=false;m_measurementKm=0;m_documentMessage.clear();rebuildGeoTiles();emit geoChanged();}
void RetroplasmaController::centerGeoLayer(const QString &id,int feature){
    if(!m_scene||!m_scene->planetary)return;
    for(auto &l:m_geoLayers)if(l.id==id){std::vector<inge::rp::GeoPoint> points;
        if(feature>=0&&feature<int(l.document.features.size()))points=l.document.features[feature].points;else for(auto &f:l.document.features)points.insert(points.end(),f.points.begin(),f.points.end());if(points.empty())return;
        double west=points[0].longitude,east=west,south=90,north=-90;for(auto p:points){double lon=west+std::remainder(p.longitude-west,360.0);west=std::min(west,lon);east=std::max(east,lon);south=std::min(south,p.latitude);north=std::max(north,p.latitude);}
        double lon=std::remainder((west+east)*.5,360.0),lat=(south+north)*.5,extent=inge::rp::surfaceDistance({south,west,0},{north,east,0});m_camera.goToGeographic({lat,lon,0},std::clamp(extent*1.8,5000.0,50000000.0));emit renderChanged();return;
    }
}
void RetroplasmaController::addPlace(const QString &name){
    if(!m_scene||!m_scene->planetary)return;std::size_t features=0;for(auto &l:m_geoLayers)features+=l.document.features.size();if(features>=500){m_documentMessage=QStringLiteral("Máximo 500 geometrías cargadas.");emit geoChanged();return;}inge::rp::GeoFeature f;f.kind=QStringLiteral("Point");f.name=name.trimmed().isEmpty()?QStringLiteral("Lugar"):name.left(256);f.points.push_back(m_camera.planetTarget());
    auto found=std::find_if(m_geoLayers.begin(),m_geoLayers.end(),[](auto &l){return l.id==QLatin1String("places");});
    if(found==m_geoLayers.end()){if(m_geoLayers.size()>=16)return;inge::rp::GeoDocument d;d.name=QStringLiteral("Mis lugares");m_geoLayers.push_back({QStringLiteral("places"),d,true});found=std::prev(m_geoLayers.end());}
    if(found->document.features.size()>=500)return;found->document.features.push_back(std::move(f));rebuildGeoTiles();m_documentMessage=QStringLiteral("Lugar agregado en el centro de la vista.");emit geoChanged();
}
void RetroplasmaController::beginMeasure(){m_measureLine={};m_measureLine.kind=QStringLiteral("LineString");m_measureLine.name=QStringLiteral("Medición");m_measuring=true;m_measurementKm=0;m_documentMessage=QStringLiteral("Toca dos posiciones sobre la Tierra para medir.");rebuildGeoTiles();emit geoChanged();}
void RetroplasmaController::cancelMeasure(){m_measuring=false;m_measureLine={};m_measurementKm=0;rebuildGeoTiles();emit geoChanged();}
bool RetroplasmaController::selectPosition(double x,double y,bool marker){
    if(!m_scene||!m_scene->planetary||!m_active)return false;inge::rp::GeoPoint hit;
    if(!inge::rp::pickPlanet(viewProjection(),m_camera.eye(),2*x/m_width-1,1-2*y/m_height,hit,71)){m_documentMessage=QStringLiteral("Toca la superficie terrestre.");emit geoChanged();return false;}
    hit.altitude=0;
    if(m_measuring){m_measureLine.points.push_back(hit);if(m_measureLine.points.size()==2){m_measurementKm=inge::rp::surfaceDistance(m_measureLine.points[0],hit)/1000;m_measuring=false;m_documentMessage=QStringLiteral("Distancia geodésica: %1 km").arg(m_measurementKm,0,'f',3);}rebuildGeoTiles();emit geoChanged();}
    else if(marker){std::size_t features=0;for(auto &l:m_geoLayers)features+=l.document.features.size();if(features>=500||m_geoLayers.size()>=16){m_documentMessage=QStringLiteral("Máximo 500 geometrías / 16 capas.");emit geoChanged();return false;}m_camera.goToGeographic(hit,5000);inge::rp::GeoDocument d;d.name=QStringLiteral("Lugar marcado");inge::rp::GeoFeature f;f.kind=QStringLiteral("Point");f.name=d.name;f.points.push_back(hit);d.features.push_back(f);m_geoLayers.push_back({QUuid::createUuid().toString(QUuid::WithoutBraces),d,true});rebuildGeoTiles();emit geoChanged();}
    else m_camera.goToGeographic(hit,std::max(2000.0,m_camera.pose().distance*.5));return true;
}
void RetroplasmaController::rebuildGeoTiles(){
    m_geoTiles.clear();double width=std::clamp(m_camera.pose().distance*2*std::tan(22.5*inge::rp::Radians)/m_height*3,10.0,30000.0);m_geoWidth=width;++m_geoRevision;std::size_t bytes=0;bool exceeded=false;
    auto add=[&](const inge::rp::GeoFeature &f){auto tile=inge::rp::geoFeatureTile(f,width);if(tile&&bytes+tile->bytes<=16*1024*1024){bytes+=tile->bytes;m_geoTiles.push_back({QStringLiteral("geo:%1:%2").arg(m_geoRevision).arg(m_geoTiles.size()),tile});}else if(tile)exceeded=true;};
    for(auto &l:m_geoLayers){if(exceeded)break;if(l.visible)for(auto &f:l.document.features){if(exceeded)break;if(f.visible)add(f);}}
    if(!m_measureLine.points.empty()){if(m_measureLine.points.size()==1){auto point=m_measureLine;point.kind=QStringLiteral("Point");add(point);}else add(m_measureLine);}
    if(exceeded){m_documentMessage=QStringLiteral("Límite gráfico de capas (16 MiB). Algunas geometrías no se muestran: oculta o elimina capas.");emit geoChanged();}emit renderChanged();
}
QVariantMap RetroplasmaController::cameraInfo()const{
    auto p=m_camera.planetTarget();double metresPerPixel=m_camera.pose().distance*2*std::tan(22.5*inge::rp::Radians)/m_height;
    double resolution=19568;for(auto &t:m_renderTiles)if(t.tile->coveragePercent>0)resolution=std::min(resolution,t.tile->resolutionMetres);
    return {{"latitude",p.latitude},{"longitude",p.longitude},{"altitude",p.altitude},{"cameraAltitude",m_camera.pose().distance},{"heading",m_camera.heading()/inge::rp::Radians},{"metresPerPixel",metresPerPixel},{"resolutionMetres",resolution}};
}
double RetroplasmaController::scaleMetres(double pixels)const{
    if(!m_scene||!m_scene->planetary||!std::isfinite(pixels)||pixels<=0)return 0;
    inge::rp::GeoPoint a,b;auto matrix=viewProjection();
    if(!inge::rp::pickPlanet(matrix,m_camera.eye(),-pixels/m_width,0,a,71)||!inge::rp::pickPlanet(matrix,m_camera.eye(),pixels/m_width,0,b,71))return 0;
    return inge::rp::surfaceDistance(a,b);
}
