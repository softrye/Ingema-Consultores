#include "RetroplasmaPlanet.h"
#include <algorithm>
#include <limits>
namespace inge::rp {
Geometry planetMesh(GeoSector box,int steps,double shell){
    Geometry out;
    if(steps<2||steps>64||box.east<=box.west||box.north<=box.south||box.west< -180||box.east>180||box.south< -90||box.north>90)return out;
    double inf=std::numeric_limits<double>::infinity();out.bounds={{inf,inf,inf},{-inf,-inf,-inf}};
    for(int row=0;row<=steps;++row)for(int col=0;col<=steps;++col){
        double u=double(col)/steps,v=double(row)/steps;
        double lon=box.west+(box.east-box.west)*u,lat=box.south+(box.north-box.south)*v;
        auto p=ecefToPlanet(geodeticToEcef({lat,lon,shell}));
        double phi=lat*Radians,lambda=lon*Radians;
        Vec3 normal{std::cos(phi)*std::cos(lambda),std::sin(phi),-std::cos(phi)*std::sin(lambda)};
        Vertex vertex;for(int i=0;i<3;++i){vertex.position[i]=float(i==0?p.x:i==1?p.y:p.z);vertex.normal[i]=float(i==0?normal.x:i==1?normal.y:normal.z);}
        vertex.uv[0]=float(u);vertex.uv[1]=float(v);out.vertices.push_back(vertex);
        out.bounds.minimum={std::min(out.bounds.minimum.x,p.x),std::min(out.bounds.minimum.y,p.y),std::min(out.bounds.minimum.z,p.z)};
        out.bounds.maximum={std::max(out.bounds.maximum.x,p.x),std::max(out.bounds.maximum.y,p.y),std::max(out.bounds.maximum.z,p.z)};
    }
    for(int row=0;row<steps;++row)for(int col=0;col<steps;++col){
        auto a=std::uint32_t(row*(steps+1)+col),b=a+1,c=a+steps+1,d=c+1;
        // ENU/ECEF -> render is an orientation-preserving rotation. East x north is outwards.
        if(box.south> -90||row>0)out.indices.insert(out.indices.end(),{a,b,c});
        if(box.north<90||row<steps-1)out.indices.insert(out.indices.end(),{b,d,c});
    }
    return out;
}
Bounds planetBounds(GeoSector sector){
    auto bounds=planetMesh(sector,4,250).bounds;
    // Conservative angular sag enclosure for extrema between the sampled longitudes/latitudes.
    double angle=std::max(sector.east-sector.west,sector.north-sector.south)*Radians/4;
    double pad=1-std::cos(angle)+1e-5;bounds.minimum=bounds.minimum-Vec3{pad,pad,pad};bounds.maximum=bounds.maximum+Vec3{pad,pad,pad};return bounds;
}
bool planetSectorVisible(GeoSector box,const Mat4 &view,Vec3 eye){
    if(!intersectsFrustum(view,planetBounds(box)))return false;
    auto n=normalized(ecefToPlanet(geodeticToEcef({(box.south+box.north)*.5,(box.west+box.east)*.5,0})));
    double angularRadius=((box.east-box.west)+(box.north-box.south))*.5*Radians;
    double horizon=.9966/std::max(1.00001,length(eye));
    return dot(n,normalized(eye))+std::sin(std::min(Pi*.5,angularRadius))>=horizon;
}
}
