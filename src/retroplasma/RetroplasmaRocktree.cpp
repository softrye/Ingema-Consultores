#include "RetroplasmaRocktree.h"
#include "RetroplasmaTextureDecoder.h"
#include <QBuffer>
#include <QByteArrayView>
#include <QImageReader>
#include <QtEndian>
#include <algorithm>
#include <cstring>
#include <limits>

namespace inge::rp::rocktree {
namespace {
constexpr qsizetype PacketLimit=16*1024*1024;
struct Field {unsigned id=0,wire=0;quint64 value=0;QByteArrayView data;};
// Independent of generated protobuf code/Eigen. Implements the wire types used by
// third_party/rocktree.proto, including packed and unpacked numeric fields.
class Reader {
    QByteArrayView bytes;qsizetype pos=0;unsigned count=0;
public:
    bool good=true;
    explicit Reader(QByteArrayView value):bytes(value){if(value.size()>PacketLimit)good=false;}
    bool varint(quint64 &value){
        value=0;
        for(unsigned shift=0;shift<70;shift+=7){
            if(pos>=bytes.size())return good=false;
            const auto byte=quint8(bytes[pos++]);
            if(shift==63&&byte>1)return good=false;
            value|=quint64(byte&127)<<shift;
            if(!(byte&128))return true;
        }
        return good=false;
    }
    bool next(Field &field){
        if(!good||pos==bytes.size())return false;
        quint64 tag=0;if(++count>100000||!varint(tag)||!(tag>>3)||tag>>3>536870911)return good=false;
        field={};field.id=unsigned(tag>>3);field.wire=unsigned(tag&7);
        if(field.wire==0)return varint(field.value);
        quint64 length=0;
        if(field.wire==1)length=8;
        else if(field.wire==5)length=4;
        else if(field.wire==2){if(!varint(length))return false;}
        else return good=false;
        if(length>quint64(bytes.size()-pos))return good=false;
        field.data=bytes.sliced(pos,qsizetype(length));pos+=qsizetype(length);return true;
    }
    bool end()const{return good&&pos==bytes.size();}
};
bool fail(QString &error,const char *code){error=QLatin1String(code);return false;}
double number(const char *bytes,bool wide){
    if(wide){auto bits=qFromLittleEndian<quint64>(bytes);double value;std::memcpy(&value,&bits,8);return value;}
    auto bits=qFromLittleEndian<quint32>(bytes);float value;std::memcpy(&value,&bits,4);return value;
}
bool numbers(const Field &field,bool wide,std::vector<double> &out){
    const qsizetype size=wide?8:4;
    if(field.wire!=(wide?1u:5u)&&field.wire!=2)return false;
    if(field.data.size()%size||out.size()+std::size_t(field.data.size()/size)>1024)return false;
    for(qsizetype i=0;i<field.data.size();i+=size){double v=number(field.data.data()+i,wide);if(!std::isfinite(v))return false;out.push_back(v);}
    return true;
}
bool key(QByteArrayView data,QString &path,quint32 &epoch){
    Reader reader(data);Field f;bool haveEpoch=false;
    while(reader.next(f)){
        if(f.id==1){if(f.wire!=2||f.data.size()>24)return false;path=QString::fromLatin1(f.data.data(),f.data.size());}
        if(f.id==2){if(f.wire!=0||f.value<1||f.value>std::numeric_limits<quint32>::max())return false;epoch=quint32(f.value);haveEpoch=true;}
    }
    return reader.end()&&haveEpoch&&validPath(path,true);
}
bool obb(QByteArrayView bytes,Vec3 head,double metres,Bounds &bounds){
    if(bytes.size()!=15||!std::isfinite(metres)||metres<=0||metres>2e7)return false;
    const auto *p=bytes.data();
    const Vec3 origin{qFromLittleEndian<qint16>(p)*metres+head.x,qFromLittleEndian<qint16>(p+2)*metres+head.y,qFromLittleEndian<qint16>(p+4)*metres+head.z};
    const double ex=quint8(p[6])*metres,ey=quint8(p[7])*metres,ez=quint8(p[8])*metres;
    const double a=qFromLittleEndian<quint16>(p+9)*Pi/32768,b=qFromLittleEndian<quint16>(p+11)*Pi/65536,c=qFromLittleEndian<quint16>(p+13)*Pi/32768;
    const double c0=std::cos(a),s0=std::sin(a),c1=std::cos(b),s1=std::sin(b),c2=std::cos(c),s2=std::sin(c);
    const Vec3 x{c0*c2-c1*s0*s2,c1*c0*s2+c2*s0,s2*s1};
    const Vec3 y{-c0*s2-c2*c1*s0,c0*c1*c2-s0*s2,c2*s1},z{s1*s0,-c0*s1,c1};
    bounds.minimum={10,10,10};bounds.maximum={-10,-10,-10};
    for(int i=0;i<8;++i){
        const auto v=ecefToPlanet(origin+x*(i&1?ex:-ex)+y*(i&2?ey:-ey)+z*(i&4?ez:-ez));
        if(!finite(v)||length(v)>5)return false;
        bounds.minimum={std::min(bounds.minimum.x,v.x),std::min(bounds.minimum.y,v.y),std::min(bounds.minimum.z,v.z)};
        bounds.maximum={std::max(bounds.maximum.x,v.x),std::max(bounds.maximum.y,v.y),std::max(bounds.maximum.z,v.z)};
    }
    return true;
}
bool texture(QByteArrayView data,QImage &image,QString &error){
    Reader reader(data);Field f;QByteArrayView payload;int format=0,width=256,height=256;unsigned images=0,direction=0;
    while(reader.next(f)){
        if(f.id==1){if(f.wire!=2||++images>1)return fail(error,"RP_ROCKTREE_TEXTURE_PAYLOAD_INVALID");payload=f.data;}
        if(f.id>=2&&f.id<=5){if(f.wire!=0||f.value>65536)return fail(error,"RP_ROCKTREE_TEXTURE_HEADER_INVALID");
            if(f.id==2)format=int(f.value);if(f.id==3)width=int(f.value);if(f.id==4)height=int(f.value);if(f.id==5)direction=unsigned(f.value);}
    }
    if(!reader.end()||images!=1||direction!=0||width<1||height<1||width>2048||height>2048||payload.size()>8*1024*1024)return fail(error,"RP_ROCKTREE_TEXTURE_INVALID");
    QByteArray bytes(payload.data(),payload.size());
    if(format==6)return decodeCrn(bytes,width,height,image,error);
    if(format==2){
        std::vector<unsigned char> input(bytes.begin(),bytes.end()),rgba;std::string detail;
        if(!decodeBc1(input,width,height,rgba,detail))return fail(error,"RP_ROCKTREE_BC1_INVALID");
        for(std::size_t i=3;i<rgba.size();i+=4)rgba[i]=255; // Upstream uploads RGB_DXT1, not RGBA_DXT1.
        image=QImage(rgba.data(),width,height,QImage::Format_RGBA8888).copy();
    }else if(format==1){
        QBuffer buffer(&bytes);buffer.open(QIODevice::ReadOnly);QImageReader jpeg(&buffer,"JPEG");
        if(jpeg.size()!=QSize(width,height))return fail(error,"RP_ROCKTREE_JPEG_DIMENSIONS_INVALID");
        image=jpeg.read().convertToFormat(QImage::Format_RGBA8888);
    }else return fail(error,"RP_ROCKTREE_TEXTURE_FORMAT_UNSUPPORTED");
    return !image.isNull()||fail(error,"RP_ROCKTREE_TEXTURE_DECODE_FAILED");
}
std::shared_ptr<const LoadedTile> mesh(QByteArrayView data,const std::vector<double> &matrix,const NodeInfo &info,QString &error,const std::atomic_bool &cancel){
    Reader reader(data);Field f;QByteArrayView packedVertices,packedUv,packedIndices,layers,tex;std::vector<double> uvTransform;
    unsigned textures=0;
    while(reader.next(f)){
        if(f.id==1||f.id==3||f.id==6||f.id==7||f.id==8){
            if(f.wire!=2){fail(error,"RP_ROCKTREE_MESH_WIRE_INVALID");return {};}
            if(f.id==1)packedVertices=f.data;if(f.id==3)packedIndices=f.data;if(f.id==7)packedUv=f.data;if(f.id==8)layers=f.data;
            if(f.id==6){if(++textures>1){fail(error,"RP_ROCKTREE_MESH_TEXTURE_COUNT_INVALID");return {};}tex=f.data;}
        }
        if(f.id==10&&!numbers(f,false,uvTransform)){fail(error,"RP_ROCKTREE_UV_TRANSFORM_INVALID");return {};}
    }
    const qsizetype count=packedVertices.size()/3;
    if(!reader.end()||packedVertices.size()%3||count<3||count>65535||packedUv.size()!=4+count*4||packedIndices.isEmpty()||layers.isEmpty()||textures!=1){fail(error,"RP_ROCKTREE_MESH_FIELDS_INVALID");return {};}
    Reader indicesReader(packedIndices);quint64 stripSize=0;
    if(!indicesReader.varint(stripSize)||stripSize<3||stripSize>1000000){fail(error,"RP_ROCKTREE_INDEX_COUNT_INVALID");return {};}
    std::vector<quint32> strip;strip.reserve(std::size_t(stripSize));quint64 zeros=0;
    for(quint64 i=0;i<stripSize;++i){quint64 delta=0;
        if(!indicesReader.varint(delta)||delta>zeros||zeros-delta>=quint64(count)){fail(error,"RP_ROCKTREE_INDEX_OUT_OF_RANGE");return {};}
        strip.push_back(quint32(zeros-delta));if(!delta)++zeros;
    }
    Reader layersReader(layers);quint64 layerCount=0,total=0,terrainEnd=0;
    if(!indicesReader.end()||!layersReader.varint(layerCount)||layerCount<1||layerCount>72){fail(error,"RP_ROCKTREE_LAYERS_INVALID");return {};}
    for(quint64 i=0;i<layerCount;++i){quint64 n=0;
        if(!layersReader.varint(n)||n>stripSize-total){fail(error,"RP_ROCKTREE_LAYER_RANGE_INVALID");return {};}
        total+=n;if(i<24)terrainEnd=total;
    }
    if(!layersReader.end()||total!=stripSize){fail(error,"RP_ROCKTREE_LAYER_TOTAL_INVALID");return {};}
    if(terrainEnd<3)return {}; // Water-only mesh; the original client uses layer_bounds[3].
    auto tile=std::make_shared<LoadedTile>();auto &g=tile->geometry;g.vertices.resize(std::size_t(count));
    const auto *uv=packedUv.data()+4;const unsigned um=1u+qFromLittleEndian<quint16>(packedUv.data()),vm=1u+qFromLittleEndian<quint16>(packedUv.data()+2);
    double uOffset=.5,vOffset=.5-double(vm),uScale=1.0/um,vScale=-1.0/vm;
    if(!uvTransform.empty()){
        if(uvTransform.size()!=4){fail(error,"RP_ROCKTREE_UV_TRANSFORM_INVALID");return {};}
        uOffset=uvTransform[0];vOffset=uvTransform[1];uScale=uvTransform[2];vScale=uvTransform[3];
    }
    tile->origin=ecefToPlanet({matrix[12],matrix[13],matrix[14]});
    tile->localPositions.reserve(std::size_t(count)*3);
    unsigned u=0,v=0;quint8 x=0,y=0,z=0;g.bounds.minimum={10,10,10};g.bounds.maximum={-10,-10,-10};
    for(qsizetype i=0;i<count;++i){
        if((i&1023)==0&&cancel.load()){error=QStringLiteral("CANCELLED");return {};}
        x=quint8(x+quint8(packedVertices[i]));y=quint8(y+quint8(packedVertices[count+i]));z=quint8(z+quint8(packedVertices[2*count+i]));
        Vec3 p=ecefToPlanet({matrix[0]*x+matrix[4]*y+matrix[8]*z+matrix[12],matrix[1]*x+matrix[5]*y+matrix[9]*z+matrix[13],matrix[2]*x+matrix[6]*y+matrix[10]*z+matrix[14]});
        if(!finite(p)||length(p)>2){fail(error,"RP_ROCKTREE_VERTEX_INVALID");return {};}
        u=(u+quint8(uv[i])+(unsigned(quint8(uv[2*count+i]))<<8))%um;
        v=(v+quint8(uv[count+i])+(unsigned(quint8(uv[3*count+i]))<<8))%vm;
        const auto relative=p-tile->origin; // Relative-to-eye/RTC precision: subtract in double BEFORE converting to float.
        tile->localPositions.insert(tile->localPositions.end(),{float(relative.x),float(relative.y),float(relative.z)});
        auto &vertex=g.vertices[std::size_t(i)];vertex.position[0]=float(p.x);vertex.position[1]=float(p.y);vertex.position[2]=float(p.z);
        vertex.uv[0]=float((u+uOffset)*uScale);vertex.uv[1]=float(1-(v+vOffset)*vScale); // terrain.vert already flips V.
        g.bounds.minimum={std::min(g.bounds.minimum.x,p.x),std::min(g.bounds.minimum.y,p.y),std::min(g.bounds.minimum.z,p.z)};
        g.bounds.maximum={std::max(g.bounds.maximum.x,p.x),std::max(g.bounds.maximum.y,p.y),std::max(g.bounds.maximum.z,p.z)};
    }
    std::vector<Vec3> normals(std::size_t(count),Vec3{});
    auto position=[&](quint32 i){const auto *p=tile->localPositions.data()+std::size_t(i)*3;return Vec3{p[0],p[1],p[2]};};
    for(std::size_t i=2;i<terrainEnd;++i){
        auto a=strip[i-2],b=strip[i-1],c=strip[i];if(i&1)std::swap(a,b);if(a==b||a==c||b==c)continue;
        g.indices.insert(g.indices.end(),{a,b,c});auto n=cross(position(b)-position(a),position(c)-position(a));
        normals[a]=normals[a]+n;normals[b]=normals[b]+n;normals[c]=normals[c]+n;
    }
    if(g.indices.empty())return {};
    for(std::size_t i=0;i<normals.size();++i){const auto n=normalized(length(normals[i])>1e-20?normals[i]:position(quint32(i))+tile->origin);g.vertices[i].normal[0]=float(n.x);g.vertices[i].normal[1]=float(n.y);g.vertices[i].normal[2]=float(n.z);}
    if(!texture(tex,tile->texture,error))return {};
    tile->bytes=g.vertices.size()*sizeof(Vertex)+g.indices.size()*sizeof(std::uint32_t)+std::size_t(tile->texture.sizeInBytes())+tile->localPositions.size()*sizeof(float);
    tile->resolutionMetres=info.metresPerTexel;tile->source=QStringLiteral("Google Earth · RockTree");return tile;
}
}
bool validPath(const QString &path,bool allowEmpty){
    if(path.size()>24||(!allowEmpty&&path.isEmpty()))return false;
    for(auto c:path)if(c<QLatin1Char('0')||c>QLatin1Char('7'))return false;return true;
}
QUrl bulkUrl(const QString &path,quint32 epoch){
    if(!validPath(path,true)||path.size()%4||!epoch)return {};
    return QUrl(QStringLiteral("https://kh.google.com/rt/earth/BulkMetadata/pb=!1m2!1s%1!2u%2").arg(path).arg(epoch));
}
QUrl nodeUrl(const NodeInfo &node){
    if(!validPath(node.path)||!node.epoch||(node.textureFormat!=1&&node.textureFormat!=2&&node.textureFormat!=6))return {};
    QString url=QStringLiteral("https://kh.google.com/rt/earth/NodeData/pb=!1m2!1s%1!2u%2!2e%3").arg(node.path).arg(node.epoch).arg(node.textureFormat);
    if(node.useImageryEpoch)url+=QStringLiteral("!3u%1").arg(node.imageryEpoch);
    return QUrl(url+QStringLiteral("!4b0"));
}
bool decodePlanetoid(const QByteArray &bytes,quint32 &epoch,double &radius,QString &error){
    error.clear();epoch=0;radius=0;Reader reader(bytes);Field f;QByteArrayView root;
    while(reader.next(f)){
        if(f.id==1){if(f.wire!=2)return fail(error,"RP_ROCKTREE_PLANET_INVALID");root=f.data;}
        if(f.id==2){if(f.wire!=5)return fail(error,"RP_ROCKTREE_PLANET_INVALID");radius=number(f.data.data(),false);}
    }
    Reader node(root);bool found=false;
    while(node.next(f))if(f.id==2){if(f.wire!=0||f.value<1||f.value>std::numeric_limits<quint32>::max())return fail(error,"RP_ROCKTREE_EPOCH_INVALID");epoch=quint32(f.value);found=true;}
    return (reader.end()&&node.end()&&found&&std::isfinite(radius)&&radius>6e6&&radius<7e6)||fail(error,"RP_ROCKTREE_PLANET_INVALID");
}
bool decodeBulk(const QByteArray &bytes,const QString &path,quint32 epoch,Bulk &out,QString &error){
    error.clear();out={};if(!validPath(path,true)||path.size()%4||!epoch)return fail(error,"RP_ROCKTREE_BULK_REQUEST_INVALID");
    Reader reader(bytes);Field f;std::vector<QByteArrayView> entries;std::vector<double> head,metres;
    QString keyPath;quint32 keyEpoch=0,imagery=0,formats=0;
    while(reader.next(f)){
        if(f.id==1){if(f.wire!=2||entries.size()>=4680)return fail(error,"RP_ROCKTREE_BULK_NODE_LIMIT");entries.push_back(f.data);}
        if(f.id==2&&(f.wire!=2||!key(f.data,keyPath,keyEpoch)))return fail(error,"RP_ROCKTREE_BULK_KEY_INVALID");
        if(f.id==3&&!numbers(f,true,head))return fail(error,"RP_ROCKTREE_BULK_CENTER_INVALID");
        if(f.id==4&&!numbers(f,false,metres))return fail(error,"RP_ROCKTREE_BULK_RESOLUTION_INVALID");
        if(f.id==5||f.id==6){if(f.wire!=0||f.value>std::numeric_limits<quint32>::max())return fail(error,"RP_ROCKTREE_BULK_DEFAULT_INVALID");if(f.id==5)imagery=quint32(f.value);else formats=quint32(f.value);}
    }
    if(!reader.end()||keyPath!=path||keyEpoch!=epoch||head.size()!=3||metres.size()!=4||entries.empty())return fail(error,"RP_ROCKTREE_BULK_CONTRACT_INVALID");
    out.path=path;out.epoch=epoch;
    for(auto bytes:entries){
        Reader entry(bytes);QByteArrayView box;quint64 values[11]{};bool present[11]{};double resolution=0;
        while(entry.next(f)){
            if(f.id==3){if(f.wire!=2)return fail(error,"RP_ROCKTREE_OBB_INVALID");box=f.data;}
            else if(f.id==4){if(f.wire!=5)return fail(error,"RP_ROCKTREE_RESOLUTION_INVALID");resolution=number(f.data.data(),false);present[4]=true;}
            else if(f.id<11){if(f.wire!=0||f.value>std::numeric_limits<quint32>::max()){
                    if(f.id==6)continue;return fail(error,"RP_ROCKTREE_NODE_METADATA_INVALID");}
                values[f.id]=f.value;present[f.id]=true;}
        }
        if(!entry.end()||!present[1])return fail(error,"RP_ROCKTREE_NODE_PATH_MISSING");
        auto packed=values[1];int depth=1+int(packed&3);packed>>=2;QString suffix;
        for(int i=0;i<depth;++i){suffix+=QChar('0'+int(packed&7));packed>>=3;}
        NodeInfo node;node.path=path+suffix;node.flags=quint32(packed);node.epoch=present[2]?quint32(values[2]):epoch;
        node.bulkEpoch=present[5]?quint32(values[5]):epoch;node.imageryEpoch=present[7]?quint32(values[7]):imagery;node.useImageryEpoch=node.flags&16;
        auto available=present[8]?values[8]:formats;node.textureFormat=available&1?1:available&32?6:available&2?2:0;
        node.metresPerTexel=present[4]?resolution:metres[std::size_t(depth-1)];
        if(!validPath(node.path)||!node.epoch||!node.bulkEpoch||out.nodes.contains(node.path))return fail(error,"RP_ROCKTREE_NODE_CONTRACT_INVALID");
        // Nodes with neither geometry nor descendants carry no renderable OBB.
        if(!node.hasData()&&!node.hasChildren())continue;
        if(!obb(box,{head[0],head[1],head[2]},node.metresPerTexel,node.bounds))return fail(error,"RP_ROCKTREE_OBB_INVALID");
        if(node.hasData()&&!node.textureFormat)return fail(error,"RP_ROCKTREE_TEXTURE_FORMAT_UNSUPPORTED");
        out.nodes.insert(node.path,node);
    }
    return !out.nodes.empty()||fail(error,"RP_ROCKTREE_BULK_EMPTY");
}
std::shared_ptr<const LoadedTile> decodeNode(const QByteArray &bytes,const NodeInfo &info,QString &error,const std::atomic_bool &cancel){
    error.clear();if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
    if(!validPath(info.path)||!info.epoch){fail(error,"RP_ROCKTREE_NODE_REQUEST_INVALID");return {};}
    Reader reader(bytes);Field f;std::vector<double> matrix;std::vector<QByteArrayView> meshes;QString packetPath;quint32 packetEpoch=0;bool haveKey=false;
    while(reader.next(f)){
        if(f.id==1&&!numbers(f,true,matrix)){fail(error,"RP_ROCKTREE_MATRIX_INVALID");return {};}
        if(f.id==2){if(f.wire!=2||meshes.size()>=64){fail(error,"RP_ROCKTREE_MESH_COUNT_INVALID");return {};}meshes.push_back(f.data);}
        if(f.id==4){haveKey=true;if(f.wire!=2||!key(f.data,packetPath,packetEpoch)){fail(error,"RP_ROCKTREE_NODE_KEY_INVALID");return {};}}
    }
    if(!reader.end()||matrix.size()!=16||meshes.empty()||std::abs(matrix[3])+std::abs(matrix[7])+std::abs(matrix[11])>1e-8||std::abs(matrix[15]-1)>1e-8
       ||(haveKey&&(packetPath!=info.path||packetEpoch!=info.epoch))){fail(error,"RP_ROCKTREE_NODE_CONTRACT_INVALID");return {};}
    auto tile=std::make_shared<LoadedTile>();tile->source=QStringLiteral("Google Earth · RockTree");tile->resolutionMetres=info.metresPerTexel;
    tile->geometry.bounds.minimum={10,10,10};tile->geometry.bounds.maximum={-10,-10,-10};
    for(auto bytes:meshes){
        if(cancel.load()){error=QStringLiteral("CANCELLED");return {};}
        auto part=mesh(bytes,matrix,info,error,cancel);if(!part){if(!error.isEmpty())return {};continue;}
        if(part->bytes>32*1024*1024-tile->bytes){fail(error,"RP_ROCKTREE_NODE_MEMORY_LIMIT");return {};}
        tile->bytes+=part->bytes;const auto b=part->geometry.bounds;auto &bounds=tile->geometry.bounds;
        bounds.minimum={std::min(bounds.minimum.x,b.minimum.x),std::min(bounds.minimum.y,b.minimum.y),std::min(bounds.minimum.z,b.minimum.z)};
        bounds.maximum={std::max(bounds.maximum.x,b.maximum.x),std::max(bounds.maximum.y,b.maximum.y),std::max(bounds.maximum.z,b.maximum.z)};
        tile->parts.push_back(std::move(part));
    }
    if(tile->parts.empty()){fail(error,"RP_ROCKTREE_NODE_HAS_NO_TERRAIN");return {};}
    return tile;
}
}
