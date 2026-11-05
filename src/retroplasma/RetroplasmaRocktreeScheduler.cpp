#include "RetroplasmaTileScheduler.h"
#include "RetroplasmaRocktree.h"
#include <algorithm>
#include <functional>

namespace inge::rp {
Schedule RetroplasmaTileScheduler::selectRocktree(const Scene &scene,const Mat4 &view,Vec3 eye,double height,
    const QHash<QString,std::shared_ptr<const LoadedTile>> &resident,const QString &revision,const EarthBudget &budget){
    Schedule out;if(!scene.rocktreeRoot)return out;int visited=0,leaves=0;
    auto visible=[&](Bounds bounds){
        if(!intersectsFrustum(view,bounds))return false;
        const auto c=center(bounds);const double extent=radius(bounds),distance=length(eye);
        // Conservative horizon test: never cull a box spanning the camera or globe centre.
        return distance<=1.0001||length(c)<=extent||dot(normalized(c),normalized(eye))+std::min(1.0,extent/std::max(.01,length(c)))>=.995/distance;
    };
    auto request=[&](const QString &key,const Lod &asset,Bounds bounds,double priority){
        if(out.wanted.contains(key))return;out.wanted.insert(key);
        if(!resident.contains(key)&&out.requests.size()<std::size_t(budget.nodes*3))out.requests.push_back({key,0,0,priority,true,asset,bounds});
    };
    auto append=[&](std::vector<RenderTile> &draw,const QString &key){
        auto tile=resident.value(key);if(!tile)return;
        if(tile->parts.empty())draw.push_back({key,tile,key});
        else for(std::size_t i=0;i<tile->parts.size();++i)draw.push_back({key+QStringLiteral("#%1").arg(qulonglong(i)),tile->parts[i],key});
    };
    struct Coverage {bool complete=false;std::vector<RenderTile> draw;};
    std::function<Coverage(const QString &,const rocktree::Bulk &)> visit;
    visit=[&](const QString &path,const rocktree::Bulk &bulk)->Coverage{
        if(++visited>budget.nodes*32)return {};
        auto it=bulk.nodes.constFind(path);if(it==bulk.nodes.cend())return {true,{}};
        const auto &node=it.value();if(!visible(node.bounds))return {true,{}};
        const auto key=revision+QStringLiteral(":rt:node:")+path+QLatin1Char(':')+QString::number(node.epoch)+QLatin1Char(':')+QString::number(node.imageryEpoch);
        const double distance=std::max(1e-6,length(center(node.bounds)-eye)-radius(node.bounds));
        if(node.hasData()){
            Lod asset;asset.planetary=true;asset.layer=QStringLiteral("rocktree-node");asset.meshPath=path;asset.epoch=node.epoch;
            asset.imageryEpoch=node.imageryEpoch;asset.useImageryEpoch=node.useImageryEpoch;asset.textureFormat=node.textureFormat;asset.geometricError=node.metresPerTexel;
            request(key,asset,node.bounds,distance+path.size()*.001);
        }
        auto current=resident.value(key);
        const double pixels=node.metresPerTexel/EarthRadius*height/(2*std::tan(22.5*Radians)*distance);
        const bool refine=node.hasChildren()&&path.size()<budget.maxLevel&&leaves<budget.nodes&&(!node.hasData()||pixels>budget.pixelError);
        if(!refine){
            ++leaves;Coverage result;result.complete=!node.hasData()||bool(current);if(current)append(result.draw,key);return result;
        }
        const rocktree::Bulk *children=&bulk;std::shared_ptr<const LoadedTile> metadata;
        if(node.hasBulk()){
            const auto metadataKey=revision+QStringLiteral(":rt:bulk:")+path+QLatin1Char(':')+QString::number(node.bulkEpoch);
            Lod asset;asset.planetary=true;asset.layer=QStringLiteral("rocktree-bulk");asset.meshPath=path;asset.epoch=node.bulkEpoch;
            request(metadataKey,asset,node.bounds,distance+path.size()*.001-.0001);
            metadata=resident.value(metadataKey);
            if(!metadata||!metadata->rocktreeBulk){Coverage result;result.complete=bool(current);if(current)append(result.draw,key);return result;}
            children=metadata->rocktreeBulk.get();
        }
        std::vector<QString> paths;
        for(int octant=0;octant<8;++octant){auto child=path+QChar('0'+octant);if(children->nodes.contains(child))paths.push_back(child);}
        if(paths.empty()){Coverage result;result.complete=!node.hasData()||bool(current);if(current)append(result.draw,key);return result;}
        std::stable_sort(paths.begin(),paths.end(),[&](const auto &a,const auto &b){return length(center(children->nodes.value(a).bounds)-eye)<length(center(children->nodes.value(b).bounds)-eye);});
        Coverage descendants;descendants.complete=true;
        for(const auto &child:paths){auto result=visit(child,*children);descendants.complete&=result.complete;descendants.draw.insert(descendants.draw.end(),result.draw.begin(),result.draw.end());}
        // Replace the whole parent only when visible child coverage is ready. This
        // avoids parent/child z fighting without a second renderer or masking pass.
        if(descendants.complete){out.wanted.remove(key);return descendants;}
        if(current){Coverage result;result.complete=true;append(result.draw,key);return result;}
        return descendants;
    };
    for(int octant=0;octant<8;++octant){auto result=visit(QString(QChar('0'+octant)),*scene.rocktreeRoot);out.draw.insert(out.draw.end(),result.draw.begin(),result.draw.end());}
    for(const auto &draw:out.draw)out.wanted.insert(draw.ownerKey);
    // Requests for parents superseded by complete child coverage are obsolete.
    out.requests.erase(std::remove_if(out.requests.begin(),out.requests.end(),[&](const auto &r){return !out.wanted.contains(r.key);}),out.requests.end());
    std::stable_sort(out.requests.begin(),out.requests.end(),[](const auto &a,const auto &b){return a.priority<b.priority;});
    return out;
}
}
