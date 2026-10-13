#include "RetroplasmaTileScheduler.h"
#include <algorithm>
#include <functional>
namespace inge::rp {
Schedule RetroplasmaTileScheduler::select(const Scene &scene,const Mat4 &view,Vec3 eye,double height,const QHash<QString,std::shared_ptr<const LoadedTile>> &resident,const QString &revision){
    Schedule out;auto key=[&](int node,int lod){return revision+":"+scene.nodes[node].id+":"+QString::number(lod);};
    auto request=[&](int node,int lod,double priority){QString id=key(node,lod);if(!out.wanted.contains(id)){out.wanted.insert(id);if(!resident.contains(id))out.requests.push_back({id,node,lod,priority});}};
    auto anyResident=[&](int node){for(int l=0;l<int(scene.nodes[node].lods.size());++l)if(resident.contains(key(node,l)))return true;return false;};
    std::function<void(int)> visit=[&](int index){
        const auto &node=scene.nodes[index];if(!intersectsFrustum(view,node.bounds))return;
        double distance=std::max(1.0,length(center(node.bounds)-eye)-radius(node.bounds));
        double projectionScale=std::max(1.0,height)/(2*std::tan(22.5*Radians)*distance);
        int desired=0;while(desired+1<int(node.lods.size())&&node.lods[desired].geometricError*projectionScale>2)++desired;
        bool refine=!node.children.empty()&&node.lods.front().geometricError*projectionScale>3;
        bool childrenReady=refine;
        if(refine)for(int child:node.children)if(intersectsFrustum(view,scene.nodes[child].bounds)){
            if(!anyResident(child)){childrenReady=false;request(child,0,distance-1e5);}
        }
        if(refine&&!childrenReady)for(int child:node.children)if(intersectsFrustum(view,scene.nodes[child].bounds)){
            // Keep loaded siblings while waiting for the remaining replacement coverage.
            for(int l=0;l<int(scene.nodes[child].lods.size());++l)if(resident.contains(key(child,l))){out.wanted.insert(key(child,l));break;}
        }
        if(childrenReady){for(int child:node.children)visit(child);return;}
        if(!anyResident(index))request(index,0,distance-1e6);
        request(index,desired,distance);
        int available=-1;for(int l=desired;l>=0;--l)if(resident.contains(key(index,l))){available=l;break;}
        if(available<0)for(int l=desired+1;l<int(node.lods.size());++l)if(resident.contains(key(index,l))){available=l;break;}
        if(available>=0){auto id=key(index,available);out.wanted.insert(id);out.draw.push_back({id,resident.value(id)});}
    };
    for(int root:scene.roots)visit(root);
    std::stable_sort(out.requests.begin(),out.requests.end(),[](const auto &a,const auto &b){return a.priority<b.priority;});
    return out;
}
}
