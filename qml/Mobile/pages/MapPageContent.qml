import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning

// Compatibilidad del shell QML histórico.
// La cartografía activa de InGe+ se ejecuta en InGe Earth con Cesium.
Page {
    id: root

    required property var auth
    property var flow: null
    property bool darkMode: false
    property int themeMode: 0
    property bool pageActive: false
    property bool coordinatePickerMode: false
    property real navigationInset: 92

    property bool gpsEnabled: false
    property bool gpsServiceEnabled: false
    property bool gpsHasFix: false
    property string gpsPermissionState: "undetermined"
    property string gpsStatusText: "GPS desactivado"
    property string gpsErrorText: ""
    property double gpsLat: NaN
    property double gpsLon: NaN
    property double gpsAlt: NaN
    property double gpsAccuracy: NaN
    property string gpsLastUpdate: "--:--:--"
    property string gpsProvider: ""
    property string currentCalicataCode: "Calicata actual"

    // API heredada de AppShell.
    property bool gpsAutoShare: false
    property bool gpsHasPermission: false
    property var gpsCoord: QtPositioning.coordinate()
    property double gpsAltitude: NaN

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()
    signal requestUsePoint(real latitude, real longitude, real altitude, string sourceLabel)
    signal requestOpenCalicatas()
    signal requestOpenLocationSettings()
    signal requestGlobalSearch(string initialText)
    signal mapInteractionChanged(bool active)
    signal requestGpsAutoShare(bool enabled)

    function effectiveLat() {
        if (isFinite(gpsLat))
            return gpsLat
        return gpsCoord && isFinite(gpsCoord.latitude) ? gpsCoord.latitude : NaN
    }

    function effectiveLon() {
        if (isFinite(gpsLon))
            return gpsLon
        return gpsCoord && isFinite(gpsCoord.longitude) ? gpsCoord.longitude : NaN
    }

    function effectiveAlt() {
        return isFinite(gpsAlt) ? gpsAlt : gpsAltitude
    }

    function hasCoordinate() {
        return isFinite(effectiveLat()) && isFinite(effectiveLon())
    }

    background: Rectangle {
        color: root.darkMode ? "#07111C" : "#F1F5F9"
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 380)
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: "InGe Earth"
            color: root.darkMode ? "#F6F9FC" : "#172033"
            font.pixelSize: 24
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: "Cesium es el motor cartográfico único de InGe+."
            color: root.darkMode ? "#B9C7D6" : "#5D6B7A"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: root.hasCoordinate()
                  ? Number(root.effectiveLat()).toFixed(6) + ", "
                    + Number(root.effectiveLon()).toFixed(6)
                  : "Sin coordenada GPS disponible"
            color: root.darkMode ? "#9CC4E0" : "#24577D"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Actualizar GPS"
            onClicked: root.requestGpsRefresh()
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            visible: root.coordinatePickerMode && root.hasCoordinate()
            text: "Usar esta ubicación"
            onClicked: root.requestUsePoint(root.effectiveLat(),
                                            root.effectiveLon(),
                                            root.effectiveAlt(),
                                            "GPS del dispositivo")
        }
    }

    function handleBack() { return false }

    Component.onCompleted: mapInteractionChanged(false)
    Component.onDestruction: mapInteractionChanged(false)
}
