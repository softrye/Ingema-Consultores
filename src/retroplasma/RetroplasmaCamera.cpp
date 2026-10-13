#include "RetroplasmaCamera.h"
#include <algorithm>
namespace inge::rp {
void Camera::reset(Bounds b,bool snap){m_extent=std::max(10.0,radius(b));m_initial={center(b),0,0.7,std::clamp(m_extent*2.8,2.0,1e7)};m_target=m_initial;if(snap)m_current=m_target;}
void Camera::step(double dt){if(!std::isfinite(dt)||dt<=0)return;double a=1-std::exp(-std::min(dt,0.25)/0.16);m_current.focus=m_current.focus+(m_target.focus-m_current.focus)*a;m_current.yaw+=(m_target.yaw-m_current.yaw)*a;m_current.pitch+=(m_target.pitch-m_current.pitch)*a;m_current.distance+=(m_target.distance-m_current.distance)*a;}
void Camera::zoom(double factor){if(std::isfinite(factor)&&factor>0)m_target.distance=std::clamp(m_target.distance*factor,2.0,1e7);}
void Camera::orbit(double yaw,double pitch){if(std::isfinite(yaw)&&std::isfinite(pitch)){m_target.yaw+=std::clamp(yaw,-Pi,Pi);m_target.pitch=std::clamp(m_target.pitch+pitch,0.03,1.54);}}
void Camera::pan(double side,double forward){if(!std::isfinite(side)||!std::isfinite(forward))return;double speed=std::clamp(m_current.distance*0.002,0.01,20000.0);Vec3 right{std::cos(m_current.yaw),0,-std::sin(m_current.yaw)},ahead{-std::sin(m_current.yaw),0,-std::cos(m_current.yaw)};m_target.focus=m_target.focus+(right*side+ahead*forward)*speed;}
void Camera::goTo(Vec3 p){if(finite(p))m_target.focus=p;}
Vec3 Camera::eye()const{double c=std::cos(m_current.pitch),s=std::sin(m_current.pitch);return m_current.focus+Vec3{std::sin(m_current.yaw)*c,s,std::cos(m_current.yaw)*c}*m_current.distance;}
Mat4 Camera::viewProjection(double aspect)const{double nearPlane=std::clamp(m_current.distance*0.0005,0.05,500.0),farPlane=std::max(10000.0,m_current.distance*4+m_extent*4);return perspective(45*Radians,aspect,nearPlane,farPlane)*lookAt(eye(),m_current.focus,{0,1,0});}
}
