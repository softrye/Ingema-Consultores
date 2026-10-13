#pragma once
#include "RetroplasmaMath.h"
namespace inge::rp {
struct CameraPose {Vec3 focus;double yaw=0,pitch=0.7,distance=500;};
class Camera {
public:
    void reset(Bounds,bool snap=false);
    void step(double seconds);
    void zoom(double factor);
    void orbit(double yaw,double pitch);
    void pan(double sideways,double forward);
    void goTo(Vec3 position);
    void north(){m_target.yaw=0;}
    CameraPose pose()const{return m_current;}
    Vec3 eye()const;
    Mat4 viewProjection(double aspect)const;
private:
    CameraPose m_current,m_target,m_initial;
    double m_extent=1000;
};
}
