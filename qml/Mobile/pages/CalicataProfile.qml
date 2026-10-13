pragma ComponentBehavior: Bound
import QtQuick
import "../lib/CalicataRules.js" as Rules

// Columna estratigráfica de ingeniería (Perfil > Vista del perfil).
// Un único eje lineal de profundidad; cada estrato se dibuja en su intervalo
// real con las capas SUCS del laboratorio (qrc:/SUCS/web, mismas teselas que
// Web resolveCalicataSucsPattern) sobre el color del estrato. Nivel freático
// opcional. Solo lectura: tocar una banda la selecciona.
Item {
    id: profile
    required property var model
    // function(index) -> { files: [url], color, label }: trama real, color y
    // rótulo del estrato en una sola lectura.
    property var bandInfo: null
    property int selectedIndex: -1
    property real totalDepth: 0
    property real waterDepth: NaN
    property bool showWater: true
    property real scaleFactor: 1
    property color ink: "#111311"
    property color muted: "#656965"
    property color gridColor: "#D8DAD6"
    property color accent: "#1F5BD6"
    property color waterColor: "#1F5BD6"
    property color paper: "#FFFFFF"
    property string emptyText: "Sin estratos registrados"
    signal selected(int index)

    readonly property real topPad: 10 * scaleFactor
    readonly property real bottomPad: 22 * scaleFactor
    readonly property real axisWidth: 44 * scaleFactor
    readonly property real columnWidth: Math.max(56 * scaleFactor, Math.min(128 * scaleFactor, width * 0.40))
    readonly property real columnX: axisWidth + 10 * scaleFactor
    readonly property real plotHeight: Math.max(0, height - topPad - bottomPad)
    // Una sola columna con escala proporcional; 3 m solo al no tener datos.
    readonly property real axisDepth: totalDepth > 0 ? totalDepth : 3
    readonly property real tickStep: axisDepth / 6
    readonly property bool waterVisible: showWater && isFinite(waterDepth) && waterDepth >= 0
                                         && waterDepth <= axisDepth
    function depthY(value) {
        return topPad + Math.max(0, Math.min(1, value / axisDepth)) * plotHeight
    }

    Rectangle { anchors.fill: parent; color: profile.paper }

    // Eje de profundidad con marcas regulares.
    Rectangle {
        x: profile.axisWidth - 1
        y: profile.topPad
        width: 1
        height: profile.plotHeight
        color: profile.gridColor
    }
    Repeater {
        model: 7
        delegate: Item {
            required property int index
            readonly property real depth: index === 6 ? profile.axisDepth : index * profile.tickStep
            y: profile.depthY(depth)
            width: profile.width
            Rectangle { x: profile.axisWidth - 6 * profile.scaleFactor; width: 6 * profile.scaleFactor; height: 1; color: profile.muted }
            Rectangle {
                x: profile.columnX + profile.columnWidth
                width: Math.max(0, profile.width - x)
                height: 1
                color: profile.gridColor
                opacity: 0.45
            }
            Text {
                y: -height / 2
                width: profile.axisWidth - 10 * profile.scaleFactor
                text: parent.depth.toFixed(2)
                horizontalAlignment: Text.AlignRight
                color: profile.muted
                font.pixelSize: 11 * profile.scaleFactor
            }
        }
    }

    // Fondo de la columna.
    Rectangle {
        x: profile.columnX
        y: profile.topPad
        width: profile.columnWidth
        height: profile.plotHeight
        color: "transparent"
        border.width: 1
        border.color: profile.gridColor
    }

    Repeater {
        id: layers
        model: profile.model
        delegate: Item {
            id: layer
            required property int index
            required property string de
            required property string a
            required property string sucs
            required property string material_origin
            required property string _extraJson
            readonly property real fromDepth: Rules.parseDecimalSafe(de)
            readonly property real toDepth: Rules.parseDecimalSafe(a)
            readonly property bool validInterval: isFinite(fromDepth) && isFinite(toDepth)
                && fromDepth >= 0 && toDepth > fromDepth
            readonly property bool isSelected: index === profile.selectedIndex
            // Solo se recalcula cuando cambian los datos de ESTE estrato.
            readonly property var info: {
                var evidence = layer._extraJson + layer.sucs + layer.material_origin + layer.index
                return profile.bandInfo ? profile.bandInfo(layer.index) : { files: [], color: "#EDEDED", label: "" }
            }
            readonly property var files: info.files
            readonly property color fill: info.color
            readonly property string tag: "E" + (index + 1)
            readonly property real labelRoom: 30 * profile.scaleFactor
            x: profile.columnX
            y: validInterval ? profile.depthY(fromDepth) : 0
            width: profile.columnWidth
            height: validInterval ? Math.max(0, profile.depthY(toDepth) - profile.depthY(fromDepth)) : 0
            visible: validInterval && fromDepth < profile.axisDepth
            clip: true

            Rectangle { anchors.fill: parent; color: layer.fill; opacity: 0.62 }
            Row {
                anchors.fill: parent
                Repeater {
                    model: layer.files
                    delegate: Image {
                        required property string modelData
                        width: layer.width / Math.max(1, layer.files.length)
                        height: layer.height
                        source: modelData
                        fillMode: Image.Tile
                        sourceSize.width: 24 * profile.scaleFactor
                        sourceSize.height: 24 * profile.scaleFactor
                        cache: true
                        smooth: true
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: profile.ink; opacity: 0.85 }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: profile.ink; opacity: 0.85 }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: layer.isSelected ? 2 : 0
                border.color: profile.accent
            }
            // Rótulo: "E1 / RA" si cabe; solo "E1" en bandas bajas.
            Rectangle {
                anchors.centerIn: parent
                visible: layer.height >= 14 * profile.scaleFactor
                width: bandLabel.implicitWidth + 8 * profile.scaleFactor
                height: Math.min(layer.height - 2, bandLabel.implicitHeight + 2 * profile.scaleFactor)
                radius: 4 * profile.scaleFactor
                color: Qt.rgba(1, 1, 1, 0.86)
                Text {
                    id: bandLabel
                    anchors.centerIn: parent
                    text: layer.height >= layer.labelRoom && layer.info.label.length
                          ? layer.tag + String.fromCharCode(10) + layer.info.label : layer.tag
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.9
                    color: "#111311"
                    font.pixelSize: 10 * profile.scaleFactor
                    font.weight: Font.DemiBold
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: profile.selected(layer.index)
            }
        }
    }

    // Nivel freático: línea discontinua sobre todo el ancho útil + rótulo.
    Item {
        id: waterMarker
        visible: profile.waterVisible
        x: profile.axisWidth
        y: profile.depthY(isFinite(profile.waterDepth) ? profile.waterDepth : 0)
        width: profile.width - profile.axisWidth
        Row {
            y: -1
            spacing: 4 * profile.scaleFactor
            Repeater {
                model: Math.max(0, Math.floor(waterMarker.width / (10 * profile.scaleFactor)))
                delegate: Rectangle { width: 6 * profile.scaleFactor; height: 2; color: profile.waterColor }
            }
        }
        Text {
            x: profile.columnX - profile.axisWidth + profile.columnWidth + 6 * profile.scaleFactor
            y: -height - 2 * profile.scaleFactor
            width: Math.max(0, waterMarker.width - x)
            text: "▽ N.F. " + (isFinite(profile.waterDepth) ? profile.waterDepth.toFixed(2) : "") + " m"
            color: profile.waterColor
            font.pixelSize: 12 * profile.scaleFactor
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Text {
        anchors.bottom: parent.bottom
        width: parent.width
        text: "0.00–" + profile.totalDepth.toFixed(2) + " m"
        color: profile.muted
        font.pixelSize: 11 * profile.scaleFactor
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 24 * profile.scaleFactor
        visible: profile.model.count === 0
        text: profile.emptyText
        color: profile.muted
        font.pixelSize: 13 * profile.scaleFactor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
