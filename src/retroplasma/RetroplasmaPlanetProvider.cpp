#include "RetroplasmaPlanetProvider.h"
#include <QUrlQuery>
#include <QDate>
#include <QImageReader>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkDiskCache>
#include <QStandardPaths>
#include <QEventLoop>
#include <QTimer>
#include <QBuffer>
#include <QMutexLocker>
#include <QElapsedTimer>
#include <algorithm>

namespace inge::rp {
std::shared_ptr<const Scene> PlanetSceneProvider::readScene(const QUrl &url,QString &error,const std::atomic_bool &cancel)const{
    if(url.scheme()!=QLatin1String("inge-earth"))return m_local.readScene(url,error,cancel);
    error.clear();if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    auto scene=std::make_shared<Scene>();scene->planetary=true;scene->title=QStringLiteral("Tierra · WGS84");
    QUrlQuery query(url);scene->imagery=query.queryItemValue(QStringLiteral("layer"));
    if(scene->imagery.isEmpty())scene->imagery=QStringLiteral("sentinel");
    if(scene->imagery!=QLatin1String("blue-marble")&&scene->imagery!=QLatin1String("landsat")&&scene->imagery!=QLatin1String("sentinel")){error=QStringLiteral("RP_IMAGERY_LAYER_UNSUPPORTED");return {};}
    scene->date=query.queryItemValue(QStringLiteral("date"));
    if(scene->imagery==QLatin1String("landsat")){
        if(scene->date.isEmpty())scene->date=QStringLiteral("auto");
        auto date=QDate::fromString(scene->date,Qt::ISODate);
        if(scene->date!=QLatin1String("auto")&&(!date.isValid()||date<QDate(2013,4,11)||date>QDate::currentDate())){error=QStringLiteral("RP_IMAGERY_DATE_INVALID");return {};}
    }
    scene->source=QStringLiteral("NASA Earth Observatory / Reto Stöckli · Blue Marble · NASA EOSDIS GIBS");
    if(scene->imagery==QLatin1String("landsat"))scene->source+=QStringLiteral(" · NASA/USGS Landsat HLS L30 · ")+(scene->date==QLatin1String("auto")?QStringLiteral("adquisición reciente por sector"):scene->date);
    if(scene->imagery==QLatin1String("sentinel"))scene->source+=QStringLiteral(" · EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016) · CC BY 4.0");
    scene->license=QStringLiteral("NASA imagery usage guidelines; USGS Landsat public domain; attribution, no endorsement");
    scene->bounds={{-1.001,-1.001,-1.001},{1.001,1.001,1.001}};
    // 32 permanent overview segments ensure all longitudes and both poles are present offline.
    for(int y=0;y<4;++y)for(int x=0;x<8;++x){
        Lod lod;lod.planetary=true;lod.layer=QStringLiteral("overview");lod.sector={-180+x*45.0,-90+y*45.0,-135+x*45.0,-45+y*45.0};
        Node node;node.id=QStringLiteral("earth/%1/%2").arg(y).arg(x);node.bounds=planetBounds(lod.sector);node.lods.push_back(lod);
        scene->roots.push_back(int(scene->nodes.size()));scene->nodes.push_back(std::move(node));
    }
    return scene;
}
QImage PlanetSceneProvider::overview(QString &error)const{
    QMutexLocker lock(&m_imageMutex);
    if(m_overview.isNull()){
        QImageReader reader(QStringLiteral(":/inge/retroplasma/earth/blue-marble-global-2048.jpg"));
        m_overview=reader.read().convertToFormat(QImage::Format_RGBA8888);
        if(m_overview.size()!=QSize(2048,1024)){m_overview={};error=QStringLiteral("RP_NASA_OVERVIEW_RESOURCE_INVALID");}
    }
    return m_overview;
}
QUrl PlanetSceneProvider::imageryUrl(const Lod &lod){
    if(lod.layer==QLatin1String("sentinel")){
        QUrl url(QStringLiteral("https://tiles.maps.eox.at/wms"));QUrlQuery q;
        q.addQueryItem("SERVICE","WMS");q.addQueryItem("REQUEST","GetMap");q.addQueryItem("VERSION","1.1.1");
        q.addQueryItem("LAYERS","s2cloudless");q.addQueryItem("STYLES","");q.addQueryItem("SRS","EPSG:4326");
        q.addQueryItem("BBOX",QStringLiteral("%1,%2,%3,%4").arg(lod.sector.west,0,'f',10).arg(lod.sector.south,0,'f',10).arg(lod.sector.east,0,'f',10).arg(lod.sector.north,0,'f',10));
        q.addQueryItem("WIDTH","256");q.addQueryItem("HEIGHT","256");q.addQueryItem("FORMAT","image/jpeg");url.setQuery(q);return url;
    }
    QUrl url(QStringLiteral("https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"));QUrlQuery q;
    const bool hls=lod.layer==QLatin1String("landsat");
    q.addQueryItem(QStringLiteral("SERVICE"),QStringLiteral("WMS"));q.addQueryItem(QStringLiteral("REQUEST"),QStringLiteral("GetMap"));q.addQueryItem(QStringLiteral("VERSION"),QStringLiteral("1.3.0"));
    q.addQueryItem(QStringLiteral("LAYERS"),hls?QStringLiteral("HLS_L30_Nadir_BRDF_Adjusted_Reflectance"):QStringLiteral("BlueMarble_NextGeneration"));
    q.addQueryItem(QStringLiteral("STYLES"),QStringLiteral("default"));q.addQueryItem(QStringLiteral("CRS"),QStringLiteral("EPSG:4326"));
    // WMS 1.3.0 EPSG:4326 axis order is latitude, longitude (south,west,north,east).
    q.addQueryItem(QStringLiteral("BBOX"),QStringLiteral("%1,%2,%3,%4").arg(lod.sector.south,0,'f',10).arg(lod.sector.west,0,'f',10).arg(lod.sector.north,0,'f',10).arg(lod.sector.east,0,'f',10));
    q.addQueryItem(QStringLiteral("WIDTH"),QStringLiteral("256"));q.addQueryItem(QStringLiteral("HEIGHT"),QStringLiteral("256"));q.addQueryItem(QStringLiteral("FORMAT"),hls?QStringLiteral("image/png"):QStringLiteral("image/jpeg"));
    if(hls){q.addQueryItem(QStringLiteral("TIME"),lod.date);q.addQueryItem(QStringLiteral("TRANSPARENT"),QStringLiteral("TRUE"));}
    url.setQuery(q);return url;
}
std::shared_ptr<const LoadedTile> PlanetSceneProvider::readTile(const Lod &lod,QString &error,const std::atomic_bool &cancel)const{
    if(!lod.planetary)return m_local.readTile(lod,error,cancel);
    error.clear();auto tile=std::make_shared<LoadedTile>();
    if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    if(lod.layer==QLatin1String("overview")){
        auto image=overview(error);if(image.isNull())return {};
        int x=qRound((lod.sector.west+180)/360*image.width()),y=qRound((90-lod.sector.north)/180*image.height());
        int width=qRound((lod.sector.east-lod.sector.west)/360*image.width()),height=qRound((lod.sector.north-lod.sector.south)/180*image.height());
        tile->texture=image.copy(x,y,width,height);tile->source=QStringLiteral("NASA Blue Marble incorporada");tile->resolutionMetres=19568;
    }else{
        if(lod.layer!=QLatin1String("blue-marble")&&lod.layer!=QLatin1String("landsat")&&lod.layer!=QLatin1String("sentinel")){error=QStringLiteral("RP_IMAGERY_LAYER_UNSUPPORTED");return {};}
        QMutexLocker networkLock(&m_networkMutex); // One disk cache writer across the two bounded workers.
        if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
        // Each manager/reply belongs exclusively to this worker thread. No GUI-thread network wait.
        QNetworkAccessManager manager;auto *cache=new QNetworkDiskCache(&manager);
        cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)+QStringLiteral("/earth-gibs"));cache->setMaximumCacheSize(128*1024*1024);manager.setCache(cache);
        bool automatic=lod.layer==QLatin1String("landsat")&&lod.date==QLatin1String("auto");
        QElapsedTimer searchClock;searchClock.start();
        for(int attempt=0;attempt<(automatic?16:1);++attempt){
        if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
        if(searchClock.elapsed()>30000)break;
        Lod candidate=lod;if(automatic)candidate.date=QDate::currentDate().addDays(-4-attempt).toString(Qt::ISODate);
        QNetworkRequest request(imageryUrl(candidate));request.setTransferTimeout(15000);request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);request.setRawHeader("User-Agent","InGePlus-Earth/1.0 (NASA-GIBS; EOX)");
        auto *reply=manager.get(request);reply->setReadBufferSize(4*1024*1024);QEventLoop loop;QTimer poll,deadline;poll.setInterval(50);deadline.setSingleShot(true);QByteArray payload;bool exceeded=false;
        QObject::connect(reply,&QNetworkReply::readyRead,&loop,[&](){payload+=reply->readAll();if(payload.size()>4*1024*1024){exceeded=true;reply->abort();}});
        QObject::connect(reply,&QNetworkReply::finished,&loop,&QEventLoop::quit);
        QObject::connect(&poll,&QTimer::timeout,&loop,[&](){if(cancel.load())reply->abort();});QObject::connect(&deadline,&QTimer::timeout,reply,&QNetworkReply::abort);poll.start();deadline.start(int(std::min<qint64>(15000,30000-searchClock.elapsed())));loop.exec();poll.stop();deadline.stop();payload+=reply->readAll();
        if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
        if(exceeded||payload.size()>4*1024*1024){error=QStringLiteral("RP_GIBS_RESPONSE_BYTE_LIMIT");return {};}
        if(reply->error()!=QNetworkReply::NoError||reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()!=200){error=QStringLiteral("RP_GIBS_NETWORK_OR_HTTP_ERROR");return {};}
        QBuffer buffer(&payload);buffer.open(QIODevice::ReadOnly);QImageReader reader(&buffer);
        if(reader.size()!=QSize(256,256)){error=QStringLiteral("RP_GIBS_TILE_SIZE_OR_FORMAT_INVALID");return {};}
        tile->texture=reader.read().convertToFormat(QImage::Format_RGBA8888);
        tile->source=lod.layer==QLatin1String("sentinel")?QStringLiteral("EOxCloudless / EOX · Sentinel 2016 · CC BY 4.0"):lod.layer==QLatin1String("landsat")?QStringLiteral("NASA/USGS HLS L30 · ")+candidate.date:QStringLiteral("NASA GIBS Blue Marble");
        if(lod.layer==QLatin1String("landsat"))tile->acquisitionDate=candidate.date;
        tile->resolutionMetres=std::max(lod.layer==QLatin1String("sentinel")?10.0:lod.layer==QLatin1String("landsat")?30.0:500.0,(lod.sector.east-lod.sector.west)*Radians*EarthRadius/256);
        if(lod.layer==QLatin1String("landsat")&&!tile->texture.isNull()){
            int covered=0;for(int y=0;y<256;++y){const auto *line=tile->texture.constScanLine(y);for(int x=0;x<256;++x)if(line[x*4+3]>=128)++covered;}
            tile->coveragePercent=covered*100/(256*256);
        }
        reply->deleteLater();
        if(!automatic||tile->coveragePercent>0)break;
        }
    }
    if(tile->texture.isNull()||cancel.load()){error=cancel.load()?QStringLiteral("CANCELLED"):QStringLiteral("RP_NASA_TEXTURE_INVALID");return {};}
    // Higher-detail shells are separated by metres to avoid coplanar z fighting with the permanent globe.
    tile->geometry=geometryFor(lod);
    if(tile->geometry.indices.empty()){error=QStringLiteral("RP_PLANET_SECTOR_INVALID");return {};}
    tile->bytes=tile->geometry.vertices.size()*sizeof(Vertex)+tile->geometry.indices.size()*sizeof(std::uint32_t)+std::size_t(tile->texture.sizeInBytes());return tile;
}
Geometry PlanetSceneProvider::geometryFor(const Lod &lod){
    // L0 must match the overview angular density; a coarser chord would be buried by depth-write.
    int steps=lod.layer==QLatin1String("overview")||lod.level==0?32:16;
    return planetMesh(lod.sector,steps,lod.layer==QLatin1String("overview")?0:60+lod.level);
}
}
