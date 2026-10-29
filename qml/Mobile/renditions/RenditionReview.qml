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
    ListModel { id: versionRows }
    onVersionsChanged: S.syncRows(versionRows, versions, ["id"])
    Component.onCompleted: S.syncRows(versionRows, versions, ["id"])
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

    function present() {
        app.confirm("Presentar rendición",
                    "Se guardará una versión inmutable con sus gastos, fondo y tipo de cambio, y pasará a revisión. Después sólo podrás editarla si administración la observa.",
                    "Presentar", false, function() {
            tab.app.call("present", {}, "present", function(ok, result, code, message) {
                if (!ok) { tab.app.toast(tab.app.errorText(code, message), "error"); return }
                tab.app.toast("Rendición presentada y confirmada por el servidor.", "success")
            })
        })
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

            // ------------------------------------------------ Presentación
            RCard {
                width: parent.width
                ui: tab.ui
                visible: tab.detail.writable
                Text { text: "Presentar para revisión"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    text: tab.presentBlocker.length ? tab.presentBlocker : "Lista para presentar. Se creará una versión inmutable."
                    color: tab.presentBlocker.length ? S.warning : S.success
                    wrapMode: Text.WordWrap
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
                Row {
                    spacing: 8 * tab.ui.u
                    RButton {
                        ui: tab.ui; primary: true; label: "Presentar rendición"
                        enabledButton: tab.presentBlocker.length === 0
                        busy: tab.app.busy("present") || tab.app.phase === "PRESENTING"
                        onActivated: tab.present()
                    }
                    RButton {
                        ui: tab.ui; glyph: 0xE145; label: "Sincronizar"
                        visible: tab.pending > 0 || !tab.remoteId.length
                        busy: tab.app.busy("sync")
                        onActivated: tab.app.synchronize()
                    }
                }
            }

            ReviewPanel {
                width: parent.width
                app: tab.app
                remoteId: tab.remoteId
                active: tab.visible
            }

            // -------------------------------------------------- Observaciones
            Text { text: "Gastos observados"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                visible: tab.observed.length === 0
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
            Text { text: "Versiones presentadas"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                visible: tab.versions.length === 0
                text: tab.remoteId.length ? "Aún no hay versiones presentadas." : "Las versiones aparecen después de sincronizar y presentar."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }
            Repeater {
                model: versionRows
                delegate: RCard {
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
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
