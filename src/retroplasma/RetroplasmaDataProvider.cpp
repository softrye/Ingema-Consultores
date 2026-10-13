#include "RetroplasmaDataProvider.h"
#include "RetroplasmaTextureDecoder.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QImageReader>
#include <QHash>
#include <functional>
#include <limits>

namespace inge::rp {
namespace {
QString resourcePath(const QUrl &url){return url.scheme()==QLatin1String("qrc")?QStringLiteral(":")+url.path():url.isLocalFile()?url.toLocalFile():QString();}
QString resolve(const QString &base,const QString &relative){
    const QString normalized=QDir::fromNativeSeparators(relative);
    if(normalized.isEmpty()||normalized.startsWith('/')||normalized.contains(':')||normalized.split('/').contains(QStringLiteral("..")))return {};
    return QDir(base).filePath(normalized);
}
QByteArray readBounded(const QString &path,qint64 limit,QString &error){QFile file(path);if(!file.open(QIODevice::ReadOnly)){error=QStringLiteral("RP_FILE_UNAVAILABLE");return {};}if(file.size()<=0||file.size()>limit){error=QStringLiteral("RP_FILE_BYTE_LIMIT");return {};}return file.readAll();}
bool number(const QJsonValue &v,double &out){if(!v.isDouble())return false;out=v.toDouble();return std::isfinite(out);}
bool bounds(const QJsonValue &value,Bounds &out){auto array=value.toArray();if(array.size()!=6)return false;double a[6];for(int i=0;i<6;++i)if(!number(array[i],a[i])||std::abs(a[i])>100000)return false;if(a[0]>a[3]||a[1]>a[4]||a[2]>a[5])return false;out={{a[0],a[2],-a[4]},{a[3],a[5],-a[1]}};return true;}
bool contains(Bounds outer,Bounds inner){constexpr double tolerance=0.02;return inner.minimum.x>=outer.minimum.x-tolerance&&inner.minimum.y>=outer.minimum.y-tolerance&&inner.minimum.z>=outer.minimum.z-tolerance&&inner.maximum.x<=outer.maximum.x+tolerance&&inner.maximum.y<=outer.maximum.y+tolerance&&inner.maximum.z<=outer.maximum.z+tolerance;}
}
std::shared_ptr<const Scene> LocalSceneProvider::readScene(const QUrl &url,QString &error,const std::atomic_bool &cancel)const{
    error.clear();auto fail=[&](const char *code)->std::shared_ptr<const Scene>{error=QLatin1String(code);return {};};
    const QString path=resourcePath(url);if(path.isEmpty())return fail("RP_LOCAL_OR_QRC_SCENE_REQUIRED");
    QByteArray bytes=readBounded(path,1024*1024,error);if(!error.isEmpty())return {};
    if(cancel.load())return fail("CANCELLED");
    QJsonParseError parse;auto document=QJsonDocument::fromJson(bytes,&parse);if(parse.error!=QJsonParseError::NoError||!document.isObject())return fail("RP_MANIFEST_JSON_INVALID");
    auto object=document.object();if(object.value(QStringLiteral("format")).toString()!=QLatin1String("inge-retroplasma-scene-v1"))return fail("RP_SCENE_FORMAT_UNSUPPORTED");
    auto scene=std::make_shared<Scene>();scene->title=object.value(QStringLiteral("title")).toString();scene->source=object.value(QStringLiteral("source")).toString();scene->license=object.value(QStringLiteral("license")).toString();scene->basePath=QFileInfo(path).path();
    if(scene->source.isEmpty()||scene->license.isEmpty())return fail("RP_CONTENT_PROVENANCE_REQUIRED");
    auto origin=object.value(QStringLiteral("origin")).toObject();
    if(!number(origin.value(QStringLiteral("latitude")),scene->origin.latitude)||!number(origin.value(QStringLiteral("longitude")),scene->origin.longitude)||!number(origin.value(QStringLiteral("altitude")),scene->origin.altitude)||std::abs(scene->origin.latitude)>90||std::abs(scene->origin.longitude)>180||std::abs(scene->origin.altitude)>100000)return fail("RP_ORIGIN_INVALID");
    auto nodes=object.value(QStringLiteral("nodes")).toArray();if(nodes.isEmpty()||nodes.size()>128)return fail("RP_NODE_LIMIT");
    QHash<QString,int> ids;std::vector<QString> parents;
    for(auto value:nodes){
        if(cancel.load())return fail("CANCELLED");
        auto nodeObject=value.toObject();Node node;node.id=nodeObject.value(QStringLiteral("id")).toString();
        if(node.id.isEmpty()||node.id.size()>128||ids.contains(node.id)||!bounds(nodeObject.value(QStringLiteral("bounds")),node.bounds))return fail("RP_NODE_ID_OR_BOUNDS_INVALID");
        auto lods=nodeObject.value(QStringLiteral("lods")).toArray();if(lods.isEmpty()||lods.size()>6)return fail("RP_LOD_LIMIT");
        double previous=std::numeric_limits<double>::infinity();
        for(auto lodValue:lods){auto data=lodValue.toObject();Lod lod;
            if(!number(data.value(QStringLiteral("error")),lod.geometricError)||lod.geometricError<0||lod.geometricError>=previous)return fail("RP_LOD_ERROR_ORDER_INVALID");
            previous=lod.geometricError;lod.meshPath=resolve(scene->basePath,data.value(QStringLiteral("mesh")).toString());lod.texturePath=resolve(scene->basePath,data.value(QStringLiteral("texture")).toString());
            if(lod.meshPath.isEmpty()||lod.texturePath.isEmpty())return fail("RP_ASSET_PATH_INVALID");node.lods.push_back(lod);
        }
        ids.insert(node.id,int(scene->nodes.size()));parents.push_back(nodeObject.value(QStringLiteral("parent")).toString());scene->nodes.push_back(std::move(node));
    }
    for(std::size_t i=0;i<scene->nodes.size();++i){
        if(parents[i].isEmpty())scene->roots.push_back(int(i));
        else {if(!ids.contains(parents[i]))return fail("RP_PARENT_NOT_FOUND");int parent=ids.value(parents[i]);if(parent==int(i)||!contains(scene->nodes[parent].bounds,scene->nodes[i].bounds))return fail("RP_PARENT_BOUNDS_INVALID");scene->nodes[i].parent=parent;scene->nodes[parent].children.push_back(int(i));}
    }
    std::vector<int> state(scene->nodes.size(),0);std::function<bool(int)> visit=[&](int index){if(state[index]==1)return false;if(state[index]==2)return true;state[index]=1;for(int child:scene->nodes[index].children)if(!visit(child))return false;state[index]=2;return true;};
    for(int i=0;i<int(scene->nodes.size());++i)if(!visit(i))return fail("RP_SPATIAL_CYCLE");
    if(scene->roots.empty())return fail("RP_NO_ROOT_NODES");
    scene->bounds=scene->nodes[scene->roots[0]].bounds;
    for(int root:scene->roots){auto b=scene->nodes[root].bounds;scene->bounds.minimum={std::min(scene->bounds.minimum.x,b.minimum.x),std::min(scene->bounds.minimum.y,b.minimum.y),std::min(scene->bounds.minimum.z,b.minimum.z)};scene->bounds.maximum={std::max(scene->bounds.maximum.x,b.maximum.x),std::max(scene->bounds.maximum.y,b.maximum.y),std::max(scene->bounds.maximum.z,b.maximum.z)};}
    return scene;
}
std::shared_ptr<const LoadedTile> LocalSceneProvider::readTile(const Lod &lod,QString &error,const std::atomic_bool &cancel)const{
    error.clear();auto tile=std::make_shared<LoadedTile>();auto bytes=readBounded(lod.meshPath,32*1024*1024,error);if(!error.isEmpty())return {};
    std::string geometryError;if(!decodeObj(bytes.toStdString(),tile->geometry,geometryError,&cancel)){error=QString::fromStdString(geometryError);return {};}
    if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    if(QFileInfo(lod.texturePath).suffix().compare(QStringLiteral("dds"),Qt::CaseInsensitive)==0){
        auto dds=readBounded(lod.texturePath,16*1024*1024,error);if(!error.isEmpty())return {};
        auto u32=[&](int at)->quint32{const auto *p=reinterpret_cast<const unsigned char *>(dds.constData()+at);return p[0]|quint32(p[1])<<8|quint32(p[2])<<16|quint32(p[3])<<24;};
        if(dds.size()<128||dds.left(4)!="DDS "||u32(4)!=124||u32(76)!=32||dds.mid(84,4)!="DXT1"||u32(12)>1024||u32(16)>1024){error=QStringLiteral("RP_DDS_BC1_FORMAT_OR_SIZE_UNSUPPORTED");return {};}
        std::vector<unsigned char> block(dds.constData()+128,dds.constData()+dds.size()),rgba;std::string textureError;
        if(!decodeBc1(block,int(u32(16)),int(u32(12)),rgba,textureError)){error=QString::fromStdString(textureError);return {};}
        tile->texture=QImage(rgba.data(),int(u32(16)),int(u32(12)),QImage::Format_RGBA8888).copy();
    }else{
        QFile texture(lod.texturePath);if(!texture.open(QIODevice::ReadOnly)||texture.size()>16*1024*1024){error=QStringLiteral("RP_TEXTURE_FILE_LIMIT");return {};}
        QImageReader reader(&texture);auto size=reader.size();
        if(!size.isValid()||qint64(size.width())*size.height()>16*1024*1024){error=QStringLiteral("RP_TEXTURE_DIMENSION_LIMIT");return {};}
        if(size.width()>1024||size.height()>1024)reader.setScaledSize(size.scaled(1024,1024,Qt::KeepAspectRatio));
        tile->texture=reader.read().convertToFormat(QImage::Format_RGBA8888);
        if(tile->texture.width()>1024||tile->texture.height()>1024)tile->texture=tile->texture.scaled(1024,1024,Qt::KeepAspectRatio,Qt::SmoothTransformation);
    }
    if(tile->texture.isNull()){error=QStringLiteral("RP_TEXTURE_DECODE_FAILED");return {};}
    if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    tile->bytes=tile->geometry.vertices.size()*sizeof(Vertex)+tile->geometry.indices.size()*sizeof(std::uint32_t)+std::size_t(tile->texture.sizeInBytes());
    if(tile->bytes>32*1024*1024){error=QStringLiteral("RP_TILE_MEMORY_LIMIT");return {};}
    return tile;
}
}
