import QtQuick
import QtQuick.Shapes
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

    // Al guardar, el campo suelta el foco: el teclado no vuelve a abrirse solo al cambiar de pestaña.
    function releaseFocus() { Qt.inputMethod.hide(); tab.forceActiveFocus() }
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
            if (!ok) {
                tab.rateError = code === "QUOTE_ORIGIN_NOT_CONFIGURED"
                    ? "Consulta automática no configurada. Se mantiene el valor guardado; puedes elegir Manual."
                    : tab.app.errorText(code, message)
                return
            }
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

    // Finanzas: composición aprobada. Solo presentación; cálculos y persistencia existentes.
    readonly property var usage: {
        var f = tab.funding || {}
        var rateValue = Number(tab.rate.rate)
        var fundPen = Number(f.pen || 0), fundUsd = Number(f.usd || 0)
        var spentPen = Number(tab.current.totalPen || 0), spentUsd = Number(tab.current.totalUsd || 0)
        if (f.enabled !== true || tab.balance.error ||
                !isFinite(fundPen) || !isFinite(fundUsd) ||
                !isFinite(spentPen) || !isFinite(spentUsd))
            return { known: false, percent: 0, arc: 0 }
        if ((fundUsd !== 0 || spentUsd !== 0) && (!isFinite(rateValue) || rateValue <= 0))
            return { known: false, percent: 0, arc: 0 }
        var conversion = isFinite(rateValue) && rateValue > 0 ? rateValue : 1
        var fund = fundPen + fundUsd * conversion
        var spent = spentPen + spentUsd * conversion
        if (!isFinite(fund) || !isFinite(spent) || fund <= 0)
            return { known: false, percent: 0, arc: 0 }
        var pct = 100 * spent / fund
        return { known: true, percent: pct, arc: Math.max(0, Math.min(1, pct / 100)) }
    }

    Flickable {
        id: financeScroll
        objectName: "financeScroll"
        anchors.fill: parent
        contentWidth: width
        // El último control y sus avisos deben poder desplazarse POR ENCIMA del Dock global.
        // No cambia la geometría del Dock; solo añade espacio de lectura al final del Flickable.
        contentHeight: financeColumn.height + Math.max(42 * tab.ui.u, tab.ui.dockArea + 28 * tab.ui.u)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height

        Column {
            id: financeColumn
            x: tab.ui.gutter
            width: parent.width - 2 * tab.ui.gutter
            spacing: 16 * tab.ui.u

            // SALDO DISPONIBLE: los importes proceden de fundBalance (C++).
            RCard {
                id: balanceHero
                objectName: "financeBalanceHero"
                width: parent.width
                ui: tab.ui
                color: S.cardGlass
                border.color: S.edge(0.94)
                radius: 24 * tab.ui.u

                Row {
                    width: parent.width
                    height: 142 * tab.ui.u
                    spacing: 6 * tab.ui.u
                    Column {
                        width: parent.width - ring.width - parent.spacing
                        spacing: 7 * tab.ui.u
                        Text {
                            text: "SALDO DISPONIBLE"
                            color: S.corporateBlue
                            font.family: tab.ui.fontFamily
                            font.pixelSize: 13 * tab.ui.u
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: !tab.balance.enabled ? "Sin fondo"
                                  : tab.balance.error ? "No disponible"
                                  : tab.balance.penCents === undefined || tab.balance.penCents === null ? "No determinable"
                                  : tab.ctl.formatCents(tab.balance.penCents, "PEN")
                            color: S.text
                            elide: Text.ElideRight
                            font.family: tab.ui.fontFamily
                            font.pixelSize: (text.length > 17 ? 19 : text.length > 13 ? 24 : 34) * tab.ui.u
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: !tab.balance.enabled ? "Configura un fondo asignado"
                                  : tab.balance.error ? "Revisa el tipo de cambio o los importes"
                                  : tab.balance.usdCents === undefined || tab.balance.usdCents === null
                                  ? "Equivalente no determinable"
                                  : "Equivalente " + tab.ctl.formatCents(tab.balance.usdCents, "USD")
                            color: S.muted
                            wrapMode: Text.WordWrap
                            font.family: tab.ui.fontFamily
                            font.pixelSize: 13 * tab.ui.u
                        }
                    }
                    Item {
                        id: ring
                        width: 102 * tab.ui.u
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        Shape {
                            anchors.fill: parent
                            ShapePath {
                                strokeColor: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.13)
                                strokeWidth: 10 * tab.ui.u
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 51 * tab.ui.u; centerY: 51 * tab.ui.u
                                    radiusX: 39 * tab.ui.u; radiusY: 39 * tab.ui.u
                                    startAngle: -90; sweepAngle: 360
                                }
                            }
                            ShapePath {
                                strokeColor: S.corporateGreen
                                strokeWidth: 10 * tab.ui.u
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 51 * tab.ui.u; centerY: 51 * tab.ui.u
                                    radiusX: 39 * tab.ui.u; radiusY: 39 * tab.ui.u
                                    startAngle: -90; sweepAngle: tab.usage.arc * 360
                                }
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 1 * tab.ui.u
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tab.usage.known ? tab.usage.percent.toFixed(1) + "%" : "—"
                                color: S.corporateGreen
                                font.family: tab.ui.fontFamily
                                font.pixelSize: 19 * tab.ui.u
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "usado"
                                color: S.muted
                                font.family: tab.ui.fontFamily
                                font.pixelSize: 12 * tab.ui.u
                            }
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1 * tab.ui.u
                    color: S.tintSoftBorder
                }
                Row {
                    width: parent.width
                    spacing: 10 * tab.ui.u
                    Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: 5 * tab.ui.u
                        Text { text: "FONDO ASIGNADO"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width
                            text: !tab.balance.enabled ? "Sin fondo"
                                  : tab.balance.fundPenCents === undefined || tab.balance.fundPenCents === null ? "—"
                                  : tab.ctl.formatCents(tab.balance.fundPenCents, "PEN")
                            elide: Text.ElideRight; color: S.text
                            font.family: tab.ui.fontFamily; font.pixelSize: 20 * tab.ui.u; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!tab.balance.enabled && Number(tab.funding.usd || 0) !== 0
                            text: tab.ctl.formatMoney(tab.funding.usd, "USD")
                            color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u
                        }
                    }
                    Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: 5 * tab.ui.u
                        Text { text: "GASTADO"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width
                            text: tab.ctl.formatMoney(tab.current.totalPen === undefined ? 0 : tab.current.totalPen, "PEN")
                            elide: Text.ElideRight; color: S.text
                            font.family: tab.ui.fontFamily; font.pixelSize: 20 * tab.ui.u; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: Number(tab.current.totalUsd || 0) !== 0
                            text: tab.ctl.formatMoney(tab.current.totalUsd, "USD")
                            color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u
                        }
                    }
                }
            }

            // Dos indicadores de revisión: se mantienen diferenciados del saldo.
            Row {
                width: parent.width
                height: 104 * tab.ui.u
                spacing: 10 * tab.ui.u
                RCard {
                    objectName: "financeDeclaredCard"
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    ui: tab.ui
                    color: S.cardGlass
                    border.color: S.edge(0.92)
                    Text { text: "DECLARADO"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: tab.ctl.formatMoney(tab.current.totalPen === undefined ? 0 : tab.current.totalPen, "PEN")
                        color: S.text; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 20 * tab.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        text: tab.ctl.formatMoney(tab.current.totalUsd === undefined ? 0 : tab.current.totalUsd, "USD")
                        color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u
                    }
                }
                RCard {
                    objectName: "financeValidatedCard"
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    ui: tab.ui
                    color: S.cardGlass
                    border.color: S.edge(0.92)
                    Text { text: "VALIDADO"; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width
                        text: tab.validated.validatedPenCents === undefined ? "—" : tab.ctl.formatCents(tab.validated.validatedPenCents, "PEN")
                        color: S.text; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 20 * tab.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        text: tab.validated.validatedUsdCents === undefined ? "—" : tab.ctl.formatCents(tab.validated.validatedUsdCents, "USD")
                        color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u
                    }
                }
            }

            // ---- Fondo asignado (rediseño aprobado): interruptor + dos montos;
            // Guardar/Deshacer sólo aparecen cuando hay cambios.
            RCard {
                objectName: "financeFundingCard"
                width: parent.width
                ui: tab.ui
                color: S.glass(0.80)
                border.color: S.edge(1)
                radius: 24 * tab.ui.u
                Item {
                    width: parent.width; height: 48 * tab.ui.u
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - fundSwitch.width - 12 * tab.ui.u
                        spacing: 2 * tab.ui.u
                        Text { text: "Fondo asignado"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.Bold }
                        Text { width: parent.width; elide: Text.ElideRight; color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                               text: tab.fundEnabled ? "Monto entregado para esta rendición" : "Gastos con dinero propio (reembolso)" }
                    }
                    Rectangle {
                        id: fundSwitch
                        objectName: "fundSwitch"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 52 * tab.ui.u; height: 32 * tab.ui.u; radius: height / 2
                        color: tab.fundEnabled ? S.accent : "#D5DBE5"
                        opacity: tab.detail.editable ? 1 : 0.5
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Rectangle {
                            width: 26 * tab.ui.u; height: width; radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: tab.fundEnabled ? parent.width - width - 3 * tab.ui.u : 3 * tab.ui.u
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        MouseArea { anchors.fill: parent; enabled: tab.detail.editable
                                    onClicked: { tab.fundEnabled = !tab.fundEnabled; tab.dirtyFund = true } }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Fondo asignado"
                        Accessible.checked: tab.fundEnabled
                    }
                }
                Row {
                    width: parent.width
                    spacing: 10 * tab.ui.u
                    visible: tab.fundEnabled
                    RField {
                        id: penField
                        objectName: "fundPen"
                        width: (parent.width - parent.spacing) / 2
                        ui: tab.ui; label: "Soles"; prefix: "S/"; numeric: true; formStyle: true
                        readOnly: !tab.detail.editable
                        onEdited: tab.dirtyFund = true
                    }
                    RField {
                        id: usdField
                        objectName: "fundUsd"
                        width: (parent.width - parent.spacing) / 2
                        ui: tab.ui; label: "Dólares"; prefix: "$"; numeric: true; formStyle: true
                        readOnly: !tab.detail.editable
                        onEdited: tab.dirtyFund = true
                    }
                }
                Row {
                    width: parent.width; spacing: 8 * tab.ui.u
                    visible: tab.detail.writable && tab.dirtyFund
                    RButton { width: (parent.width - parent.spacing) / 3; ui: tab.ui; label: "Deshacer"; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.06)
                              enabledButton: !tab.app.busy("financial:funding_set:" + tab.detail.localId)
                              onActivated: { tab.dirtyFund = false; tab.load() } }
                    RButton { width: (parent.width - parent.spacing) * 2 / 3; ui: tab.ui; primary: true; label: "Guardar fondo"
                              enabledButton: tab.detail.editable
                              busy: tab.app.busy("financial:funding_set:" + tab.detail.localId)
                              onActivated: { tab.releaseFocus(); tab.saveFunding() } }
                }
                Text {
                    width: parent.width
                    visible: tab.error.length > 0
                    text: tab.error; wrapMode: Text.WordWrap
                    color: S.danger; font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
            }

            // ---- Tipo de cambio: Auto/Manual compacto, valor grande, actualizar
            // como icono; en Manual el número es editable.
            RCard {
                objectName: "financeExchangeCard"
                width: parent.width
                ui: tab.ui
                color: S.glass(0.80)
                border.color: S.edge(1)
                radius: 24 * tab.ui.u
                Item {
                    width: parent.width; height: 44 * tab.ui.u
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Tipo de cambio"; color: S.text
                           font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.Bold }
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 150 * tab.ui.u; height: 42 * tab.ui.u; radius: 12 * tab.ui.u; color: S.track
                        Rectangle {                                  // píldora deslizante del selector
                            readonly property real cell: (modeRow.width - (2 - 1) * modeRow.spacing) / Math.max(1, 2)
                            visible: true
                            x: modeRow.x + (tab.automatic ? 0 : 1) * (cell + modeRow.spacing)
                            y: modeRow.y
                            width: cell; height: modeRow.height; radius: 9 * tab.ui.u
                            color: S.pill()
                            Behavior on x { enabled: tab.ui.reducedMotion !== true
                                            SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.25 } }
                        }
                        Row {
                            id: modeRow
                            anchors.fill: parent; anchors.margins: 3 * tab.ui.u; spacing: 2 * tab.ui.u
                            Repeater {
                                model: [{ k: true, l: "Auto" }, { k: false, l: "Manual" }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool on: tab.automatic === modelData.k
                                    width: (modeRow.width - modeRow.spacing) / 2; height: modeRow.height; radius: 9 * tab.ui.u
                                    color: "transparent"
                                    Text { anchors.centerIn: parent; text: parent.modelData.l; color: parent.on ? S.accent : S.text
                                           font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u; font.weight: parent.on ? Font.Bold : Font.DemiBold }
                                    MouseArea { anchors.fill: parent; enabled: tab.detail.editable && !parent.on
                                                onClicked: { tab.automatic = parent.modelData.k; tab.dirtyRate = true } }
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData.l
                                    Accessible.checked: on
                                }
                            }
                        }
                    }
                }
                Item {
                    width: parent.width; height: autoRate.implicitHeight
                    visible: tab.automatic
                    Column {
                        id: autoRate
                        width: parent.width - (quoteButton.visible ? quoteButton.width + 12 * tab.ui.u : 0)
                        spacing: 2 * tab.ui.u
                        Row {
                            spacing: 6 * tab.ui.u
                            Text { id: rateBig; text: rateField.text.length ? rateField.text : "Sin cotización"; color: S.text; font.family: tab.ui.fontFamily
                                   font.pixelSize: (rateField.text.length ? 40 : 24) * tab.ui.u; font.weight: Font.ExtraBold }
                            Text { anchors.baseline: rateBig.baseline; text: "S/ por US$"; color: S.muted
                                   font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u; font.weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap; color: S.muted
                            font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                            text: tab.rate.quoted_on ? ["BCRP/SBS", "venta del " + S.date(tab.rate.quoted_on)]
                                                       .concat(tab.rate.checked_at ? ["revisado " + S.date(String(tab.rate.checked_at).slice(0, 10))] : []).join(" · ")
                                                     : "Cotización aún no disponible"
                        }
                    }
                    RButton {
                        id: quoteButton
                        objectName: "financeQuoteButton"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 48 * tab.ui.u; height: width; radius: width / 2
                        ui: tab.ui
                        visible: tab.detail.writable
                        glyph: 0xE145
                        color: S.tintSoft
                        enabledButton: tab.detail.editable
                        busy: tab.app.busy("quote:" + tab.detail.localId)
                        Accessible.name: "Consultar cotización BCRP/SBS"
                        onActivated: tab.quote()
                    }
                }
                RField {
                    id: rateField
                    objectName: "exchangeRate"
                    width: parent.width
                    visible: !tab.automatic
                    ui: tab.ui; label: "S/ por US$"; numeric: true; formStyle: true
                    readOnly: !tab.detail.editable
                    error: tab.rateError
                    onEdited: tab.dirtyRate = true
                }
                Text { visible: !tab.automatic; width: parent.width; wrapMode: Text.WordWrap; text: "Se usará este valor hasta que vuelvas a Auto."
                       color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u }
                RButton {
                    width: parent.width; ui: tab.ui; primary: true
                    visible: tab.detail.writable && !tab.automatic && tab.dirtyRate
                    label: "Guardar tipo de cambio"
                    enabledButton: tab.detail.editable && rateField.text.trim().length > 0
                    busy: tab.app.busy("financial:exchange_set:" + tab.detail.localId)
                    onActivated: { tab.releaseFocus(); tab.saveManualRate() }
                }
                Rectangle { width: parent.width; height: 1; color: S.tintSoftBorder }
                Item {
                    width: parent.width; height: 24 * tab.ui.u
                    readonly property real rateValue: Number(String(rateField.text).replace(",", "."))
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "US$ 100 equivalen a"; color: S.muted
                           font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                           text: parent.rateValue > 0 ? "S/ " + (parent.rateValue * 100).toFixed(2) : "—"
                           color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u; font.weight: Font.Bold }
                }
                Rectangle {
                    width: parent.width
                    height: quoteNotice.implicitHeight + 24 * tab.ui.u
                    radius: 14 * tab.ui.u
                    color: S.glass(0.70)
                    border.width: 1
                    border.color: Qt.rgba(198 / 255, 47 / 255, 62 / 255, 0.22)
                    visible: tab.rateError.length > 0 && tab.automatic
                    Text {
                        id: quoteNotice
                        x: 12 * tab.ui.u
                        y: 12 * tab.ui.u
                        width: parent.width - 24 * tab.ui.u
                        text: tab.rateError
                        wrapMode: Text.WordWrap
                        color: S.danger
                        font.family: tab.ui.fontFamily
                        font.pixelSize: 13 * tab.ui.u
                    }
                }
            }

            // Se preserva la versión financiera congelada cuando existe.
            RCard {
                width: parent.width; ui: tab.ui
                visible: tab.frozen !== null
                color: S.cardGlass
                border.color: S.edge(0.94)
                Text { text: "Suplementos congelados de la versión vigente"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
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
        }
    }
}
