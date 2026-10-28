import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Estado, presentación, versiones inmutables, observaciones y acciones de
// revisión. Las acciones dependen del contexto efectivo del servidor
// (get_rendition_review_context_v03); un botón sólo se habilita si el
// servidor concede esa transición.
Item {
    id: tab
    property var detail
    readonly property var app: detail.app
    readonly property var ui: detail.ui
    readonly property var ctl: detail.ctl
    readonly property var current: detail.current
    readonly property string remoteId: String(current.remoteId || "")
    readonly property var versions: detail.selected ? (app.st.versions || []) : []
    readonly property var observed: (detail.selected ? (app.st.expenses || []) : []).filter(function(e) {
        return e.archived !== true && (S.text_(e, "reviewStatus", "review_status").toUpperCase() === "OBSERVADO"
                                       || S.text_(e, "reviewComment", "review_comment").length > 0)
    })
    readonly property int expenseCount: (detail.selected ? (app.st.expenses || []) : []).filter(function(e) { return e.archived !== true }).length
    readonly property int pending: Number(current.pendingCount || 0)
    readonly property string presentBlocker: !detail.writable ? "La rendición no tiene permiso efectivo de edición."
        : detail.conflict ? "Resuelve el conflicto de sincronización antes de presentar."
        // Paridad con el servidor (rendition_working_snapshot_guard_v01).
        : Number(detail.current.workingCount || 0) > 0 ? "Hay " + Number(detail.current.workingCount)
              + " borrador(es) de gasto sin terminar. Regístralos o descártalos antes de presentar."
        : !remoteId.length ? "Sincroniza la rendición con el servidor antes de presentarla."
        : pending > 0 ? "Hay " + pending + " cambios pendientes de sincronizar. Sincroniza antes de presentar."
        : expenseCount === 0 ? "Agrega al menos un gasto."
        : app.phase !== "IDLE" ? "Espera a que termine la sincronización en curso."
        : ""

    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    // Deslizar hacia abajo actualiza (mismo gesto que Gastos).
    readonly property real pull: Math.max(0, reviewFlick.originY - reviewFlick.contentY)
    readonly property string status: S.text_(current, "status").toUpperCase()
    readonly property int stepIndex: status.indexOf("APROB") >= 0 ? 3 : status.indexOf("OBSERV") >= 0 ? 2
                                   : status.indexOf("REVIS") >= 0 || status.indexOf("PRESENT") >= 0 ? 1 : 0
    readonly property string statusLabel: {
        // Etiqueta única del controlador (con tildes: «En revisión»).
        var t = app.ctl ? app.ctl.statusLabel(status.length ? status : "BORRADOR") : (status || "Borrador")
        return t + (stepIndex === 0 && detail.writable ? " · edición autorizada" : "")
    }
    // Actualizar = sincronización silenciosa + contexto de revisión del servidor.
    function refresh() {
        tab.detail.refreshFromPull()
        reviewPanel.loadContext()
    }
    function present() {
        app.confirm("Presentar rendición",
                    "Se guardará una versión inmutable con sus gastos, fondo y tipo de cambio, y pasará a revisión. Después sólo podrás editarla si administración la observa.",
                    "Presentar", false, function() {
            tab.app.call("present", {}, "present", function(ok, result, code, message) {
                // Clave fija: un intento fallido anterior se retira al presentar con éxito
                // (antes el aviso quedaba y el fondo seguía en rojo).
                if (!ok) { tab.app.reportProblem(tab.app.errorText(code, message), "", "present:" + tab.detail.localId); return }
                if (tab.app.ctl) tab.app.ctl.resolveIssue("present:" + tab.detail.localId)
                tab.app.toast("Rendición presentada y confirmada por el servidor.", "success")
            })
        })
    }

    Flickable {
        id: reviewFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 140 * tab.ui.u
        boundsBehavior: Flickable.DragOverBounds
        onDraggingChanged: if (!dragging && tab.pull >= tab.detail.pullThreshold) tab.refresh()
        clip: true
        Column {
            id: column
            x: tab.ui.gutter
            width: parent.width - 2 * tab.ui.gutter
            spacing: 12 * tab.ui.u

            // ------------------------------------------------ Estado (rediseño aprobado)
            RCard {
                objectName: "reviewStateCard"
                width: parent.width
                ui: tab.ui
                color: S.glass(0.80)
                border.color: S.edge(1)
                radius: 24 * tab.ui.u
                Item {
                    width: parent.width; height: Math.max(stateText.implicitHeight, 44 * tab.ui.u)
                    Column {
                        id: stateText
                        width: parent.width - 56 * tab.ui.u
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * tab.ui.u
                        Text { text: "Estado"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u; font.weight: Font.DemiBold }
                        Text { width: parent.width; text: tab.statusLabel; wrapMode: Text.WordWrap; color: S.text
                               font.family: tab.ui.fontFamily; font.pixelSize: 22 * tab.ui.u; font.weight: Font.ExtraBold }
                    }
                    RButton {
                        objectName: "reviewRefresh"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 44 * tab.ui.u; height: width; radius: width / 2
                        ui: tab.ui; glyph: 0xE145; color: S.tintSoft
                        busy: tab.app.busy("sync")
                        Accessible.name: "Actualizar revisión"
                        onActivated: tab.refresh()
                    }
                }
                Row {
                    id: steps
                    width: parent.width; spacing: 4 * tab.ui.u
                    Repeater {
                        model: ["Borrador", "En revisión", "Observada", "Aprobada"]
                        delegate: Column {
                            id: step
                            required property string modelData
                            required property int index
                            width: (steps.width - 3 * steps.spacing) / 4; spacing: 6 * tab.ui.u
                            Rectangle { width: step.width; height: 6 * tab.ui.u; radius: height / 2
                                        color: step.index <= tab.stepIndex && !(step.index === 2 && tab.stepIndex === 3) ? S.accent : S.ink(0.10)
                                        Behavior on color { ColorAnimation { duration: 300 } } }
                            Text { width: step.width; text: step.modelData; elide: Text.ElideRight; color: S.text
                                   font.family: tab.ui.fontFamily; font.pixelSize: 11.5 * tab.ui.u; font.weight: Font.DemiBold }
                        }
                    }
                }
                RButton {
                    width: parent.width; height: 54 * tab.ui.u; radius: 16 * tab.ui.u
                    visible: tab.detail.writable
                    ui: tab.ui; primary: true; glyph: 0xE152; label: "Presentar rendición"
                    enabledButton: tab.presentBlocker.length === 0
                    busy: tab.app.busy("present") || tab.app.phase === "PRESENTING"
                    onActivated: tab.present()
                }
                Text {
                    width: parent.width
                    visible: tab.detail.writable && tab.presentBlocker.length > 0
                    text: tab.presentBlocker
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                }
            }

            ReviewPanel {
                id: reviewPanel
                width: parent.width
                app: tab.app
                remoteId: tab.remoteId
                active: tab.visible
            }

            // -------------------------------------------------- Observaciones
            Item { width: parent.width; height: 32 * tab.ui.u
                   Text { anchors.verticalCenter: parent.verticalCenter; text: "Gastos observados"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                   Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Math.max(28 * tab.ui.u, obsCount.implicitWidth + 16 * tab.ui.u); height: 28 * tab.ui.u; radius: height / 2; color: S.ink(0.06)
                               Text { id: obsCount; anchors.centerIn: parent; text: tab.observed.length; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u; font.weight: Font.Bold } } }
            Text {
                width: parent.width
                visible: false                       // el contador «0» ya lo indica
                text: "No hay observaciones sobre los gastos."
                color: S.muted
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }
            Repeater {
                model: tab.observed
                delegate: RCard {
                    required property var modelData
                    width: column.width
                    ui: tab.ui
                    clickable: true
                    onActivated: tab.app.openExpense(tab.detail.localId, String(modelData.localId))
                    Text {
                        width: parent.width
                        text: (S.text_(modelData, "concept") || "Gasto") + " · " + tab.ctl.formatMoney(modelData.amount, S.text_(modelData, "currencyCode", "currency_code"))
                        color: S.text; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u
                    }
                    Text {
                        width: parent.width
                        text: S.text_(modelData, "reviewComment", "review_comment") || "Observado por administración."
                        color: S.warning; wrapMode: Text.WordWrap
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                }
            }

            // ------------------------------------------------------ Versiones
            Item { width: parent.width; height: 32 * tab.ui.u
                   Text { anchors.verticalCenter: parent.verticalCenter; text: "Versiones presentadas"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.Bold }
                   Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Math.max(28 * tab.ui.u, verCount.implicitWidth + 16 * tab.ui.u); height: 28 * tab.ui.u; radius: height / 2; color: S.ink(0.06)
                               Text { id: verCount; anchors.centerIn: parent; text: tab.versions.length; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u; font.weight: Font.Bold } } }
            Text {
                width: parent.width
                visible: false                       // el contador «0» ya lo indica
                text: tab.remoteId.length ? "Aún no hay versiones presentadas." : "Las versiones aparecen después de sincronizar y presentar."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }
            Repeater {
                model: tab.versions
                delegate: RCard {
                    required property var modelData
                    width: column.width
                    ui: tab.ui
                    Text {
                        width: parent.width
                        text: "Versión " + (modelData.version_number || "?") + " · " + S.date(S.text_(modelData, "submitted_at", "created_at"))
                              + (S.text_(modelData, "id") === String(tab.current.currentVersionId || "") ? " · vigente" : "")
                        color: S.text
                        font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u
                    }
                    Text {
                        width: parent.width
                        text: "Snapshot inmutable " + S.text_(modelData, "snapshot_hash", "snapshot_sha256").substring(0, 12)
                        color: S.muted; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                }
            }
        }
    }
}
