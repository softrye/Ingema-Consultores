#include "RetroplasmaController.h"
#include "RetroplasmaTileScheduler.h"
#include "RetroplasmaPlanetProvider.h"
#include <QUrlQuery>
#include <QGuiApplication>
#include <QResource>
#include <QtConcurrent/QtConcurrentRun>
#include <algorithm>

static void initializeRetroplasmaResources(){Q_INIT_RESOURCE(rp_shaders);Q_INIT_RESOURCE(rp_samples);}
namespace {
constexpr std::size_t CacheLimit=64*1024*1024;
using SceneResult=std::pair<std::shared_ptr<const inge::rp::Scene>,QString>;
using TileResult=std::pair<std::shared_ptr<const inge::rp::LoadedTile>,QString>;
bool contains(inge::rp::Bounds a,inge::rp::Bounds b){constexpr double e=0.02;return b.minimum.x>=a.minimum.x-e&&b.minimum.y>=a.minimum.y-e&&b.minimum.z>=a.minimum.z-e&&b.maximum.x<=a.maximum.x+e&&b.maximum.y<=a.maximum.y+e&&b.maximum.z<=a.maximum.z+e;}
}
RetroplasmaController::RetroplasmaController(QObject *parent):QObject(parent),m_provider(std::make_shared<inge::rp::PlanetSceneProvider>()),m_mailbox(std::make_shared<inge::rp::MetricsMailbox>()){
    initializeRetroplasmaResources();m_pool.setMaxThreadCount(2);m_tick.setInterval(16);
    connect(&m_tick,&QTimer::timeout,this,&RetroplasmaController::tick);
    if(auto *app=qobject_cast<QGuiApplication *>(QCoreApplication::instance())){
        connect(app,&QGuiApplication::applicationStateChanged,this,[this](Qt::ApplicationState state){m_appVisible=state==Qt::ApplicationActive;if(m_active&&m_appVisible){m_clock.restart();m_tick.start();}else m_tick.stop();emit renderChanged();});
    }
    connect(QCoreApplication::instance(),&QCoreApplication::aboutToQuit,this,&RetroplasmaController::close);
}
RetroplasmaController::~RetroplasmaController(){close();m_pool.waitForDone();}
void RetroplasmaController::open(){if(m_active)return;m_active=true;m_mailbox=std::make_shared<inge::rp::MetricsMailbox>();m_presentedFrames=m_lastFrameCount=0;m_fps=m_frameMs=0;m_clock.restart();m_telemetryClock.start();if(m_appVisible)m_tick.start();openPlanet();emit changed();}
void RetroplasmaController::openPlanet(){m_preservedCamera.reset();loadScene(QUrl(QStringLiteral("inge-earth://global")));}
void RetroplasmaController::setPlanetImagery(const QString &layer,const QString &date){
    if(!m_active||(layer!=QLatin1String("blue-marble")&&layer!=QLatin1String("landsat")))return;
    if(m_scene&&m_scene->planetary)m_preservedCamera=m_camera;
    QUrl url(QStringLiteral("inge-earth://global"));QUrlQuery q;q.addQueryItem(QStringLiteral("layer"),layer);if(!date.isEmpty())q.addQueryItem(QStringLiteral("date"),date);url.setQuery(q);loadScene(url);
}
void RetroplasmaController::cancelJobs(){if(m_manifestCancel)m_manifestCancel->store(true);for(auto &job:m_jobs)job.cancelled->store(true);m_jobs.clear();}
void RetroplasmaController::loadLocalScene(const QString &path){loadScene(path.startsWith(QLatin1String("file:"))||path.startsWith(QLatin1String("qrc:"))?QUrl(path):QUrl::fromLocalFile(path));}
void RetroplasmaController::retryScene(){if(m_active&&!m_sceneUrl.isEmpty()){if(m_scene&&m_scene->planetary)m_preservedCamera=m_camera;loadScene(m_sceneUrl);}}
void RetroplasmaController::close(){if(!m_active&&!m_manifestBusy)return;++m_generation;m_active=false;m_tick.stop();cancelJobs();m_scene.reset();m_cache.clear();m_failed.clear();m_renderTiles.clear();m_pendingTarget.reset();m_preservedCamera.reset();m_manifestBusy=false;m_navigationMode=false;m_status=QStringLiteral("CLOSED");emit renderChanged();emit changed();}
void RetroplasmaController::loadScene(const QUrl &url){
    if(!m_active)return;m_sceneUrl=url;cancelJobs();m_cache.clear();m_failed.clear();m_renderTiles.clear();m_scene.reset();m_manifestBusy=true;m_status=url.scheme()==QLatin1String("inge-earth")?QStringLiteral("Cargando Tierra WGS84 / NASA…"):QStringLiteral("Cargando escena local…");quint64 generation=++m_generation;
    auto cancel=std::make_shared<std::atomic_bool>(false);m_manifestCancel=cancel;auto provider=m_provider;
    auto *watcher=new QFutureWatcher<SceneResult>(this);
    connect(watcher,&QFutureWatcher<SceneResult>::finished,this,[this,watcher,generation,cancel](){
        auto result=watcher->result();watcher->deleteLater();if(generation!=m_generation||cancel->load()||!m_active)return;
        m_manifestBusy=false;m_scene=result.first;
        if(!m_scene)m_status=result.second;else {if(m_scene->planetary){if(m_preservedCamera)m_camera=*m_preservedCamera;else m_camera.resetPlanet(true);}else m_camera.reset(m_scene->bounds,true);m_preservedCamera.reset();if(m_pendingTarget){auto point=*m_pendingTarget;m_pendingTarget.reset();goTo(point.latitude,point.longitude,point.altitude);}m_status=QStringLiteral("Cargando mallas y texturas…");schedule();}
        emit renderChanged();emit changed();
    });
    watcher->setFuture(QtConcurrent::run(&m_pool,[provider,url,cancel](){SceneResult result;try{if(!cancel->load())result.first=provider->readScene(url,result.second,*cancel);}catch(...){result.second=QStringLiteral("RP_SCENE_READ_OR_MEMORY_ERROR");}return result;}));
    emit renderChanged();emit changed();
}
void RetroplasmaController::setViewport(double width,double height){m_width=std::max(1.0,width);m_height=std::max(1.0,height);}
void RetroplasmaController::framePresented(){if(renderActive())++m_presentedFrames;}
void RetroplasmaController::tick(){
    if(!m_active||!m_appVisible)return;
    double dt=m_clock.restart()/1000.0;m_camera.step(std::min(dt,0.1));
    if(++m_ticks%6==0)schedule();
    if(m_telemetryClock.elapsed()>=500){quint64 frames=m_presentedFrames;double ms=m_telemetryClock.restart();m_fps=ms>0?(frames-m_lastFrameCount)*1000.0/ms:0;m_frameMs=m_fps>0?1000.0/m_fps:0;m_lastFrameCount=frames;emit changed();}
    emit renderChanged();
}
void RetroplasmaController::schedule(){
    if(!m_scene||!m_active)return;
    QHash<QString,std::shared_ptr<const inge::rp::LoadedTile>> resident;for(auto it=m_cache.begin();it!=m_cache.end();++it)resident.insert(it.key(),it.value().tile);
    auto selection=chooseTiles(resident);
    m_renderTiles=std::move(selection.draw);for(auto &tile:m_renderTiles)m_cache[tile.key].used=++m_usage;
    for(auto it=m_jobs.begin();it!=m_jobs.end();++it)if(!selection.wanted.contains(it.key()))it.value().cancelled->store(true);
    trimCache(selection.wanted);
    for(auto request:selection.requests){
        if(m_jobs.size()>=2)break;if(m_jobs.contains(request.key)||m_cache.contains(request.key)||m_failed.contains(request.key))continue;
        const auto lod=request.direct?request.asset:m_scene->nodes[request.node].lods[request.lod];const auto nodeBounds=request.direct?request.bounds:m_scene->nodes[request.node].bounds;const quint64 generation=m_generation;
        auto cancel=std::make_shared<std::atomic_bool>(false);m_jobs.insert(request.key,{cancel});auto provider=m_provider;
        auto *watcher=new QFutureWatcher<TileResult>(this);
        connect(watcher,&QFutureWatcher<TileResult>::finished,this,[this,watcher,generation,cancel,key=request.key,nodeBounds](){
            auto result=watcher->result();watcher->deleteLater();if(generation!=m_generation||!m_active)return;
            m_jobs.remove(key);if(cancel->load()){schedule();return;}
            if(result.first&&!contains(nodeBounds,result.first->geometry.bounds)){result.first.reset();result.second=QStringLiteral("RP_MESH_OUTSIDE_NODE_BOUNDS");}
            if(result.first){
                m_cache.insert(key,{result.first,++m_usage});
                QHash<QString,std::shared_ptr<const inge::rp::LoadedTile>> resident;
                for(auto it=m_cache.begin();it!=m_cache.end();++it)resident.insert(it.key(),it.value().tile);
                // Recompute before eviction: complete children can now release their parent.
                auto next=chooseTiles(resident);
                auto protectedKeys=next.wanted;protectedKeys.insert(key);
                for(const auto &tile:next.draw)protectedKeys.insert(tile.key);
                // Preflight before eviction: a rejected replacement cannot evict its parent.
                std::size_t protectedBytes=0;for(auto it=m_cache.begin();it!=m_cache.end();++it)if(protectedKeys.contains(it.key()))protectedBytes+=it.value().tile->bytes;
                if(protectedBytes>CacheLimit){m_cache.remove(key);m_failed.insert(key,QStringLiteral("RP_CPU_TRANSITION_MEMORY_LIMIT"));}
                else trimCache(protectedKeys);
            }else m_failed.insert(key,result.second);
            schedule();emit renderChanged();emit changed();
        });
        watcher->setFuture(QtConcurrent::run(&m_pool,[provider,lod,cancel](){TileResult result;try{if(!cancel->load())result.first=provider->readTile(lod,result.second,*cancel);}catch(...){result.second=QStringLiteral("RP_TILE_DECODE_OR_MEMORY_ERROR");}return result;}));
    }
    if(!m_failed.empty())m_status=QStringLiteral("Error de datos: ")+m_failed.constBegin().value();
    else if(m_renderTiles.empty())m_status=m_jobs.empty()?QStringLiteral("Sin contenido en esta vista"):QStringLiteral("Cargando nodos…");
    else m_status=m_jobs.empty()?m_scene->title:QStringLiteral("Escena visible · refinando LOD…");
}
inge::rp::Schedule RetroplasmaController::chooseTiles(const QHash<QString,std::shared_ptr<const inge::rp::LoadedTile>> &resident)const{
    return m_scene->planetary?inge::rp::RetroplasmaTileScheduler::selectPlanet(*m_scene,viewProjection(),m_camera.eye(),m_height,resident,QString::number(m_generation)):inge::rp::RetroplasmaTileScheduler::select(*m_scene,viewProjection(),m_camera.eye(),m_height,resident,QString::number(m_generation));
}
void RetroplasmaController::trimCache(const QSet<QString> &protectedKeys){
    std::size_t bytes=0;for(const auto &entry:m_cache)bytes+=entry.tile->bytes;
    while(bytes>CacheLimit){auto candidate=m_cache.end();for(auto it=m_cache.begin();it!=m_cache.end();++it)if(!protectedKeys.contains(it.key())&&(candidate==m_cache.end()||it.value().used<candidate.value().used))candidate=it;if(candidate==m_cache.end()){m_status=QStringLiteral("RP_VISIBLE_CPU_CACHE_LIMIT");break;}bytes-=candidate.value().tile->bytes;m_cache.erase(candidate);}
}
void RetroplasmaController::orbit(double dx,double dy){if(m_active&&std::isfinite(dx)&&std::isfinite(dy))m_camera.orbit(-dx*0.006,dy*0.006);}
void RetroplasmaController::pan(double dx,double dy){if(m_active)m_camera.pan(-dx,dy);}
void RetroplasmaController::zoom(double scale){if(m_active&&std::isfinite(scale)&&scale>0)m_camera.zoom(1/scale);}
void RetroplasmaController::rotateView(double radians){if(m_active)m_camera.rotateHeading(radians);}
bool RetroplasmaController::goTo(double latitude,double longitude,double altitude){
    if(!m_active||!std::isfinite(latitude)||!std::isfinite(longitude)||!std::isfinite(altitude)||std::abs(latitude)>90||std::abs(longitude)>180||std::abs(altitude)>100000)return false;
    if(!m_scene){m_pendingTarget=inge::rp::GeoPoint{latitude,longitude,altitude};return true;}
    if(m_scene->planetary)m_camera.goToGeographic({latitude,longitude,altitude});else m_camera.goTo(inge::rp::enuToRender(inge::rp::ecefToEnu(inge::rp::geodeticToEcef({latitude,longitude,altitude}),m_scene->origin)));emit renderChanged();return true;
}
bool RetroplasmaController::command(const QString &name){
    if(!m_active)return false;
    if(name==QLatin1String("navigation")){m_navigationMode=!m_navigationMode;emit changed();return true;}
    if(!m_scene)return false;
    if(m_scene->planetary&&(name==QLatin1String("southAmerica")||name==QLatin1String("peru")||name==QLatin1String("lima"))){
        if(name==QLatin1String("southAmerica"))m_camera.goToGeographic({-15,-60,0},6500000);
        else if(name==QLatin1String("peru"))m_camera.goToGeographic({-9.2,-75,0},2800000);
        else m_camera.goToGeographic({-12.0464,-77.0428,153.0},120000);
        emit renderChanged();return true;
    }
    if(name==QLatin1String("zoomIn"))m_camera.zoom(0.75);else if(name==QLatin1String("zoomOut"))m_camera.zoom(1.333333);
    else if(name==QLatin1String("rotateLeft"))m_camera.orbit(-0.25,0);else if(name==QLatin1String("rotateRight"))m_camera.orbit(0.25,0);
    else if(name==QLatin1String("tiltUp"))m_camera.orbit(0,0.15);else if(name==QLatin1String("tiltDown"))m_camera.orbit(0,-0.15);
    else if(name==QLatin1String("panLeft"))m_camera.pan(-50,0);else if(name==QLatin1String("panRight"))m_camera.pan(50,0);
    else if(name==QLatin1String("panUp")||name==QLatin1String("forward"))m_camera.pan(0,50);else if(name==QLatin1String("panDown")||name==QLatin1String("backward"))m_camera.pan(0,-50);
    else if(name==QLatin1String("reset")){if(m_scene->planetary)m_camera.resetPlanet();else m_camera.reset(m_scene->bounds);}else if(name==QLatin1String("north"))m_camera.north();else return false;
    emit renderChanged();return true;
}
QString RetroplasmaController::coordinates()const{if(!m_scene)return {};auto point=m_scene->planetary?m_camera.planetTarget():inge::rp::ecefToGeodetic(inge::rp::enuToEcef(inge::rp::renderToEnu(m_camera.pose().focus),m_scene->origin));return QStringLiteral("%1°, %2° · objetivo %3 m · cámara %4 m").arg(point.latitude,0,'f',6).arg(point.longitude,0,'f',6).arg(point.altitude,0,'f',1).arg(m_camera.pose().distance,0,'f',1);}
QString RetroplasmaController::sourceName()const{
    if(!m_scene)return {};if(!m_scene->planetary)return m_scene->source;
    double finest=19568;int hls=0,coverage=0;QString firstDate,lastDate;for(const auto &entry:m_renderTiles){if(entry.tile->coveragePercent>0)finest=std::min(finest,entry.tile->resolutionMetres);if(entry.tile->source.contains(QLatin1String("HLS"))){++hls;coverage+=entry.tile->coveragePercent;if(entry.tile->coveragePercent>0){auto date=entry.tile->acquisitionDate;if(firstDate.isEmpty()||date<firstDate)firstDate=date;if(lastDate.isEmpty()||date>lastDate)lastDate=date;}}}
    return m_scene->source+QStringLiteral("\nBase mundial incorporada: ~19.6 km/píxel; Blue Marble GIBS: 500 m nativos.\nResolución más fina cargada: ~%1 m/píxel.").arg(finest,0,'f',0)
        +(m_scene->imagery==QLatin1String("landsat")?QStringLiteral(" HLS: 30 m nativos, cobertura parcial/nubes; %1% de píxeles con datos en tiles HLS cargados.").arg(hls?coverage/hls:0):QString())
        +(firstDate.isEmpty()?QString():QStringLiteral(" Fechas cargadas: %1 — %2.").arg(firstDate,lastDate))
        +QStringLiteral(" Zoom mínimo de cámara: 40 km; no detalle urbano submétrico.");
}
QVariantMap RetroplasmaController::metrics()const{std::lock_guard lock(m_mailbox->mutex);auto &m=m_mailbox->value;std::size_t cpu=0;for(const auto &entry:m_cache)cpu+=entry.tile->bytes;return {{QStringLiteral("fps"),m_fps},{QStringLiteral("frameMs"),m_frameMs},{QStringLiteral("cpuRecordMs"),m.cpuRecordMs},{QStringLiteral("gpuMiB"),double(m.gpuBytes)/1048576},{QStringLiteral("cpuMiB"),double(cpu)/1048576},{QStringLiteral("meshes"),m.meshes},{QStringLiteral("triangles"),m.triangles},{QStringLiteral("textures"),m.textures},{QStringLiteral("pending"),m_jobs.size()},{QStringLiteral("decodeErrors"),m_failed.size()},{QStringLiteral("renderError"),m.error},{QStringLiteral("backend"),m.backend}};}
