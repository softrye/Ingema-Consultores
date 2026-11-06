pragma ComponentBehavior: Bound
import QtQuick
import ".." as Mobile
Item {
    id: kawaiiLayer
    property var controller: null
    property bool active: false
    property bool dark: false
    property bool lowCost: false
    property string mode: "unknown"
    readonly property bool moving: active && controller && controller.motionActive
    readonly property real seconds: controller ? controller.visualSeconds : 0
    enabled: false
    visible: active
    clip: true
    Rectangle { anchors.fill: parent; color: kawaiiLayer.dark ? "#21192C" : "#FFF5FB" }
    Mobile.AuroraField {
        anchors.fill: parent
        visible: kawaiiLayer.active
        motion: kawaiiLayer.moving
        lowPower: kawaiiLayer.lowCost
        baseColor: kawaiiLayer.dark ? "#21192C" : "#FFF5FB"
        deepColor: kawaiiLayer.dark ? "#13283B" : "#E9F8FF"
        primaryColor: "#FF83BE"
        accentColor: "#8BDCF6"
        tintColor: kawaiiLayer.mode==="error" || kawaiiLayer.mode==="offline" ? "#D9483B" : "#F2B21B"
        tintAmount: ["error","offline","attention"].indexOf(kawaiiLayer.mode)>=0 ? 0.65 : 0
    }
    KawaiiMascot {
        active: kawaiiLayer.active; frame: 0; tilePixels: 96
        width: Math.min(142,kawaiiLayer.width*0.3); height: width
        x: -8; y: Math.max(112,kawaiiLayer.height*0.17)+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.5)*5:0)
        opacity: kawaiiLayer.dark ? 0.64 : 0.76
    }
    KawaiiMascot {
        active: kawaiiLayer.active; frame: 1; tilePixels: 96
        width: Math.min(148,kawaiiLayer.width*0.29); height: width
        x: kawaiiLayer.width-width+12; y: 30+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.4)*6:0)
        opacity: kawaiiLayer.dark ? 0.68 : 0.80
    }
    // Static and animated engineer hats reuse the global visual clock.
    Repeater {
        model: kawaiiLayer.active ? 3 : 0
        delegate: Image {
            required property int index
            width: 30+index*5; height: width
            x: kawaiiLayer.width * ([0.08,0.77,0.37][index])
            y: kawaiiLayer.height * ([0.41,0.64,0.89][index])
                +(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.4+index)*4:0)
            source: "qrc:/images/kawaii/helmet.svg"
            sourceSize: Qt.size(48,40)
            opacity: kawaiiLayer.dark ? 0.32 : 0.45
            rotation: [-18,12,-9][index]
        }
    }
    Repeater {
        model: kawaiiLayer.active ? (kawaiiLayer.lowCost?6:12) : 0
        delegate: Image {
            required property int index
            width: index%2?18:25; height: width
            x: ((index*37+13)%89)/100*kawaiiLayer.width
            y: ((index*23+18)%83)/100*kawaiiLayer.height+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.45+index)*6:0)
            source: "qrc:/images/kawaii/sparkle.svg"
            sourceSize: Qt.size(40,40)
            opacity: kawaiiLayer.dark ? 0.47 : 0.62
            rotation: index*19
        }
    }
}
