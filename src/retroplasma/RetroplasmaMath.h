#pragma once
#include <array>
#include <cmath>
namespace inge::rp {
constexpr double Pi=3.14159265358979323846, Radians=Pi/180.0;
struct Vec3 { double x=0,y=0,z=0; };
inline Vec3 operator+(Vec3 a,Vec3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
inline Vec3 operator-(Vec3 a,Vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
inline Vec3 operator*(Vec3 a,double b){return {a.x*b,a.y*b,a.z*b};}
inline double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double length(Vec3 a){return std::sqrt(dot(a,a));}
inline Vec3 normalized(Vec3 a){double n=length(a);return n>1e-15?a*(1/n):Vec3{0,1,0};}
inline bool finite(Vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
struct GeoPoint {double latitude=0,longitude=0,altitude=0;};
struct Bounds {Vec3 minimum,maximum;};
struct Mat4 {std::array<double,16> v{};double &at(int r,int c){return v[c*4+r];}double at(int r,int c)const{return v[c*4+r];}};
Mat4 operator*(const Mat4 &,const Mat4 &);
Mat4 perspective(double fov,double aspect,double nearPlane,double farPlane);
Mat4 lookAt(Vec3 eye,Vec3 focus,Vec3 up);
bool intersectsFrustum(const Mat4 &,const Bounds &);
Vec3 geodeticToEcef(GeoPoint);
GeoPoint ecefToGeodetic(Vec3);
Vec3 ecefToEnu(Vec3,GeoPoint origin);
Vec3 enuToEcef(Vec3,GeoPoint origin);
inline Vec3 enuToRender(Vec3 enu){return {enu.x,enu.z,-enu.y};}
inline Vec3 renderToEnu(Vec3 xyz){return {xyz.x,-xyz.z,xyz.y};}
inline Vec3 center(Bounds b){return (b.minimum+b.maximum)*0.5;}
inline double radius(Bounds b){return length(b.maximum-b.minimum)*0.5;}
}
