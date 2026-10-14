#include "RetroplasmaPlanetProvider.h"
#include "RetroplasmaTileScheduler.h"
#include "RetroplasmaCamera.h"
#include <QCoreApplication>
#include <QResource>
#include <QUrlQuery>
#include <QtConcurrent/QtConcurrentRun>
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
static int checks=0;
static void require(bool value,const char *why){++checks;if(!value)throw std::runtime_error(why);}
static double radialIntersection(const Geometry &mesh,Vec3 direction){
    for(std::size_t i=0;i<mesh.indices.size();i+=3){
        auto point=[&](int index){auto &v=mesh.vertices[mesh.indices[i+index]];return Vec3{v.position[0],v.position[1],v.position[2]};};
        auto a=point(0),b=point(1),c=point(2),edge=b-a,other=c-a,h=cross(direction,other);double det=dot(edge,h);if(std::abs(det)<1e-14)continue;
        auto offset=a*(-1),q=cross(offset,edge);double u=dot(offset,h)/det,v=dot(direction,q)/det,d=dot(other,q)/det;
        if(u>=-1e-8&&v>=-1e-8&&u+v<=1+1e-8&&d>0)return d;
    }
    return 0;
}
int main(int argc,char **argv){
    QCoreApplication app(argc,argv);Q_INIT_RESOURCE(rp_samples);
    PlanetSceneProvider provider;QString error;std::atomic_bool cancel{false};
    auto scene=provider.readScene(QUrl("inge-earth://global?layer=blue-marble"),error,cancel);
    require(scene&&scene->planetary&&scene->nodes.size()==32,"global scene consists of 32 ellipsoid sectors");
    Lod overview;overview.planetary=true;overview.layer="overview";overview.sector={-90,-45,-45,0};
    auto baseMesh=PlanetSceneProvider::geometryFor(overview);Lod remote=overview;remote.layer="blue-marble";
    auto remoteMesh=PlanetSceneProvider::geometryFor(remote);
    for(double latitude:{-33.3,-21.7,-12.3})for(double longitude:{-81.7,-77.1,-62.3}){
        auto ray=normalized(ecefToPlanet(geodeticToEcef({latitude,longitude,0})));
        auto baseRadius=radialIntersection(baseMesh,ray),remoteRadius=radialIntersection(remoteMesh,ray);
        require(baseRadius>0&&remoteRadius>baseRadius,"remote L0 texture surface must be above opaque overview at interior points");
    }
    QHash<QString,std::shared_ptr<const LoadedTile>> cache;
    for(const auto &node:scene->nodes){auto tile=provider.readTile(node.lods[0],error,cancel);require(tile&&tile->texture.size()==QSize(256,256),"actual NASA JPEG decodes into geographic sector");require(tile->geometry.vertices.size()==1089,"real ellipsoid geometry uploaded with satellite sector");cache.insert("g:overview:"+node.id,tile);}
    Camera camera;camera.resetPlanet(true);
    auto global=RetroplasmaTileScheduler::selectPlanet(*scene,camera.viewProjection(1),camera.eye(),600,cache,"g");
    require(global.draw.size()==32&&global.requests.empty(),"entire world remains available offline with zero remote requests in space");
    camera.goToGeographic({-12.0464,-77.0428,0});for(int i=0;i<150;++i)camera.step(.016);
    auto lima=RetroplasmaTileScheduler::selectPlanet(*scene,camera.viewProjection(1),camera.eye(),600,cache,"g");
    require(lima.draw.size()>=32&&!lima.requests.empty(),"regional GIBS refinement keeps full planet base coverage");
    require(lima.requests.size()<=96,"regional tile request budget bounded");
    bool limaRequested=false;
    for(const auto &request:lima.requests){require(request.direct&&request.asset.level<=5,"Blue Marble native resolution cap");auto s=request.asset.sector;if(s.west<=-77.0428&&s.east>=-77.0428&&s.south<=-12.0464&&s.north>=-12.0464)limaRequested=true;}
    require(limaRequested,"Lima's real geographic sector requested");
    auto hls=provider.readScene(QUrl("inge-earth://global?layer=landsat&date=2026-10-05"),error,cancel);require(hls&&hls->imagery=="landsat","USGS Landsat provider accepted with explicit date");
    auto detail=RetroplasmaTileScheduler::selectPlanet(*hls,camera.viewProjection(1),camera.eye(),600,cache,"g");
    require(!detail.requests.empty()&&detail.requests.size()<=96,"HLS quadtree requested within budget");
    for(const auto &request:detail.requests)require(request.asset.level<=9,"30m resolution cap, no unlimited source zoom");
    Lod asset;asset.planetary=true;asset.layer="landsat";asset.date="2026-10-05";asset.sector={-78,-13,-77,-12};
    QUrlQuery query(PlanetSceneProvider::imageryUrl(asset));require(query.queryItemValue("BBOX")=="-13.0000000000,-78.0000000000,-12.0000000000,-77.0000000000","WMS 1.3 EPSG:4326 axis order");
    require(query.queryItemValue("LAYERS")=="HLS_L30_Nadir_BRDF_Adjusted_Reflectance"&&query.queryItemValue("TIME")=="2026-10-05","official GIBS Landsat layer and date");
    for(auto target:{GeoPoint{51.5,-.12,0},GeoPoint{35.67,139.65,0},GeoPoint{-33.8,151.2,0},GeoPoint{89.999,179.99,0},GeoPoint{-89.999,-179.99,0},GeoPoint{0,179.99,0}}){
        camera.goToGeographic(target);for(int i=0;i<150;++i)camera.step(.016);
        auto region=RetroplasmaTileScheduler::selectPlanet(*scene,camera.viewProjection(.7),camera.eye(),600,cache,"g");
        bool found=false;for(auto request:region.requests){auto s=request.asset.sector;if(s.west<=target.longitude&&s.east>=target.longitude&&s.south<=target.latitude&&s.north>=target.latitude)found=true;}
        require(found,"global coordinate target retained by frustum/horizon/LOD selection");
    }
    if(qEnvironmentVariableIsSet("RP_TEST_GIBS")){
        asset.sector={-77.08,-12.08,-76.99,-11.99};
        for(auto layer:{QStringLiteral("blue-marble"),QStringLiteral("landsat")}){
            asset.layer=layer;if(layer=="landsat")asset.date="auto";auto future=QtConcurrent::run([&](){return provider.readTile(asset,error,cancel);});future.waitForFinished();auto tile=future.result();
            if(!tile)std::cerr<<error.toStdString()<<'\n';
            require(tile&&tile->texture.size()==QSize(256,256),"live official GIBS tile fetched and decoded on worker");
            std::cout<<"LIVE_GIBS "<<layer.toStdString()<<" coverage="<<tile->coveragePercent<<"% resolution="<<tile->resolutionMetres<<"m date="<<tile->acquisitionDate.toStdString()<<"\n";
        }
    }
    auto eox=provider.readScene(QUrl("inge-earth://global?layer=sentinel"),error,cancel);
    require(eox&&eox->imagery=="sentinel","authorized EOX 2016 provider accepted");
    asset.layer="sentinel";QUrlQuery eoxQuery(PlanetSceneProvider::imageryUrl(asset));
    require(eoxQuery.queryItemValue("LAYERS")=="s2cloudless"&&eoxQuery.queryItemValue("VERSION")=="1.1.1","2016 EOX EPSG4326 WMS layer");
    require(eoxQuery.queryItemValue("BBOX")=="-78.0000000000,-13.0000000000,-77.0000000000,-12.0000000000","EOX WMS111 longitude-first axis order");
    camera.goToGeographic({-12.0464,-77.0428,0},2000);for(int i=0;i<180;++i)camera.step(.016);
    require(camera.pose().distance<2100,"city zoom reaches 2km rather than former 40km floor");
    auto city=RetroplasmaTileScheduler::selectPlanet(*eox,camera.viewProjection(1),camera.eye(),1200,cache,"g");
    bool fine=false,progressive=false;for(const auto&r:city.requests){fine|=r.asset.level>=10;progressive|=r.asset.level<8;require(r.asset.level<=11,"10m native detail bounded at level11");}
    require(fine&&progressive,"city requests fine imagery with coarse parents for progressive coverage");
    if(qEnvironmentVariableIsSet("RP_TEST_EOX")){
        asset.layer="sentinel";asset.level=11;asset.sector={-77.05,-12.05,-77.02802734375,-12.02802734375};
        auto future=QtConcurrent::run([&](){return provider.readTile(asset,error,cancel);});future.waitForFinished();auto tile=future.result();
        if(!tile)std::cerr<<error.toStdString()<<'\n';require(tile&&tile->texture.size()==QSize(256,256)&&tile->resolutionMetres>=10&&tile->resolutionMetres<11,"live licensed EOX 2016 tile at native 10m");
        std::cout<<"LIVE_EOX LIMA 2016 256x256 effective_resolution="<<tile->resolutionMetres<<"m\n";
    }
    cancel.store(true);require(!provider.readTile(scene->nodes[0].lods[0],error,cancel)&&error=="CANCELLED","planet load cancellation obeyed");
    std::cout<<"PLANET PROVIDER PASS "<<checks<<" checks\n";
}
