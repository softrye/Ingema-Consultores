#pragma once
#include "RetroplasmaGeometryDecoder.h"
namespace inge::rp {
constexpr double EarthRadius=6378137.0;
struct GeoSector {double west=-180,south=-90,east=180,north=90;};
inline Vec3 ecefToPlanet(Vec3 p){return {p.x/EarthRadius,p.z/EarthRadius,-p.y/EarthRadius};}
inline Vec3 planetToEcef(Vec3 p){return {p.x*EarthRadius,-p.z*EarthRadius,p.y*EarthRadius};}
Geometry planetMesh(GeoSector,int subdivisions=16,double shellMetres=0);
Bounds planetBounds(GeoSector);
bool planetSectorVisible(GeoSector,const Mat4 &,Vec3 eye);
}
