import QtQuick
import "../../qml/Mobile/renditions"

// Vista previa SÓLO DE DESARROLLO de las auras de Rendiciones (no se empaqueta:
// no figura en CMake ni en el módulo InGe.Mobile). Muestra el componente real
// RendicionesSyncAura con los tres pares de color, sin tocar la sincronización
// real, el bridge ni Supabase. Abrir con el visor de Qt (no compila nada):
//   C:\Qt\6.9.3\mingw_64\bin\qml.exe tests\renditions\aura_preview.qml
// Toque en un panel: alterna gama baja (ciclo ×1.4) para comparar.
Rectangle {
    width: 1200; height: 860
    color: "#FFFFFF"
    Row {
        anchors.fill: parent
        Repeater {
            model: [["synced", "Sincronizado: azul + verde"], ["error", "Error: azul marino + rojo"],
                    ["pending", "Neutro: azul + gris (sin éxito ni error)"]]
            delegate: Rectangle {
                required property var modelData
                width: 400; height: parent.height
                color: "#FFFFFF"
                border.color: "#E3E8F0"
                clip: true
                RendicionesSyncAura {
                    id: preview
                    anchors.fill: parent
                    mode: modelData[0]
                    running: true
                }
                Rectangle {                         // panel y tarjeta como en la app (38% / 90%)
                    x: 12; y: 180; width: parent.width - 24; height: parent.height - 200
                    radius: 30; color: Qt.rgba(1, 1, 1, 0.38); border.color: Qt.rgba(1, 1, 1, 0.95)
                    Rectangle { x: 18; y: 70; width: parent.width - 36; height: 220; radius: 22; color: Qt.rgba(1, 1, 1, 0.90) }
                }
                Text {
                    x: 16; y: 16
                    text: modelData[1] + (preview.lowCost ? " · gama baja" : "")
                    font.pixelSize: 16; color: "#151A30"
                }
                MouseArea { anchors.fill: parent; onClicked: preview.lowCost = !preview.lowCost }
            }
        }
    }
}
