import QtQuick

// Susto de Halloween a pantalla completa (~1,8 s). Sin animaciones propias: el
// zoom y el temblor se derivan del reloj único del HalloweenController
// (scareRemainingMs), que avanza con el Timer de InGeCoreFlow. Toque = cerrar.
Item {
    id: notice
    required property var controller
    property real bottomInset: 100
    visible: controller.scareVisible
    readonly property real progress: Math.max(0, Math.min(1, 1 - controller.scareRemainingMs / 1800))
    readonly property bool still: controller.staticNotice
    // Entrada en 0,25 s con rebote; luego queda en 1.
    readonly property real zoom: still ? 1 : progress < 0.14 ? 0.25 + progress / 0.14 * 0.95
                                              : progress < 0.25 ? 1.2 - (progress - 0.14) / 0.11 * 0.2 : 1
    // Temblor fuerte al inicio que se apaga.
    readonly property real shake: still ? 0 : Math.sin(progress * 90) * 14 * Math.max(0, 1 - progress * 1.6)

    Rectangle {
        anchors.fill: parent
        color: "#2B1047"
        opacity: notice.still ? 0.82 : Math.min(0.88, notice.progress * 6) * (notice.progress > 0.85 ? (1 - notice.progress) / 0.15 : 1)
    }
    Column {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: notice.shake
        anchors.verticalCenterOffset: -notice.shake * 0.4
        spacing: 8
        scale: notice.zoom
        rotation: notice.shake * 0.35
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(notice.width, notice.height) * 0.62; height: width
            sourceSize: Qt.size(512, 512)
            source: "qrc:/images/halloween/" + (["ghost", "cat", "pumpkin"][Math.max(0, notice.controller.scareKind)]) + ".svg"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: notice.controller.scareKind === 1 ? "¡Miau!" : "¡Buuu!"
            color: "#FF8A1F"; font.pixelSize: Math.min(notice.width, notice.height) * 0.14; font.bold: true
            style: Text.Outline; styleColor: "#170A28"
        }
    }
    MouseArea { anchors.fill: parent; onClicked: notice.controller.dismiss() }
    Accessible.role: Accessible.Button
    Accessible.name: "Susto de Halloween. Toca para cerrar."
    Accessible.onPressAction: notice.controller.dismiss()
}
