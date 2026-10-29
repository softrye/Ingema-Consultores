#include "RetroplasmaTileScheduler.h"
#include <algorithm>
#include <functional>
namespace inge::rp {
Schedule RetroplasmaTileScheduler::selectPlanet(const Scene &scene,const Mat4 &view,Vec3 eye,double height,const QHash<QString,std::shared_ptr<const LoadedTile>> &resident,const QString &revision){
    Schedule out;QSet<QString> drawn;int leaves=0,remoteRequests=0;
    auto draw=[&](const QString &key){if(resident.contains(key)&&!drawn.contains(key)){drawn.insert(key);out.wanted.insert(key);out.draw.push_back({key,resident.value(key)});}};
    auto request=[&](const QString &key,const Lod &asset,double priority){if(out.wanted.contains(key))return;if(asset.layer!=QLatin1String("overview")&&remoteRequests++>=96)return;out.wanted.insert(key);if(!resident.contains(key))out.requests.push_back({key,0,0,priority,true,asset,planetBounds(asset.sector)});};
    const bool detail=scene.imagery==QLatin1String("landsat");const int maxLevel=scene.imagery==QLatin1String("sentinel")?11:detail?9:5;
    std::function<void(GeoSector,int,int,int,QString)> visit=[&](GeoSector box,int level,int x,int y,QString ancestor){
        if(!planetSectorVisible(box,view,eye))return;
        auto middle=ecefToPlanet(geodeticToEcef({(box.south+box.north)*.5,(box.west+box.east)*.5,0}));
        double distance=std::max(.0001,length(middle-eye));
        double pixels=(box.east-box.west)*Radians*height/(2*std::tan(22.5*Radians)*distance);
        QString key=revision+QStringLiteral(":gibs:%1:%2:%3:%4").arg(scene.imagery).arg(level).arg(y).arg(x);
        if(resident.contains(key)){ancestor=key;out.wanted.insert(key);}
        if(level>=3&&pixels>360&&level<maxLevel){
            Lod parent;parent.planetary=true;parent.sector=box;parent.layer=scene.imagery;parent.date=scene.date;parent.level=level;
            request(key,parent,distance-1.0/double(level+1));
        }
        if(pixels>360&&level<maxLevel&&leaves<80){
            double lon=(box.west+box.east)*.5,lat=(box.south+box.north)*.5;
            struct Cell{GeoSector box;int x,y;};
            std::array<Cell,4> cells{{{{box.west,box.south,lon,lat},x*2,y*2},{{lon,box.south,box.east,lat},x*2+1,y*2},{{box.west,lat,lon,box.north},x*2,y*2+1},{{lon,lat,box.east,box.north},x*2+1,y*2+1}}};
            auto proximity=[&](GeoSector s){return length(ecefToPlanet(geodeticToEcef({(s.south+s.north)*.5,(s.west+s.east)*.5,0}))-eye);};
            std::stable_sort(cells.begin(),cells.end(),[&](auto a,auto b){return proximity(a.box)<proximity(b.box);});
            for(auto cell:cells)visit(cell.box,level+1,cell.x,cell.y,ancestor);return;
        }
        if(++leaves>96)return;
        // Leaf textures never become a flat map: each is uploaded on an ECEF ellipsoid segment.
        Lod asset;asset.planetary=true;asset.sector=box;asset.layer=scene.imagery;asset.date=scene.date;asset.level=level;
        if(detail){
            // Blue Marble regional underlay stays available beneath daily HLS holes/clouds.
            int baseLevel=std::min(level,5),shift=level-baseLevel;double size=45.0/std::pow(2.0,baseLevel);
            int bx=x>>shift,by=y>>shift;Lod base=asset;base.layer=QStringLiteral("blue-marble");base.level=baseLevel;base.date.clear();
            base.sector={-180+bx*size,-90+by*size,-180+(bx+1)*size,-90+(by+1)*size};
            auto baseKey=revision+QStringLiteral(":gibs:blue-marble:%1:%2:%3").arg(baseLevel).arg(by).arg(bx);
            request(baseKey,base,distance-.25);draw(baseKey);
        }
        request(key,asset,distance);if(resident.contains(key))draw(key);else if(!ancestor.isEmpty())draw(ancestor);
    };
    for(int root:scene.roots){
        const auto &node=scene.nodes[root];auto key=revision+QStringLiteral(":overview:")+node.id;
        request(key,node.lods[0],-1000);draw(key); // Pinned all-world coverage, also across fast rotations/offline.
    }
    auto roots=scene.roots;
    std::stable_sort(roots.begin(),roots.end(),[&](int a,int b){return length(center(scene.nodes[a].bounds)-eye)<length(center(scene.nodes[b].bounds)-eye);});
    if(length(eye)<3.0)for(int root:roots)visit(scene.nodes[root].lods[0].sector,0,root%8,root/8,{});
    std::stable_sort(out.requests.begin(),out.requests.end(),[](const auto &a,const auto &b){return a.priority<b.priority;});return out;
}
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
