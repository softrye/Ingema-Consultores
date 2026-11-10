import QtQuick
import InGe 1.0

// Panel "Agregar herramienta" (Home V1, 2026-10-12; Preview 2). Solo ofrece
// elementos respaldados por servicios reales: proyectos y calicatas de
// CalicataCloud, Configuración y Perfil. Lo que aún no tiene un flujo real
// se muestra deshabilitado como "Pendiente de integración".
Item {
    id: panel

    property real u: 1
    property string fontFamily: ""
    property string iconFamily: ""
    property var existingKeys: []          // claves ya presentes en el Home
    property var glass: null               // HomeScreen: material glass compartido
    property var removedApps: []           // apps predeterminadas quitadas del Home
    signal addRequested(var item)
    signal closeRequested()

    // Selector de destino de un acceso directo: "" | "project" | "calicataProject" | "calicata"
    property string picking: ""
    property var pickedProject: null

    readonly property var projects: CalicataCloud.projects || []
    readonly property var calicatas: CalicataCloud.projectCalicatas || []

    function has(key) { return existingKeys.indexOf(key) >= 0 }
    function projectLabel(p) {
        var code = p && p.code ? String(p.code) : ""
        var name = p && p.name ? String(p.name) : ""
        return code.length > 0 && name.length > 0 ? code + " · " + name : (name || code || String(p.id || ""))
    }
    function calicataLabel(c) {
        var code = c.code || c.calicata_code || c.visible_code || ""
        return String(code || c.name || c.id || "")
    }
    function startPicking(kind) {
        picking = kind
        pickedProject = null
        CalicataCloud.refreshProjects()
    }
    function chooseProject(p) {
        if (picking === "widgetProject") {
            // Widget de Calicatas ligado a un proyecto real.
            addRequested({ key: "widget:calicatas:" + p.id, type: "widget", kind: "calicatasProject",
                           targetId: String(p.id), title: "Calicatas",
                           subtitle: projectLabel(p), size: "wide" })
            picking = ""
        } else if (picking === "project") {
            addRequested({ key: "project:" + p.id, type: "shortcut", kind: "project",
                           targetId: String(p.id), title: String(p.name || p.code || ""),
                           subtitle: String(p.code || ""), span: 1 })
            picking = ""
        } else {
            pickedProject = p
            picking = "calicata"
            CalicataCloud.listProjectCalicatas(String(p.id))
        }
    }
    function chooseCalicata(c) {
        if (!pickedProject)
            return
        addRequested({ key: "calicata:" + c.id, type: "shortcut", kind: "calicata",
                       targetId: String(c.id), projectId: String(pickedProject.id),
                       title: calicataLabel(c), subtitle: projectLabel(pickedProject), span: 1 })
        picking = ""
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.height + 140 * panel.u
        onContentYChanged: if (panel.glass) panel.glass.glassTick++
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: 20 * panel.u
            width: parent.width - 40 * panel.u
            spacing: 10 * panel.u

            Item { width: 1; height: 8 * panel.u }
            Rectangle {   // asa del panel
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46 * panel.u; height: 5 * panel.u; radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.55)
            }
            Item {
                width: parent.width
                height: title.height + 8 * panel.u
                Text {
                    id: title
                    y: 22 * panel.u
                    width: parent.width - 60 * panel.u
                    text: "Agregar herramienta"
                    color: "white"
                    font.family: panel.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: 30 * panel.u
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    anchors.right: parent.right
                    y: 2 * panel.u
                    id: closeButton
                    width: 46 * panel.u; height: width; radius: width / 2
                    color: "transparent"
                    GlassSurface { ui: panel.glass; radius: closeButton.width / 2; margin: 6 * panel.u }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCharCode(0xE1B2)   // lucide x
                        font.family: panel.iconFamily
                        font.pixelSize: 22 * panel.u
                        color: "white"
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: panel.closeRequested() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cerrar"
                }
            }
            Text {
                width: parent.width
                text: "Personaliza tu inicio con las herramientas que más utilizas."
                color: Qt.rgba(1, 1, 1, 0.82)
                font.family: panel.fontFamily
                font.pixelSize: 17 * panel.u
                wrapMode: Text.WordWrap
            }

            // ------------------------------------------- Selector de destino
            Column {
                width: parent.width
                spacing: 8 * panel.u
                visible: panel.picking !== ""
                Item { width: 1; height: 8 * panel.u }
                SectionLabel {
                    ui: panel
                    text: panel.picking === "calicata" && panel.pickedProject
                          ? "CALICATAS · " + panel.projectLabel(panel.pickedProject).toUpperCase()
                          : (panel.picking === "widgetProject" ? "WIDGET DE CALICATAS · SELECCIONA UN PROYECTO"
                                                               : "SELECCIONA UN PROYECTO")
                }
                Text {
                    width: parent.width
                    visible: CalicataCloud.busy
                    text: "Cargando datos de tu cuenta…"
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.family: panel.fontFamily
                    font.pixelSize: 15 * panel.u
                }
                Text {
                    width: parent.width
                    visible: !CalicataCloud.busy
                             && (panel.picking === "calicata" ? panel.calicatas.length === 0 : panel.projects.length === 0)
                    text: CalicataCloud.lastError.length > 0 ? CalicataCloud.lastError
                          : (panel.picking === "calicata" ? "Este proyecto no tiene calicatas disponibles."
                                                          : "No hay proyectos disponibles.")
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.family: panel.fontFamily
                    font.pixelSize: 15 * panel.u
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: panel.picking === "calicata" ? panel.calicatas : (panel.picking !== "" ? panel.projects : [])
                    delegate: OptionRow {
                        ui: panel
                        required property var modelData
                        width: content.width
                        compact: true
                        glyph: panel.picking === "calicata" ? 0xE0EE : 0xE0D7
                        title: panel.picking === "calicata" ? panel.calicataLabel(modelData) : panel.projectLabel(modelData)
                        subtitle: panel.picking === "calicata" ? String(modelData.status || "") : ""
                        added: panel.has((panel.picking === "calicata" ? "calicata:"
                                          : panel.picking === "widgetProject" ? "widget:calicatas:" : "project:") + modelData.id)
                        actionGlyph: panel.picking === "calicataProject" ? 0xE06F : 0xE13D
                        onActivated: panel.picking === "calicata" ? panel.chooseCalicata(modelData) : panel.chooseProject(modelData)
                    }
                }
                OptionRow {
                    ui: panel
                    width: content.width
                    compact: true
                    glyph: 0xE1B2
                    title: "Cancelar selección"
                    actionGlyph: 0
                    onActivated: panel.picking = ""
                }
            }

            // ---------------------------------------------------- WIDGETS
            Column {
                width: parent.width
                spacing: 10 * panel.u
                visible: panel.picking === ""
                Item { width: 1; height: 10 * panel.u }
                SectionLabel { ui: panel; text: "WIDGETS" }
                OptionRow {
                    ui: panel
                    width: content.width
                    highlighted: true
                    glyph: 0xE0EE
                    title: "Agregar widget de Calicata"
                    subtitle: "Selecciona el proyecto que mostrará el widget."
                    actionGlyph: 0xE06F
                    onActivated: panel.startPicking("widgetProject")
                }
                OptionRow {
                    ui: panel
                    width: content.width
                    glyph: 0xE0E8
                    title: "Agregar widget de InGe Earth"
                    subtitle: "Pendiente de integración: el visor aún no tiene datos disponibles."
                    available: false
                }

                // Apps predeterminadas que el usuario quitó: se pueden volver a agregar.
                Item { width: 1; height: 6 * panel.u; visible: panel.removedApps.length > 0 }
                SectionLabel { ui: panel; text: "APLICACIONES"; visible: panel.removedApps.length > 0 }
                Repeater {
                    model: panel.removedApps
                    delegate: OptionRow {
                        required property var modelData
                        ui: panel
                        width: content.width
                        glyph: modelData.kind === "rendiciones_app" ? 0xE3D3
                               : modelData.kind === "earth_app" ? 0xE0E8
                               : modelData.kind === "drive_app" ? 0xE0D7 : 0xE0EE
                        title: modelData.title
                        subtitle: modelData.subtitle
                        onActivated: panel.addRequested(modelData)
                    }
                }

                Item { width: 1; height: 6 * panel.u }
                SectionLabel { ui: panel; text: "ACCESOS DIRECTOS" }
                OptionRow {
                    ui: panel
                    width: content.width
                    glyph: 0xE3D3
                    title: "Agregar acceso directo de Rendición"
                    subtitle: "Pendiente de integración con el listado de rendiciones."
                    available: false
                }
                OptionRow {
                    ui: panel
                    width: content.width
                    glyph: 0xE0D7
                    title: "Agregar acceso directo a proyecto"
                    subtitle: "Selecciona un proyecto de Calicatas."
                    onActivated: panel.startPicking("project")
                }
                OptionRow {
                    ui: panel
                    width: content.width
                    glyph: 0xE0EE
                    title: "Agregar acceso directo a calicata"
                    subtitle: "Selecciona una calicata específica."
                    onActivated: panel.startPicking("calicataProject")
                }

                Item { width: 1; height: 6 * panel.u }
                SectionLabel { ui: panel; text: "HERRAMIENTAS" }
                OptionRow { ui: panel; width: content.width; compact: true; glyph: 0xE0CC; title: "Nuevo Documento"; subtitle: "Pendiente de integración."; available: false }
                OptionRow { ui: panel; width: content.width; compact: true; glyph: 0xE0D7; title: "Nuevo Proyecto"; subtitle: "Pendiente de integración."; available: false }
                OptionRow { ui: panel; width: content.width; compact: true; glyph: 0xE0EE; title: "Nueva Calicata"; subtitle: "Pendiente de integración."; available: false }
                OptionRow { ui: panel; width: content.width; compact: true; glyph: 0xE3D3; title: "Nueva Rendición"; subtitle: "Pendiente de integración."; available: false }
                OptionRow {
                    ui: panel
                    width: content.width; compact: true; glyph: 0xE154
                    title: "Configuración"; subtitle: "Ajusta la aplicación a tu medida."
                    added: panel.has("tool:settings")
                    onActivated: panel.addRequested({ key: "tool:settings", type: "tool", kind: "settings",
                                                      title: "Configuración", subtitle: "Ajustes de InGe+", span: 1 })
                }
            }
        }
    }

    // ------------------------------------------------------ Componentes
    component SectionLabel: Text {
        property var ui
        color: Qt.rgba(1, 1, 1, 0.75)
        font.family: ui.fontFamily
        font.weight: Font.DemiBold
        font.pixelSize: 14 * ui.u
        font.letterSpacing: 0.6
    }

    component OptionRow: Rectangle {
        id: row
        property var ui
        property int glyph: 0
        property string title: ""
        property string subtitle: ""
        property bool compact: false
        property bool highlighted: false
        property bool available: true
        property bool added: false
        property int actionGlyph: 0xE13D      // lucide plus
        signal activated()

        height: (compact ? 66 : 92) * row.ui.u
        radius: 16 * row.ui.u
        color: "transparent"
        opacity: available ? 1 : 0.5
        GlassSurface { ui: row.ui.glass; radius: row.radius; margin: 8 * row.ui.u }

        Rectangle {
            id: iconBox
            visible: !row.compact
            x: 12 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            width: 68 * row.ui.u; height: width; radius: 14 * row.ui.u
            color: row.highlighted ? "#0654A2" : Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.25)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
        }
        Text {
            id: icon
            x: row.compact ? 22 * row.ui.u : iconBox.x + (iconBox.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCharCode(row.glyph)
            font.family: row.ui.iconFamily
            font.pixelSize: (row.compact ? 30 : 38) * row.ui.u
            color: "white"
        }
        Column {
            x: row.compact ? 72 * row.ui.u : 96 * row.ui.u
            width: row.width - x - 100 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * row.ui.u
            Text {
                width: parent.width
                text: row.title
                color: "white"
                font.family: row.ui.fontFamily
                font.pixelSize: (row.compact ? 17 : 18) * row.ui.u
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: row.subtitle.length > 0
                text: row.subtitle
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: row.ui.fontFamily
                font.pixelSize: 14 * row.ui.u
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        Rectangle {
            visible: row.actionGlyph !== 0 && row.available
            anchors.right: chevron.left
            anchors.rightMargin: 14 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            width: 44 * row.ui.u; height: width; radius: width / 2
            color: "transparent"
            border.width: 1.5; border.color: Qt.rgba(1, 1, 1, row.added ? 0.35 : 0.9)
            Text {
                anchors.centerIn: parent
                text: String.fromCharCode(row.added ? 0xE06F : row.actionGlyph)
                font.family: row.ui.iconFamily
                font.pixelSize: 24 * row.ui.u
                color: Qt.rgba(1, 1, 1, row.added ? 0.45 : 1)
            }
        }
        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 14 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCharCode(0xE06F)   // lucide chevron-right
            font.family: row.ui.iconFamily
            font.pixelSize: 24 * row.ui.u
            color: Qt.rgba(1, 1, 1, row.available ? 0.9 : 0.4)
        }
        MouseArea {
            anchors.fill: parent
            enabled: row.available && !row.added
            onClicked: row.activated()
        }
        Accessible.role: Accessible.Button
        Accessible.name: row.title + (row.available ? "" : ", pendiente de integración") + (row.added ? ", ya agregado" : "")
    }
}
