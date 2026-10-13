import QtQuick 2.15
import QtQuick.Window 2.15

// V50: estrategia unica de desplazamiento por IME para contenido editable.
// Android/Qt determinan el viewport; este componente solo desplaza lo minimo
// indispensable para mantener visible el control que posee el foco.
Flickable {
    id: root

    property var flow: null
    property real imeTopMargin: 12.0
    property real imeBottomMargin:
        flow && flow.imeFieldMargin !== undefined ? flow.imeFieldMargin : 20.0
    property bool restoreOnImeClose: true

    readonly property var imeWindow: root.Window.window
    readonly property bool imeVisible:
        flow && flow.imeVisible !== undefined
        ? flow.imeVisible : false
    readonly property real imeAvailableContentHeight:
        flow && flow.availableContentHeight !== undefined
        ? flow.availableContentHeight
        : (imeWindow ? imeWindow.height : root.height)

    property bool __imeSessionActive: false
    property real __imeBaselineContentY: 0.0

    function __maximumContentY() {
        return Math.max(0.0, contentHeight - height)
    }

    function __clampContentY(value) {
        return Math.max(0.0, Math.min(__maximumContentY(), Number(value) || 0.0))
    }

    function __focusedEditor() {
        if (!imeWindow)
            return null

        var focusItem = imeWindow.activeFocusItem
        if (!focusItem)
            return null

        // Solo responde por editores contenidos en este Flickable. Esto evita
        // que el scroll principal se mueva cuando el foco pertenece a un Popup
        // que posee su propio ImeAwareFlickable.
        var item = focusItem
        var editor = focusItem
        var belongsToThisFlickable = false
        while (item) {
            if (item === root || item === root.contentItem) {
                belongsToThisFlickable = true
                break
            }
            try {
                if (item.inputMethodHints !== undefined
                        && item.height >= editor.height)
                    editor = item
            } catch (error) {
            }
            item = item.parent
        }
        if (!belongsToThisFlickable)
            return null

        try {
            var point = editor.mapToItem(root, 0, 0)
            if (!isFinite(point.x) || !isFinite(point.y))
                return null
        } catch (error) {
            return null
        }
        return editor
    }

    function __visibleBottom() {
        var bottom = height
        if (!imeWindow || !imeWindow.contentItem)
            return bottom

        try {
            var mapped = imeWindow.contentItem.mapToItem(
                        root, 0, imeAvailableContentHeight)
            bottom = Math.min(bottom, mapped.y)
        } catch (error) {
        }
        return Math.max(0.0, bottom)
    }

    function __animateTo(value) {
        var targetValue = __clampContentY(value)
        if (Math.abs(contentY - targetValue) < 0.5) {
            imeScrollAnimation.stop()
            contentY = targetValue
            return
        }

        imeScrollAnimation.stop()
        imeScrollAnimation.from = contentY
        imeScrollAnimation.to = targetValue
        var requestedDuration = flow && flow.imeScrollDuration !== undefined
                ? Number(flow.imeScrollDuration) : 190
        if (!isFinite(requestedDuration) || requestedDuration < 0)
            requestedDuration = 190
        imeScrollAnimation.duration = Math.max(0, Math.round(requestedDuration))
        imeScrollAnimation.restart()
    }

    function ensureActiveFocusVisible() {
        if (!imeVisible || height <= 0.0)
            return

        var editor = __focusedEditor()
        if (!editor)
            return

        var position
        try {
            position = editor.mapToItem(root, 0, 0)
        } catch (error) {
            return
        }

        var editorTop = position.y
        var editorBottom = position.y + Math.max(1.0, editor.height)
        var visibleTop = imeTopMargin
        var visibleBottom = __visibleBottom() - imeBottomMargin
        if (visibleBottom <= visibleTop)
            return

        var delta = 0.0
        if (editorBottom > visibleBottom)
            delta = editorBottom - visibleBottom
        else if (editorTop < visibleTop)
            delta = editorTop - visibleTop

        if (Math.abs(delta) >= 0.5)
            __animateTo(contentY + delta)
    }

    function __queueEnsure() {
        if (imeVisible)
            imeEnsureTimer.restart()
    }

    function __beginImeSession() {
        if (!__imeSessionActive) {
            __imeSessionActive = true
            __imeBaselineContentY = contentY
        }
        __queueEnsure()
    }

    function __endImeSession() {
        imeEnsureTimer.stop()
        if (!__imeSessionActive)
            return

        __imeSessionActive = false
        if (restoreOnImeClose) {
            Qt.callLater(function() {
                root.__animateTo(root.__imeBaselineContentY)
            })
        }
    }

    onImeVisibleChanged: {
        if (imeVisible)
            __beginImeSession()
        else
            __endImeSession()
    }
    onHeightChanged: __queueEnsure()

    Component.onCompleted: {
        if (imeVisible)
            __beginImeSession()
    }

    Connections {
        target: root.flow
        enabled: root.flow !== null && root.flow !== undefined
        ignoreUnknownSignals: true

        function onImeKeyboardRectangleChanged() { root.__queueEnsure() }
        function onAvailableContentHeightChanged() { root.__queueEnsure() }
    }

    Connections {
        target: root.imeWindow
        enabled: root.imeWindow !== null && root.imeWindow !== undefined
        ignoreUnknownSignals: true

        function onActiveFocusItemChanged() { root.__queueEnsure() }
    }

    Timer {
        id: imeEnsureTimer
        interval: 24
        repeat: false
        onTriggered: root.ensureActiveFocusVisible()
    }

    NumberAnimation {
        id: imeScrollAnimation
        target: root
        property: "contentY"
        easing.type: Easing.OutCubic
    }
}
