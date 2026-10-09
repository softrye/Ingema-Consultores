import QtQuick
// FIX_QT69_V33_1: API Qt 6 completa para DragHandler.activeTranslation.
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "flowcore" as FlowCore
import "components" as Components

Item {
    id: root

    // M06_BUSCADOR_GLOBAL_V30_FINAL
    // M06_V30_1_BUSCADOR_COMPACTO: corrige expansión vertical del encabezado.
    // M05_INGECOREFLOW_V31: sheet táctil, física adaptativa y cristal ligero.
    anchors.fill: parent
    z: 1800

    property var flow: null
    property bool darkMode: false
    property bool presented: false
    property string currentUserName: ""
    property string currentEmailExact: ""
    property string currentCalicataCode: ""
    property string currentCalicataProject: ""
    property bool guestMode: false
    property int maxVisibleResults: 24
    property real sheetDragOffsetV31: 0.0
    property real sheetDragProgressV31: 0.0
    property real sheetDragVelocityV31: 0.0

    readonly property bool motionAllowed:
        flow !== null
        && flow !== undefined
        && flow.motionAllowed === true

    readonly property int fastDuration:
        flow && flow.fastDuration !== undefined ? flow.fastDuration : 105

    readonly property int normalDuration:
        flow && flow.normalDuration !== undefined ? flow.normalDuration : 180

    readonly property int sheetDuration:
        flow && flow.sheetDuration !== undefined ? flow.sheetDuration : 300

    readonly property real pressScale:
        flow && flow.compactPressScale !== undefined ? flow.compactPressScale : 0.95

    signal resultActivated(string kind, string payload, string title)

    visible: presented || opacity > 0.001
    enabled: presented
    focus: presented
    opacity: presented ? 1.0 : 0.0

    function bgColor() { return flow ? flow.theme.backgroundGrouped : (darkMode ? "#070A0D" : "#F4F7FB") }
    function cardColor() { return flow ? flow.theme.surfaceElevated : (darkMode ? "#232A32" : "#FFFFFF") }
    function softColor() { return flow ? flow.theme.infoContainer : (darkMode ? "#172B3B" : "#EAF4FB") }
    function pressedColor() { return flow ? flow.theme.pressed : (darkMode ? "#2A323B" : "#E3EFFB") }
    function textColor() { return flow ? flow.theme.textPrimary : (darkMode ? "#F4F7FB" : "#151A30") }
    function mutedColor() { return flow ? flow.theme.textSecondary : (darkMode ? "#AAB4C0" : "#667085") }
    function borderColor() { return flow ? flow.theme.border : (darkMode ? "#3B4652" : "#DDE7F2") }
    function accentColor() { return flow ? flow.theme.accent : (darkMode ? "#65B4F3" : "#0B6EAE") }
    function withAlpha(colorValue, alphaValue) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alphaValue)
    }

    function clean(value) {
        if (value === undefined || value === null)
            return ""
        return String(value).replace(/^\s+|\s+$/g, "")
    }

    // La normalización solo crea una copia temporal para buscar.
    // Nunca reemplaza correos, nombres ni datos almacenados.
    function normalize(value) {
        return clean(value).toLocaleLowerCase()
            .replace(/[áàäâ]/g, "a")
            .replace(/[éèëê]/g, "e")
            .replace(/[íìïî]/g, "i")
            .replace(/[óòöô]/g, "o")
            .replace(/[úùüû]/g, "u")
            .replace(/ñ/g, "n")
    }

    function groupOrder(groupName) {
        switch (groupName) {
        case "Calicatas": return 0
        case "Mapa": return 1
        case "Documentos": return 2
        case "Rendiciones": return 3
        case "Exportaciones": return 4
        case "Perfil": return 5
        case "Configuración": return 6
        default: return 99
        }
    }

    function sourceResults() {
        var code = clean(currentCalicataCode)
        var project = clean(currentCalicataProject)
        var person = clean(currentUserName)
        var exactMail = currentEmailExact === undefined || currentEmailExact === null
                ? ""
                : String(currentEmailExact)

        var profileSubtitle = guestMode
                ? "Cuenta local de invitado"
                : (exactMail.length > 0 ? exactMail : "Datos de cuenta y sesión")

        var currentFichaTitle = code.length > 0
                ? "Ficha actual · " + code
                : "Ficha actual"

        var currentFichaSubtitle = project.length > 0
                ? project
                : "Continuar con los datos abiertos"

        return [
            {
                group: "Calicatas",
                title: "Abrir Calicatas",
                subtitle: "Crear, editar y revisar fichas geotécnicas",
                kind: "navigate",
                payload: "calicata_editor",
                iconName: "module.calicatas",
                keywords: "calicata calicatas ficha fichas nueva crear editar campo excavacion estratos"
            },
            {
                group: "Calicatas",
                title: currentFichaTitle,
                subtitle: currentFichaSubtitle,
                kind: "navigate",
                payload: "calicata_editor",
                iconName: "calicatas.save",
                keywords: "actual continuar " + code + " " + project
            },
            {
                group: "Mapa",
                title: "Mapa GPS",
                subtitle: "Ubicación, coordenadas y punto de campo",
                kind: "navigate",
                payload: "map",
                iconName: "nav.map",
                keywords: "mapa gps ubicacion localizacion coordenadas latitud longitud punto campo"
            },
            {
                group: "Documentos",
                title: "Documentos",
                subtitle: "Abrir carpetas, archivos, fotos e informes",
                kind: "navigate",
                payload: "docs",
                iconName: "nav.documents",
                keywords: "documentos archivo archivos carpetas fotos informes anexos recursos local drive"
            },
            {
                group: "Rendiciones",
                title: "Rendiciones",
                subtitle: "Borradores, gastos y versiones presentadas",
                kind: "navigate",
                payload: "renditions",
                iconName: "nav.documents",
                keywords: "rendiciones rendicion gastos viaticos presentar versiones proyectos"
            },
            {
                group: "Exportaciones",
                title: "Archivos Excel exportados",
                subtitle: "Abrir Documentos y filtrar archivos XLSX",
                kind: "filter",
                payload: "exports_excel",
                iconName: "export.excel",
                keywords: "exportacion exportaciones exportar excel xlsx hojas calculo archivos"
            },
            {
                group: "Perfil",
                title: person.length > 0 && person !== "Invitado"
                       ? "Perfil de " + person
                       : "Perfil de usuario",
                subtitle: profileSubtitle,
                kind: "overlay",
                payload: "profile",
                iconName: "profile.user",
                keywords: "perfil usuario cuenta avatar foto nombre correo sesion " + person + " " + exactMail
            },
            {
                group: "Configuración",
                title: "Configuración",
                subtitle: "Abrir la sección de Ajustes",
                kind: "navigate",
                payload: "settings",
                iconName: "nav.settings",
                keywords: "configuracion configuración ajustes tema idioma permisos almacenamiento version"
            }
        ]
    }

    function matchScore(item, normalizedQuery) {
        if (normalizedQuery.length === 0)
            return 1

        var title = normalize(item.title)
        var group = normalize(item.group)
        var haystack = normalize(item.title + " " + item.subtitle + " " + item.keywords + " " + item.group)
        var tokens = normalizedQuery.split(/\s+/)
        var score = 0

        if (title === normalizedQuery)
            score += 100
        else if (title.indexOf(normalizedQuery) === 0)
            score += 70
        else if (title.indexOf(normalizedQuery) >= 0)
            score += 50

        if (group === normalizedQuery)
            score += 45
        else if (group.indexOf(normalizedQuery) >= 0)
            score += 20

        for (var i = 0; i < tokens.length; ++i) {
            var token = tokens[i]
            if (token.length === 0)
                continue
            if (haystack.indexOf(token) < 0)
                return -1
            score += 12
        }

        return score
    }

    function refresh() {
        filteredResults.clear()

        var normalizedQuery = normalize(searchField.text)
        var source = sourceResults()
        var matches = []

        for (var i = 0; i < source.length; ++i) {
            var item = source[i]
            var score = matchScore(item, normalizedQuery)
            if (score >= 0) {
                item.score = score
                item.originalOrder = i
                matches.push(item)
            }
        }

        matches.sort(function(a, b) {
            var groupDifference = groupOrder(a.group) - groupOrder(b.group)
            if (groupDifference !== 0)
                return groupDifference
            if (b.score !== a.score)
                return b.score - a.score
            return a.originalOrder - b.originalOrder
        })

        var limit = Math.min(matches.length, maxVisibleResults)
        for (var j = 0; j < limit; ++j) {
            var match = matches[j]
            filteredResults.append({
                group: match.group,
                title: match.title,
                subtitle: match.subtitle,
                kind: match.kind,
                payload: match.payload,
                iconName: match.iconName
            })
        }
    }

    function open(initialText) {
        var initial = initialText === undefined || initialText === null
                ? ""
                : String(initialText)

        searchField.text = initial
        presented = true
        refresh()

        Qt.callLater(function() {
            root.forceActiveFocus()
            searchField.forceActiveFocus()
            searchField.selectAll()
        })
    }

    function closeSearch() {
        presented = false
        searchField.text = ""
        filteredResults.clear()
        sheetDragOffsetV31 = 0.0
        sheetDragProgressV31 = 0.0
        sheetDragVelocityV31 = 0.0
    }

    function updateSheetDragV31(handler) {
        if (!handler.active)
            return

        var raw = Math.max(0.0, Number(handler.activeTranslation.y) || 0.0)
        sheetDragVelocityV31 = Math.max(0.0, Number(handler.centroid.velocity.y) || 0.0)
        sheetDragOffsetV31 = raw * 0.72
        sheetDragProgressV31 = Math.max(0.0, Math.min(1.0, raw / 170.0))
    }

    function finishSheetDragV31(handler) {
        var raw = Math.max(0.0, Number(handler.activeTranslation.y) || 0.0)
        var shouldClose = flow
                && flow.shouldDismissSheet(raw, sheetDragVelocityV31)

        if (shouldClose) {
            closeSearch()
            return
        }

        sheetReboundV31.restart()
    }

    function activateFirstResult() {
        if (filteredResults.count <= 0)
            return

        var first = filteredResults.get(0)
        resultActivated(first.kind, first.payload, first.title)
        closeSearch()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            if (root.flow && root.flow.imeVisible) {
                Qt.inputMethod.hide()
                event.accepted = true
                return
            }
            closeSearch()
            event.accepted = true
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.normalDuration
            easing.type: root.flow && root.flow.easeOut !== undefined
                         ? root.flow.easeOut
                         : Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: sheetReboundV31

        NumberAnimation {
            target: root
            property: "sheetDragOffsetV31"
            to: 0.0
            duration: root.flow ? root.flow.dismissReboundDuration : 180
            easing.type: root.flow ? root.flow.easeEmphasized : Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "sheetDragProgressV31"
            to: 0.0
            duration: root.flow ? root.flow.dismissReboundDuration : 180
            easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        }
    }

    ListModel {
        id: filteredResults
    }

    Rectangle {
        anchors.fill: parent
        color: root.flow
               ? root.flow.scrimColor(root.darkMode, 1.0)
               : "#85000000"
        opacity: root.presented ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.normalDuration
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeSearch()
        }
    }

    FlowCore.FlowGlassSurface {
        id: panel
        flow: root.flow
        materialRole: "emphasized"
        // The Dock already owns the QML backdrop; native strips cannot cover
        // this sheet, so native pages retain the existing safe material.
        darkMode: root.darkMode
        strength: 0.98
        fallbackLight: root.cardColor()
        fallbackDark: root.cardColor()
        width: Math.min(parent.width - 24, 520)
        height: Math.min(
                    parent.height - 40,
                    Math.max(420, Math.min(600, parent.height * 0.78))
                )
        radius: 24
        border.color: root.flow
                      ? root.flow.glassBorderColor(root.darkMode)
                      : root.borderColor()
        border.width: 1
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: (root.presented ? 1.0 : 0.0)
                 * (1.0 - 0.22 * root.sheetDragProgressV31)
        scale: (root.presented ? 1.0 : (root.motionAllowed ? 0.972 : 1.0))
               * (1.0 - 0.018 * root.sheetDragProgressV31)
        transformOrigin: Item.Center

        transform: Translate {
            id: panelTranslateV31
            y: (root.presented || !root.motionAllowed ? 0 : 18)
               + root.sheetDragOffsetV31
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.normalDuration
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.sheetDuration
                easing.type: root.flow && root.flow.easeEmphasized !== undefined
                             ? root.flow.easeEmphasized
                             : Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Item {
                Layout.fillWidth: true
                Layout.minimumHeight: 12
                Layout.preferredHeight: 12
                Layout.maximumHeight: 12

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 5
                    radius: 3
                    color: root.withAlpha(root.mutedColor(), 0.46)
                }

                DragHandler {
                    id: searchSheetDragV31
                    target: null
                    dragThreshold: root.flow ? root.flow.swipeActivationDistance : 16
                    xAxis.enabled: false
                    yAxis.enabled: true
                    grabPermissions: PointerHandler.CanTakeOverFromItems
                                     | PointerHandler.ApprovesTakeOverByAnything

                    onActiveTranslationChanged: root.updateSheetDragV31(searchSheetDragV31)

                    onActiveChanged: {
                        if (!active)
                            root.finishSheetDragV31(searchSheetDragV31)
                    }

                    onCanceled: sheetReboundV31.restart()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 42
                Layout.preferredHeight: 42
                Layout.maximumHeight: 42
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "Buscar en InGe+"
                    color: root.textColor()
                    font.pixelSize: 18
                    font.bold: true
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                Components.FlowIconButton {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    Layout.minimumWidth: 42
                    Layout.minimumHeight: 42
                    Layout.maximumWidth: 42
                    Layout.maximumHeight: 42
                    iconName: "system.close"
                    flow: root.flow
                    iconColor: root.mutedColor()
                    selectedIconColor: root.accentColor()
                    idleColor: root.softColor()
                    pressedColor: root.pressedColor()
                    cornerRadius: 14
                    onClicked: root.closeSearch()
                }
            }

            Rectangle {
                id: searchBox
                Layout.fillWidth: true
                Layout.minimumHeight: 50
                Layout.preferredHeight: 50
                Layout.maximumHeight: 50
                radius: 16
                color: root.softColor()
                border.color: searchField.activeFocus
                              ? root.accentColor()
                              : root.borderColor()
                border.width: searchField.activeFocus ? 2 : 1

                Behavior on border.color {
                    ColorAnimation {
                        duration: root.fastDuration
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 10
                    spacing: 9

                    Components.FlowIcon {
                        Layout.preferredWidth: 21
                        Layout.preferredHeight: 21
                        Layout.alignment: Qt.AlignVCenter
                        name: "action.search"
                        flow: root.flow
                        active: searchField.activeFocus
                        tintColor: root.mutedColor()
                        activeTintColor: root.accentColor()
                        inactiveOpacity: 1.0
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        placeholderText: "Escribe una búsqueda"
                        color: root.textColor()
                        placeholderTextColor: root.mutedColor()
                        font.pixelSize: 15
                        selectByMouse: true
                        inputMethodHints: Qt.ImhNoPredictiveText
                        EnterKey.type: Qt.EnterKeySearch
                        verticalAlignment: TextInput.AlignVCenter
                        background: Item {}

                        onTextChanged: root.refresh()
                        onAccepted: root.activateFirstResult()

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                                if (root.flow && root.flow.imeVisible) {
                                    Qt.inputMethod.hide()
                                    event.accepted = true
                                    return
                                }
                                root.closeSearch()
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            Flickable {
                id: chipsFlick
                Layout.fillWidth: true
                Layout.minimumHeight: 36
                Layout.preferredHeight: 36
                Layout.maximumHeight: 36
                contentWidth: chipsRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                pressDelay: root.flow ? root.flow.touchPressDelay : 80
                flickDeceleration: root.flow ? root.flow.flickDeceleration : 3000
                maximumFlickVelocity: root.flow
                                      ? root.flow.compactMaximumFlickVelocity
                                      : 2200
                boundsBehavior: root.motionAllowed
                                ? Flickable.DragAndOvershootBounds
                                : Flickable.StopAtBounds
                clip: true

                Row {
                    id: chipsRow
                    height: parent.height
                    spacing: 8

                    SearchChip {
                        label: "Calicatas"
                        queryText: "calicata"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                    SearchChip {
                        label: "Mapa"
                        queryText: "mapa"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                    SearchChip {
                        label: "Documentos"
                        queryText: "documentos"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                    SearchChip {
                        label: "Excel"
                        queryText: "excel"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                    SearchChip {
                        label: "Perfil"
                        queryText: "perfil"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                    SearchChip {
                        label: "Ajustes"
                        queryText: "configuracion"
                        flow: root.flow
                        darkMode: root.darkMode
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumHeight: 1
                Layout.preferredHeight: 1
                Layout.maximumHeight: 1
                color: root.borderColor()
            }

            ListView {
                id: resultsView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: filteredResults
                clip: true
                spacing: 7
                pressDelay: root.flow ? root.flow.touchPressDelay : 80
                flickDeceleration: root.flow ? root.flow.flickDeceleration : 3000
                maximumFlickVelocity: root.flow
                                      ? root.flow.scrollVelocity(contentHeight, height)
                                      : 2400
                boundsBehavior: root.motionAllowed
                                ? Flickable.DragAndOvershootBounds
                                : Flickable.StopAtBounds
                currentIndex: filteredResults.count > 0 ? 0 : -1
                visible: filteredResults.count > 0

                ScrollIndicator.vertical: ScrollIndicator {
                    active: resultsView.moving || resultsView.dragging
                }

                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    width: resultsView.width
                    height: 30

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: section
                        color: root.accentColor()
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                delegate: Rectangle {
                    id: resultCard
                    required property string group
                    required property string title
                    required property string subtitle
                    required property string kind
                    required property string payload
                    required property string iconName

                    width: resultsView.width
                    height: 68
                    radius: 16
                    color: resultMouse.pressed
                           ? root.pressedColor()
                           : root.softColor()
                    border.color: root.borderColor()
                    border.width: 1
                    scale: resultMouse.pressed ? root.pressScale : 1.0
                    clip: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastDuration
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: root.fastDuration
                            easing.type: root.flow && root.flow.easeOut !== undefined
                                         ? root.flow.easeOut
                                         : Easing.OutCubic
                        }
                    }

                    FlowCore.FlowRipple {
                        id: resultRipple
                        flow: root.flow
                        rippleColor: root.withAlpha(root.accentColor(), 0.20)
                        enabled: root.motionAllowed
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 10
                        anchors.topMargin: 9
                        anchors.bottomMargin: 9
                        spacing: 11

                        Rectangle {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            Layout.alignment: Qt.AlignVCenter
                            radius: 14
                            color: root.cardColor()
                            border.color: root.borderColor()

                            Components.FlowIcon {
                                anchors.centerIn: parent
                                width: 27
                                height: 27
                                name: resultCard.iconName
                                flow: root.flow
                                pressed: resultMouse.pressed
                                tintColor: root.accentColor()
                                activeTintColor: root.accentColor()
                                inactiveOpacity: 1.0
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: resultCard.title
                                color: root.textColor()
                                font.pixelSize: 14
                                font.bold: true
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: resultCard.subtitle
                                color: root.mutedColor()
                                font.pixelSize: 11
                                maximumLineCount: 1
                                elide: Text.ElideMiddle
                            }
                        }

                        Components.FlowIcon {
                            Layout.preferredWidth: 19
                            Layout.preferredHeight: 19
                            Layout.alignment: Qt.AlignVCenter
                            name: "system.chevronRight"
                            flow: root.flow
                            pressed: resultMouse.pressed
                            tintColor: root.mutedColor()
                            activeTintColor: root.accentColor()
                            inactiveOpacity: 0.8
                        }
                    }

                    MouseArea {
                        id: resultMouse
                        anchors.fill: parent

                        onPressed: function(mouse) {
                            resultRipple.trigger(mouse.x, mouse.y)
                        }

                        onClicked: {
                            root.resultActivated(
                                resultCard.kind,
                                resultCard.payload,
                                resultCard.title
                            )
                            root.closeSearch()
                        }
                    }
                }

                footer: Item {
                    width: resultsView.width
                    height: 10
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: filteredResults.count === 0
                spacing: 8

                Item {
                    Layout.fillHeight: true
                }

                Components.FlowIcon {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    Layout.alignment: Qt.AlignHCenter
                    name: "action.search"
                    flow: root.flow
                    tintColor: root.mutedColor()
                    activeTintColor: root.accentColor()
                    inactiveOpacity: 0.5
                }

                Text {
                    Layout.fillWidth: true
                    text: "Sin resultados"
                    color: root.textColor()
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "Prueba con calicata, mapa, documentos, excel, perfil o configuración."
                    color: root.mutedColor()
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }

    component SearchChip: Rectangle {
        id: chip

        property string label: ""
        property string queryText: ""
        property var flow: null
        property bool darkMode: false

        width: chipText.implicitWidth + 24
        height: 34
        radius: 17
        color: chipMouse.pressed
               ? (flow ? flow.theme.pressed : (darkMode ? "#2A323B" : "#E3EFFB"))
               : (flow ? flow.theme.infoContainer : (darkMode ? "#172B3B" : "#EAF4FB"))
        border.color: flow ? flow.theme.border : (darkMode ? "#3B4652" : "#DDE7F2")
        scale: chipMouse.pressed
               ? (flow && flow.compactPressScale !== undefined
                  ? flow.compactPressScale
                  : 0.95)
               : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: flow && flow.fastDuration !== undefined
                          ? flow.fastDuration
                          : 105
            }
        }

        FlowCore.FlowRipple {
            id: chipRipple
            flow: chip.flow
            rippleColor: chip.flow
                         ? Qt.rgba(chip.flow.theme.accent.r,
                                   chip.flow.theme.accent.g,
                                   chip.flow.theme.accent.b,
                                   0.20)
                         : (chip.darkMode ? "#3365B4F3" : "#330B6EAE")
            enabled: chip.flow !== null
                     && chip.flow !== undefined
                     && chip.flow.motionAllowed === true
        }

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.flow ? chip.flow.theme.textSecondary
                             : (chip.darkMode ? "#AAB4C0" : "#4D5A6A")
            font.pixelSize: 11
            font.bold: true
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent

            onPressed: function(mouse) {
                chipRipple.trigger(mouse.x, mouse.y)
            }

            onClicked: searchField.text = chip.queryText
        }
    }
}
