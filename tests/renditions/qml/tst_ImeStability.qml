import QtQuick
import QtQuick.Window
import QtTest
import "../../../qml/Mobile/flowcore" as FlowCore

TestCase {
    id: test
    name: "RenditionsImeStability"
    visible: true
    when: windowShown
    width: 412; height: 915
    QtObject {
        id: flow
        property bool imeVisible: false
        property bool imeAnimating: false
        property real imeFieldMargin: 20
        property int imeScrollDuration: 0
        property real availableContentHeight: test.Window.window ? test.Window.window.height : 915
    }
    Component {
        id: editorComponent
        FlowCore.ImeAwareFlickable {
            width: 300; height: 80
            contentWidth: width; contentHeight: 800
            flow: testFlow
            property alias input: input
            TextEdit { id: input; x: 10; y: 300; width: 260; height: 200; text: "Field"; font.pixelSize: 16; wrapMode: TextEdit.Wrap }
        }
    }
    readonly property var testFlow: flow
    function cleanup() { flow.imeVisible = false; flow.imeAnimating = false; wait(10) }
    function test_tallEditorDoesNotOscillateForRepeatedImeUpdates() {
        var flick = createTemporaryObject(editorComponent, test)
        flick.input.forceActiveFocus()
        flow.imeVisible = true
        wait(60)
        flick.ensureActiveFocusVisible()
        wait(10)
        var initial = flick.contentY
        for (var i = 0; i < 8; ++i) {
            flick.ensureActiveFocusVisible()
            wait(5)
            compare(flick.contentY, initial, "same focus and viewport must not alternate top/bottom")
        }
    }
    function test_typingInsideVisibleCaretDoesNotMoveThePageAgain() {
        var flick = createTemporaryObject(editorComponent, test)
        flick.input.forceActiveFocus()
        flow.imeVisible = true
        wait(60)
        flick.ensureActiveFocusVisible()
        wait(10)
        var initial = flick.contentY
        for (var i = 0; i < 20; ++i) {
            flick.input.text += "x"
            flick.ensureActiveFocusVisible()
            wait(5)
            compare(flick.contentY, initial, "typing one line must keep the viewport stable")
        }
    }
    function test_newLinesStillRevealTheCursor() {
        var flick = createTemporaryObject(editorComponent, test)
        flick.input.forceActiveFocus()
        flow.imeVisible = true
        wait(60)
        var initial = flick.contentY
        flick.input.text = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
        flick.input.cursorPosition = flick.input.length
        wait(50)
        verify(flick.contentY > initial, "a cursor that moves below the viewport must remain reachable")
        var settled = flick.contentY
        flick.ensureActiveFocusVisible()
        wait(10)
        compare(flick.contentY, settled)
    }
    function test_waitsUntilImeAnimationFinishes() {
        flow.imeAnimating = true
        var flick = createTemporaryObject(editorComponent, test)
        flick.input.forceActiveFocus()
        flow.imeVisible = true
        wait(60)
        compare(flick.contentY, 0)
        flow.imeAnimating = false
        tryVerify(function() { return flick.contentY > 0 })
    }
    function test_modalPolicyDoesNotRestoreAnOldScrollPositionOnKeyboardClose() {
        var flick = createTemporaryObject(editorComponent, test)
        flick.restoreOnImeClose = false
        flick.input.forceActiveFocus()
        flow.imeVisible = true
        wait(60)
        var settled = flick.contentY
        verify(settled > 0)
        flow.imeVisible = false
        wait(40)
        compare(flick.contentY, settled)
    }
}
