import QtQuick
Item {
    id: decor
    property var controller: null
    property bool active: false
    property bool vertical: false
    property real u: 1
    enabled: false
    visible: active
    KawaiiMascot {
        active: decor.active; frame: 0; tilePixels: 96
        width: 34*decor.u; height: width
        x: -4*decor.u; y: -18*decor.u
    }
    KawaiiMascot {
        active: decor.active; frame: 1; tilePixels: 96
        width: 38*decor.u; height: width
        x: parent.width-width+4*decor.u
        y: decor.vertical ? parent.height-height+8*decor.u : -20*decor.u
    }
    KawaiiMascot {
        id: guest
        readonly property bool showing: decor.active && !decor.vertical && decor.controller && decor.controller.kawaiiGuestVisible
        readonly property real progress: showing ? Math.max(0,Math.min(1,1-decor.controller.kawaiiClock.remainingMs/8000)) : 0
        readonly property real t: decor.controller ? decor.controller.visualSeconds : 0
        active: showing
        visible: showing
        frame: decor.controller && decor.controller.kawaiiClock.serial%2===0 ? 3 : 2
        tilePixels: 192
        width: 88*decor.u; height: width
        x: Math.max(24*decor.u,Math.min(parent.width-width-12*decor.u,parent.width*0.57))
        y: -height+15*decor.u-Math.sin(Math.min(1,progress*5)*Math.PI)*12*decor.u
        opacity: Math.max(0,Math.min(1,progress*8,(1-progress)*8))
        rotation: frame===3 ? Math.sin(t*3.5)*3 : Math.sin(t*1.8)*1.2
    }
}
