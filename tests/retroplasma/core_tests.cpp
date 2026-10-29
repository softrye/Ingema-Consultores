#include "RetroplasmaMath.h"
#include "RetroplasmaCamera.h"
#include "RetroplasmaGeometryDecoder.h"
#include "RetroplasmaTextureDecoder.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
static int checks = 0;
static void require(bool ok, const char *why) { ++checks; if (!ok) throw std::runtime_error(why); }
static bool close(double a, double b, double epsilon) { return std::abs(a-b) < epsilon; }
int main() {
    auto equator = geodeticToEcef({0,0,0});
    require(close(equator.x,6378137.0,0.00001) && close(equator.y,0,0.00001),"WGS84 equator");
    for (GeoPoint p : {GeoPoint{-12.0464,-77.0428,153.2},GeoPoint{89.999,179.999,30},GeoPoint{-90,0,500}}) {
        auto q=ecefToGeodetic(geodeticToEcef(p));
        require(close(p.latitude,q.latitude,0.000001)&&close(p.altitude,q.altitude,0.01),"WGS84 inverse latitude/altitude");
    }
    GeoPoint origin{-12.0464,-77.0428,100};
    auto enu=ecefToEnu(geodeticToEcef(origin),origin);
    require(length(enu)<0.000001,"local origin exact");
    Vec3 local{0.013,250,12};
    auto round=ecefToEnu(enuToEcef(local,origin),origin);
    require(length(round-local)<0.000001,"centimetre ENU precision");
    auto vp=perspective(45*Radians,1,1,100)*lookAt({0,0,10},{0,0,0},{0,1,0});
    require(intersectsFrustum(vp,{{-1,-1,-1},{1,1,1}}),"visible AABB");
    require(!intersectsFrustum(vp,{{100,100,0},{110,110,1}}),"outside AABB culled");
    Camera camera; camera.reset({{-100,0,-100},{100,30,100}},true);
    double before=camera.pose().distance;
    camera.zoom(0.5); require(camera.pose().distance==before,"zoom is interpolated");
    camera.step(0.16); require(camera.pose().distance<before&&camera.pose().distance>before*0.5,"zoom moves toward target");
    camera.orbit(200,200); camera.step(1);
    require(std::isfinite(camera.pose().yaw)&&camera.pose().pitch<1.56,"orientation clamped and finite");
    camera.zoom(0); camera.step(1); require(camera.pose().distance>=2,"invalid zoom cannot break camera");
    Geometry geometry; std::string error;
    const char *obj="v 0 0 0\nv 10 0 0\nv 0 10 0\nvt 0 0\nvt 1 0\nvt 0 1\nf 1/1 2/2 3/3\n";
    require(decodeObj(obj,geometry,error),"textured triangle loaded");
    require(geometry.indices.size()==3&&geometry.vertices.size()==3,"indexed geometry");
    require(geometry.vertices[0].normal[1]>0.99,"ENU normal becomes Y up");
    require(!decodeObj("v 0 0 0\nf 1/1 2/2 3/3\n",geometry,error),"bad index recoverable");
    require(!decodeObj("v nan 0 0\n",geometry,error),"NaN rejected");
    require(!decodeObj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n",geometry,error),"UV required for textured scene");
    std::vector<unsigned char> bc1{0x00,0xf8,0xe0,0x07,0,0,0,0}, rgba;
    require(decodeBc1(bc1,4,4,rgba,error),"BC1 portable decode");
    require(rgba.size()==64&&rgba[0]==255&&rgba[1]==0&&rgba[2]==0&&rgba[3]==255,"BC1 red block exact");
    require(!decodeBc1({0,0},4,4,rgba,error),"truncated BC1 recoverable");
    require(!decodeBc1(bc1,100000,100000,rgba,error),"texture dimension bound");
    std::cout<<"RETROPLASMA CORE PASS "<<checks<<" checks\n";
}
