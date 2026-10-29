import QtQuick
import "RStyle.js" as S

// Panel "Estado de Rendiciones" (diagnóstico contextual). Se abre SÓLO a
// petición del usuario desde el Dock (Home de Rendiciones o sugerencias de la
// ficha); nunca se abre solo. Mismo menú 3D Touch (RGlassMenu) que el resto del
// Dock, en tamaño grande y desplazable. Lista el modelo CENTRALIZADO de
// incidencias (RenditionsUi.diagnostics, catálogo determinista en C++): nombre,
// ubicación, qué sucede, cómo solucionarlo y la acción real disponible.
// Sin IA: [aiExtension] es el punto de extensión para sugerencias futuras y sólo
// se carga con la IA de Rendiciones habilitada (hoy INGE_RENDITIONS_AI_ENABLED=0).
RGlassMenu {
    id: panel
    objectName: "diagnosticsPanel"
    property var app
    property var diagnostics: ({})
    property Component aiExtension: null
    property bool aiEnabled: false
    property string busyKey: ""                 // acción en curso (anti doble toque)
    signal runAction(var incident)
    cardWidth: 380 * ui.u

    readonly property var incidents: {
        var list = diagnostics && diagnostics.incidents ? diagnostics.incidents : []
        var out = []
        for (var i = 0; i < list.length; ++i) out.push(list[i])
        return out
    }
    readonly property int errors: Number(diagnostics && diagnostics.errors || 0)
    readonly property int attention: Number(diagnostics && diagnostics.attention || 0)

    Item {
        width: parent.width
        height: 56 * panel.ui.u
        Column {
            x: 6 * panel.ui.u
            width: parent.width - 56 * panel.ui.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * panel.ui.u
            Text { text: "Estado de Rendiciones"; color: S.text
                   font.family: panel.ui.fontFamily; font.pixelSize: 19 * panel.ui.u; font.weight: Font.DemiBold }
            Text {
                objectName: "diagnosticsSummary"
                width: parent.width
                text: panel.incidents.length === 0 ? "Sin fallos técnicos activos"
                     : (panel.errors > 0 ? panel.errors + (panel.errors === 1 ? " incidencia bloqueante" : " incidencias bloqueantes") : "")
                       + (panel.errors > 0 && panel.attention > 0 ? " · " : "")
                       + (panel.attention > 0 ? panel.attention + (panel.attention === 1 ? " requiere atención" : " requieren atención") : "")
                color: S.muted; elide: Text.ElideRight
                font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
            }
        }
        Rectangle {
            objectName: "diagnosticsClose"
            width: 40 * panel.ui.u; height: width; radius: width / 2
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: closeTap.pressed ? S.ink(0.12) : S.ink(0.05)
            Text { anchors.centerIn: parent; text: String.fromCharCode(0xE1B2); color: S.text
                   font.family: panel.ui.iconFamily; font.pixelSize: 20 * panel.ui.u }
            MouseArea { id: closeTap; anchors.fill: parent; onClicked: panel.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cerrar"
        }
    }

    Flickable {
        id: list
        width: parent.width
        height: Math.min(contentHeight, Math.max(160 * panel.ui.u, panel.height * 0.58))
        contentWidth: width
        contentHeight: rows.implicitHeight + 6 * panel.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height
        Column {
            id: rows
            width: list.width
            spacing: 8 * panel.ui.u
            Item { width: 1; height: 2 * panel.ui.u }
            Repeater {
                model: panel.incidents
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool blocking: modelData.severity === "error"
                    readonly property var act: modelData.action || ({})
                    objectName: "incident:" + modelData.key
                    width: rows.width
                    height: body.implicitHeight + 24 * panel.ui.u
                    radius: 16 * panel.ui.u
                    color: blocking ? Qt.rgba(198 / 255, 47 / 255, 62 / 255, 0.06) : Qt.rgba(242 / 255, 178 / 255, 27 / 255, 0.09)
                    border.width: 1
                    border.color: blocking ? Qt.rgba(198 / 255, 47 / 255, 62 / 255, 0.18) : Qt.rgba(242 / 255, 178 / 255, 27 / 255, 0.28)
                    Column {
                        id: body
                        x: 14 * panel.ui.u; y: 12 * panel.ui.u
                        width: parent.width - 28 * panel.ui.u
                        spacing: 4 * panel.ui.u
                        Row {
                            spacing: 8 * panel.ui.u
                            width: parent.width
                            Rectangle { width: 10 * panel.ui.u; height: width; radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: row.blocking ? S.danger : S.warning }
                            Text { width: parent.width - 18 * panel.ui.u; text: row.modelData.title; color: S.text; wrapMode: Text.Wrap
                                   font.family: panel.ui.fontFamily; font.pixelSize: 16 * panel.ui.u; font.weight: Font.DemiBold }
                        }
                        Text { width: parent.width; text: row.modelData.area + "  ·  " + row.modelData.code; color: S.muted; wrapMode: Text.Wrap
                               font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u }
                        Text { width: parent.width; topPadding: 4 * panel.ui.u; text: "Qué sucede: " + row.modelData.what
                               color: S.text; wrapMode: Text.Wrap; font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u }
                        Text { width: parent.width; visible: String(row.modelData.cause || "").length > 0
                               text: "Causa: " + String(row.modelData.cause || ""); color: S.muted; wrapMode: Text.Wrap
                               font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u }
                        Text { width: parent.width; text: "Cómo solucionarlo: " + row.modelData.how
                               color: S.text; wrapMode: Text.Wrap; font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u }
                        RButton {
                            visible: String(row.act.kind || "").length > 0
                            objectName: "incidentAction:" + row.modelData.key
                            ui: panel.ui
                            primary: row.act.kind !== "dismiss"
                            label: String(row.act.label || "")
                            busy: panel.busyKey === row.modelData.key
                            onActivated: panel.runAction(row.modelData)
                        }
                    }
                }
            }
            Text {
                visible: panel.incidents.length === 0
                width: rows.width
                topPadding: 8 * panel.ui.u; bottomPadding: 8 * panel.ui.u
                text: "Todo en orden. No hay fallos técnicos activos.\nLos gastos por completar aparecen como sugerencias dentro de cada rendición; no son fallos."
                color: S.muted; wrapMode: Text.Wrap
                font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
            }
            // Punto de extensión: sugerencias de InGe IA (desactivado en esta versión).
            Loader {
                width: rows.width
                active: panel.aiEnabled && panel.aiExtension !== null
                sourceComponent: panel.aiExtension
            }
        }
    }
}
