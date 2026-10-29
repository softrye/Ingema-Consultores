import QtQuick
import QtTest
import "../../../qml/Mobile/renditions" as Renditions
import "../../../qml/Mobile/renditions/RStyle.js" as S

TestCase {
    id: test
    name: "RenditionsRenderStability"
    when: windowShown
    width: 412; height: 915
    QtObject {
        id: ui
        property real u: 1
        property string fontFamily: ""
        property string iconFamily: ""
        property real topInset: 24
        property real gutter: 18
        property real dockArea: 96
        property bool reducedMotion: true
        property var cardGlassUi: null
        property real dockGlassRefraction: 0
        property real dockGlassBevel: 0
        property real dockGlassContrast: 0
        property real dockGlassFrost: 0
        property real dockGlassShadowAlpha: 0
    }
    QtObject {
        id: ctl
        property bool ready: true
        function filterRenditions(q, s, p) { return app.st.renditions || [] }
        function completion(row) { return {known: false} }
        function project(id) { return {} }
        function projectLabel(id) { return "" }
        function statusLabel(status) { return status }
        function formatMoney(value, currency) { return String(value) }
    }
    QtObject {
        id: app
        property var ui: testUi
        property var ctl: testCtl
        property var st: ({renditions: []})
        property bool modalOpen: false
        property var touchLayer: null
        property var homeTouchItem: null
        property var homeTouchMenu: null
        property var createSheetEditor: null
        property string phase: "IDLE"
        function busy(key) { return false }
    }
    readonly property var testUi: ui
    readonly property var testCtl: ctl
    Component { id: homeComponent; Renditions.RenditionsHome { app: testApp; width: 412; height: 915 } }
    readonly property var testApp: app
    function renditionCard(item, id) {
        if (item.row && item.row.localId === id) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = renditionCard(children[i], id)
            if (found) return found
        }
        return null
    }
    ListModel { id: rows }
    Repeater {
        id: repeater
        model: rows
        delegate: Item {
            required property string rowJson
            readonly property var row: JSON.parse(rowJson)
        }
    }
    function cleanup() { rows.clear() }
    function test_diffPreservesIdentityAndUpdatesContent() {
        S.syncRows(rows, [{localId: "a", amount: 1}, {localId: "b", amount: 2}], ["localId"])
        var a = repeater.itemAt(0), b = repeater.itemAt(1)
        S.syncRows(rows, [{localId: "a", amount: 1}, {localId: "b", amount: 2}], ["localId"])
        compare(repeater.itemAt(0), a)
        compare(repeater.itemAt(1), b)
        S.syncRows(rows, [{localId: "b", amount: 3}, {localId: "c", amount: 4}, {localId: "a", amount: 1}], ["localId"])
        compare(repeater.itemAt(0), b)
        compare(repeater.itemAt(2), a)
        compare(b.row.amount, 3)
        S.syncRows(rows, [{localId: "a", amount: 1}], ["localId"])
        compare(rows.count, 1)
        compare(repeater.itemAt(0), a)
        S.syncRows(rows, [], ["localId"])
        compare(rows.count, 0)
    }
    function test_receivedVersionsHaveDistinctIdentity() {
        S.syncRows(rows, [{rendition_id: "r", version_number: 1}, {rendition_id: "r", version_number: 2}], ["rendition_id", "version_number"])
        var version2 = repeater.itemAt(1)
        S.syncRows(rows, [{rendition_id: "r", version_number: 2}], ["rendition_id", "version_number"])
        compare(rows.count, 1)
        compare(repeater.itemAt(0), version2)
    }
    function test_realHomeKeepsCardWhenRpcUpdatesMetadata() {
        app.st = {renditions: [{localId: "a", status: "BORRADOR", amount: 1}]}
        var home = createTemporaryObject(homeComponent, test)
        verify(home !== null)
        var before = renditionCard(home, "a")
        verify(before !== null)
        app.st = {busy: true, renditions: [{localId: "a", status: "BORRADOR", amount: 1}]}
        wait(30)
        compare(renditionCard(home, "a"), before)
        app.st = {busy: false, renditions: [{localId: "a", status: "APROBADO", amount: 1}]}
        wait(30)
        compare(renditionCard(home, "a"), before)
        compare(before.row.status, "APROBADO")
    }
}
