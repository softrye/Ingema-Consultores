import QtQuick 2.15

QtObject {
    readonly property string idle: "idle"
    readonly property string focused: "focused"
    readonly property string hovered: "hovered"
    readonly property string pressed: "pressed"
    readonly property string selected: "selected"
    readonly property string loading: "loading"
    readonly property string success: "success"
    readonly property string warning: "warning"
    readonly property string error: "error"
    readonly property string disabled: "disabled"
    readonly property string expanded: "expanded"
    readonly property string collapsed: "collapsed"
    readonly property string dragging: "dragging"

    function effective(enabled, busy, hasError, hasSuccess,
                       isPressed, isFocused, isHovered, isSelected) {
        if (!enabled)
            return disabled
        if (busy)
            return loading
        if (hasError)
            return error
        if (hasSuccess)
            return success
        if (isPressed)
            return pressed
        if (isFocused)
            return focused
        if (isHovered)
            return hovered
        if (isSelected)
            return selected
        return idle
    }
}
