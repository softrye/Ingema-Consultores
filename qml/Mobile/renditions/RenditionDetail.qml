import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Ficha de una rendición propia: cabecera con estados reales y pestañas de
// Gastos, Finanzas, Documentos y Revisión. La fuente es el estado publicado
// por el bridge para la selección actual (`select`).
Item {
    id: page
    property var app
    property string localId: ""
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property bool selected: String(app.st.selectedLocalId || "") === localId
    readonly property var current: {
        if (selected && app.st.current && app.st.current.localId === localId) return app.st.current
        var rows = app.st.renditions || []
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].localId === localId) return rows[i]
        return ({})
    }
    readonly property bool exists: String(current.localId || "").length > 0
    readonly property bool writable: exists && ctl.canEdit(current)
    readonly property bool syncing: String(current.syncState || "") === "SYNCING"
    readonly property bool conflict: ["CONFLICT", "NEEDS_RECONCILIATION"].indexOf(String(current.syncState || "")) >= 0
    readonly property bool editable: writable && !conflict && !syncing
    readonly property string title: S.text_(current, "visibleCode", "visible_code") || "Borrador"
    property string tab: "expenses"

    function handleBack() { return false }
    Component.onDestruction: if (page.ctl) page.ctl.send("closeDetail", {}, "")

    Column {
        id: top
        x: page.ui.gutter
        y: 4 * page.ui.u
        width: parent.width - 2 * page.ui.gutter
        spacing: 10 * page.ui.u

        Text {
            width: parent.width
            visible: !page.exists
            text: "La rendición ya no está disponible en esta cuenta."
            color: S.danger
            font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
        }
        Flow {
            width: parent.width
            spacing: 8 * page.ui.u
            RBadge { ui: page.ui; label: page.ctl.statusLabel(String(page.current.status || "BORRADOR")); tone: S.statusColor(page.current.status) }
            RBadge {
                ui: page.ui
                label: page.ctl.syncLabel(String(page.current.syncState || "")) + (Number(page.current.pendingCount || 0) > 0 ? " · " + page.current.pendingCount + " pendientes" : "")
                tone: S.syncColor(page.current.syncState)
            }
            RBadge { ui: page.ui; visible: !page.writable && page.exists; label: "Solo lectura"; tone: S.muted }
            RBadge { ui: page.ui; visible: Number(page.current.versionNumber || 0) > 0; label: "Versión " + page.current.versionNumber; tone: S.accentSoft }
        }
        Text {
            width: parent.width
            text: "Período " + S.period(page.current.periodStart, page.current.periodEnd) + " · " + page.ctl.projectLabel(String(page.current.primaryProjectId || ""))
            color: S.muted; wrapMode: Text.WordWrap
            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
        }
        Text {
            width: parent.width
            visible: String(page.current.syncError || "").length > 0
            text: page.ctl.errorText("", String(page.current.syncError || ""))
            color: S.danger; wrapMode: Text.WordWrap
            font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
        }
        Text {
            width: parent.width
            visible: page.conflict
            text: "Hay un conflicto con el servidor. Pulsa «Actualizar» para traer la versión vigente antes de seguir editando; tus cambios locales se conservan."
            color: S.warning; wrapMode: Text.WordWrap
            font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
        }
        Row {
            spacing: 8 * page.ui.u
            RButton {
                ui: page.ui; glyph: 0xE1D0; label: "Editar datos"
                visible: page.writable
                enabledButton: page.editable
                onActivated: page.app.openEditor(page.current)
            }
            RButton {
                ui: page.ui; glyph: 0xE145; label: "Actualizar"
                busy: page.app.busy("refresh")
                onActivated: page.app.refresh()
            }
        }
        Flow {
            width: parent.width
            spacing: 8 * page.ui.u
            Repeater {
                model: [["expenses", "Gastos"], ["financial", "Finanzas"], ["documents", "Documentos"], ["review", "Revisión"]]
                delegate: RChip {
                    required property var modelData
                    ui: page.ui
                    label: modelData[1]
                    selected: page.tab === modelData[0]
                    onActivated: page.tab = modelData[0]
                }
            }
        }
    }

    Item {
        anchors.top: top.bottom
        anchors.topMargin: 10 * page.ui.u
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        RenditionExpenses { objectName: "expensesTab"; anchors.fill: parent; visible: page.tab === "expenses"; detail: page }
        RenditionFinancial { objectName: "financialTab"; anchors.fill: parent; visible: page.tab === "financial"; detail: page }
        RenditionDocuments { objectName: "documentsTab"; anchors.fill: parent; visible: page.tab === "documents"; detail: page }
        RenditionReview { objectName: "reviewTab"; anchors.fill: parent; visible: page.tab === "review"; detail: page }
    }
}
