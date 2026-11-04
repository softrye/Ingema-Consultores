import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "RStyle.js" as S
import ".." as Mobile                          // GlassSurface: Liquid Glass oficial
import InGe.CoreFlow 3.0 as CoreFlowModule           // ganchos «Extrema» del motor único

// Diálogo de confirmación (Liquid Glass): tarjeta de vidrio claro centrada,
// icono según la acción, texto centrado y dos botones anchos. Misma API ask().
Popup {
    id: confirm
    property var ui
    property string title: ""
    property string message: ""
    property string acceptLabel: "Confirmar"
    property bool destructive: false
    property var acceptCallback: null
    // Icono y tono deducidos de la acción: archivar (ámbar), borrar (rojo), otra (azul).
    readonly property bool archiving: /archiv/i.test(acceptLabel)
    readonly property color tone: archiving ? "#D08A12" : (destructive ? "#D64550" : S.accent)
    readonly property int glyph: archiving ? 0xE041 : (destructive ? 0xE18D : 0xE0F9)

    function ask(titleText, messageText, label, destructiveAction, callback) {
        title = titleText
        message = messageText
        acceptLabel = label || "Confirmar"
        destructive = destructiveAction === true
        acceptCallback = callback
        open()
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 48 * ui.u : 340, 380 * ui.u)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: 22 * ui.u
    topPadding: 26 * ui.u

    // «Extrema»: nace más pequeña y desenfocada (sheetStartScale / sheetOriginBlur de InGeCoreFlow).
    readonly property var flowCore: CoreFlowModule.InGeCoreFlow
    readonly property bool extreme: flowCore.extremeMotion === true
    property real originBlur: 0
    enter: Transition { ParallelAnimation {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: confirm.extreme ? confirm.flowCore.sheetStartScale : 0.88; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: confirm; property: "originBlur"; from: confirm.flowCore.sheetOriginBlur; to: 0; duration: 320; easing.type: Easing.OutCubic } } }
    exit: Transition { ParallelAnimation {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.InCubic } } }

    // Velo esmerilado detrás (atenúa sin ennegrecer).
    Overlay.modal: Rectangle {
        color: Qt.rgba(14 / 255, 24 / 255, 44 / 255, 0.38)
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    background: Item {
        readonly property bool liquid: (confirm.ui.liquidGlass !== false && !!confirm.ui.liquidGlassMaterial && !!confirm.ui.cardGlassUi)
        Mobile.GlassSurface {                // Liquid Glass oficial (preset único del Dock)
            visible: confirm.ui.liquidGlass !== false && !!confirm.ui.liquidGlassMaterial && !!confirm.ui.cardGlassUi && (textureReady || fallbackOn)
            ui: confirm.ui.cardGlassUi || null
            material: confirm.ui.liquidGlassMaterial || null
            tint: confirm.ui.dockGlassTint                  // oscuro igual que claro y el Dock: sin tinte negro
            radius: 28 * confirm.ui.u
            margin: 10 * confirm.ui.u
        }
        Rectangle {
            id: glassShape
            anchors.fill: parent; radius: 28 * confirm.ui.u
            color: S.halloween ? S.popup : S.dark ? Qt.rgba(18 / 255, 22 / 255, 32 / 255, 0.97) : S.glass(0.97)
            border.width: 1; border.color: S.edge(0.95)
            visible: false
        }
        MultiEffect {                                  // sombra suave de la tarjeta
            visible: !parent.liquid
            anchors.fill: glassShape; source: glassShape
            shadowEnabled: true; shadowColor: Qt.rgba(10 / 255, 20 / 255, 40 / 255, 0.35)
            shadowBlur: 1.0; shadowVerticalOffset: 10 * confirm.ui.u; autoPaddingEnabled: true
        }
        Rectangle {                                    // brillo superior del vidrio
            visible: !parent.liquid
            anchors.fill: parent; anchors.margins: 1; radius: 27 * confirm.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: S.glass(0.55) }
                GradientStop { position: 0.35; color: S.glass(0.0) }
            }
        }
    }

    contentItem: Column {
        layer.enabled: confirm.originBlur > 0.01
        layer.effect: MultiEffect { blurEnabled: true; blur: confirm.originBlur; blurMax: 32 }
        spacing: 10 * confirm.ui.u
        Rectangle {                                    // icono de la acción
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56 * confirm.ui.u; height: width; radius: width / 2
            color: Qt.rgba(confirm.tone.r, confirm.tone.g, confirm.tone.b, 0.13)
            border.width: 1; border.color: Qt.rgba(confirm.tone.r, confirm.tone.g, confirm.tone.b, 0.22)
            Text { anchors.centerIn: parent; text: String.fromCharCode(confirm.glyph); color: confirm.tone
                   font.family: confirm.ui.iconFamily; font.pixelSize: 26 * confirm.ui.u }
        }
        Item { width: 1; height: 2 * confirm.ui.u }
        Text {
            width: parent.width
            text: confirm.title
            color: S.text
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: confirm.ui.fontFamily
            font.pixelSize: 19 * confirm.ui.u
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: confirm.message
            color: S.muted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.15
            font.family: confirm.ui.fontFamily
            font.pixelSize: 14.5 * confirm.ui.u
        }
        Item { width: 1; height: 8 * confirm.ui.u }
        Row {
            id: actions
            width: parent.width
            spacing: 10 * confirm.ui.u
            Repeater {
                model: 2
                delegate: Rectangle {
                    id: btn
                    required property int index
                    readonly property bool accept: index === 1
                    width: (actions.width - actions.spacing) / 2; height: 50 * confirm.ui.u; radius: height / 2
                    color: accept ? confirm.tone : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.07)
                    border.width: accept ? 0 : 1; border.color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.06)
                    scale: tap.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Text { anchors.centerIn: parent; width: parent.width - 16 * confirm.ui.u; horizontalAlignment: Text.AlignHCenter
                           elide: Text.ElideRight; text: btn.accept ? confirm.acceptLabel : "Cancelar"
                           color: btn.accept ? (confirm.destructive || confirm.archiving ? "white" : S.onAccent) : S.text
                           font.family: confirm.ui.fontFamily; font.pixelSize: 15.5 * confirm.ui.u; font.weight: Font.DemiBold }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        onClicked: {
                            if (!btn.accept) { confirm.close(); return }
                            var callback = confirm.acceptCallback
                            confirm.acceptCallback = null
                            confirm.close()
                            if (callback) callback()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: btn.accept ? confirm.acceptLabel : "Cancelar"
                }
            }
        }
    }
}
