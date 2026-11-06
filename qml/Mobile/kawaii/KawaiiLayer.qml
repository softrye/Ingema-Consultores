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
        width: Math.min(116,kawaiiLayer.width*0.26); height: width
        x: 8; y: kawaiiLayer.height-height-72+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.5)*5:0)
        opacity: kawaiiLayer.dark ? 0.16 : 0.24
    }
    KawaiiMascot {
        active: kawaiiLayer.active; frame: 1; tilePixels: 96
        width: Math.min(124,kawaiiLayer.width*0.28); height: width
        x: kawaiiLayer.width-width-8; y: 24+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.4)*6:0)
        opacity: kawaiiLayer.dark ? 0.18 : 0.27
    }
    Repeater {
        model: kawaiiLayer.active ? (kawaiiLayer.lowCost?3:6) : 0
        delegate: Image {
            required property int index
            width: index%2?14:20; height: width
            x: ((index*37+13)%89)/100*kawaiiLayer.width
            y: ((index*23+18)%83)/100*kawaiiLayer.height+(kawaiiLayer.moving?Math.sin(kawaiiLayer.seconds*0.45+index)*6:0)
            source: "qrc:/images/kawaii/sparkle.svg"
            sourceSize: Qt.size(40,40)
            opacity: kawaiiLayer.dark ? 0.25 : 0.38
            rotation: index*19
        }
    }
}
