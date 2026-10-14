import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Fondo PEN/USD, tipo de cambio (manual o BCRP/SBS) y saldo común. Los
// importes y el saldo se calculan en C++ (RenditionMoney); la escritura es
// saveFinancial (outbox con request_id y CAS). Nunca se inventa una cotización.
Item {
    id: tab
    property var detail
    readonly property var app: detail.app
    readonly property var ui: detail.ui
    readonly property var ctl: detail.ctl
    readonly property var current: detail.current
    readonly property var funding: current.funding || ({})
    readonly property var rate: current.exchangeRate || ({})
    readonly property var balance: ctl.fundBalance(current)
    readonly property var frozen: {
        var remote = app.st.remoteCurrent || ({})
        return String(remote.financialVersionId || "").length ? remote : null
    }
    readonly property var validated: detail.selected ? ctl.totals((app.st.expenses || []).filter(function(e) { return e.archived !== true })) : ({})

    property bool fundEnabled: false
    property bool automatic: false
    property bool dirtyFund: false
    property bool dirtyRate: false
    property string error: ""
    property string rateError: ""
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    function load() {
        // Lee el estado publicado directamente (no las propiedades derivadas en
        // plena actualización) y nunca pisa lo que el usuario está editando.
        var f = (tab.current && tab.current.funding) || {}
        var r = (tab.current && tab.current.exchangeRate) || {}
        if (!dirtyFund) {
            fundEnabled = f.enabled === true
            penField.text = f.pen === undefined || f.pen === null ? "0" : String(f.pen)
            usdField.text = f.usd === undefined || f.usd === null ? "0" : String(f.usd)
        }
        if (!dirtyRate) {
            automatic = String(r.mode || "MANUAL") === "AUTOMATIC"
            rateField.text = r.rate === undefined || r.rate === null ? "" : String(r.rate)
        }
    }
    Component.onCompleted: load()
    onCurrentChanged: load()

    function saveFunding() {
        var values = { enabled: fundEnabled, pen: fundEnabled ? penField.text.trim() : "0", usd: fundEnabled ? usdField.text.trim() : "0" }
        var problem = ctl.fundingError(values)
        if (problem.length) { error = problem; return }
        submit("funding_set", values, Number(current.rowVersion || 0), function() { tab.dirtyFund = false })
    }
    function saveManualRate() {
        var value = rateField.text.trim().replace(",", ".")
        var problem = ctl.rateError(value)
        if (problem.length) { rateError = problem; return }
        submit("exchange_set", { mode: "MANUAL", rate: value, quoted_on: null }, Number(current.rowVersion || 0),
               function() { tab.dirtyRate = false })
    }
    function submit(kind, values, expectedRowVersion, onSaved) {
        error = ""
        rateError = ""
        var life = tab.life
        app.call("saveFinancial", { localId: detail.localId, kind: kind, values: values, expectedRowVersion: expectedRowVersion },
                 "financial:" + kind + ":" + detail.localId, function(ok, result, code, message) {
            if (!ok) { if (life.alive) tab.error = tab.app.errorText(code, message); return }
            if (life.alive) onSaved()
            tab.app.toast("Guardado en el equipo · pendiente de sincronizar con el servidor.", "success")
        })
    }
    function quote() {
        if (!String(current.remoteId || "").length) {
            rateError = "Sincroniza la rendición con el servidor antes de consultar la cotización."
            return
        }
        rateError = ""
        var life = tab.life
        var base = Number(current.rowVersion || 0)
        var localId = detail.localId
        app.call("exchangeQuote", { renditionId: String(current.remoteId) }, "quote:" + localId,
                 function(ok, q, code, message) {
            if (!life.alive) return
            if (!ok) { tab.rateError = tab.app.errorText(code, message); return }
            // La cotización tardía no se aplica si la ficha cambió mientras llegaba.
            if (Number(tab.current.rowVersion || 0) !== base || tab.detail.localId !== localId || !tab.detail.editable) {
                tab.rateError = "La rendición cambió mientras llegaba la cotización; vuelve a consultarla."
                return
            }
            if (q.source !== "BCRP_SBS_VENTA" || !String(q.quotedOn || "").length || !String(q.checkedAt || "").length
                    || tab.ctl.rateError(String(q.rate)).length) {
                tab.rateError = "Cotización no válida; se conserva el tipo de cambio guardado."
                return
            }
            rateField.text = String(q.rate)
            tab.submit("exchange_set", { mode: "AUTOMATIC", rate: String(q.rate), quoted_on: q.quotedOn, checked_at: q.checkedAt },
                       base, function() { tab.dirtyRate = false })
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

            RCard {
                width: parent.width
                ui: tab.ui
                Text { text: "Totales declarados"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u }
                Text {
                    width: parent.width
                    text: tab.ctl.formatMoney(tab.current.totalPen === undefined ? 0 : tab.current.totalPen, "PEN") + "   ·   "
                          + tab.ctl.formatMoney(tab.current.totalUsd === undefined ? 0 : tab.current.totalUsd, "USD")
                    color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 18 * tab.ui.u; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    visible: tab.validated.count !== undefined
                    text: "Validados " + tab.ctl.formatCents(tab.validated.validatedPenCents, "PEN") + " · " + tab.ctl.formatCents(tab.validated.validatedUsdCents, "USD")
                    color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
                Text { text: "Saldo del fondo"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: S.text
                    font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u
                    text: !tab.balance.enabled ? "Sin fondo asignado."
                          : tab.balance.error ? "No se puede calcular: " + (tab.balance.error === "INVALID_EXCHANGE_RATE" ? "tipo de cambio no válido." : "importe no válido.")
                          : "Fondo " + tab.ctl.formatCents(tab.balance.fundPenCents, "PEN") + " + " + tab.ctl.formatCents(tab.balance.fundUsdCents, "USD")
                            + "\nDisponible: " + (tab.balance.penCents === undefined || tab.balance.penCents === null ? "no determinable" : tab.ctl.formatCents(tab.balance.penCents, "PEN"))
                            + "  ·  " + (tab.balance.usdCents === undefined || tab.balance.usdCents === null ? "no determinable" : tab.ctl.formatCents(tab.balance.usdCents, "USD"))
                            + (tab.balance.hasRate ? "" : "\nRegistra el tipo de cambio para convertir saldos entre monedas.")
                }
                Text {
                    width: parent.width
                    text: "Tipo de cambio: " + (tab.rate.rate === undefined || tab.rate.rate === null ? "sin registrar"
                          : String(tab.rate.rate) + " PEN/USD · " + (tab.rate.mode === "AUTOMATIC" ? "BCRP/SBS venta del " + S.date(tab.rate.quoted_on) : "manual"))
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
            }

            RCard {
                width: parent.width
                ui: tab.ui
                visible: tab.frozen !== null
                Text { text: "Suplementos congelados de la versión vigente"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: S.muted
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                    text: {
                        if (!tab.frozen) return ""
                        var f = tab.frozen.funding || {}, r = tab.frozen.exchangeRate || {}
                        return "Fondo: " + (f.enabled === true ? tab.ctl.formatMoney(f.pen, "PEN") + " + " + tab.ctl.formatMoney(f.usd, "USD") : "sin fondo")
                               + "\nTipo de cambio: " + (r.rate === undefined || r.rate === null ? "sin registrar" : String(r.rate))
                               + "\nEstos valores no cambian aunque se edite la copia de trabajo."
                    }
                }
            }

            Text {
                width: parent.width
                visible: !tab.detail.writable
                text: "Los valores financieros están en solo lectura para esta rendición."
                color: S.warning; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }

            // ---------------------------------------------------- Fondo
            Text { text: "Fondo asignado"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold }
            Row {
                spacing: 8 * tab.ui.u
                RChip { ui: tab.ui; label: "Con fondo"; selected: tab.fundEnabled; enabledChip: tab.detail.editable; onActivated: { tab.fundEnabled = true; tab.dirtyFund = true } }
                RChip { ui: tab.ui; label: "Sin fondo"; selected: !tab.fundEnabled; enabledChip: tab.detail.editable; onActivated: { tab.fundEnabled = false; tab.dirtyFund = true } }
            }
            Row {
                width: parent.width
                spacing: 10 * tab.ui.u
                visible: tab.fundEnabled
                RField { id: penField; objectName: "fundPen"; width: (parent.width - 10 * tab.ui.u) / 2; ui: tab.ui; label: "Fondo PEN"; numeric: true; readOnly: !tab.detail.editable; onEdited: tab.dirtyFund = true }
                RField { id: usdField; objectName: "fundUsd"; width: (parent.width - 10 * tab.ui.u) / 2; ui: tab.ui; label: "Fondo USD"; numeric: true; readOnly: !tab.detail.editable; onEdited: tab.dirtyFund = true }
            }
            RButton {
                width: parent.width
                ui: tab.ui
                visible: tab.detail.writable
                primary: tab.dirtyFund
                label: "Guardar fondo"
                enabledButton: tab.detail.editable && tab.dirtyFund
                busy: tab.app.busy("financial:funding_set:" + tab.detail.localId)
                onActivated: tab.saveFunding()
            }
            Text {
                width: parent.width
                visible: tab.error.length > 0
                text: tab.error
                color: S.danger; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }

            // ------------------------------------------- Tipo de cambio
            Text { text: "Tipo de cambio"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold }
            Row {
                spacing: 8 * tab.ui.u
                RChip { ui: tab.ui; label: "Manual"; selected: !tab.automatic; enabledChip: tab.detail.editable; onActivated: { tab.automatic = false; tab.dirtyRate = true } }
                RChip { ui: tab.ui; label: "Automático BCRP/SBS"; selected: tab.automatic; enabledChip: tab.detail.editable; onActivated: { tab.automatic = true; tab.dirtyRate = true } }
            }
            RField {
                id: rateField
                objectName: "exchangeRate"
                width: parent.width
                ui: tab.ui
                label: "PEN por USD"
                numeric: true
                readOnly: !tab.detail.editable || tab.automatic
                error: tab.rateError
                onEdited: tab.dirtyRate = true
            }
            RButton {
                width: parent.width
                ui: tab.ui
                visible: tab.detail.writable && !tab.automatic
                label: "Guardar tipo de cambio manual"
                enabledButton: tab.detail.editable && rateField.text.trim().length > 0
                busy: tab.app.busy("financial:exchange_set:" + tab.detail.localId)
                onActivated: tab.saveManualRate()
            }
            RButton {
                width: parent.width
                ui: tab.ui
                visible: tab.detail.writable && tab.automatic
                glyph: 0xE145
                label: "Consultar cotización BCRP/SBS"
                enabledButton: tab.detail.editable
                busy: tab.app.busy("quote:" + tab.detail.localId)
                onActivated: tab.quote()
            }
        }
    }
}
