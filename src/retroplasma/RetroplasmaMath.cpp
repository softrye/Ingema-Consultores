#include "RetroplasmaMath.h"
#include <algorithm>
namespace inge::rp {
Mat4 operator*(const Mat4 &a,const Mat4 &b){Mat4 out;for(int c=0;c<4;++c)for(int r=0;r<4;++r)for(int k=0;k<4;++k)out.at(r,c)+=a.at(r,k)*b.at(k,c);return out;}
Mat4 perspective(double fov,double aspect,double n,double f){
    Mat4 m;if(!(aspect>0&&n>0&&f>n))return m;
    double t=1/std::tan(fov*0.5);m.at(0,0)=t/aspect;m.at(1,1)=t;
    m.at(2,2)=-(f+n)/(f-n);m.at(2,3)=-2*f*n/(f-n);m.at(3,2)=-1;return m;
}
Mat4 lookAt(Vec3 eye,Vec3 focus,Vec3 up){
    Vec3 f=normalized(focus-eye),s=normalized(cross(f,up)),u=cross(s,f);Mat4 m;
    m.at(0,0)=s.x;m.at(0,1)=s.y;m.at(0,2)=s.z;m.at(0,3)=-dot(s,eye);
    m.at(1,0)=u.x;m.at(1,1)=u.y;m.at(1,2)=u.z;m.at(1,3)=-dot(u,eye);
    m.at(2,0)=-f.x;m.at(2,1)=-f.y;m.at(2,2)=-f.z;m.at(2,3)=dot(f,eye);m.at(3,3)=1;return m;
}
bool intersectsFrustum(const Mat4 &m,const Bounds &b){
    for(int axis=0;axis<3;++axis)for(int sign:{-1,1}){
        bool outside=true;
        for(int corner=0;corner<8;++corner){
            std::array<double,4> p{corner&1?b.maximum.x:b.minimum.x,corner&2?b.maximum.y:b.minimum.y,corner&4?b.maximum.z:b.minimum.z,1};
            double d=0;for(int i=0;i<4;++i)d+=(m.at(3,i)+sign*m.at(axis,i))*p[i];
            if(d>=0){outside=false;break;}
        }
        if(outside)return false;
    }return true;
}
constexpr double A=6378137.0,E2=6.6943799901413165e-3;
Vec3 geodeticToEcef(GeoPoint p){double lat=p.latitude*Radians,lon=p.longitude*Radians;
    double s=std::sin(lat),n=A/std::sqrt(1-E2*s*s);return {(n+p.altitude)*std::cos(lat)*std::cos(lon),(n+p.altitude)*std::cos(lat)*std::sin(lon),(n*(1-E2)+p.altitude)*s};}
GeoPoint ecefToGeodetic(Vec3 p){
    double horizontal=std::hypot(p.x,p.y),lon=std::atan2(p.y,p.x),lat=std::atan2(p.z,horizontal*(1-E2)),h=0;
    if(horizontal<1e-8)return {p.z>=0?90.0:-90.0,0,std::abs(p.z)-A*std::sqrt(1-E2)};
    for(int i=0;i<12;++i){double s=std::sin(lat),n=A/std::sqrt(1-E2*s*s);h=horizontal/std::cos(lat)-n;lat=std::atan2(p.z,horizontal*(1-E2*n/(n+h)));}
    double s=std::sin(lat),n=A/std::sqrt(1-E2*s*s);h=horizontal/std::cos(lat)-n;return {lat/Radians,lon/Radians,h};
}
Vec3 ecefToEnu(Vec3 p,GeoPoint o){
    Vec3 d=p-geodeticToEcef(o);double lat=o.latitude*Radians,lon=o.longitude*Radians,s=std::sin(lat),c=std::cos(lat),sl=std::sin(lon),cl=std::cos(lon);
    return {-sl*d.x+cl*d.y,-s*cl*d.x-s*sl*d.y+c*d.z,c*cl*d.x+c*sl*d.y+s*d.z};
}
Vec3 enuToEcef(Vec3 p,GeoPoint o){
    double lat=o.latitude*Radians,lon=o.longitude*Radians,s=std::sin(lat),c=std::cos(lat),sl=std::sin(lon),cl=std::cos(lon);
    return geodeticToEcef(o)+Vec3{-sl*p.x-s*cl*p.y+c*cl*p.z,cl*p.x-s*sl*p.y+c*sl*p.z,c*p.y+s*p.z};
}
}
