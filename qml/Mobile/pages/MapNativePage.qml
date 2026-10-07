import QtQuick
import QtQuick.Controls
import "../flowcore" as FlowCore

Page {
    id: root
    required property var graphicsCore
    property var auth: null
    property var flow: null
    property bool darkMode: false
    property int themeMode: 0
    property real navigationInset: 0
    property bool pageActive: false
    property bool gpsEnabled: false
    property bool gpsServiceEnabled: false
    property bool gpsHasFix: false
    property bool gpsFollow: false
    property string gpsPermissionState: "undetermined"
    property string gpsStatusText: ""
    property string gpsErrorText: ""
    property double gpsLat: NaN
    property double gpsLon: NaN
    property double gpsAlt: NaN
    property double gpsAccuracy: NaN
    property string gpsLastUpdate: ""
    property string gpsProvider: ""
    property string currentCalicataCode: ""
    property string currentProjectId: ""
    property string currentProjectName: ""
    property bool earthHostWasOpened: false

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()
    signal requestGpsFollow(bool enabled)
    signal requestUsePoint(real latitude, real longitude, real altitude, string sourceLabel)
    signal requestOpenCalicatas()
    signal requestExitMap()
    signal requestMeasure()
    signal requestGlobalSearch(string initialText)
    signal requestOpenLocationSettings()
    signal mapInteractionChanged(bool active)
    background: Rectangle {
        color: "#07111C"
    }

    // Misma composición que la pantalla de carga del HTML de Earth: mientras
    // la vista nativa aún no pinta, el usuario ve una sola pantalla continua.
    Item {
        anchors.fill: parent
        visible: root.pageActive && root.earthHostWasOpened

        Rectangle {
            anchors.fill: parent
            color: "#07111C"
        }

        Column {
            anchors.centerIn: parent
            spacing: 10

            // Mismo anillo que el HTML (FluentUI FluProgressRing, MIT).
            FlowCore.FlowProgressRing {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48; height: 48
                strokeWidth: 3
                running: root.pageActive && root.earthHostWasOpened
                color: "#CFE3F5"
                backgroundColor: "#1FFFFFFF"
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Preparando InGe Earth"
                color: "#F4F8FC"
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Preparando interfaz…"
                color: "#8FA3B8"
                font.pixelSize: 13
            }
        }
    }

    function syncGraphicsLifecycle() {
        if (pageActive) {
            earthHostWasOpened = graphicsCore.openEarth()
        } else {
            earthHostWasOpened = false
            graphicsCore.closeEarth()
        }
    }

    onPageActiveChanged: syncGraphicsLifecycle()

    Connections {
        target: root.graphicsCore
        function onStateChanged() {
            if (root.pageActive && root.earthHostWasOpened
                    && root.graphicsCore.earthState === "CLOSED") {
                root.earthHostWasOpened = false
                root.requestExitMap()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 360)
        spacing: 12
        visible: !root.pageActive || !root.earthHostWasOpened
        Label {
            width: parent.width
            text: "InGe Earth"
            color: "#F6F9FC"
            font.pixelSize: 22
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Label {
            width: parent.width
            text: "Próximamente"
            color: "#B9C7D6"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Component.onCompleted: syncGraphicsLifecycle()
    Component.onDestruction: {
        if (!pageActive)
            graphicsCore.closeEarth()
    }
}
