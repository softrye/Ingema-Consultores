import QtQuick 2.15

QtObject {
    readonly property int linear: Easing.Linear
    readonly property int enter: Easing.OutCubic
    readonly property int exit: Easing.InCubic
    readonly property int standard: Easing.InOutCubic
    readonly property int emphasized: Easing.OutQuart
    readonly property int overshoot: Easing.OutBack
}
