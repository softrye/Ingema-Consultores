import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Documentos de la rendición: ubicación en InGe Drive, sustentos por gasto
// (copia local durable + objeto privado en el servidor), apertura con URL
// firmada de 60 s (attachmentAccess) y exportaciones PDF/XLSX de la versión
// inmutable (ownerExport). Reutiliza el almacenamiento existente.
Item {
    id: tab
    property var detail
    readonly property var app: detail.app
    readonly property var ui: detail.ui
    readonly property var ctl: detail.ctl
    readonly property var current: detail.current
    readonly property var expenses: detail.selected ? (app.st.expenses || []).filter(function(e) { return e.archived !== true }) : []
    readonly property var remote: detail.selected ? (app.st.attachments || []) : []
    ListModel { id: expenseRows }
    onExpensesChanged: S.syncRows(expenseRows, expenses, ["localId"])
    Component.onCompleted: S.syncRows(expenseRows, expenses, ["localId"])
    readonly property bool exportable: String(current.remoteId || "").length > 0 && String(current.currentVersionId || "").length > 0
                                       && ["BORRADOR", "OBSERVADO"].indexOf(String(current.status || "BORRADOR")) < 0
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    function remoteFor(expense) {
        var id = S.text_(expense, "remoteId")
        return remote.filter(function(a) { return id.length && S.text_(a, "expense_id", "expenseId") === id && !S.text_(a, "archived_at").length })
    }
    function localFor(expense) {
        return (expense.attachments || []).filter(function(a) { return !S.text_(a, "archived_at").length && S.text_(a, "phase") !== "READY" })
    }
    function open(attachmentId) {
        app.call("attachmentAccess", { attachmentId: attachmentId }, "access:" + attachmentId, function(ok, result, code, message) {
            if (!ok) { tab.app.toast(tab.app.errorText(code, message), "error"); return }
            var row = (result.rows || [])[0] || {}
            if (!String(row.signedUrl || "").length) { tab.app.toast("El servidor no devolvió un acceso al sustento.", "error"); return }
            Qt.openUrlExternally(row.signedUrl)
        })
    }
    function archive(attachment) {
        app.confirm("Retirar sustento", "Se archivará «" + S.text_(attachment, "file_name", "fileName") + "» en el servidor. La versión presentada conserva su copia.",
                    "Retirar", true, function() {
            tab.app.call("archiveAttachment", { attachmentId: S.text_(attachment, "id"), rowVersion: Number(attachment.row_version || 0) },
                         "archive:" + S.text_(attachment, "id"), function(ok, result, code, message) {
                tab.app.toast(ok ? "Solicitud enviada; la lista se actualizará al confirmar el servidor." : tab.app.errorText(code, message), ok ? "info" : "error")
            })
        })
    }
    function exportVersion(format) {
        // Exportación híbrida: el destino se elige en el menú 3D Touch.
        tab.app.askExportDestination(format, function(destination) { tab.app.runExport(format, destination) })
    }

    // ---- Rediseño aprobado: avance neutro, una tarjeta por gasto con
    // miniaturas, «+ Adjuntar», hoja Abrir/Retirar y Drive + Exportar al final.
    readonly property int withSupport: expenses.filter(function(e) { return remoteFor(e).length + localFor(e).length > 0 }).length
    property var sheetFile: null
    property bool sheetRemote: false
    function fileName(row) { return S.text_(row, "file_name", "fileName") || "Sustento" }
    function isPdf(row) { return /\.pdf$/i.test(fileName(row)) }

    component FileTile: Rectangle {
        id: fileTile
        property var row
        property bool remoteFile: false
        width: 72 * tab.ui.u; height: 84 * tab.ui.u; radius: 14 * tab.ui.u
        color: tileTap.pressed ? S.tintSoft : S.surfaceStrong
        border.width: 1; border.color: S.tintSoftBorder
        Column {
            anchors.centerIn: parent
            spacing: 6 * tab.ui.u
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 38 * tab.ui.u; height: 44 * tab.ui.u
                visible: tab.isPdf(fileTile.row)
                Rectangle { anchors.fill: parent; radius: 5 * tab.ui.u; color: "#E2231A" }
                Rectangle { anchors.right: parent.right; width: 13 * tab.ui.u; height: width; color: "#F7A29D" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * tab.ui.u
                       text: "PDF"; color: "white"; font.family: tab.ui.fontFamily; font.pixelSize: 11 * tab.ui.u; font.weight: Font.ExtraBold }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 36 * tab.ui.u; height: width; radius: 10 * tab.ui.u; color: S.accent
                visible: !tab.isPdf(fileTile.row)
                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0F6); color: "white"
                       font.family: tab.ui.iconFamily; font.pixelSize: 20 * tab.ui.u }
            }
            Text { width: 62 * tab.ui.u; horizontalAlignment: Text.AlignHCenter; text: tab.fileName(fileTile.row); elide: Text.ElideMiddle
                   color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 11 * tab.ui.u }
        }
        MouseArea { id: tileTap; anchors.fill: parent
                    onClicked: { tab.sheetFile = fileTile.row; tab.sheetRemote = fileTile.remoteFile; fileSheet.open() } }
        Accessible.role: Accessible.Button
        Accessible.name: "Archivo " + tab.fileName(row)
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 140 * tab.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: column
            x: tab.ui.gutter
            width: parent.width - 2 * tab.ui.gutter
            spacing: 12 * tab.ui.u

            Item {
                width: parent.width; height: 26 * tab.ui.u
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Sustentos"; color: S.text
                       font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.Bold }
                Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; color: S.muted
                       text: tab.withSupport + " de " + tab.expenses.length + " gastos con sustento"
                       font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u }
            }
            Rectangle {
                width: parent.width; height: 6 * tab.ui.u; radius: height / 2; color: S.ink(0.08)
                Rectangle { height: parent.height; radius: parent.radius; color: S.accent
                            width: parent.width * tab.withSupport / Math.max(1, tab.expenses.length)
                            Behavior on width { NumberAnimation { duration: 240 } } }
            }
            Repeater {
                model: expenseRows
                delegate: RCard {
                    id: expenseCard
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
                    readonly property var remoteRows: tab.remoteFor(modelData)
                    readonly property var localRows: tab.localFor(modelData)
                    ListModel { id: remoteFiles }
                    ListModel { id: localFiles }
                    onRemoteRowsChanged: S.syncRows(remoteFiles, remoteRows, ["id"])
                    onLocalRowsChanged: S.syncRows(localFiles, localRows, ["localId"])
                    Component.onCompleted: {
                        S.syncRows(remoteFiles, remoteRows, ["id"])
                        S.syncRows(localFiles, localRows, ["localId"])
                    }
                    width: column.width
                    ui: tab.ui
                    color: S.glass(0.80); border.color: S.edge(1); radius: 22 * tab.ui.u
                    Item {
                        width: parent.width; height: 40 * tab.ui.u
                        Rectangle { width: 40 * tab.ui.u; height: width; radius: 12 * tab.ui.u; color: S.tintSoft
                                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0CC); color: S.accent
                                           font.family: tab.ui.iconFamily; font.pixelSize: 21 * tab.ui.u } }
                        Column {
                            x: 52 * tab.ui.u; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - amountText.width - 10 * tab.ui.u
                            Text { width: parent.width; text: S.text_(expenseCard.modelData, "concept") || "Gasto"; elide: Text.ElideRight
                                   color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                            Text { width: parent.width; elide: Text.ElideRight; color: S.muted
                                   text: S.date(S.text_(expenseCard.modelData, "expenseDate", "expense_date"))
                                   font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u }
                        }
                        Text { id: amountText; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                               text: tab.ctl.formatMoney(expenseCard.modelData.amount, S.text_(expenseCard.modelData, "currencyCode", "currency_code"))
                               color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                    }
                    Flow {
                        width: parent.width; spacing: 8 * tab.ui.u
                        Repeater { model: remoteFiles
                                   delegate: FileTile { required property string rowJson; row: JSON.parse(rowJson); remoteFile: true } }
                        Repeater { model: localFiles
                                   delegate: FileTile { required property string rowJson; row: JSON.parse(rowJson); remoteFile: false } }
                        Rectangle {
                            visible: tab.detail.writable
                            width: 72 * tab.ui.u; height: 84 * tab.ui.u; radius: 14 * tab.ui.u
                            color: addTap.pressed ? S.tintSoft : "transparent"
                            border.width: 1.5; border.color: "#AEB8C8"
                            opacity: tab.detail.editable ? 1 : 0.5
                            Column {
                                anchors.centerIn: parent; spacing: 4 * tab.ui.u
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(0xE13D); color: S.accent
                                       font.family: tab.ui.iconFamily; font.pixelSize: 22 * tab.ui.u }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Adjuntar"; color: S.accent
                                       font.family: tab.ui.fontFamily; font.pixelSize: 11.5 * tab.ui.u; font.weight: Font.DemiBold }
                            }
                            MouseArea { id: addTap; anchors.fill: parent; enabled: tab.detail.editable
                                        onClicked: tab.app.openExpense(tab.detail.localId, String(expenseCard.modelData.localId)) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Adjuntar comprobante"
                        }
                    }
                }
            }

            // Drive + exportación: una sola tarjeta al final (se usan menos).
            RCard {
                width: parent.width
                ui: tab.ui
                color: S.glass(0.80); border.color: S.edge(1); radius: 22 * tab.ui.u
                Item {
                    width: parent.width; height: 44 * tab.ui.u
                    Rectangle { width: 40 * tab.ui.u; height: width; radius: 12 * tab.ui.u; color: S.tintSoft
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0D7); color: S.accent
                                       font.family: tab.ui.iconFamily; font.pixelSize: 21 * tab.ui.u } }
                    Column {
                        x: 52 * tab.ui.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x
                        Text { text: "InGe Drive"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                        Text { width: parent.width; elide: Text.ElideRight; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u
                               text: String(tab.current.documentParentNodeId || "").length
                                     ? (S.text_(tab.current, "documentParentNodeName", "folderName") || "Proyecto principal")
                                       + (String(tab.current.documentNodeId || "").length ? " · expediente creado" : " · se crea al sincronizar")
                                     : "Sin carpeta: elígela en los datos de la rendición" }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: S.tintSoftBorder }
                Item {
                    width: parent.width; height: 44 * tab.ui.u
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - exportActions.width - 10 * tab.ui.u
                        Text { text: "Exportar"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                        Text { width: parent.width; elide: Text.ElideRight; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u
                               text: tab.exportable ? "Versión " + (tab.current.versionNumber || "") + " presentada" : "Se habilita al presentar la rendición" }
                    }
                    Row {
                        id: exportActions
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6 * tab.ui.u
                        RButton { visible: tab.exportable; ui: tab.ui; width: 64 * tab.ui.u; label: "PDF"; primary: true
                                  busy: tab.app.busy("export:pdf"); onActivated: tab.exportVersion("pdf") }
                        RButton { visible: tab.exportable; ui: tab.ui; width: 70 * tab.ui.u; label: "Excel"; color: S.tintSoft
                                  busy: tab.app.busy("export:xlsx"); onActivated: tab.exportVersion("xlsx") }
                        Rectangle { visible: !tab.exportable; width: pdfXls.implicitWidth + 24 * tab.ui.u; height: 32 * tab.ui.u; radius: height / 2; color: S.ink(0.06)
                                    Text { id: pdfXls; anchors.centerIn: parent; text: "PDF · Excel"; color: S.muted
                                           font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u; font.weight: Font.DemiBold } }
                    }
                }
            }
        }
    }

    // Hoja del archivo: Abrir como acción principal; Retirar aparte.
    Popup {
        id: fileSheet
        objectName: "documentFileSheet"
        parent: Overlay.overlay
        modal: true; dim: true; focus: true
        width: parent ? Math.min(parent.width - 24 * tab.ui.u, 520 * tab.ui.u) : 0
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? parent.height - height - tab.ui.dockArea - 12 * tab.ui.u : 0
        padding: 16 * tab.ui.u
        background: Rectangle { radius: 24 * tab.ui.u; color: S.popup; border.width: 1; border.color: S.edge(1) }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: tab.ui.reducedMotion ? 0 : 180 }
                            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: tab.ui.reducedMotion ? 0 : 240; easing.type: Easing.OutBack } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: tab.ui.reducedMotion ? 0 : 140 } }
        contentItem: Column {
            spacing: 10 * tab.ui.u
            Text { width: parent.width; text: tab.sheetFile ? tab.fileName(tab.sheetFile) : ""; elide: Text.ElideMiddle
                   color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
            Text { width: parent.width; visible: !tab.sheetRemote; wrapMode: Text.WordWrap; color: S.muted
                   text: tab.sheetFile ? tab.ctl.syncLabel(tab.app.syncState(tab.sheetFile)) : ""
                   font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u }
            RButton { width: parent.width; height: 50 * tab.ui.u; ui: tab.ui; primary: true; label: "Abrir"
                      visible: tab.sheetRemote
                      busy: tab.sheetFile ? tab.app.busy("access:" + S.text_(tab.sheetFile, "id")) : false
                      onActivated: { var id = S.text_(tab.sheetFile, "id"); fileSheet.close(); tab.open(id) } }
            RButton { width: parent.width; ui: tab.ui; danger: true; label: "Retirar archivo"; color: "transparent"
                      visible: tab.sheetRemote && tab.detail.writable
                      enabledButton: tab.detail.editable
                      onActivated: { var row = tab.sheetFile; fileSheet.close(); tab.archive(row) } }
            RButton { width: parent.width; ui: tab.ui; label: "Cerrar"; color: S.ink(0.06); onActivated: fileSheet.close() }
        }
    }
}
