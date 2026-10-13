import QtQuick

// A Qt surface for diagnostic pixels. It never substitutes a map/globe engine.
Rectangle {
    id: host
    required property var bridge
    property string fontFamily: ""
    property real u: 1
    color: "#07111C"
    radius: 14 * u
    clip: true
    Image {
        anchors.fill: parent
        anchors.margins: 4 * host.u
        visible: host.bridge.frameFresh
        source: host.bridge.frameUrl
        cache: false
        asynchronous: false
        fillMode: Image.PreserveAspectFit
    }
    Text {
        anchors.centerIn: parent
        width: parent.width - 32 * host.u
        visible: !host.bridge.frameFresh
        text: "Sin superficie interactiva de Google Earth\n\nLa prueba visual requiere cuadros actualizados y una fuente visible."
        color: "#B4C2D3"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: host.fontFamily
        font.pixelSize: 14 * host.u
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: captureLabel.implicitHeight + 16 * host.u
        color: "#D907111C"
        visible: host.bridge.frameFresh
        Text {
            id: captureLabel
            anchors.centerIn: parent
            width: parent.width - 20 * host.u
            text: "PRUEBA VISUAL · captura elegida por el usuario\nOrigen no verificado · sin control del globo"
            color: "#FFCF87"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: host.fontFamily
            font.pixelSize: 12 * host.u
        }
    }
    // No MouseArea/PanHandler forwards touches: ImageReader has no Earth input channel.
}
