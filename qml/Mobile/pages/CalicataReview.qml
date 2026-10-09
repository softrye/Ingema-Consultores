pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes as Shapes
import "../flowcore" as FlowCore
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

// Revisión de cierre de la calicata. Solo presentación: todos los valores llegan de
// CalicataFormPage (Rules.reviewSummary / reviewFacts / reviewRecommendations /
// reviewConclusion sobre la misma instantánea que exporta). Las exportaciones viven
// en el Dock: esta pantalla no tiene botones de exportar.
//
// Liquid Glass: material del sistema (FlowCore.LiquidGlassSurface) sobre un ambiente
// propio y estático (la página es ancestro y no puede ser backdrop). Una sola
// superficie por tarjeta, con grab congelado (re-grab solo si cambia su geometría);
// los elementos internos son translúcidos, sin vidrio anidado (coste acotado en A12).
Item {
    id: review

    // ---- datos (FormPage)
    required property var summary
    required property var facts
    required property var recommendations
    required property string conclusion
    required property string observations
    required property bool reviewed
    property var excavabilityLabels: []
    property var stabilityLabels: []
    property string aiText: ""
    property bool aiBusy: false
    property var aiFindings: []
    property string codeText: ""

    // ---- tema
    property var flow: null
    property Flickable viewport: null
    property real scaleFactor: 1
    property bool darkMode: false
    property color ink: "#151A30"
    property color muted: "#656876"
    property color accent: "#0654A2"
    property color accentSoft: "#EBF1F8"
    property color good: "#486426"
    property color warn: "#DE7A12"
    property color danger: "#D9483B"

    signal sectionSelected(int section)
    signal issueSelected(var issue)
    signal refreshRequested()

    function dp(v) { return Math.round(v * review.scaleFactor) }
    function fmt(v, digits) { return isFinite(v) ? Number(v).toFixed(digits === undefined ? 2 : digits) : "—" }
    function statusColor(status) {
        return status === "complete" ? review.good : status === "blocker" ? review.danger
             : status === "warning" ? review.warn : review.accent
    }
    function statusIcon(status) {
        return status === "complete" ? "action.check" : status === "blocker" ? "status.error"
             : status === "warning" ? "status.warning" : "status.sync"
    }
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function cardIsVisible(y, height) {
        if (!review.viewport || !review.parent) return true
        var origin = review.parent.mapToItem(review.viewport.contentItem, review.x, review.y)
        var top = origin.y + content.y + y
        return top + height > review.viewport.contentY
            && top < review.viewport.contentY + review.viewport.height
    }
    readonly property var components: review.summary && review.summary.components ? review.summary.components : []
    readonly property var pendingComponents: review.components.filter(function(c) { return c.status === "blocker" || c.status === "warning" })
    readonly property real motionScale: review.flow && review.flow.motionAllowed === false ? 0 : 1
    readonly property bool narrow: review.width < review.dp(380)

    // Entrada: las tarjetas aparecen escalonadas (opacity + desplazamiento corto).
    property real reveal: 0
    onVisibleChanged: {
        if (visible) revealAnim.restart()
        else { revealAnim.stop(); reveal = 0 }
    }
    Component.onCompleted: if (visible) revealAnim.restart()
    NumberAnimation {
        id: revealAnim
        target: review; property: "reveal"; from: 0; to: 1
        duration: 520 * review.motionScale + 1
        easing.type: Easing.OutCubic
    }

    implicitHeight: content.implicitHeight + review.dp(8)

    // ---- ambiente estático: lo que el vidrio refracta (blanco, azul muy sutil)
    Rectangle {
        id: ambient
        // También lo refractan las celdas, insignias y chips (Liquid Glass real).
        objectName: "calicataGlassBackdrop"
        anchors.fill: parent
        // Sin esquinas transparentes: el vidrio pinta opaco lo que captura y una
        // esquina vacía saldría negra.
        radius: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: review.darkMode ? "#182440" : "#F7FAFF" }
            GradientStop { position: 1.0; color: review.darkMode ? "#151A30" : "#FFFFFF" }
        }
        Shapes.Shape {
            anchors.fill: parent
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.12; centerY: Math.min(ambient.height * 0.10, review.dp(260))
                    centerRadius: ambient.width * 0.75
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: review.tint(review.accent, review.darkMode ? 0.20 : 0.14) }
                    GradientStop { position: 1.0; color: review.tint(review.accent, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.92; centerY: ambient.height * 0.45
                    centerRadius: ambient.width * 0.70
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.rgba(0.561, 0.698, 0.835, review.darkMode ? 0.14 : 0.12) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.561, 0.698, 0.835, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.20; centerY: ambient.height * 0.88
                    centerRadius: ambient.width * 0.65
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.rgba(0.678, 0.725, 0.616, review.darkMode ? 0.10 : 0.08) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.678, 0.725, 0.616, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // ---------------------------------------------------------------- componentes
    component ReviewCard: Item {
        id: card
        property int order: 0
        property real cardRadius: review.dp(22)
        default property alias body: cardBody.data
        readonly property real appear: Math.max(0, Math.min(1, review.reveal * 6 - card.order * 0.55))
        readonly property bool inViewport: review.visible && review.cardIsVisible(card.y, card.height)
        readonly property bool glassShown: cardTokens.shown
        Layout.fillWidth: true
        implicitHeight: cardBody.implicitHeight + review.dp(32)
        opacity: card.appear
        transform: Translate { y: (1 - card.appear) * review.dp(14) }
        QtObject {
            id: cardTokens
            readonly property bool shown: card.visible && card.opacity > 0 && card.inViewport
            readonly property Item glassBackdrop: ambient
            readonly property real materialPosition: 0
            readonly property bool lowCostGlass: Mobile.InGeCoreFlow.lowMemoryMode
                || Mobile.InGeCoreFlow.performance.profile >= Mobile.InGeCoreFlow.performance.safe
            readonly property color glassTint: review.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
            // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
            readonly property color fallbackGlass: review.darkMode ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
            readonly property real rimLight: review.darkMode ? 0.18 : 0.20
            readonly property real rimShade: review.darkMode ? 0.04 : 0.035
            readonly property real rimSheen: review.darkMode ? 0.03 : 0.015
            readonly property real edgeContrast: review.darkMode ? 0.0 : 0.03
            readonly property real glassSaturation: 1.12
            readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, review.darkMode ? 0.22 : 0.09)
        }
        FlowCore.LiquidGlassSurface {
            anchors.fill: parent
            visible: cardTokens.shown
            tokens: cardTokens
            cornerRadius: card.cardRadius
            surfaceName: "calicata-review-card"
            // Preset del panel "Información de la calicata".
            lens: 0.3
            frost: 8
            frostTaps: 6
            magnify: 0
            bevel: review.dp(14)
            elevation: true
            liveCapture: false   // ambiente estático: un grab, re-grab solo si cambia la geometría
            // La tarjeta ocupa todo el ancho del ambiente: el margen de captura del
            // shader (6 px) caería fuera y pintaría negro. Se recorta dentro del ambiente.
            captureRect: {
                var dependency = card.x + card.y + card.width + card.height + (cardTokens.shown ? 1 : 0)
                var m = 6
                var p = card.mapToItem(ambient, 0, 0)
                var w = Math.min(card.width, ambient.width - 2 * m)
                var h = Math.min(card.height, ambient.height - 2 * m)
                return Qt.rect(Math.max(m, Math.min(p.x, ambient.width - w - m)),
                               Math.max(m, Math.min(p.y, ambient.height - h - m)), Math.max(1, w), Math.max(1, h))
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: card.cardRadius
            // Velo y filo del peek "Información de la calicata".
            color: review.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.30) : Qt.rgba(0.98, 0.99, 1.0, 0.42)
            border.width: 1
            border.color: review.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.30)
        }
        ColumnLayout {
            id: cardBody
            x: review.dp(16)
            y: review.dp(16)
            width: card.width - review.dp(32)
            spacing: review.dp(12)
        }
    }

    component IconBadge: Rectangle {
        id: badge
        property string icon: ""
        property color tone: review.accent
        property real iconSize: review.dp(18)
        implicitWidth: review.dp(38); implicitHeight: review.dp(38)
        radius: review.dp(12)
        color: "transparent"
        CalicataLiquidGlass { dark: review.darkMode; accent: badge.tone; anchors.fill: parent; radius: badge.radius; tone: "tinted" }
        Components.FlowIcon {
            anchors.centerIn: parent
            width: badge.iconSize; height: width
            name: badge.icon
            flow: review.flow
            tintColor: badge.tone; activeTintColor: badge.tone; inactiveOpacity: 1
        }
    }

    component CardHeader: RowLayout {
        id: header
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property string trailing: ""
        property color trailingColor: review.accent
        property int section: -1
        signal tapped()
        Layout.fillWidth: true
        spacing: review.dp(12)
        IconBadge { icon: header.icon }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { Layout.fillWidth: true; text: header.title; color: review.ink; font.pixelSize: review.dp(16); font.weight: Font.DemiBold; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; visible: header.subtitle.length > 0; text: header.subtitle; color: review.muted; font.pixelSize: review.dp(12); elide: Text.ElideRight }
        }
        Text { visible: header.trailing.length > 0; text: header.trailing; color: header.trailingColor; font.pixelSize: review.dp(24); font.weight: Font.Bold }
        Item {
            visible: header.section >= 0
            implicitWidth: review.dp(28); implicitHeight: review.dp(28)
            Components.FlowIcon {
                anchors.centerIn: parent
                width: review.dp(18); height: width
                name: "system.chevronRight"; flow: review.flow
                tintColor: review.muted; activeTintColor: review.accent; inactiveOpacity: 1
            }
        }
        TapHandler {
            enabled: header.section >= 0
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: review.sectionSelected(header.section)
        }
    }

    // Celda de Liquid Glass real (material de control) dentro de la tarjeta.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string value: ""
        property string label: ""
        property color tone: review.accent
        property int section: -1
        Layout.fillWidth: true
        implicitHeight: review.dp(64)
        radius: review.dp(16)
        color: "transparent"
        scale: tileTap.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: tileTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
        CalicataLiquidGlass { dark: review.darkMode; accent: review.accent; anchors.fill: parent; radius: tile.radius; pressed: tileTap.pressed }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: review.dp(12); anchors.rightMargin: review.dp(10)
            spacing: review.dp(10)
            Components.FlowIcon {
                Layout.preferredWidth: review.dp(22); Layout.preferredHeight: review.dp(22)
                name: tile.icon; flow: review.flow
                tintColor: tile.tone; activeTintColor: tile.tone; inactiveOpacity: 1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: tile.value; color: review.ink; font.pixelSize: review.dp(17); font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: tile.label; color: review.muted; font.pixelSize: review.dp(11.5); elide: Text.ElideRight }
            }
        }
        TapHandler {
            id: tileTap
            enabled: tile.section >= 0
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: review.sectionSelected(tile.section)
        }
        Accessible.role: Accessible.Button
        Accessible.name: tile.label + ": " + tile.value
    }

    component StatusChip: Rectangle {
        id: chip
        required property var modelData
        readonly property color tone: review.statusColor(chip.modelData.status)
        implicitHeight: review.dp(32)
        implicitWidth: chipRow.implicitWidth + review.dp(20)
        radius: height / 2
        color: "transparent"
        scale: chipTap.pressed ? 0.97 : 1
        CalicataLiquidGlass { dark: review.darkMode; accent: chip.tone; anchors.fill: parent; radius: chip.radius; tone: "tinted"; pressed: chipTap.pressed }
        Behavior on scale { NumberAnimation { duration: chipTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: review.dp(6)
            Components.FlowIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: review.dp(14); height: width
                name: review.statusIcon(chip.modelData.status); flow: review.flow
                tintColor: chip.tone; activeTintColor: chip.tone; inactiveOpacity: 1
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.label; color: review.ink; font.pixelSize: review.dp(12) }
        }
        TapHandler { id: chipTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: review.sectionSelected(chip.modelData.section) }
        Accessible.role: Accessible.Button
        Accessible.name: chip.modelData.label + ", " + chip.modelData.percent + " %"
    }

    // ---------------------------------------------------------------- contenido
    ColumnLayout {
        id: content
        width: review.width
        spacing: review.dp(14)

        // 1 · Estado general + componentes
        ReviewCard {
            order: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: review.dp(12)
                IconBadge { icon: "documents.file"; implicitWidth: review.dp(46); implicitHeight: review.dp(46); radius: review.dp(15); iconSize: review.dp(22) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; text: "Estado de la calicata"; color: review.ink; font.pixelSize: review.dp(16); font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; visible: review.codeText.length > 0; text: review.codeText; color: review.muted; font.pixelSize: review.dp(12); elide: Text.ElideRight }
                }
                Text {
                    text: review.reviewed ? Math.round((review.summary.percent || 0) * Math.min(1, review.reveal * 1.4)) + "%" : "—"
                    color: review.accent
                    font.pixelSize: review.dp(30)
                    font.weight: Font.Bold
                }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: review.dp(10)
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: review.tint(review.accent, review.darkMode ? 0.18 : 0.12)
                }
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, (review.summary.percent || 0) / 100)) * Math.min(1, review.reveal * 1.4)
                    height: parent.height
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: review.accent }
                        GradientStop { position: 1.0; color: Qt.lighter(review.accent, 1.45) }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: review.muted
                font.pixelSize: review.dp(12.5)
                text: !review.reviewed ? "Revisión pendiente: se actualiza al abrir esta etapa."
                      : review.summary.pendingCount > 0
                        ? "Faltan " + review.summary.pendingCount + (review.summary.pendingCount === 1 ? " elemento" : " elementos") + " para completar la calicata."
                        : review.summary.warningCount > 0
                          ? "Sin bloqueos · " + review.summary.warningCount + (review.summary.warningCount === 1 ? " aviso por revisar." : " avisos por revisar.")
                          : "Ficha completa: lista para exportar desde el Dock."
            }
            Flow {
                Layout.fillWidth: true
                spacing: review.dp(8)
                Repeater {
                    model: review.components
                    delegate: StatusChip {}
                }
            }
        }

        // 2 · Elementos pendientes (accionables: llevan a la sección y al estrato)
        ReviewCard {
            id: pendingCard
            order: 1
            visible: review.pendingComponents.length > 0
            property bool expanded: true
            RowLayout {
                Layout.fillWidth: true
                spacing: review.dp(12)
                IconBadge { icon: review.summary.pendingCount > 0 ? "status.error" : "status.warning"; tone: review.summary.pendingCount > 0 ? review.danger : review.warn }
                Text {
                    Layout.fillWidth: true
                    text: (review.summary.pendingCount > 0 ? "Elementos pendientes (" + review.summary.pendingCount + ")" : "Avisos (" + review.summary.warningCount + ")")
                    color: review.ink; font.pixelSize: review.dp(16); font.weight: Font.DemiBold; elide: Text.ElideRight
                }
                Components.FlowIcon {
                    Layout.preferredWidth: review.dp(18); Layout.preferredHeight: review.dp(18)
                    name: "system.up"; flow: review.flow
                    tintColor: review.muted; activeTintColor: review.accent; inactiveOpacity: 1
                    rotation: pendingCard.expanded ? 0 : 180
                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: pendingCard.expanded = !pendingCard.expanded }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: pendingCard.expanded ? pendingList.implicitHeight : 0
                clip: true
                Behavior on implicitHeight { NumberAnimation { duration: 220 * review.motionScale + 1; easing.type: Easing.OutCubic } }
                ColumnLayout {
                    id: pendingList
                    width: parent.width
                    spacing: review.dp(8)
                    opacity: pendingCard.expanded ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Repeater {
                        model: review.pendingComponents
                        delegate: Rectangle {
                            id: pendingRow
                            required property var modelData
                            readonly property color tone: review.statusColor(pendingRow.modelData.status)
                            readonly property var issues: pendingRow.modelData.blockers.length ? pendingRow.modelData.blockers : pendingRow.modelData.warnings
                            Layout.fillWidth: true
                            implicitHeight: pendingRowContent.implicitHeight + review.dp(20)
                            radius: review.dp(16)
                            color: pendingTap.pressed ? review.tint(pendingRow.tone, 0.18) : review.tint(pendingRow.tone, review.darkMode ? 0.14 : 0.08)
                            border.width: 1
                            border.color: review.tint(pendingRow.tone, 0.22)
                            scale: pendingTap.pressed ? 0.985 : 1
                            Behavior on scale { NumberAnimation { duration: pendingTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
                            RowLayout {
                                id: pendingRowContent
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: review.dp(12); anchors.rightMargin: review.dp(10)
                                spacing: review.dp(12)
                                IconBadge { icon: review.statusIcon(pendingRow.modelData.status); tone: pendingRow.tone; implicitWidth: review.dp(34); implicitHeight: review.dp(34) }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: review.dp(1)
                                    Text { Layout.fillWidth: true; text: pendingRow.modelData.label; color: review.ink; font.pixelSize: review.dp(14); font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text {
                                        Layout.fillWidth: true
                                        text: pendingRow.issues.length ? pendingRow.issues[0].message
                                              + (pendingRow.issues.length > 1 ? "  · y " + (pendingRow.issues.length - 1) + " más" : "") : ""
                                        color: review.muted; font.pixelSize: review.dp(12); wrapMode: Text.WordWrap
                                    }
                                }
                                Components.FlowIcon {
                                    Layout.preferredWidth: review.dp(16); Layout.preferredHeight: review.dp(16)
                                    name: "system.chevronRight"; flow: review.flow
                                    tintColor: review.muted; activeTintColor: review.accent; inactiveOpacity: 1
                                }
                            }
                            TapHandler {
                                id: pendingTap
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: {
                                    var issue = pendingRow.issues.length ? pendingRow.issues[0] : null
                                    if (issue) review.issueSelected(issue)
                                    else review.sectionSelected(pendingRow.modelData.section)
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: pendingRow.modelData.label
                        }
                    }
                }
            }
        }

        // 3 · Resumen (datos reales de la ficha)
        ReviewCard {
            order: 2
            CardHeader { icon: "geotechnical.stratigraphy"; title: "Resumen de la calicata"; section: 4 }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: review.dp(10)
                rowSpacing: review.dp(10)
                Tile { icon: "map.layers"; value: String(review.facts.strata || 0); label: review.facts.strata === 1 ? "Estrato" : "Estratos"; section: 4 }
                Tile { icon: "calgen.depth"; value: review.fmt(review.facts.finalDepth) + " m"; label: "Profundidad total"; section: 3 }
                Tile { icon: "lab.flask"; value: String(review.facts.samples || 0); label: (review.facts.samples === 1 ? "Muestra" : "Muestras") + " · " + (review.facts.labRows || 0) + " con ensayos"; section: 5 }
                Tile { icon: "action.camera"; value: (review.facts.photos || 0) + " / 3"; label: "Fotografías"; section: 7 }
                Tile {
                    Layout.columnSpan: 2
                    readonly property var place: review.facts.location || ({ text: "", datum: "" })
                    icon: "map.location"
                    tone: place.text.length ? review.accent : review.warn
                    value: place.text.length ? place.text : "Sin ubicación"
                    label: "Ubicación" + (place.datum.length ? " · " + place.datum : "")
                    section: 2
                }
                Tile {
                    visible: !!review.facts.predominantCode
                    icon: "module.stratigraphy"
                    value: review.facts.predominantCode || "—"
                    label: "Suelo predominante · " + review.fmt(review.facts.predominantThickness) + " m"
                    section: 4
                }
                Tile {
                    icon: "calgen.water"
                    tone: review.facts.waterStatus === "NO_EVALUADO" ? review.warn : review.accent
                    value: review.facts.waterStatus === "ENCONTRADO" ? review.fmt(review.facts.waterDepth) + " m"
                           : review.facts.waterStatus === "NO_ENCONTRADO" ? "No encontrado" : "No evaluado"
                    label: "Nivel freático"
                    section: 3
                }
            }
        }

        // 4 · Perfil estratigráfico (vista gráfica proporcional a los espesores reales)
        ReviewCard {
            order: 3
            CardHeader { icon: "module.stratigraphy"; title: "Perfil estratigráfico"; subtitle: "Vista gráfica · espesores reales"; section: 4 }
            Text {
                Layout.fillWidth: true
                visible: !review.facts.segments || review.facts.segments.length === 0
                text: "Sin estratos con intervalo válido."
                color: review.muted; font.pixelSize: review.dp(12.5)
            }
            Item {
                id: profileGraph
                Layout.fillWidth: true
                visible: review.facts.segments && review.facts.segments.length > 0
                implicitHeight: review.dp(74)
                readonly property real total: Math.max(0.05, review.facts.finalDepth || 0)
                // Regla: 5 marcas desde 0 hasta la profundidad total.
                Repeater {
                    model: 5
                    delegate: Text {
                        required property int index
                        x: Math.min(profileGraph.width - implicitWidth, Math.max(0, profileGraph.width * index / 4 - implicitWidth / 2))
                        y: 0
                        text: (profileGraph.total * index / 4).toFixed(1) + " m"
                        color: review.muted
                        font.pixelSize: review.dp(10.5)
                    }
                }
                Canvas {
                    id: profileCanvas
                    y: review.dp(20)
                    width: parent.width
                    height: review.dp(44)
                    property real sweep: Math.min(1, review.reveal * 1.3)
                    onSweepChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    Connections { target: review; function onFactsChanged() { profileCanvas.requestPaint() } }
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var segs = review.facts.segments || [], total = profileGraph.total, r = review.dp(12)
                        ctx.save()
                        ctx.beginPath()
                        ctx.moveTo(r, 0); ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r)
                        ctx.lineTo(width, height - r); ctx.arcTo(width, height, width - r, height, r)
                        ctx.lineTo(r, height); ctx.arcTo(0, height, 0, height - r, r)
                        ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r)
                        ctx.closePath()
                        ctx.clip()
                        var limit = width * sweep
                        for (var i = 0; i < segs.length; ++i) {
                            var x0 = width * segs[i].from / total, x1 = width * segs[i].to / total
                            if (x0 >= limit) break
                            ctx.fillStyle = segs[i].color || "#E7E7E4"
                            ctx.fillRect(x0, 0, Math.min(x1, limit) - x0, height)
                            if (i > 0) { ctx.fillStyle = "rgba(255,255,255,0.85)"; ctx.fillRect(x0 - 1, 0, 2, height) }
                            var label = segs[i].code || ""
                            ctx.font = "600 " + review.dp(12) + "px sans-serif"
                            if (label.length && (x1 - x0) > ctx.measureText(label).width + review.dp(10) && x1 <= limit) {
                                ctx.fillStyle = "rgba(17,24,39,0.82)"
                                ctx.fillText(label, x0 + (x1 - x0 - ctx.measureText(label).width) / 2, height / 2 + review.dp(4))
                            }
                        }
                        // Nivel freático (dato único de la calicata).
                        if (isFinite(review.facts.waterDepth) && review.facts.waterDepth <= total) {
                            var wx = width * review.facts.waterDepth / total
                            if (wx <= limit) {
                                ctx.strokeStyle = String(review.accent); ctx.lineWidth = review.dp(2)
                                ctx.setLineDash([review.dp(4), review.dp(3)])
                                ctx.beginPath(); ctx.moveTo(wx, 0); ctx.lineTo(wx, height); ctx.stroke()
                            }
                        }
                        ctx.restore()
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                visible: review.facts.segments && review.facts.segments.length > 0
                columns: review.narrow ? 2 : 3
                columnSpacing: review.dp(10)
                rowSpacing: review.dp(8)
                Repeater {
                    model: review.facts.segments || []
                    delegate: RowLayout {
                        id: legendRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: review.dp(8)
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: review.dp(3)
                            implicitWidth: review.dp(12); implicitHeight: review.dp(12)
                            radius: width / 2
                            color: legendRow.modelData.color || "#E7E7E4"
                            border.width: 1; border.color: review.tint(review.ink, 0.15)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { Layout.fillWidth: true; text: "Estrato " + (legendRow.modelData.index + 1); color: review.ink; font.pixelSize: review.dp(12.5); font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: review.fmt(legendRow.modelData.from) + " – " + review.fmt(legendRow.modelData.to) + " m"; color: review.ink; font.pixelSize: review.dp(12); elide: Text.ElideRight }
                            Text {
                                Layout.fillWidth: true
                                text: (legendRow.modelData.code || "Sin clasificar") + (legendRow.modelData.description.length ? " · " + legendRow.modelData.description : "")
                                color: review.muted; font.pixelSize: review.dp(11); elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                            }
                        }
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: review.issueSelected({ section: 4, stratum: legendRow.modelData.index })
                        }
                    }
                }
            }
        }

        // 5 · Rendimiento de excavación (excavabilidad registrada por estrato)
        ReviewCard {
            id: performanceCard
            order: 4
            readonly property bool hasIndex: isFinite(review.facts.excavabilityIndex)
            CardHeader {
                icon: "calgen.machine"
                title: "Rendimiento de excavación"
                subtitle: performanceCard.hasIndex ? "Excavabilidad registrada en " + review.facts.excavabilityCoverage + " % del perfil" : "Datos de campo de la ficha"
                trailing: performanceCard.hasIndex ? review.facts.excavabilityIndex + "%" : ""
            }
            GridLayout {
                id: performanceGrid
                Layout.fillWidth: true
                columns: review.narrow || !performanceCard.hasIndex ? 1 : 2
                columnSpacing: review.dp(14)
                rowSpacing: review.dp(12)
                Item {
                    visible: performanceCard.hasIndex
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    implicitWidth: review.dp(140); implicitHeight: review.dp(140)
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        property real value: Math.min(1, review.reveal * 1.25) * (isFinite(review.facts.excavabilityIndex) ? review.facts.excavabilityIndex / 100 : 0)
                        onValueChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var lw = review.dp(12), rad = width / 2 - lw / 2 - 1
                            ctx.lineCap = "round"
                            ctx.lineWidth = lw
                            ctx.strokeStyle = review.darkMode ? "rgba(255,255,255,0.10)" : "rgba(31,91,214,0.10)"
                            ctx.beginPath(); ctx.arc(width / 2, height / 2, rad, 0, Math.PI * 2); ctx.stroke()
                            if (value <= 0) return
                            var grad = ctx.createLinearGradient(0, height, width, 0)
                            grad.addColorStop(0, String(review.accent))
                            grad.addColorStop(1, String(review.good))
                            ctx.strokeStyle = grad
                            ctx.beginPath()
                            ctx.arc(width / 2, height / 2, rad, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * value)
                            ctx.stroke()
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(ring.value * 100) + "%"; color: review.ink; font.pixelSize: review.dp(28); font.weight: Font.Bold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Excavabilidad"; color: review.muted; font.pixelSize: review.dp(11) }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: review.dp(8)
                    Tile {
                        icon: "calgen.depth"
                        value: review.fmt(review.facts.finalDepth) + " m" + (isFinite(review.facts.reachedPercent) ? " · " + review.facts.reachedPercent + " %" : "")
                        label: isFinite(review.facts.requestedDepth) ? "Profundidad alcanzada de " + review.fmt(review.facts.requestedDepth) + " m" : "Profundidad alcanzada"
                        section: 3
                    }
                    Tile {
                        visible: isFinite(review.facts.volume)
                        icon: "map.measure"
                        value: review.fmt(review.facts.volume) + " m³"
                        label: "Volumen excavado · " + review.fmt(review.facts.length) + " × " + review.fmt(review.facts.width) + " m"
                        section: 3
                    }
                    Tile {
                        visible: isFinite(review.facts.durationDays)
                        icon: "calendar.date"
                        value: review.facts.durationDays + (review.facts.durationDays === 1 ? " día" : " días")
                        label: "Duración (fechas de inicio y fin)"
                        section: 1
                    }
                    Tile {
                        // Rendimiento real = volumen ÷ días; avance = profundidad ÷ días (Rules.reviewFacts).
                        visible: isFinite(review.facts.advanceRate)
                        icon: "calgen.depth"
                        value: (isFinite(review.facts.productivity) ? review.fmt(review.facts.productivity) + " m³/día · " : "")
                               + review.fmt(review.facts.advanceRate) + " m/día"
                        label: isFinite(review.facts.productivity) ? "Rendimiento y avance reales" : "Avance real (sin dimensiones para volumen)"
                        section: 1
                    }
                    Tile {
                        visible: review.facts.predominantExcavability >= 0
                        icon: "calgen.machine"
                        value: review.excavabilityLabels[review.facts.predominantExcavability] || "—"
                        label: "Excavabilidad predominante"
                        section: 4
                    }
                    Tile {
                        visible: review.facts.predominantStability >= 0
                        icon: "security.account"
                        tone: review.facts.predominantStability === 0 ? review.danger : review.facts.predominantStability === 1 ? review.warn : review.good
                        value: review.stabilityLabels[review.facts.predominantStability] || "—"
                        label: "Estabilidad predominante"
                        section: 4
                    }
                    Tile {
                        // Riesgo operativo determinista (Rules.reviewFacts): estabilidad de campo + nivel freático.
                        readonly property int risk: review.facts.operationalRisk === undefined ? -1 : review.facts.operationalRisk
                        icon: "security.account"
                        tone: risk === 2 ? review.danger : risk === 1 ? review.warn : risk === 0 ? review.good : review.muted
                        value: risk === 2 ? "Alto" : risk === 1 ? "Medio" : risk === 0 ? "Bajo" : "Datos insuficientes"
                        label: "Riesgo operativo" + ((review.facts.operationalRiskReasons || []).length
                               ? " · " + review.facts.operationalRiskReasons.join(", ")
                               : risk === -1 ? " · estabilidad en " + (review.facts.stabilityCoverage || 0) + " % del perfil" : "")
                        section: 4
                    }
                }
            }
        }

        // 6 · Completitud por componente (requisitos del validador cumplidos)
        ReviewCard {
            order: 5
            CardHeader { icon: "status.success"; title: "Completitud por componente"; subtitle: "% de requisitos del validador cumplidos" }
            Item {
                id: chart
                Layout.fillWidth: true
                implicitHeight: review.dp(190)
                readonly property real axisWidth: review.dp(34)
                readonly property real plotTop: review.dp(8)
                readonly property real plotHeight: review.dp(132)
                readonly property real slot: (chart.width - chart.axisWidth) / Math.max(1, review.components.length)
                Repeater {
                    model: [100, 50, 0]
                    delegate: Item {
                        required property var modelData
                        width: chart.width
                        y: chart.plotTop + chart.plotHeight * (1 - modelData / 100)
                        Text { y: -height / 2; text: parent.modelData + "%"; color: review.muted; font.pixelSize: review.dp(10) }
                        Rectangle { x: chart.axisWidth; width: chart.width - chart.axisWidth; height: 1; color: review.tint(review.ink, parent.modelData === 0 ? 0.18 : 0.07) }
                    }
                }
                Repeater {
                    model: review.components
                    delegate: Item {
                        id: barSlot
                        required property var modelData
                        required property int index
                        readonly property color tone: review.statusColor(barSlot.modelData.status)
                        x: chart.axisWidth + chart.slot * barSlot.index
                        width: chart.slot
                        height: chart.height
                        Rectangle {
                            id: bar
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(review.dp(34), barSlot.width * 0.56)
                            readonly property real grow: Math.max(0, Math.min(1, review.reveal * 2.2 - barSlot.index * 0.12))
                            height: Math.max(review.dp(3), chart.plotHeight * barSlot.modelData.percent / 100 * bar.grow)
                            y: chart.plotTop + chart.plotHeight - height
                            radius: review.dp(8)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.lighter(barSlot.tone, 1.35) }
                                GradientStop { position: 1.0; color: barSlot.tone }
                            }
                            // Brillo vertical sutil (vidrio), sin efectos costosos.
                            Rectangle {
                                x: parent.width * 0.18; y: review.dp(3)
                                width: parent.width * 0.18; height: Math.max(0, parent.height - review.dp(6))
                                radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.28)
                            }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: chart.plotTop + chart.plotHeight + review.dp(8)
                            width: barSlot.width
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: barSlot.modelData.label; color: review.muted; font.pixelSize: review.dp(10.5); elide: Text.ElideRight }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: barSlot.modelData.percent + "%"; color: review.ink; font.pixelSize: review.dp(12.5); font.weight: Font.DemiBold }
                        }
                        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: review.sectionSelected(barSlot.modelData.section) }
                        Accessible.role: Accessible.Button
                        Accessible.name: barSlot.modelData.label + " " + barSlot.modelData.percent + " %"
                    }
                }
            }
        }

        // 7 · Análisis y conclusiones (resumen factual + InGe AI cuando se solicita)
        ReviewCard {
            id: analysisCard
            order: 6
            property int tab: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: review.dp(12)
                IconBadge { icon: "calgen.description" }
                Text { Layout.fillWidth: true; text: "Análisis y conclusiones"; color: review.ink; font.pixelSize: review.dp(16); font.weight: Font.DemiBold; elide: Text.ElideRight }
                Rectangle {
                    visible: review.aiBusy
                    implicitHeight: review.dp(34)
                    implicitWidth: aiRow.implicitWidth + review.dp(22)
                    radius: height / 2
                    color: review.tint(review.accent, review.darkMode ? 0.18 : 0.10)
                    border.width: 1; border.color: review.tint(review.accent, 0.30)
                    Row {
                        id: aiRow
                        anchors.centerIn: parent
                        spacing: review.dp(6)
                        FlowCore.FlowProgressRing {
                            anchors.verticalCenter: parent.verticalCenter
                            running: analysisCard.glassShown && review.aiBusy
                            width: review.dp(14); height: width
                            strokeWidth: review.dp(2)
                            color: review.accent
                            backgroundColor: review.tint(review.accent, 0.18)
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Analizando…"; color: review.accent; font.pixelSize: review.dp(12.5); font.weight: Font.DemiBold }
                    }
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "InGe AI está analizando la ficha"
                }
            }
            // Segmentado: Conclusión · Recomendaciones · Observaciones
            Item {
                Layout.fillWidth: true
                implicitHeight: review.dp(38)
                CalicataLiquidGlass { dark: review.darkMode; accent: review.accent; anchors.fill: parent; radius: height / 2 }
                // Pestaña activa = la lente de selección del material (como en el Dock).
                CalicataLiquidGlass {
                    dark: review.darkMode; accent: review.accent
                    width: (parent.width - review.dp(8)) / 3
                    height: parent.height - review.dp(8)
                    x: review.dp(4) + width * analysisCard.tab
                    y: review.dp(4)
                    radius: height / 2
                    selected: true
                    Behavior on x { NumberAnimation { duration: 220 * review.motionScale + 1; easing.type: Easing.OutCubic } }
                }
                Row {
                    anchors.fill: parent
                    anchors.margins: review.dp(4)
                    Repeater {
                        model: ["Conclusión", "Recomendaciones", "Observaciones"]
                        delegate: Item {
                            id: tabItem
                            required property string modelData
                            required property int index
                            width: (parent.width) / 3
                            height: parent.height
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - review.dp(6)
                                horizontalAlignment: Text.AlignHCenter
                                text: tabItem.modelData
                                color: analysisCard.tab === tabItem.index ? review.accent : review.muted
                                font.pixelSize: review.dp(review.narrow ? 11 : 12)
                                font.weight: analysisCard.tab === tabItem.index ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: analysisCard.tab = tabItem.index }
                            Accessible.role: Accessible.PageTab
                            Accessible.name: tabItem.modelData
                        }
                    }
                }
            }
            // Conclusión: InGe AI (si se solicitó) + resumen factual de la ficha.
            ColumnLayout {
                Layout.fillWidth: true
                visible: analysisCard.tab === 0
                spacing: review.dp(10)
                Text {
                    Layout.fillWidth: true
                    visible: review.aiText.length > 0
                    text: "InGe AI"
                    color: review.accent; font.pixelSize: review.dp(11); font.weight: Font.DemiBold; font.letterSpacing: 0.6
                }
                Text {
                    Layout.fillWidth: true
                    visible: review.aiText.length > 0
                    text: review.aiText
                    color: review.ink; font.pixelSize: review.dp(13); wrapMode: Text.WordWrap; lineHeight: 1.15
                }
                Text {
                    Layout.fillWidth: true
                    text: "RESUMEN DE LA FICHA"
                    color: review.muted; font.pixelSize: review.dp(10.5); font.weight: Font.DemiBold; font.letterSpacing: 0.8
                }
                Text {
                    Layout.fillWidth: true
                    text: review.conclusion
                    color: review.ink; font.pixelSize: review.dp(13); wrapMode: Text.WordWrap; lineHeight: 1.15
                }
                Text {
                    Layout.fillWidth: true
                    visible: review.aiText.length === 0
                    text: "Generado con los datos registrados (sin inferencias). Usa InGe AI para una revisión asistida."
                    color: review.muted; font.pixelSize: review.dp(11); wrapMode: Text.WordWrap
                }
            }
            // Recomendaciones sustentadas por datos (y hallazgos de InGe AI, accionables).
            ColumnLayout {
                Layout.fillWidth: true
                visible: analysisCard.tab === 1
                spacing: review.dp(6)
                Text {
                    Layout.fillWidth: true
                    visible: review.recommendations.length === 0 && review.aiFindings.length === 0
                    text: "Sin recomendaciones: los datos registrados no indican acciones adicionales."
                    color: review.muted; font.pixelSize: review.dp(12.5); wrapMode: Text.WordWrap
                }
                Repeater {
                    model: review.recommendations.concat(review.aiFindings)
                    delegate: Rectangle {
                        id: recRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: recText.implicitHeight + review.dp(18)
                        radius: review.dp(14)
                        color: recTap.pressed ? review.tint(review.accent, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: 130 } }
                        Rectangle {
                            x: review.dp(10); y: review.dp(14)
                            width: review.dp(6); height: width; radius: width / 2
                            color: review.accent
                        }
                        Text {
                            id: recText
                            x: review.dp(24); y: review.dp(9)
                            width: parent.width - review.dp(32)
                            text: String(recRow.modelData.text || recRow.modelData.message || "")
                            color: review.ink; font.pixelSize: review.dp(12.5); wrapMode: Text.WordWrap
                        }
                        TapHandler {
                            id: recTap
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: review.issueSelected({ section: Number(recRow.modelData.section),
                                                             stratum: recRow.modelData.stratum === undefined ? -1 : Number(recRow.modelData.stratum),
                                                             message: String(recRow.modelData.text || recRow.modelData.message || "") })
                        }
                    }
                }
            }
            // Observaciones de la ficha.
            ColumnLayout {
                Layout.fillWidth: true
                visible: analysisCard.tab === 2
                spacing: review.dp(8)
                Text {
                    Layout.fillWidth: true
                    text: review.observations.trim().length ? review.observations : "Sin observaciones registradas."
                    color: review.observations.trim().length ? review.ink : review.muted
                    font.pixelSize: review.dp(13); wrapMode: Text.WordWrap
                }
                Rectangle {
                    implicitHeight: review.dp(34)
                    implicitWidth: editRow.implicitWidth + review.dp(22)
                    radius: height / 2
                    color: editTap.pressed ? review.tint(review.accent, 0.20) : review.tint(review.accent, review.darkMode ? 0.16 : 0.08)
                    border.width: 1; border.color: review.tint(review.accent, 0.24)
                    Row {
                        id: editRow
                        anchors.centerIn: parent
                        spacing: review.dp(6)
                        Components.FlowIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: review.dp(14); height: width
                            name: "action.edit"; flow: review.flow
                            tintColor: review.accent; activeTintColor: review.accent; inactiveOpacity: 1
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Editar observaciones"; color: review.accent; font.pixelSize: review.dp(12.5); font.weight: Font.DemiBold }
                    }
                    TapHandler { id: editTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: review.sectionSelected(8) }
                }
            }
        }
    }
}
