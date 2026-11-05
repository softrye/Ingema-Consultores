#include "RetroplasmaRocktree.h"
#include "RetroplasmaTileScheduler.h"
#include <QCoreApplication>
#include <QFile>
#include <QBuffer>
#include <QtEndian>
#include <cstring>
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
static void check(bool value,const char *message){if(!value)throw std::runtime_error(message);}
static QByteArray var(quint64 value){QByteArray out;do{unsigned char c=value&127;value>>=7;out.append(char(c|(value?128:0)));}while(value);return out;}
static QByteArray field(unsigned n,const QByteArray &bytes){return var((n<<3)|2)+var(quint64(bytes.size()))+bytes;}
static QByteArray integer(unsigned n,quint64 value){return var(n<<3)+var(value);}
static QByteArray doubles(const std::vector<double> &values){QByteArray out;for(double value:values){quint64 bits;std::memcpy(&bits,&value,8);bits=qToLittleEndian(bits);out.append(reinterpret_cast<const char *>(&bits),8);}return out;}
static QByteArray fixture(const char *name){QFile file(QStringLiteral(RP_ROCKTREE_FIXTURES)+QLatin1Char('/')+QLatin1String(name));check(file.open(QIODevice::ReadOnly),"fixture opens");return file.readAll();}
int main(int argc,char **argv){
    QCoreApplication app(argc,argv);QString error;quint32 epoch=0;double radius=0;
    check(rocktree::decodePlanetoid(QByteArray::fromHex("0a0610f80728f80715846dc24a"),epoch,radius,error),"real PlanetoidMetadata response");
    check(epoch==1016&&radius>6000000&&radius<7000000,"epoch and planet radius");
    for(auto bytes:{QByteArray(),QByteArray::fromHex("0a7f00"),QByteArray::fromHex("8080808080808080808000"),QByteArray::fromHex("0b00")})
        check(!rocktree::decodePlanetoid(bytes,epoch,radius,error)&&!error.isEmpty(),"malformed packets rejected");
    check(!rocktree::validPath("../../secret")&&!rocktree::validPath("08")&&rocktree::validPath("01234567"),"only bounded octant paths");
    rocktree::NodeInfo node;node.path="0273";node.epoch=1016;node.imageryEpoch=1030;node.useImageryEpoch=true;node.textureFormat=1;
    check(rocktree::nodeUrl(node).toString().contains("!1s0273!2u1016!2e1!3u1030!4b0"),"explicit imagery epoch retained");
    node.useImageryEpoch=false;check(!rocktree::nodeUrl(node).toString().contains("!3u"),"optional imagery epoch absent");
    node.path="../x";check(rocktree::nodeUrl(node).isEmpty(),"unsafe request rejected before network");
    rocktree::Bulk bulk;check(!rocktree::decodeBulk(QByteArray::fromHex("0a01ff"),"",1016,bulk,error),"truncated metadata rejected");
    check(rocktree::decodePlanetoid(fixture("planetoid.pb"),epoch,radius,error),"recorded real planet packet");
    check(rocktree::decodeBulk(fixture("root-bulk.pb"),"",epoch,bulk,error),"recorded real root metadata");
    check(bulk.nodes.contains("02")&&bulk.nodes["02"].imageryEpoch==1040,"per-node imagery epoch overrides bulk default 1030");
    check(!rocktree::decodeBulk(fixture("root-bulk.pb"),"0123",epoch,bulk,error),"metadata cannot change requested octant");
    std::atomic_bool cancel{true};node.path="02";
    check(!rocktree::decodeNode({},node,error,cancel)&&error=="CANCELLED","cancel before allocating a mesh");
    cancel=false;
    QImage image(2,2,QImage::Format_RGB32);image.fill(Qt::blue);QByteArray jpeg;QBuffer buffer(&jpeg);buffer.open(QIODevice::WriteOnly);check(image.save(&buffer,"JPEG"),"test JPEG generated");
    auto texture=field(1,jpeg)+integer(2,1)+integer(3,2)+integer(4,2);
    auto mesh=field(1,QByteArray::fromHex("0001ff000001000000"))+field(3,QByteArray::fromHex("03000000"))
        +field(7,QByteArray::fromHex("010001000001ff000001000000000000"))+field(8,QByteArray::fromHex("0103"))+field(6,texture);
    std::vector<double> matrix(16,0);matrix[1]=matrix[6]=matrix[8]=matrix[15]=1;matrix[12]=EarthRadius;
    const auto packet=field(1,doubles(matrix))+field(2,mesh)+field(2,mesh);
    node.epoch=1016;node.metresPerTexel=1;
    auto tile=rocktree::decodeNode(packet,node,error,cancel);
    check(bool(tile)&&tile->parts.size()==2,"all textured meshes are preserved");
    check(tile->parts[0]->geometry.indices.size()==3&&tile->parts[0]->texture.size()==QSize(2,2),"strip converted and image decoded");
    auto invalid=field(1,doubles(matrix))+field(2,field(1,QByteArray::fromHex("010203")));
    check(!rocktree::decodeNode(invalid,node,error,cancel)&&!error.isEmpty(),"incomplete mesh fails explicitly");
    QImage out;check(!rocktree::decodeCrn(QByteArray(80,'\0'),2,2,out,error),"invalid CRN ranges rejected before decompressor");
    Scene scene;scene.planetary=true;auto root=std::make_shared<rocktree::Bulk>();node.path="0";node.imageryEpoch=0;node.flags=4;node.bounds={{.99,-.01,-.01},{1.01,.01,.01}};root->nodes.insert(node.path,node);scene.rocktreeRoot=root;
    QHash<QString,std::shared_ptr<const LoadedTile>> resident;const auto owner=QStringLiteral("7:rt:node:0:1016:0");resident.insert(owner,tile);
    Mat4 view;for(int i=0;i<4;++i)view.at(i,i)=1;
    auto selected=RetroplasmaTileScheduler::selectRocktree(scene,view,{3,0,0},780,resident,"7",EarthBudget{});
    check(selected.draw.size()==2&&selected.draw[0].ownerKey==owner&&selected.wanted.contains(owner),"multipart rendering retains one cache owner");
    std::cout<<"PASS RockTree real metadata, malformed packets, geometry, textures, multipart ownership and cancellation\n";
}
