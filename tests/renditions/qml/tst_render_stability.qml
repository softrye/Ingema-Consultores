import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml/Mobile/renditions" as Renditions
import "../../../qml/Mobile" as Mobile
import "../../../qml/Mobile/renditions/RStyle.js" as S

TestCase {
    id: test
    name: "RenditionsRenderStability"
    when: windowShown
    visible: true
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
        property bool liquidGlass: true
        property bool dockLowCostGlass: true
        property string appSkin: "none"
    }
    QtObject {
        id: ctl
        property bool ready: true
        property var state: ({renditions: []})
        property var diagnostics: ({})
        property var pendingKeys: []
        property int syncCalls: 0
        property int requests: 0
        property var calls: []
        function newId() { return "test-client" }
        function send(operation, args, key) {
            calls.push({operation: operation, args: args})
            if (operation === "sync") ++syncCalls
            return "test-request-" + (++requests)
        }
        function isPending(key) { return false }
        function filterRenditions(q, s, p) { return app.st.renditions || [] }
        function completion(row) { return {known: false} }
        function project(id) { return {} }
        function projectLabel(id) { return "" }
        function statusLabel(status) { return status }
        function formatMoney(value, currency) { return String(value) }
        function today() { return "2026-10-29" }
        function catalog(kind) { return [] }
        function canEdit(row) { return true }
        function totals(rows) { return {count: rows.length, penCents: 0, usdCents: 0} }
        function formatCents(value, currency) { return String(value) }
        function fundBalance(row) { return {} }
        function syncLabel(state) { return state }
        function visibleSyncError(message) { return message }
        function amountError(value) { return "" }
        function expenseError(rendition, expense) { return "" }
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
        property var flow: null
        property string phase: "IDLE"
        property var calls: []
        function busy(key) { return false }
        function syncState(row) { return String(row.syncState || "SYNCED") }
        function call(operation, args, key, done) { calls.push({operation: operation, args: args}); return "request" }
    }
    readonly property var testUi: ui
    readonly property var testCtl: ctl
    Component { id: homeComponent; Renditions.RenditionsHome { app: testApp; width: 412; height: 915 } }
    Component { id: glassComponent; Mobile.GlassSurface { ui: null; visible: true } }
    QtObject { id: flow; property bool imeVisible: false }
    readonly property var testFlow: flow
    Component {
        id: shellComponent
        Renditions.RenditionsApp {
            ui: testUi; ctl: testCtl; flow: testFlow
            active: true; width: 412; height: 915
        }
    }
    Component {
        id: channelComponent
        QtObject {
            property string topic: ""
            property bool active: false
            property var trackMeta: ({})
            property var members: []
            property string state: "JOINED"
            function broadcast(event, payload) {}
            signal broadcastReceived(string event, var payload)
            signal rejoined()
        }
    }
    Component {
        id: fakeDetailComponent
        Item {
            property bool isRenditionDetail: true
            property bool ownHeader: true
            property string remoteId: "remote-test"
            property string localId: "local-test"
            property var current: ({})
            property bool editable: false
            property bool renderInteractionBusy: false
            property string projectLine: ""
            property QtObject expensesTab: QtObject {
                property bool editorActive: false
                property var focusTileItem: null
                property string query: ""
            }
        }
    }
    readonly property var testApp: app
    QtObject {
        id: expenseDetail
        property var app: testApp
        property var ui: testUi
        property var ctl: testCtl
        property bool selected: true
        property bool writable: false
        property bool editable: false
        property bool expensesKnown: true
        property var current: ({})
        property var balance: ({})
        property var rate: ({})
        property string localId: "test-rendition"
        property real pullThreshold: 76
    }
    readonly property var testExpenseDetail: expenseDetail
    Component {
        id: expensesComponent
        Renditions.RenditionExpenses { detail: testExpenseDetail; width: 412; height: 915 }
    }
    Component {
        id: documentsComponent
        Renditions.RenditionDocuments { detail: testExpenseDetail; width: 412; height: 915 }
    }
    Component {
        id: reviewPanelComponent
        Renditions.ReviewPanel { app: testApp; remoteId: "remote-test"; active: false; width: 380 }
    }
    function modeledCard(item, id) {
        if (item.modelData && item.modelData.localId === id) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = modeledCard(children[i], id)
            if (found) return found
        }
        return null
    }
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
    property var volatileRows: []
    property int volatileCreations: 0
    property int stableCreations: 0
    Repeater {
        id: volatileRepeater
        model: test.volatileRows
        delegate: Item { required property var modelData; Component.onCompleted: ++test.volatileCreations }
    }
    Repeater {
        id: repeater
        model: rows
        delegate: Item {
            Component.onCompleted: ++test.stableCreations
            required property string rowJson
            readonly property var row: JSON.parse(rowJson)
        }
    }
    function cleanup() { rows.clear(); volatileRows = []; app.st = {renditions: []}; flow.imeVisible = false }
    function test_twentyRowUpdatesCreateZeroStableDelegates() {
        volatileRows = [{localId: "a", amount: 0}]
        S.syncRows(rows, [{localId: "a", amount: 0}], ["localId"])
        wait(5)
        var volatileBefore = volatileCreations, stableBefore = stableCreations
        verify(volatileRepeater.itemAt(0) !== null)
        for (var i = 0; i < 20; ++i) {
            volatileRows = [{localId: "a", amount: i + 1}]
            S.syncRows(rows, [{localId: "a", amount: i + 1}], ["localId"])
            wait(5)
        }
        compare(volatileCreations - volatileBefore, 20)
        compare(stableCreations - stableBefore, 0)
    }
    function test_equalArrayPayloadAlreadyPreservesDelegatesInQt693() {
        volatileRows = [{localId: "a", amount: 1}]
        wait(5)
        var before = volatileCreations
        for (var i = 0; i < 20; ++i) {
            volatileRows = [{localId: "a", amount: 1}]
            wait(5)
        }
        compare(volatileCreations - before, 0)
    }
    function test_draftReturnConfirmsWithoutReasonAndDoesNotSendOldObservation() {
        var panel = createTemporaryObject(reviewPanelComponent, test)
        verify(panel !== null)
        panel.context = {status: "EN_REVISION", row_version: 7, next_states: ["BORRADOR", "OBSERVADO"]}
        panel.nextState = "BORRADOR"
        compare(findChild(panel, "reviewConfirm").visible, true)
        compare(findChild(panel, "reviewReason").visible, false)
        panel.reason = "Previous observation"
        var count = app.calls.length
        panel.transition()
        compare(app.calls.length, count + 1)
        compare(app.calls[count].args.nextState, "BORRADOR")
        compare(app.calls[count].args.reason, "")
        panel.nextState = "OBSERVADO"
        panel.reason = ""
        compare(findChild(panel, "reviewConfirm").visible, false)
        compare(findChild(panel, "reviewReason").visible, true)
    }
    function test_dockDraftSheetSendsEmptyReasonAndObservationsStillNeedOne() {
        var shell = createTemporaryObject(shellComponent, test)
        var stack = findChild(shell, "renditionsHome").StackView.view
        stack.push(fakeDetailComponent, {}, StackView.Immediate)
        shell.reviewCtx = {row_version: 7, next_states: ["BORRADOR", "OBSERVADO"]}
        var sheet = findChild(shell, "stateSheet")
        sheet.openFor("transition", "BORRADOR")
        compare(findChild(shell, "stateChangeReason").visible, false)
        var count = ctl.calls.length
        sheet.submit()
        compare(ctl.calls.length, count + 1)
        compare(ctl.calls[count].operation, "reviewTransition")
        compare(ctl.calls[count].args.reason, "")
        sheet.busy = false
        sheet.openFor("transition", "OBSERVADO")
        count = ctl.calls.length
        sheet.submit()
        compare(ctl.calls.length, count)
        verify(sheet.errorText.length > 0)
        sheet.close()
    }
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
    function test_realExpensesKeepDelegateThroughRpcAndAmountChange() {
        app.st = {expenses: [{localId: "a", concept: "Test", amount: "1.00", currencyCode: "PEN"}]}
        var expenses = createTemporaryObject(expensesComponent, test)
        verify(expenses !== null)
        var before = findChild(expenses, "expense:a")
        verify(before !== null)
        app.st = {busy: true, expenses: [{localId: "a", concept: "Test", amount: "1.00", currencyCode: "PEN"}]}
        wait(30)
        compare(findChild(expenses, "expense:a"), before)
        app.st = {busy: false, expenses: [{localId: "a", concept: "Test", amount: "2.00", currencyCode: "PEN"}]}
        wait(30)
        compare(findChild(expenses, "expense:a"), before)
        compare(before.modelData.amount, "2.00")
    }
    function test_realDocumentsKeepExpenseWhenAttachmentsArrive() {
        var expense = {localId: "a", remoteId: "remote-exp", concept: "Test", amount: "1.00", currencyCode: "PEN", attachments: []}
        app.st = {expenses: [expense], attachments: []}
        var documents = createTemporaryObject(documentsComponent, test)
        verify(documents !== null)
        var before = modeledCard(documents, "a")
        verify(before !== null)
        app.st = {expenses: [expense], attachments: [{id: "file-a", expense_id: "remote-exp", file_name: "Test.pdf"}]}
        wait(30)
        compare(modeledCard(documents, "a"), before)
        compare(before.remoteRows.length, 1)
        app.st = {busy: false, expenses: [expense], attachments: [{id: "file-a", expense_id: "remote-exp", file_name: "Test.pdf"}]}
        wait(30)
        compare(modeledCard(documents, "a"), before)
    }
    function test_hiddenShellRetainsTextureProducer() {
        var shell = createTemporaryObject(shellComponent, test)
        verify(shell !== null)
        var capture = findChild(shell, "renditionBackdropCapture")
        verify(capture !== null)
        var producer = capture.sourceItem
        verify(producer !== null)
        shell.visible = false
        wait(0)
        compare(capture.sourceItem, producer)
        compare(shell.cardCaptureAllowed, false)
    }

    function test_forcingGlassVisibleCannotDrawWithoutTexture() {
        var glass = createTemporaryObject(glassComponent, test)
        verify(glass !== null)
        compare(glass.textureReady, false)
        var shader = findChild(glass, "glassShader")
        verify(shader !== null)
        compare(shader.visible, false)
        compare(shader.enabled, false)
    }
    function test_capturePausesForNavigationMenusAndKeyboard() {
        var shell = createTemporaryObject(shellComponent, test)
        verify(shell !== null)
        tryCompare(shell, "renderCaptureBlocked", false)
        shell.navigationTransitionActive = true
        compare(shell.cardCaptureAllowed, false)
        shell.navigationTransitionActive = false
        shell.dockMenuVisible = true
        compare(shell.cardCaptureAllowed, false)
        shell.dockMenuVisible = false
        flow.imeVisible = true
        compare(shell.cardCaptureAllowed, false)
        flow.imeVisible = false
        tryCompare(shell, "cardCaptureAllowed", true)
        shell.active = false
        compare(shell.cardCaptureAllowed, false)
    }
    function test_realtimeDefersEditsCoalescesAndIgnoresSelf() {
        var shell = createTemporaryObject(shellComponent, test)
        var home = findChild(shell, "renditionsHome")
        verify(home !== null)
        var stack = home.StackView.view
        verify(stack !== null)
        var detail = stack.push(fakeDetailComponent, {}, StackView.Immediate)
        compare(shell.liveRenditionId, "remote-test")
        var channel = createTemporaryObject(channelComponent, test)
        shell.liveChannel = channel
        var baseline = ctl.syncCalls
        detail.expensesTab.editorActive = true
        channel.broadcastReceived("invalidate", {origin: "other"})
        channel.broadcastReceived("invalidate", {origin: "other"})
        wait(250)
        compare(ctl.syncCalls, baseline)
        compare(shell.liveReloadPending, true)
        detail.expensesTab.editorActive = false
        tryCompare(ctl, "syncCalls", baseline + 1)
        compare(shell.liveReloadPending, false)
        channel.broadcastReceived("invalidate", {origin: shell.liveOrigin})
        wait(250)
        compare(ctl.syncCalls, baseline + 1)
        shell.navigationTransitionActive = true
        channel.broadcastReceived("invalidate", {})
        wait(250)
        compare(ctl.syncCalls, baseline + 1)
        shell.navigationTransitionActive = false
        tryCompare(ctl, "syncCalls", baseline + 2)
        detail.expensesTab.editorActive = true
        channel.broadcastReceived("invalidate", {})
        compare(shell.liveReloadPending, true)
        stack.pop()
        tryCompare(shell, "liveRenditionId", "")
        compare(shell.liveReloadPending, false)
        wait(250)
        compare(ctl.syncCalls, baseline + 2)
    }
}
