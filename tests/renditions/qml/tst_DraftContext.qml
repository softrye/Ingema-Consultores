import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml/Mobile/renditions" as Renditions

Item {
    id: scene
    width: 420
    height: 850
    QtObject {
        id: fakeApp
        property var ui: ({ u: 1, gutter: 14, dockArea: 100, topInset: 0, reducedMotion: true, fontFamily: "Arial", iconFamily: "Arial" })
        property var flow: null
        property var dockAnchor: dock
        property bool modalOpen: false
        property var continued: []
        property var commands: []
        property var confirmation: null
        property var dockRequests: []
        property string phase: "IDLE"
        property var st: ({ expenses: [], workingRows: [], editorDrafts: {}, current: {}, selectedLocalId: "rendition" })
        property var ctl: ({
            totals: function(rows) { return { penCents: 0, usdCents: 0, count: rows.length } },
            fundBalance: function() { return { penCents: 0, usdCents: 0 } },
            formatCents: function() { return "0.00" },
            formatMoney: function(amount) { return "S/ " + amount },
            amountError: function() { return "" },
            visibleSyncError: function(s) { return s },
            canEdit: function() { return true },
            catalog: function() { return [] },
            newId: function() { return "synthetic" },
            today: function() { return "2026-10-24" },
            syncLabel: function() { return "Sincronizado" },
            completion: function() { return {known:false} },
            project: function() { return {} },
            projectLabel: function(id) { return id },
            statusLabel: function() { return "Borrador" },
            send: function() {},
            fundingError: function() { return "" },
            rateError: function() { return "" }
        })
        function busy(key) { return false }
        function syncState(row) { return "SYNCED" }
        function dockCommand(command) { dockRequests = dockRequests.concat([command]) }
        function closeMenus() {}
        function openExpense(rendition, expense, working) { continued = [rendition, expense, working] }
        function call(operation, args, key, callback) { commands = commands.concat([{ operation: operation, args: args, callback: callback }]); return "synthetic" }
        function confirm(title, message, label, destructive, callback) { confirmation = callback }
    }
    QtObject {
        id: fakeDetail
        property var app: fakeApp
        property var ui: fakeApp.ui
        property var ctl: fakeApp.ctl
        property string localId: "rendition"
        property bool selected: true
        property bool writable: true
        property bool expensesKnown: true
        property var balance: ({})
        property var rate: ({})
        property var current: ({})
        property real pullThreshold: 80
    }
    Renditions.RenditionExpenses { id: screen; anchors.fill: parent; detail: fakeDetail }
    Component { id: detailComponent; Renditions.RenditionDetail { app: fakeApp; localId: "rendition" } }
    Item {
        id: dock
        y: 750; width: parent.width; height: 80
        property int activations: 0
        MouseArea { anchors.fill: parent; onClicked: dock.activations++ }
    }
    TestCase {
        id: tests
        name: "DraftContextDesktop"
        when: windowShown
        function row(id) {
            return { id: id, syncState: "SYNCED", inCloud: true, form: {
                concept: "Borrador " + id, amount: "25.00", beneficiary: "Proveedor", expenseDate: "2026-10-24"
            }, sources: [{ name: "receipt" }] }
        }
        function init() {
            scene.width = 420; scene.height = 850; dock.y = 750
            screen.visible = true; screen.query = ""; screen.sortBy = "date"
            fakeDetail.writable = true
            dock.activations = 0
            fakeApp.continued = []; fakeApp.commands = []; fakeApp.confirmation = null
            fakeApp.dockRequests = []
            fakeApp.st = { expenses: [], workingRows: [row("a"), row("b"), row("c")], editorDrafts: {}, current: {}, selectedLocalId: "rendition" }
            wait(30)
        }
        function menu() { return findChild(scene, "draftContextMenu") }
        function popup() { return findChild(scene, "draftContextPopup") }
        function card(id) { return findChild(screen, "draft:" + id) }
        function labeled(item, label) {
            if (item.label !== undefined && item.label === label && item.visible) return item
            for (var child of item.children) {
                var found = labeled(child, label)
                if (found) return found
            }
            return null
        }
        function visibleTexts(item) {
            if (!item.visible) return []
            var result = item.text !== undefined ? [String(item.text)] : []
            for (var child of item.children) result = result.concat(visibleTexts(child))
            return result
        }
        function cleanup() { screen.handleBack(); screen.finishEditor(); wait(250) }
        function test_modalSectionsSyncAndSafeClose() {
            var row = {localId:"edit", rowVersion:4, concept:"Original", amount:"12.80", currencyCode:"PEN", expenseDate:"2026-10-13"}
            fakeApp.st = {expenses:[row], workingRows:[], editorDrafts:{}, selectedLocalId:"rendition", current:{}}
            wait(30)
            var card = findChild(screen,"expense:edit")
            var heightBefore = card.height
            mouseClick(card,15,15)
            wait(200)
            var popup = findChild(scene,"expenseEditorPopup")
            var form = findChild(screen,"expandedExpenseForm")
            verify(popup.visible && popup.modal)
            compare(card.height,heightBefore,"the form does not expand the list")
            var concept = findChild(form,"quickConceptInput")
            concept.text = "Cambios locales"; form.changed()
            for (var section of [1,2,3,0]) {
                var button=findChild(screen,"expenseEditorTabs").children.filter(function(c){return c.objectName==="expenseEditorSection:"+section})[0]
                verify(button!==undefined,"section selector exists")
                mouseClick(button)
                compare(form.section,section)
                compare(form.values().concept,"Cambios locales")
                compare(findChild(screen,"expandedExpenseForm"),form)
            }
            fakeApp.st = {expenses:[{localId:"edit",rowVersion:11,concept:"Servidor",amount:"13.00",currencyCode:"PEN"}],
                workingRows:[],editorDrafts:{},selectedLocalId:"rendition",current:{}}
            wait(30)
            compare(form.values().concept,"Cambios locales")
            compare(form.baseRowVersion,4,"keep the originally opened CAS version")
            verify(popup.x>=0 && popup.y>=0)
            verify(popup.y+popup.height<=scene.height-fakeApp.ui.dockArea)
            var scroll = findChild(screen,"expenseEditorScroll")
            verify(scroll.height>0 && scroll.contentHeight>scroll.height)
            form.saving=true
            screen.handleBack()
            verify(popup.visible && fakeApp.confirmation===null)
            form.saving=false
            screen.handleBack()
            verify(fakeApp.confirmation!==null && popup.visible)
            fakeApp.confirmation()
            var command=fakeApp.commands[fakeApp.commands.length-1]
            compare(command.operation,"saveEditorDraft")
            verify(popup.visible,"wait for the local copy acknowledgement")
            command.callback(true)
            tryCompare(popup,"visible",false)
        }
        function test_tabHideWaitsForLocalCheckpoint() {
            var row = {localId:"hide-test", rowVersion:2, concept:"Taxi", amount:"12.80",
                       currencyCode:"PEN", expenseDate:"2026-10-13"}
            fakeApp.st = {expenses:[row], workingRows:[], editorDrafts:{},
                          selectedLocalId:"rendition", current:{}}
            wait(30)
            mouseClick(findChild(screen,"expense:hide-test"),15,15)
            var popup = findChild(scene,"expenseEditorPopup")
            var form = findChild(screen,"expandedExpenseForm")
            verify(popup.visible)
            var concept = findChild(form,"quickConceptInput")
            concept.text = "Taxi editado"
            form.changed()
            fakeApp.commands=[]
            screen.visible=false
            var writes=fakeApp.commands.filter(function(c){return c.operation==="saveEditorDraft"})
            verify(writes.length>0,"hiding a tab saves a local checkpoint first")
            verify(popup.visible,"modal remains open until the checkpoint is acknowledged")
            writes[writes.length-1].callback(true)
            tryCompare(popup,"visible",false)
            compare(screen.expandedId,"")
        }
        function test_modalAttachmentsAndSectionVisibility() {
            var row = {localId:"attachment-test", rowVersion:3, concept:"Taxi", amount:"12.80",
                       currencyCode:"PEN", expenseDate:"2026-10-13"}
            fakeApp.st = {expenses:[row], workingRows:[], editorDrafts:{},
                          selectedLocalId:"rendition", current:{}}
            wait(30)
            mouseClick(findChild(screen,"expense:attachment-test"),15,15)
            var popup = findChild(scene,"expenseEditorPopup")
            var form = findChild(screen,"expandedExpenseForm")
            var attachments = findChild(form,"expenseEditorAttachments")
            verify(popup.visible)
            form.selectSection(3)                       // Sustentos vive en su propia sección
            verify(attachments !== null && attachments.visible)
            var oldDescribe = fakeApp.ctl.describeLocalFile
            fakeApp.ctl.describeLocalFile = function(url) {
                return {localUri:String(url), fileName:"taxi.jpg",
                        sizeBytes:2048, mimeType:"image/jpeg"}
            }
            form.addFile("file:///synthetic/taxi.jpg")
            compare(form.pending.length,1)
            compare(form.files.length,1)
            compare(form.files[0].kind,"pending")
            form.selectSection(2)
            verify(!attachments.visible,"payment tab does not repeat attachments")
            form.selectSection(3)
            verify(attachments.visible,"attachments are accessible from Sustentos")
            compare(form.files[0].name,"taxi.jpg")
            form.removeFile(form.files[0])
            compare(form.pending.length,0)
            fakeApp.ctl.describeLocalFile = oldDescribe
            var remote = {kind:"remote",id:"remote-file",name:"invoice.pdf",uri:"",data:{row_version:1}}
            form.viewFile(remote)
            var cmd=fakeApp.commands[fakeApp.commands.length-1]
            compare(cmd.operation,"attachmentAccess")
            compare(cmd.args.attachmentId,"remote-file")
        }
        function test_realDetailHeaderAndSections() {
            screen.visible = false
            scene.width = 360
            fakeApp.st = {expenses:[], workingRows:[], editorDrafts:{}, selectedLocalId:"rendition", current:{
                localId:"rendition", displayName:"JENNIFER", clientName:"BCP", location:"AREQUIPA", expensesLoaded:true
            }}
            var detail = createTemporaryObject(detailComponent, scene, {width:scene.width, height:scene.height})
            verify(detail !== null)
            var texts = visibleTexts(detail).join("|")
            verify(texts.indexOf("JENNIFER") >= 0)
            verify(texts.indexOf("Cliente: BCP") >= 0 && texts.indexOf("Ubicación: AREQUIPA") >= 0)
            for (var section of ["financial", "documents", "review", "expenses"]) {
                var button = findChild(detail, "renditionSection:" + section)
                verify(button !== null)
                mouseClick(button)
                compare(detail.tab, section)
                verify(button.selected)
            }
            // La cabecera ya no tiene botones (Documentos en la barra, Información en el Dock).
            verify(findChild(detail, "renditionHeaderAction:documents") === null)
            verify(findChild(detail, "renditionHeaderAction:info") === null)
        }
        function test_registeredLayoutAndPersistentExpansion() {
            fakeApp.st = { expenses: [
                {localId:"one", expenseDate:"2026-10-01", concept:"Primero", amount:"10.00", currencyCode:"PEN"},
                {localId:"two", expenseDate:"2026-10-24", concept:"Concepto largo de transporte y alimentación", amount:"1234567.89", currencyCode:"USD"}
            ], workingRows: [], editorDrafts: {}, current: {}, selectedLocalId: "rendition" }
            wait(30)
            var container = findChild(screen, "expenseSummaryContainer")
            verify(container !== null, "one outer financial container")
            var grid = findChild(container, "expenseSummary")
            var boxes = grid.children.filter(function(child) { return child.kind === "metrics" })
            compare(boxes.length, 4)
            verify(boxes[0].x < boxes[1].x && boxes[0].y === boxes[1].y)
            verify(boxes[2].y > boxes[0].y && boxes[2].x === boxes[0].x)
            compare(screen.visibleExpenses[0].localId, "two")
            verify(findChild(screen, "expenseFilterControl") !== null)
            mouseClick(findChild(screen, "expenseFilterControl"))
            verify(findChild(screen, "expenseSortMenu").open)   // un solo icono: ordenar + buscar
            findChild(screen, "expenseSortMenu").close()
            screen.sortBy = "concept"
            compare(screen.visibleExpenses[0].localId, "two")
            screen.query = "Primero"
            compare(screen.visibleExpenses.length, 1)
            compare(screen.visibleExpenses[0].localId, "one")
            screen.query = ""; screen.sortBy = "date"
            wait(30) // Column repositions the delegates after the filter is removed.
            var persistentForm = findChild(screen, "expandedExpenseForm")
            var expense = findChild(screen, "expense:two")
            verify(expense !== null)
            mouseClick(expense, 15, 15)
            compare(screen.expandedId, "two")
            verify(findChild(scene, "expenseEditorPopup").visible, "registered cards open the large modal editor")
            compare(findChild(screen, "expandedExpenseForm"), persistentForm)
            expense = findChild(screen, "expense:two")
            scene.width = 320
            wait(30)
            verify(findChild(expense, "expenseAmount").width > 0)
            verify(expense.width <= scene.width)
            screen.expandedId = ""
        }
        function test_fullCardAndSingleWidth() {
            verify(card("c").width > card("a").width * 1.9)
            for (var id of ["a", "b", "c"]) {
                var box = card(id)
                mouseClick(box, box.width - 3, box.height - 3)
                tryCompare(menu(), "open", true)
                compare(screen.selectedDraftId, id)
                verify(popup().modal)
                mouseClick(menu(), 3, 3)
                tryCompare(popup(), "visible", false)
            }
        }
        function test_longPressAndBack() {
            // Mismo gesto del Home: pulsación larga = modo edición de cajas + opciones.
            var box = card("a")
            mousePress(box, 20, 20)
            wait(900)
            mouseRelease(box, 20, 20)
            verify(findChild(screen, "boxEditMenu").open)    // Deep Press: menú 3D Touch
            compare(screen.selectedDraftId, "a")
            verify(findChild(screen, "tileDraftAction:Registrar") !== null)
            verify(screen.handleBack())                  // cierra el menú
            verify(!findChild(screen, "boxEditMenu").open)
        }
        function test_boxEditingSizeIconAndOrder() {
            screen.enterEdit(null)
            screen.setCfg("metrics", "pen", "presentation", "icon")
            wait(30)
            var grid = findChild(screen, "expenseSummary")
            var tiles = grid.children.filter(function(child) { return child.kind === "metrics" })
            var pen = tiles.filter(function(t) { return t.key === "pen" })[0]
            verify(pen.width < tiles.filter(function(t) { return t.key === "usd" })[0].width, "icon presentation is smaller")
            screen.setCfg("metrics", "usd", "size", "wide")
            wait(30)
            compare(tiles.filter(function(t) { return t.key === "usd" })[0].width, grid.width)
            var first = screen.layout.metrics.order[0]
            var other = tiles.filter(function(t) { return t.key === screen.layout.metrics.order[1] })[0]
            var moving = tiles.filter(function(t) { return t.key === first })[0]
            screen.dragKey = "metrics:" + first
            screen.dragOver(moving, Qt.point(other.x + 2, other.y + 2))
            screen.endDrag()
            compare(screen.layout.metrics.order[1], first, "drag reorders and persists")
            screen.exitEdit()
        }
        function test_cleanCardAndContentTouch() {
            var texts = visibleTexts(card("a")).join("|")
            verify(texts.indexOf("Borrador a") >= 0)
            verify(texts.indexOf("Proveedor") >= 0)
            for (var redundant of ["En la nube", "Borrador en la nube", "sustento", "Continuar", "Registrar", "Descartar", "···"])
                verify(texts.indexOf(redundant) < 0, redundant)
            compare(fakeApp.st.workingRows[0].sources.length, 1)
            for (var point of [[30, 30], [130, 30], [40, 80], [40, 125]]) {
                mouseClick(card("a"), point[0], point[1])
                tryCompare(menu(), "open", true)
                verify(screen.handleBack())
                tryCompare(popup(), "visible", false)
            }
        }
        function test_modalBlocksDockAndEscape() {
            mouseClick(card("a"), 30, 30)
            wait(250)
            mouseClick(dock, 10, 10)
            compare(dock.activations, 0)
            tryCompare(popup(), "visible", false)
            mouseClick(dock, 10, 10)
            compare(dock.activations, 1)
            mouseClick(card("a"), 30, 30)
            wait(250)
            keyClick(Qt.Key_Escape)
            tryCompare(popup(), "visible", false)
        }
        function test_conflictKeepsSpecialActions() {
            var conflict = row("conflict"); conflict.syncState = "CONFLICT"
            fakeApp.st = { expenses: [], workingRows: [conflict], editorDrafts: {}, current: {}, selectedLocalId: "rendition" }
            wait(30)
            var inspect = labeled(card("conflict"), "Revisar versión del servidor")
            verify(inspect !== null)
            mouseClick(inspect)
            compare(fakeApp.commands[0].operation, "workingInspect")
            verify(!menu().open)
            mouseClick(card("conflict"), 2, 2)
            wait(250)
            for (var action of ["Continuar", "Registrar", "Descartar"])
                verify(!findChild(menu(), "draftAction:" + action).enabledButton)
        }
        function test_actionsAndConfirmation() {
            mouseClick(card("b"), 40, 70)
            tryCompare(menu(), "open", true)
            wait(250)
            mouseClick(findChild(menu(), "draftAction:Continuar"))
            compare(fakeApp.continued.join(","), "rendition,,b")
            tryCompare(popup(), "visible", false)
            mouseClick(card("c"), 40, 70)
            wait(250)
            mouseClick(findChild(menu(), "draftAction:Registrar"))
            compare(fakeApp.commands[0].operation, "promoteWorking")
            compare(fakeApp.commands[0].args.workingId, "c")
            tryCompare(popup(), "visible", false)
            mouseClick(card("a"), 40, 70)
            wait(250)
            mouseClick(findChild(menu(), "draftAction:Descartar"))
            verify(fakeApp.confirmation !== null)
            compare(fakeApp.commands.length, 1, "discard waits for confirmation")
            fakeApp.confirmation()
            compare(fakeApp.commands[1].operation, "archiveWorking")
            compare(fakeApp.commands[1].args.workingId, "a")
        }
        function test_boundsAndDisabled() {
            fakeDetail.writable = false
            mouseClick(card("a"), 2, 2)
            wait(250)
            var action = findChild(menu(), "draftAction:Registrar")
            verify(!action.enabledButton)
            mouseClick(action)
            compare(fakeApp.commands.length, 0)
            verify(menu().open)
            var glass = action.parent.parent
            verify(glass.x >= menu().margin)
            verify(glass.x + glass.width <= menu().width - menu().margin + 0.01)
            verify(glass.y >= menu().margin)
            verify(glass.y + glass.height < dock.y)
            screen.handleBack()
            tryCompare(popup(), "visible", false)
            scene.width = 320; scene.height = 480; dock.y = 380
            screen.openDraftMenu(fakeApp.st.workingRows[0], scene, 318, 478)
            wait(250)
            verify(glass.x + glass.width <= menu().width - menu().margin + 0.01)
            verify(glass.y >= menu().margin)
            verify(glass.y + glass.height < dock.y)
        }
    }
}
