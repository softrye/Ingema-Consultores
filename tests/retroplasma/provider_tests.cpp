#include "RetroplasmaDataProvider.h"
#include "RetroplasmaTileScheduler.h"
#include "RetroplasmaCamera.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
static int count=0;
static void check(bool value,const char *message){++count;if(!value)throw std::runtime_error(message);}
int main(int argc,char **argv){
    QCoreApplication app(argc,argv);LocalSceneProvider provider;QString error;std::atomic_bool cancel{false};
    auto url=QUrl::fromLocalFile(QStringLiteral(RP_SOURCE_DIR "/scene.json"));auto scene=provider.readScene(url,error,cancel);
    check(bool(scene),"actual local manifest loads");check(scene->nodes.size()==5&&scene->roots.size()==1,"spatial hierarchy loads");
    for(const auto &node:scene->nodes)for(const auto &lod:node.lods){auto tile=provider.readTile(lod,error,cancel);check(bool(tile),"actual OBJ/PNG LOD loads");check(!tile->texture.isNull()&&tile->geometry.indices.size()>0,"textured geometry present");}
    check(!provider.readScene(QUrl("https://example.invalid/scene.json"),error,cancel),"remote source forbidden");
    QTemporaryDir temp;QFile source(url.toLocalFile());source.open(QIODevice::ReadOnly);auto object=QJsonDocument::fromJson(source.readAll()).object();auto nodes=object["nodes"].toArray();auto child=nodes[1].toObject();child["parent"]="missing";nodes[1]=child;object["nodes"]=nodes;
    QFile broken(temp.filePath("scene.json"));broken.open(QIODevice::WriteOnly);broken.write(QJsonDocument(object).toJson());broken.close();
    check(!provider.readScene(QUrl::fromLocalFile(broken.fileName()),error,cancel)&&error=="RP_PARENT_NOT_FOUND","missing parent rejected");
    auto node=nodes[0].toObject();auto levels=node["lods"].toArray();auto level=levels[0].toObject();level["mesh"]="../escape.obj";levels[0]=level;node["lods"]=levels;nodes[0]=node;object["nodes"]=nodes;broken.open(QIODevice::WriteOnly|QIODevice::Truncate);broken.write(QJsonDocument(object).toJson());broken.close();
    check(!provider.readScene(QUrl::fromLocalFile(broken.fileName()),error,cancel)&&error=="RP_ASSET_PATH_INVALID","asset traversal rejected");
    source.seek(0);auto partial=QJsonDocument::fromJson(source.readAll()).object();auto partialNodes=partial["nodes"].toArray();
    while(partialNodes.size()>2)partialNodes.removeLast();partial["nodes"]=partialNodes;
    broken.open(QIODevice::WriteOnly|QIODevice::Truncate);broken.write(QJsonDocument(partial).toJson());broken.close();
    check(!provider.readScene(QUrl::fromLocalFile(broken.fileName()),error,cancel)&&error=="RP_CHILD_COVERAGE_INCOMPLETE","partial child region cannot replace full parent");
    Camera camera;camera.reset(scene->bounds,true);QHash<QString,std::shared_ptr<const LoadedTile>> cache;
    auto coarse=provider.readTile(scene->nodes[0].lods[0],error,cancel);cache.insert("g:root:0",coarse);
    auto first=RetroplasmaTileScheduler::select(*scene,camera.viewProjection(1),camera.eye(),500,cache,"g");
    check(first.draw.size()==1&&first.draw[0].key=="g:root:0","parent covers while children missing");check(!first.requests.empty(),"refinement queued");
    cache.insert("g:tile0:0",provider.readTile(scene->nodes[1].lods[0],error,cancel));
    auto waiting=RetroplasmaTileScheduler::select(*scene,camera.viewProjection(1),camera.eye(),500,cache,"g");
    check(waiting.draw.size()==1&&waiting.draw[0].key=="g:root:0","partial replacement keeps parent");
    check(waiting.wanted.contains("g:tile0:0"),"resident child protected until siblings arrive");
    for(int i=1;i<5;++i)cache.insert(QString("g:tile%1:0").arg(i-1),provider.readTile(scene->nodes[i].lods[0],error,cancel));
    auto refined=RetroplasmaTileScheduler::select(*scene,camera.viewProjection(1),camera.eye(),500,cache,"g");
    check(refined.draw.size()==4,"children replace parent only when coverage ready");
    for(auto tile:refined.draw)check(tile.key!="g:root:0","no parent/child overlap");
    for(int i=1;i<5;++i)cache.insert(QString("g:tile%1:1").arg(i-1),provider.readTile(scene->nodes[i].lods[1],error,cancel));
    auto fine=RetroplasmaTileScheduler::select(*scene,camera.viewProjection(1),camera.eye(),100000,cache,"g");
    for(int i=0;i<4;++i)check(!fine.wanted.contains(QString("g:tile%1:0").arg(i)),"old coarse LOD released after complete finer coverage");
    cancel.store(true);check(!provider.readScene(url,error,cancel)&&error=="CANCELLED","obsolete scene cancelled");
    std::cout<<"RETROPLASMA PROVIDER PASS "<<count<<" checks\n";
}
