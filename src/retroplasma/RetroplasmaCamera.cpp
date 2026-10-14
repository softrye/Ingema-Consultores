#include "RetroplasmaCamera.h"
#include "RetroplasmaPlanet.h"
#include <algorithm>
namespace inge::rp {
void Camera::reset(Bounds b,bool snap){m_planetary=false;m_extent=std::max(10.0,radius(b));m_initial={center(b),0,0.7,std::clamp(m_extent*2.8,2.0,1e7)};m_target=m_initial;if(snap)m_current=m_target;}
void Camera::resetPlanet(bool snap){m_planetary=true;m_targetHeading=0;m_initial={{0,0,0},-60*Radians,5*Radians,22000000};m_target=m_initial;if(snap){m_current=m_target;m_heading=0;}else m_target.yaw=m_current.yaw+std::remainder(m_target.yaw-m_current.yaw,2*Pi);}
void Camera::framePlanet(double aspect,bool snap){
    resetPlanet(snap);
    // Fit the whole limb to the shortest viewport dimension, including portrait phones.
    double angle=std::atan(std::tan(22.5*Radians)*std::clamp(aspect,.28,1.0))*.90;
    m_initial.distance=m_target.distance=std::clamp(EarthRadius/std::sin(angle)-EarthRadius,2000.0,50000000.0);
    if(snap)m_current.distance=m_target.distance;
}
void Camera::goToGeographic(GeoPoint p,double cameraAltitude){if(!m_planetary||!std::isfinite(p.latitude)||!std::isfinite(p.longitude)||!std::isfinite(p.altitude)||!std::isfinite(cameraAltitude))return;m_target.yaw+=std::remainder(p.longitude*Radians-m_target.yaw,2*Pi);m_target.pitch=std::clamp(p.latitude*Radians,-Pi*.5+1e-6,Pi*.5-1e-6);m_target.focus.y=p.altitude;m_target.distance=std::clamp(cameraAltitude,2000.0,50000000.0);}
void Camera::rotateHeading(double radians){if(m_planetary&&std::isfinite(radians))m_targetHeading+=std::clamp(radians,-Pi,Pi);}
GeoPoint Camera::planetPosition()const{return {m_current.pitch/Radians,std::remainder(m_current.yaw/Radians,360.0),m_current.distance+m_current.focus.y};}
GeoPoint Camera::planetTarget()const{auto p=planetPosition();p.altitude=m_current.focus.y;return p;}
void Camera::step(double dt){if(!std::isfinite(dt)||dt<=0)return;double a=1-std::exp(-std::min(dt,0.25)/0.16);m_current.focus=m_current.focus+(m_target.focus-m_current.focus)*a;m_current.yaw+=(m_target.yaw-m_current.yaw)*a;m_current.pitch+=(m_target.pitch-m_current.pitch)*a;m_current.distance+=(m_target.distance-m_current.distance)*a;m_heading+=(m_targetHeading-m_heading)*a;}
void Camera::zoom(double factor){if(std::isfinite(factor)&&factor>0)m_target.distance=std::clamp(m_target.distance*factor,m_planetary?2000.0:2.0,m_planetary?50000000.0:1e7);}
void Camera::orbit(double yaw,double pitch){if(std::isfinite(yaw)&&std::isfinite(pitch)){m_target.yaw+=std::clamp(yaw,-Pi,Pi);m_target.pitch=std::clamp(m_target.pitch+pitch,m_planetary?-Pi*.5+1e-6:0.03,m_planetary?Pi*.5-1e-6:1.54);}}
void Camera::pan(double side,double forward){if(!std::isfinite(side)||!std::isfinite(forward))return;if(m_planetary){double speed=std::clamp(m_current.distance/EarthRadius*.002,1e-6,.006);orbit((side*std::cos(m_heading)+forward*std::sin(m_heading))*speed,(forward*std::cos(m_heading)-side*std::sin(m_heading))*speed);return;}double speed=std::clamp(m_current.distance*0.002,0.01,20000.0);Vec3 right{std::cos(m_current.yaw),0,-std::sin(m_current.yaw)},ahead{-std::sin(m_current.yaw),0,-std::cos(m_current.yaw)};m_target.focus=m_target.focus+(right*side+ahead*forward)*speed;}
void Camera::goTo(Vec3 p){if(finite(p))m_target.focus=p;}
Vec3 Camera::eye()const{if(m_planetary)return ecefToPlanet(geodeticToEcef(planetPosition()));double c=std::cos(m_current.pitch),s=std::sin(m_current.pitch);return m_current.focus+Vec3{std::sin(m_current.yaw)*c,s,std::cos(m_current.yaw)*c}*m_current.distance;}
Mat4 Camera::viewProjection(double aspect)const{
    if(m_planetary){auto p=planetTarget();auto surface=ecefToPlanet(geodeticToEcef(p));double t=std::clamp((m_current.distance-1000000)/6000000,0.0,1.0);auto focus=surface*(1-t);
        double phi=p.latitude*Radians,lambda=p.longitude*Radians;Vec3 north{-std::sin(phi)*std::cos(lambda),std::cos(phi),std::sin(phi)*std::sin(lambda)};
        auto right=normalized(cross(focus-eye(),north));north=north*std::cos(m_heading)+right*std::sin(m_heading);
        double nearPlane=std::max(.00001,m_current.distance/EarthRadius*.25),farPlane=length(eye())+2.1;
        return perspective(45*Radians,aspect,nearPlane,farPlane)*lookAt(eye(),focus,north);
    }
    double nearPlane=std::clamp(m_current.distance*0.0005,0.05,500.0),farPlane=std::max(10000.0,m_current.distance*4+m_extent*4);return perspective(45*Radians,aspect,nearPlane,farPlane)*lookAt(eye(),m_current.focus,{0,1,0});
}
}
