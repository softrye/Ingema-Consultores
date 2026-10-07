import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Page {
    id: root

    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2

    readonly property var pageFlow: Mobile.InGeCoreFlow



    // === ARM HYBRID PHONE/TABLET HELPERS ===
    readonly property real __armWidth:  width  > 0 ? width  : 420
    readonly property real __armHeight: height > 0 ? height : 820
    readonly property real __armMinSide: Math.min(__armWidth, __armHeight)
    readonly property bool __armPhone: __armMinSide < 600
    readonly property bool __armTablet: !__armPhone
    readonly property real __armScale: __armPhone
        ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0))
        : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
    readonly property int __touchTarget: Math.round((__armPhone ? 56 : 60) * __armScale)
    readonly property int __touchPressDelay: 140
    readonly property real __flickVelocity: __armPhone ? 1600 : 2200
    function __dp(v) { return Math.round(v * __armScale) }
    function __sp(v) { return Math.max(12, Math.round(v * __armScale)) }

    implicitWidth: root.__dp(420)
    implicitHeight: root.__dp(820)

    required property var auth
    property bool darkMode: false

    signal requestOpenCalicata()
    signal requestOpenTalud()
    signal requestOpenPE()
    signal requestOpenEG()
    signal requestOpenMap()
    signal requestOpenDocs()

    // === HeaderBar lee estas propiedades desde AppShell ===
    property string greetingText: "Hola, Invitado"
    property string subGreetingText: "Centro de trabajo InGe+"
    property bool showSearch: true

    // === Compatibilidad con HomePage.qml ===
    property alias cardCalicata: cardCalicata
    property alias cardTalud:    cardTalud
    property alias cardPE:       cardPE
    property alias cardEG:       cardEG
    property alias cardPend1:    cardPend1
    property alias cardPend2:    cardPend2
    property alias cardPend3:    cardPend3
    property alias cardPend4:    cardPend4

    property real pad: root.__dp(root.__armPhone ? 16 : 24)
    property real gap: root.__dp(root.__armPhone ? 12 : 16)
    property real cardW: root.__armPhone
                         ? ((width - (pad * 2) - gap) / 2)
                         : Math.min(root.__dp(250), (width - (pad * 2) - (gap * 2)) / 3)
    property real cardH: Math.max(root.__dp(142), cardW * 0.92)

    function asset(path) { return "qrc:/ui/v2/" + path }

    function searchAccepted(text) {
        var q = (text || "").toString().trim()
        if (q.length === 0)
            return
        console.log("[Home] búsqueda recibida:", q)
    }

    function bgColor() { return darkMode ? "#10151C" : "#F7F9FC" }
    function cardColor() { return darkMode ? "#161D26" : "#FFFFFF" }
    function cardSoftColor() { return darkMode ? "#1D2733" : "#F1F6FC" }
    function textColor() { return darkMode ? "#F4F7FA" : "#16202A" }
    function mutedColor() { return darkMode ? "#AAB7C5" : "#5E6A78" }
    function borderColor() { return darkMode ? "#2A3442" : "#D7DEE7" }
    function primaryColor() { return darkMode ? "#3D8DDB" : "#0B5FA5" }
    function successColor() { return darkMode ? "#39B97C" : "#1D8F5A" }
    function warningColor() { return darkMode ? "#E3AB3C" : "#D38A17" }

    background: Rectangle { color: root.bgColor() }

    ScrollView {
        id: sv
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            id: body
            width: sv.availableWidth
            padding: root.pad
            spacing: root.__dp(16)

            Rectangle {
                width: parent.width - (body.padding * 2)
                height: root.__dp(134)
                radius: root.__dp(24)
                color: root.darkMode ? "#142033" : "#EAF3FF"
                border.color: root.darkMode ? "#26384E" : "#D4E6FA"
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.asset("backgrounds/bg_topographic_lines.svg")
                    fillMode: Image.PreserveAspectCrop
                    opacity: root.darkMode ? 0.12 : 0.22
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: root.__dp(16)
                    spacing: root.__dp(14)

                    Rectangle {
                        width: root.__dp(58)
                        height: root.__dp(58)
                        radius: root.__dp(18)
                        color: root.darkMode ? "#223247" : "#FFFFFF"
                        border.color: root.borderColor()
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            anchors.centerIn: parent
                            width: root.__dp(34)
                            height: root.__dp(34)
                            source: root.asset("home/icon_home_new_calicata.svg")
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    Column {
                        width: parent.width - root.__dp(72)
                        spacing: root.__dp(5)
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: "Panel principal"
                            color: root.textColor()
                            font.pixelSize: root.__sp(20)
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: "Crea fichas, revisa mapas y organiza documentos desde un inicio limpio."
                            color: root.mutedColor()
                            font.pixelSize: root.__sp(12)
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: root.__dp(8)

                            StatusPill {
                                text: "Calicatas activo"
                                colorBase: root.successColor()
                                darkMode: root.darkMode
                            }

                            StatusPill {
                                text: "Otros módulos próximamente"
                                colorBase: root.warningColor()
                                darkMode: root.darkMode
                            }
                        }
                    }
                }
            }

            Label {
                width: parent.width - (body.padding * 2)
                text: "Accesos rápidos"
                color: root.textColor()
                font.pixelSize: root.__sp(18)
                font.bold: true
            }

            Row {
                width: parent.width - (body.padding * 2)
                spacing: root.__dp(10)

                QuickActionButton {
                    width: (parent.width - root.__dp(20)) / 3
                    height: root.__dp(86)
                    title: "Nueva"
                    subtitle: "Calicata"
                    iconSource: root.asset("home/icon_home_new_calicata.svg")
                    darkMode: root.darkMode
                    onClicked: root.requestOpenCalicata()
                }

                QuickActionButton {
                    width: (parent.width - root.__dp(20)) / 3
                    height: root.__dp(86)
                    title: "Mapa"
                    subtitle: "Ubicación"
                    iconSource: root.asset("home/icon_home_map.svg")
                    darkMode: root.darkMode
                    onClicked: root.requestOpenMap()
                }

                QuickActionButton {
                    width: (parent.width - root.__dp(20)) / 3
                    height: root.__dp(86)
                    title: "Docs"
                    subtitle: "Archivos"
                    iconSource: root.asset("home/icon_home_docs.svg")
                    darkMode: root.darkMode
                    onClicked: root.requestOpenDocs()
                }
            }

            Label {
                width: parent.width - (body.padding * 2)
                text: "Módulos"
                color: root.textColor()
                font.pixelSize: root.__sp(18)
                font.bold: true
            }

            Flow {
                id: grid
                width: parent.width - (body.padding * 2)
                spacing: root.gap

                HomeModuleCard {
                    id: cardCalicata
                    width: root.cardW
                    height: root.cardH
                    title: "Ficha de calicata"
                    subtitle: "Registro técnico de campo"
                    iconSource: root.asset("home/icon_home_new_calicata.svg")
                    enabledModule: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardTalud
                    width: root.cardW
                    height: root.cardH
                    title: "Ficha de talud"
                    subtitle: "Módulo en preparación"
                    iconSource: root.asset("home/icon_home_talud.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardPE
                    width: root.cardW
                    height: root.cardH
                    title: "Perfiles estratigráficos"
                    subtitle: "Módulo en preparación"
                    iconSource: root.asset("home/icon_home_strata.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardEG
                    width: root.cardW
                    height: root.cardH
                    title: "Estaciones geomecánicas"
                    subtitle: "Módulo en preparación"
                    iconSource: root.asset("home/icon_home_geomechanics.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardPend1
                    width: root.cardW
                    height: root.cardH
                    title: "Inventario"
                    subtitle: "Próximamente"
                    iconSource: root.asset("home/icon_home_coming_soon.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardPend2
                    width: root.cardW
                    height: root.cardH
                    title: "Reportes"
                    subtitle: "Próximamente"
                    iconSource: root.asset("home/icon_home_coming_soon.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardPend3
                    width: root.cardW
                    height: root.cardH
                    title: "Sincronización"
                    subtitle: "Próximamente"
                    iconSource: root.asset("home/icon_home_coming_soon.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }

                HomeModuleCard {
                    id: cardPend4
                    width: root.cardW
                    height: root.cardH
                    title: "Asistencia"
                    subtitle: "Próximamente"
                    iconSource: root.asset("home/icon_home_coming_soon.svg")
                    comingSoon: true
                    darkMode: root.darkMode
                }
            }

            Rectangle {
                width: parent.width - (body.padding * 2)
                height: root.__dp(74)
                radius: root.__dp(18)
                color: root.cardColor()
                border.color: root.borderColor()

                Row {
                    anchors.fill: parent
                    anchors.margins: root.__dp(12)
                    spacing: root.__dp(10)

                    Image {
                        width: root.__dp(32)
                        height: root.__dp(32)
                        source: root.asset("shared_icons/icon_info.svg")
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        width: parent.width - root.__dp(44)
                        text: "Los módulos no terminados quedan bloqueados como Próximamente para evitar entradas accidentales."
                        color: root.mutedColor()
                        font.pixelSize: root.__sp(11)
                        wrapMode: Text.WordWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    component StatusPill: Rectangle {
        property string text: ""
        property color colorBase: "#0B5FA5"
        property bool darkMode: false

        width: label.implicitWidth + 18
        height: 26
        radius: 13
        color: darkMode ? Qt.rgba(colorBase.r, colorBase.g, colorBase.b, 0.18)
                        : Qt.rgba(colorBase.r, colorBase.g, colorBase.b, 0.12)
        border.color: Qt.rgba(colorBase.r, colorBase.g, colorBase.b, 0.36)

        Label {
            id: label
            anchors.centerIn: parent
            text: parent.text
            color: parent.colorBase
            font.pixelSize: 10
            font.bold: true
        }
    }

    component QuickActionButton: Button {
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        property bool darkMode: false

        padding: 0
        background: Rectangle {
            radius: 18
            color: parent.down ? (parent.darkMode ? "#243349" : "#E6F1FF")
                               : (parent.darkMode ? "#161D26" : "#FFFFFF")
            border.color: parent.darkMode ? "#2A3442" : "#D7DEE7"
        }

        contentItem: Column {
            anchors.centerIn: parent
            spacing: 4

            Image {
                width: 28
                height: 28
                anchors.horizontalCenter: parent.horizontalCenter
                source: parent.parent.iconSource
                fillMode: Image.PreserveAspectFit
            }

            Label {
                text: parent.parent.title
                color: parent.parent.darkMode ? "#F4F7FA" : "#16202A"
                font.pixelSize: 12
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Label {
                text: parent.parent.subtitle
                color: parent.parent.darkMode ? "#AAB7C5" : "#5E6A78"
                font.pixelSize: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    component HomeModuleCard: Button {
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        property bool comingSoon: false
        property bool enabledModule: false
        property bool darkMode: false

        padding: 0

        background: Rectangle {
            radius: 18
            color: parent.down ? (parent.darkMode ? "#243349" : "#E6F1FF")
                               : (parent.darkMode ? "#161D26" : "#FFFFFF")
            border.color: parent.enabledModule ? (parent.darkMode ? "#3D8DDB" : "#0B5FA5")
                                               : (parent.darkMode ? "#2A3442" : "#D7DEE7")
            border.width: parent.enabledModule ? 1.4 : 1
        }

        contentItem: Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Rectangle {
                width: 52
                height: 52
                radius: 18
                color: parent.parent.enabledModule
                       ? (parent.parent.darkMode ? "#193352" : "#EAF3FF")
                       : (parent.parent.darkMode ? "#1D2733" : "#F1F4F8")
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    source: parent.parent.parent.iconSource
                    fillMode: Image.PreserveAspectFit
                    opacity: parent.parent.parent.comingSoon ? 0.72 : 1
                }
            }

            Label {
                width: parent.width
                text: parent.parent.title
                color: parent.parent.darkMode ? "#F4F7FA" : "#16202A"
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Label {
                width: parent.width
                text: parent.parent.subtitle
                color: parent.parent.darkMode ? "#AAB7C5" : "#5E6A78"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Rectangle {
                width: coming.implicitWidth + 18
                height: 24
                radius: 12
                color: parent.parent.comingSoon
                       ? (parent.parent.darkMode ? "#332B18" : "#FFF5DA")
                       : (parent.parent.darkMode ? "#183426" : "#E9F8F0")
                border.color: parent.parent.comingSoon
                              ? (parent.parent.darkMode ? "#6A5320" : "#F0D48A")
                              : (parent.parent.darkMode ? "#2F7A50" : "#BFE8CE")
                visible: parent.parent.comingSoon || parent.parent.enabledModule
                anchors.horizontalCenter: parent.horizontalCenter

                Label {
                    id: coming
                    anchors.centerIn: parent
                    text: parent.parent.parent.comingSoon ? "Próximamente" : "Disponible"
                    color: parent.parent.parent.comingSoon
                           ? (parent.parent.parent.darkMode ? "#E3AB3C" : "#9A6A12")
                           : (parent.parent.parent.darkMode ? "#39B97C" : "#1D8F5A")
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }
}
