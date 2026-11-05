#include "CesiumRocktreeAssets.h"
#include "RetroplasmaRocktreeProvider.h"
#include <QBuffer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QtEndian>
#include <cstring>
#include <algorithm>
#include <QMutex>
#include <QMutexLocker>

namespace inge::earth {
using namespace inge::rp;
namespace {
QMutex sessionMutex;
std::shared_ptr<std::atomic_bool> sessionCancel=std::make_shared<std::atomic_bool>(true);
QJsonArray box(Bounds b){
    auto c=planetToEcef(center(b)),e=(b.maximum-b.minimum)*(.5*EarthRadius);
    return {c.x,c.y,c.z,e.x,0,0,0,e.z,0,0,0,e.y};
}
QJsonObject nodeJson(const rocktree::NodeInfo &node,const rocktree::Bulk &bulk,int limit,const QString &prefix){
    QJsonObject out{{"boundingVolume",QJsonObject{{"box",box(node.bounds)}}},{"geometricError",node.metresPerTexel*4},{"refine","REPLACE"}};
    if(node.hasData())out["content"]=QJsonObject{{"uri",prefix+QStringLiteral("mesh/%1/%2/%3/%4/%5.b3dm").arg(node.path).arg(node.epoch).arg(node.textureFormat).arg(node.useImageryEpoch?1:0).arg(node.imageryEpoch)}};
    QJsonArray children;
    if(node.hasChildren()&&node.path.size()<limit){
        if(node.hasBulk())children.append(QJsonObject{{"boundingVolume",QJsonObject{{"box",box(node.bounds)}}},{"geometricError",node.metresPerTexel*4},
            {"content",QJsonObject{{"uri",prefix+QStringLiteral("bulk/%1/%2.json").arg(node.path).arg(node.bulkEpoch)}}}});
        else for(int i=0;i<8;++i){auto it=bulk.nodes.constFind(node.path+QChar('0'+i));if(it!=bulk.nodes.cend())children.append(nodeJson(it.value(),bulk,limit,prefix));}
    }
    if(!children.empty())out["children"]=children;else out["geometricError"]=0;
    return out;
}
QByteArray tileset(const rocktree::Bulk &bulk,int limit){
    const QString prefix=QStringLiteral("/earth-data/p%1/").arg(limit);QJsonArray children;
    for(int i=0;i<8;++i){auto it=bulk.nodes.constFind(bulk.path+QChar('0'+i));if(it!=bulk.nodes.cend())children.append(nodeJson(it.value(),bulk,limit,prefix));}
    QJsonObject root{{"boundingVolume",QJsonObject{{"sphere",QJsonArray{0,0,0,15000000}}}},{"geometricError",1e7},{"refine","REPLACE"},{"children",children}};
    return QJsonDocument(QJsonObject{{"asset",QJsonObject{{"version","1.0"},{"copyright","Google Earth / respective imagery providers"}}},{"geometricError",1e8},{"root",root}}).toJson(QJsonDocument::Compact);
}
void word(QByteArray &out,quint32 value){value=qToLittleEndian(value);out.append(reinterpret_cast<const char *>(&value),4);}
void pad(QByteArray &out,int alignment,char value='\0'){while(out.size()%alignment)out.append(value);}
QByteArray b3dm(const LoadedTile &tile,QString &error){
    QByteArray binary;QJsonArray views,accessors,images,textures,materials,meshes,nodes;
    const auto origin=tile.parts.front()->origin;
    auto view=[&](const QByteArray &bytes,int target=0){pad(binary,4);int offset=int(binary.size());binary+=bytes;QJsonObject object{{"buffer",0},{"byteOffset",offset},{"byteLength",bytes.size()}};
        if(target)object["target"]=target;views.append(object);return views.size()-1;};
    auto floats=[](const std::vector<float> &values){QByteArray bytes;bytes.reserve(qsizetype(values.size()*4));for(float v:values){quint32 bits;std::memcpy(&bits,&v,4);word(bytes,bits);}return bytes;};
    for(const auto &part:tile.parts){
        const auto &g=part->geometry;std::vector<float> positions,normals,uv;positions.reserve(g.vertices.size()*3);normals.reserve(g.vertices.size()*3);uv.reserve(g.vertices.size()*2);
        Vec3 low{1e20,1e20,1e20},high{-1e20,-1e20,-1e20};
        if(part->localPositions.size()!=g.vertices.size()*3){error="CESIUM_RTC_POSITIONS_INVALID";return {};}
        for(const auto &v:g.vertices){
            const auto *relative=part->localPositions.data()+std::size_t(&v-g.vertices.data())*3;
            auto point=Vec3{relative[0],relative[1],relative[2]}+(part->origin-origin);point=point*EarthRadius;
            positions.insert(positions.end(),{float(point.x),float(point.y),float(point.z)});normals.insert(normals.end(),{v.normal[0],v.normal[1],v.normal[2]});uv.insert(uv.end(),{v.uv[0],1-v.uv[1]});
            low={std::min(low.x,point.x),std::min(low.y,point.y),std::min(low.z,point.z)};high={std::max(high.x,point.x),std::max(high.y,point.y),std::max(high.z,point.z)};
        }
        int base=int(accessors.size());auto positionView=view(floats(positions),34962),normalView=view(floats(normals),34962),uvView=view(floats(uv),34962);
        accessors.append(QJsonObject{{"bufferView",positionView},{"componentType",5126},{"count",qint64(g.vertices.size())},{"type","VEC3"},{"min",QJsonArray{low.x,low.y,low.z}},{"max",QJsonArray{high.x,high.y,high.z}}});
        accessors.append(QJsonObject{{"bufferView",normalView},{"componentType",5126},{"count",qint64(g.vertices.size())},{"type","VEC3"}});
        accessors.append(QJsonObject{{"bufferView",uvView},{"componentType",5126},{"count",qint64(g.vertices.size())},{"type","VEC2"}});
        QByteArray indices;for(auto index:g.indices)word(indices,index);
        accessors.append(QJsonObject{{"bufferView",view(indices,34963)},{"componentType",5125},{"count",qint64(g.indices.size())},{"type","SCALAR"}});
        QByteArray png;QBuffer buffer(&png);buffer.open(QIODevice::WriteOnly);if(!part->texture.save(&buffer,"PNG")){error="CESIUM_TEXTURE_ENCODING_FAILED";return {};}
        const int texture=int(textures.size());images.append(QJsonObject{{"bufferView",view(png)},{"mimeType","image/png"}});textures.append(QJsonObject{{"source",texture},{"sampler",0}});
        materials.append(QJsonObject{{"pbrMetallicRoughness",QJsonObject{{"baseColorTexture",QJsonObject{{"index",texture}}},{"metallicFactor",0},{"roughnessFactor",1}}},{"extensions",QJsonObject{{"KHR_materials_unlit",QJsonObject{}}}}});
        meshes.append(QJsonObject{{"primitives",QJsonArray{QJsonObject{{"attributes",QJsonObject{{"POSITION",base},{"NORMAL",base+1},{"TEXCOORD_0",base+2}}},{"indices",base+3},{"material",texture}}}}});
        nodes.append(QJsonObject{{"mesh",texture}});
        if(binary.size()>16*1024*1024){error="CESIUM_CONTENT_MEMORY_LIMIT";return {};}
    }
    QJsonArray nodeIndices;for(int i=0;i<nodes.size();++i)nodeIndices.append(i);
    QJsonObject model{{"asset",QJsonObject{{"version","2.0"}}},{"extensionsUsed",QJsonArray{"KHR_materials_unlit"}},{"scene",0},{"scenes",QJsonArray{QJsonObject{{"nodes",nodeIndices}}}},{"nodes",nodes},{"meshes",meshes},{"accessors",accessors},{"bufferViews",views},{"buffers",QJsonArray{QJsonObject{{"byteLength",binary.size()}}}},{"images",images},{"textures",textures},{"samplers",QJsonArray{QJsonObject{{"wrapS",33071},{"wrapT",33071},{"minFilter",9729},{"magFilter",9729}}}},{"materials",materials}};
    QByteArray json=QJsonDocument(model).toJson(QJsonDocument::Compact);pad(json,4,' ');pad(binary,4);
    // Align the embedded GLB and the enclosing 3D Tile to eight bytes.
    // Use JSON whitespace; BIN padding may exceed buffer.byteLength by at most 3.
    if((28+json.size()+binary.size())%8)json.append("    ");
    QByteArray glb;glb.append("glTF",4);word(glb,2);word(glb,quint32(12+8+json.size()+8+binary.size()));word(glb,quint32(json.size()));word(glb,0x4E4F534A);glb+=json;word(glb,quint32(binary.size()));word(glb,0x004E4942);glb+=binary;
    const auto rtc=planetToEcef(origin);QByteArray feature=QJsonDocument(QJsonObject{{"BATCH_LENGTH",0},{"RTC_CENTER",QJsonArray{rtc.x,rtc.y,rtc.z}}}).toJson(QJsonDocument::Compact);
    while((28+feature.size())%8)feature.append(' ');
    QByteArray out("b3dm",4);word(out,1);word(out,quint32(28+feature.size()+glb.size()));word(out,quint32(feature.size()));word(out,0);word(out,0);word(out,0);out+=feature;out+=glb;return out;
}
}
void setAssetSession(bool active){QMutexLocker lock(&sessionMutex);sessionCancel->store(true);sessionCancel=std::make_shared<std::atomic_bool>(!active);}
QByteArray rocktreeAsset(const QString &path){
    std::shared_ptr<std::atomic_bool> token;{QMutexLocker lock(&sessionMutex);token=sessionCancel;}
    QString error;const auto &cancel=*token;RocktreeSceneProvider provider;QByteArray result;
    try{
        auto match=QRegularExpression(QStringLiteral("^p(1[0-9]|20|21)/(root\\.json|bulk/([0-7]{4,20})/([0-9]{1,10})\\.json|mesh/([0-7]{1,21})/([0-9]{1,10})/([126])/([01])/([0-9]{1,10})\\.b3dm)$")).match(path);
        if(!match.hasMatch())error="CESIUM_ASSET_PATH_INVALID";
        else{
            const int limit=match.captured(1).toInt();
            if(match.captured(2)=="root.json"){auto scene=provider.readScene(QUrl("inge-earth://global"),error,cancel);if(scene)result=tileset(*scene->rocktreeRoot,limit);}
            else if(!match.captured(3).isEmpty()){Lod lod;lod.planetary=true;lod.layer="rocktree-bulk";lod.meshPath=match.captured(3);lod.epoch=match.captured(4).toUInt();auto tile=provider.readTile(lod,error,cancel);if(tile)result=tileset(*tile->rocktreeBulk,limit);}
            else{Lod lod;lod.planetary=true;lod.layer="rocktree-node";lod.meshPath=match.captured(5);lod.epoch=match.captured(6).toUInt();lod.textureFormat=match.captured(7).toInt();lod.useImageryEpoch=match.captured(8)=="1";lod.imageryEpoch=match.captured(9).toUInt();auto tile=provider.readTile(lod,error,cancel);if(tile)result=b3dm(*tile,error);}
        }
    }catch(...){error="CESIUM_ASSET_DECODE_OR_MEMORY_ERROR";}
    return !result.isEmpty()?result:QJsonDocument(QJsonObject{{"error",error.isEmpty()?QStringLiteral("CESIUM_ASSET_EMPTY"):error}}).toJson(QJsonDocument::Compact);
}
}
