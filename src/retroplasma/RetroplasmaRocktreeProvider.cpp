#include "RetroplasmaRocktreeProvider.h"
#include <QEventLoop>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QTimer>
#include <QElapsedTimer>

namespace inge::rp {
namespace {
// QNetworkDiskCache has a single writer, including across replaced providers.
QMutex cacheMutex;
QByteArray fetch(const QUrl &url,QString &error,const std::atomic_bool &cancel){
    if(url.scheme()!=QLatin1String("https")||url.host()!=QLatin1String("kh.google.com")||!url.path().startsWith(QLatin1String("/rt/earth/"))){error=QStringLiteral("RP_ROCKTREE_URL_INVALID");return {};}
    // Wait cancelably rather than blocking a worker indefinitely on the cache lock.
    while(!cacheMutex.tryLock(50))if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    struct Unlock {~Unlock(){cacheMutex.unlock();}} unlock;
    if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    QNetworkAccessManager manager;auto *cache=new QNetworkDiskCache(&manager);
    cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)+QStringLiteral("/earth-rocktree"));
    cache->setMaximumCacheSize(128*1024*1024);manager.setCache(cache);
    QNetworkRequest request(url);request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
    // PlanetoidMetadata points to the current root epoch; only versioned packets
    // may reuse an immutable cache entry without checking the network.
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,url.path().endsWith(QLatin1String("/PlanetoidMetadata"))?QNetworkRequest::AlwaysNetwork:QNetworkRequest::PreferCache);
    auto *reply=manager.get(request);reply->setReadBufferSize(16*1024*1024+1);QEventLoop loop;QTimer guard;guard.setInterval(25);QElapsedTimer clock;clock.start();
    bool tooLarge=false,timedOut=false;
    QObject::connect(reply,&QNetworkReply::downloadProgress,&loop,[&](qint64 received,qint64 total){if(received>16*1024*1024||total>16*1024*1024){tooLarge=true;reply->abort();}});
    QObject::connect(reply,&QIODevice::readyRead,&loop,[&](){if(reply->bytesAvailable()>16*1024*1024){tooLarge=true;reply->abort();}});
    QObject::connect(&guard,&QTimer::timeout,&loop,[&](){if(cancel.load()||clock.elapsed()>20000){timedOut=!cancel.load();reply->abort();}});
    QObject::connect(reply,&QNetworkReply::finished,&loop,&QEventLoop::quit);guard.start();
    if(!reply->isFinished())loop.exec();guard.stop();
    const int http=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if(cancel.load())error=QStringLiteral("CANCELLED");
    else if(tooLarge)error=QStringLiteral("RP_ROCKTREE_RESPONSE_SIZE_LIMIT");
    else if(timedOut||reply->error()==QNetworkReply::TimeoutError)error=QStringLiteral("RP_ROCKTREE_TIMEOUT");
    else if(http!=200)error=QStringLiteral("RP_ROCKTREE_HTTP_%1").arg(http);
    else if(reply->error()!=QNetworkReply::NoError)error=QStringLiteral("RP_ROCKTREE_NETWORK_%1").arg(int(reply->error()));
    if(!error.isEmpty())return {};
    auto data=reply->read(16*1024*1024+1);
    if(data.isEmpty()||data.size()>16*1024*1024){error=QStringLiteral("RP_ROCKTREE_RESPONSE_EMPTY_OR_OVERSIZE");return {};}
    return data;
}
}
std::shared_ptr<const Scene> RocktreeSceneProvider::readScene(const QUrl &url,QString &error,const std::atomic_bool &cancel)const{
    error.clear();if(url.scheme()!=QLatin1String("inge-earth")){error=QStringLiteral("RP_ROCKTREE_SCENE_URL_INVALID");return {};}
    auto planet=fetch(QUrl(QStringLiteral("https://kh.google.com/rt/earth/PlanetoidMetadata")),error,cancel);if(!error.isEmpty())return {};
    quint32 epoch=0;double radius=0;if(!rocktree::decodePlanetoid(planet,epoch,radius,error))return {};
    auto bytes=fetch(rocktree::bulkUrl({},epoch),error,cancel);if(!error.isEmpty())return {};
    auto bulk=std::make_shared<rocktree::Bulk>();if(!rocktree::decodeBulk(bytes,{},epoch,*bulk,error))return {};
    auto scene=std::make_shared<Scene>();scene->planetary=true;scene->imagery=QStringLiteral("rocktree");
    scene->title=QStringLiteral("Google Earth · mallas 3D RockTree");scene->source=QStringLiteral("Google Earth / proveedores de imágenes · RockTree (interfaz no documentada)");
    scene->bounds={{-1.1,-1.1,-1.1},{1.1,1.1,1.1}};scene->rocktreeRoot=bulk;return scene;
}
std::shared_ptr<const LoadedTile> RocktreeSceneProvider::readTile(const Lod &lod,QString &error,const std::atomic_bool &cancel)const{
    error.clear();if(!lod.planetary||(lod.layer!=QLatin1String("rocktree-node")&&lod.layer!=QLatin1String("rocktree-bulk"))){error=QStringLiteral("RP_ROCKTREE_ASSET_INVALID");return {};}
    if(lod.layer==QLatin1String("rocktree-bulk")){
        auto bytes=fetch(rocktree::bulkUrl(lod.meshPath,lod.epoch),error,cancel);if(!error.isEmpty())return {};
        auto bulk=std::make_shared<rocktree::Bulk>();if(!rocktree::decodeBulk(bytes,lod.meshPath,lod.epoch,*bulk,error))return {};
        auto tile=std::make_shared<LoadedTile>();tile->rocktreeBulk=bulk;
        tile->bytes=std::size_t(bytes.size())+std::size_t(bulk->nodes.size())*(sizeof(rocktree::NodeInfo)+128);return tile;
    }
    rocktree::NodeInfo node;node.path=lod.meshPath;node.epoch=lod.epoch;node.imageryEpoch=lod.imageryEpoch;
    node.useImageryEpoch=lod.useImageryEpoch;node.textureFormat=lod.textureFormat;node.metresPerTexel=lod.geometricError;
    auto bytes=fetch(rocktree::nodeUrl(node),error,cancel);if(!error.isEmpty())return {};
    return rocktree::decodeNode(bytes,node,error,cancel);
}
}
