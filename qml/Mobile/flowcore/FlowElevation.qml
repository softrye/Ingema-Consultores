import QtQuick 2.15

QtObject {
    readonly property int flat: 0
    readonly property int low: 1
    readonly property int medium: 2
    readonly property int high: 3

    readonly property real lowShadowOpacity: 0.10
    readonly property real mediumShadowOpacity: 0.16
    readonly property real highShadowOpacity: 0.24

    function shadowOpacity(level) {
        if (level >= high)
            return highShadowOpacity
        if (level >= medium)
            return mediumShadowOpacity
        if (level >= low)
            return lowShadowOpacity
        return 0.0
    }
}
