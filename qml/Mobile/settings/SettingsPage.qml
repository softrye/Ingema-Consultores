import QtQuick

// Página de ajustes: encabezado (atrás · título · «···») y contenido desplazable.
Item {
    id: page
    property var ui
    property string title: ""
    property string footer: ""
    property bool showMore: false
    readonly property bool dark: !!ui && ui.darkTheme === true
    readonly property color inkColor: dark ? "#F2F4F8" : "#151A30"
    property Component bottomBar: null                 // barra fija inferior (p. ej. «Guardar cambios»)
    default property alias content: body.data
    signal back()
    signal more()
    // Entrada del contenido: sube y aparece (se repite cada vez que se abre Configuración).
    function replay() {
        enterAnim.stop()
        body.opacity = 0
        enterShift.y = 26 * page.ui.u
        enterAnim.start()
    }

    Item {
        id: header
        width: parent.width; height: 56 * page.ui.u + page.ui.topInset
        Text { x: 12 * page.ui.u; y: page.ui.topInset + 14 * page.ui.u; text: String.fromCharCode(0xE06E); color: page.inkColor
               font.family: page.ui.iconFamily; font.pixelSize: 24 * page.ui.u
               MouseArea { anchors.fill: parent; anchors.margins: -12 * page.ui.u; onClicked: page.back() } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: page.ui.topInset + 14 * page.ui.u; text: page.title; color: page.inkColor
               font.family: page.ui.fontFamily; font.pixelSize: 19 * page.ui.u; font.weight: Font.Bold }
        Text { visible: page.showMore; anchors.right: parent.right; anchors.rightMargin: 14 * page.ui.u; y: page.ui.topInset + 14 * page.ui.u
               text: String.fromCharCode(0xE0B6); color: page.inkColor; font.family: page.ui.iconFamily; font.pixelSize: 22 * page.ui.u
               MouseArea { anchors.fill: parent; anchors.margins: -12 * page.ui.u; onClicked: page.more() } }
    }
    Flickable {
        anchors.top: header.bottom; anchors.bottom: bottomHost.top
        width: parent.width
        contentHeight: body.height + footerText.height + 40 * page.ui.u
        boundsBehavior: Flickable.DragOverBounds
        clip: true
        Column {
            id: body; x: 16 * page.ui.u; width: parent.width - 2 * x; spacing: 12 * page.ui.u
            opacity: 0
            transform: Translate { id: enterShift; y: 18 * page.ui.u }
            Component.onCompleted: page.replay()
        }
        ParallelAnimation {
            id: enterAnim
            SequentialAnimation {
                PauseAnimation { duration: page.ui.reducedMotion ? 0 : 90 }
                NumberAnimation { target: body; property: "opacity"; to: 1; duration: page.ui.reducedMotion ? 0 : 420; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: page.ui.reducedMotion ? 0 : 90 }
                NumberAnimation { target: enterShift; property: "y"; to: 0; duration: page.ui.reducedMotion ? 0 : 620; easing.type: Easing.OutQuint }
            }
        }
        Text { id: footerText; y: body.height + 16 * page.ui.u; width: parent.width; horizontalAlignment: Text.AlignHCenter
               text: page.footer; visible: text.length > 0; color: page.dark ? "#A3A9B6" : "#5A6378"
               font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
    }
    Item {
        id: bottomHost
        anchors.bottom: parent.bottom; width: parent.width
        height: page.bottomBar ? bottomLoader.height + 28 * page.ui.u : 0
        Rectangle {                                       // velo para que la barra flote sobre el contenido
            anchors.fill: parent; visible: page.bottomBar !== null
            gradient: Gradient { GradientStop { position: 0.0; color: page.dark ? Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0) : Qt.rgba(243 / 255, 246 / 255, 251 / 255, 0) }
                                 GradientStop { position: 0.35; color: page.dark ? Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.92) : Qt.rgba(243 / 255, 246 / 255, 251 / 255, 0.85) } }
        }
        Loader { id: bottomLoader; x: 16 * page.ui.u; y: 10 * page.ui.u; width: parent.width - 32 * page.ui.u; sourceComponent: page.bottomBar }
    }
}
