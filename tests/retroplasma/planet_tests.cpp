#include "RetroplasmaPlanet.h"
#include "RetroplasmaCamera.h"
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
static int checks=0;
static void require(bool ok,const char *why){++checks;if(!ok)throw std::runtime_error(why);}
int main(){
    require(std::abs(length(ecefToPlanet(geodeticToEcef({0,0,0})))-1)<1e-10,"equatorial radius normalized");
    require(std::abs(ecefToPlanet(geodeticToEcef({90,0,0})).y-0.996647189335)<1e-10,"WGS84 polar flattening");
    for(GeoSector sector: {GeoSector{-180,-90,-135,-45},GeoSector{135,45,180,90},GeoSector{-90,-45,-45,0}}){
        auto mesh=planetMesh(sector,16,0);
        require(mesh.vertices.size()==289&&mesh.indices.size()<=1536,"bounded indexed planet segment");
        for(const auto &v:mesh.vertices){require(std::isfinite(v.position[0])&&std::isfinite(v.normal[1]),"finite polar position and normal");require(v.uv[0]>=0&&v.uv[0]<=1&&v.uv[1]>=0&&v.uv[1]<=1,"sector UV range");}
        for(std::size_t i=0;i<mesh.indices.size();i+=3){
            auto point=[&](int j){auto &v=mesh.vertices[mesh.indices[i+j]];return Vec3{v.position[0],v.position[1],v.position[2]};};
            auto a=point(0),b=point(1),c=point(2);auto n=cross(b-a,c-a);
            require(length(n)<1e-10||dot(n,a+b+c)>0,"outward CCW winding including poles");
        }
    }
    auto east=planetMesh({135,-45,180,0},16,0),west=planetMesh({-180,-45,-135,0},16,0);
    for(int row=0;row<=16;++row)for(int axis=0;axis<3;++axis)require(std::abs(east.vertices[row*17+16].position[axis]-west.vertices[row*17].position[axis])<1e-6,"antimeridian seam closes");
    Camera c;c.resetPlanet(true);auto global=c.planetPosition();require(global.altitude>1e7,"initial camera in space");
    c.goToGeographic({-12.0464,-77.0428,153});require(c.planetPosition().altitude==global.altitude,"geographic transition does not jump");
    for(int i=0;i<150;++i)c.step(.016);
    auto lima=c.planetPosition();require(std::abs(lima.latitude+12.0464)<.001&&std::abs(lima.longitude+77.0428)<.001,"camera arrives Lima");
    require(lima.altitude>=40000&&lima.altitude<200000,"regional altitude respects 30m imagery floor");
    c.orbit(2*Pi,0);for(int i=0;i<150;++i)c.step(.016);require(finite(c.eye()),"full longitude rotation remains finite");
    c.goToGeographic({89.9999,179.9,0});for(int i=0;i<150;++i)c.step(.016);for(double v:c.viewProjection(1).v)require(std::isfinite(v),"pole view has valid up vector");
    c.resetPlanet();for(int i=0;i<150;++i)c.step(.016);require(c.planetPosition().altitude>1e7,"reset returns entire globe");
    std::cout<<"PLANET CORE PASS "<<checks<<" checks\n";
}
