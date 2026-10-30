import QtQuick
import "RStyle.js" as S
import ".." as Mobile

// Tarjeta de rendición del diseño aprobado. Datos reales del estado publicado.
// - Los dos puntos = estado ADMINISTRATIVO de la ficha (Borrador ámbar,
//   Observada rojo, En revisión azul, Aprobada verde); nunca sincronización.
// - Avance: sólo si el modelo trae un campo real (progress/progressPercent);
//   sin fuente verificable la barra queda vacía y no se muestra porcentaje.
Rectangle {
    id: card
    Component.onCompleted: S.renderCount("rendition_delegate_created")
    property var ui
    property var ctl
    property var row: ({})
    signal activated()
    signal held()                                  // pulsación prolongada → menú 3D Touch

    readonly property string code: S.text_(row, "visibleCode", "visible_code")
    readonly property string renditionName: S.renditionDisplayName(S.text_(row, "displayName", "display_name"), code)
    // Principal; si falta, el primer proyecto asociado (IDs reales, nunca texto).
    readonly property string projectId: {
        var id = S.text_(row, "primaryProjectId", "primary_project_id")
        if (id.length) return id
        var ids = row.projectIds || []
        return ids.length ? String(ids[0]) : ""
    }
    // La lista remota v06 no trae proyectos: sin detalle cargado no se afirma «Sin proyecto».
    readonly property bool projectsKnown: row.projectIds !== undefined || S.text_(row, "primaryProjectId", "primary_project_id").length > 0
                                          || S.text_(row, "primaryProjectName", "primary_project_name").length > 0
    readonly property var project: ctl && projectId.length ? ctl.project(projectId) : ({})
    readonly property string projectName: S.text_(project, "name", "project_name") || S.text_(row, "primaryProjectName", "primary_project_name")
    readonly property string projectCode: S.text_(project, "code", "project_code")
    // Avance calculado en C++ (RenditionUiController::completion) con los
    // requisitos reales de presentación; null = no evaluable sin el detalle.
    property var progressOverride: undefined          // recibidas: sin cálculo propio
    readonly property var progressValue: {
        if (progressOverride !== undefined) return progressOverride
        if (!ctl) return null
        var c = ctl.completion(row)
        return c.known ? c.percent : null
    }
    // Importes: null del servidor sólo se muestra como 0 si se sabe que no hay gastos.
    readonly property bool expensesKnown: row.expenseCount !== undefined && row.expenseCount !== null
    function amount(value, currency) {
        if (value === undefined || value === null || value === "")
            return expensesKnown && Number(row.expenseCount) === 0 ? ctl.formatMoney(0, currency)
                                                                    : (currency === "USD" ? "US$ —" : "S/ —")
        return ctl.formatMoney(value, currency)
    }
    readonly property color statusTone: S.statusColor(row.status)

    implicitHeight: content.implicitHeight + 34 * ui.u
    radius: 22 * ui.u
    readonly property bool glassOn: !!ui && !!ui.cardGlassUi && !!ui.cardGlassUi.glassTexture
                                    && ui.cardGlassUi.glassReady !== false
    // Fuera de pantalla no se dibuja el vidrio (ahorra pasadas de GPU al desplazar).
    readonly property bool onScreen: {
        if (!glassOn) return false
        var tick = ui.cardGlassUi.glassTick
        var p = mapToItem(null, 0, 0)
        return p.y + height > -20 && p.y < (Window.height > 0 ? Window.height : 2400) + 20
    }
    color: glassOn ? (tap.pressed ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                   : (tap.pressed ? S.lite(247, 249, 252, 0.95) : S.glass(0.90))
    border.width: glassOn ? 0 : 1
    border.color: S.dark ? Qt.rgba(1, 1, 1, 0.12) : S.ink(0.05)
    Mobile.GlassSurface {                             // Liquid Glass real (material del Dock), claro y oscuro
        ui: card.glassOn ? card.ui.cardGlassUi : null
        visible: card.onScreen
        radius: card.radius
        margin: 10 * card.ui.u
        tint: S.dark ? (S.halloween ? Qt.rgba(48 / 255, 16 / 255, 66 / 255, 0.50) : Qt.rgba(10 / 255, 14 / 255, 24 / 255, 0.42)) : Qt.rgba(1, 1, 1, 0.78)
        refraction: S.dark ? card.ui.dockGlassRefraction : 0          // claro: sin lente oscura
        specular: S.dark ? 0.75 : 0.45                                   // oscuro: filo claro como iOS
        bevel: card.ui.dockGlassBevel
        contrast: card.ui.dockGlassContrast
        frost: S.dark ? card.ui.dockGlassFrost : 7 * card.ui.u           // esmerilado blanco intenso
        edge: S.dark ? (S.halloween ? Qt.rgba(1, 150 / 255, 50 / 255, 0.55) : Qt.rgba(1, 1, 1, 0.38)) : Qt.rgba(1, 1, 1, 0.95)
        shadowAlpha: S.dark ? card.ui.dockGlassShadowAlpha : 0.10
    }
    Rectangle {                                       // brillo superior del vidrio oscuro
        visible: S.dark && !card.glassOn
        anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
    scale: tap.pressed ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

    // Sombra suave estática.
    Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 6 * card.ui.u; anchors.margins: -1; radius: card.radius; visible: !card.glassOn; color: S.dark ? Qt.rgba(0, 0, 0, 0.35) : S.ink(0.045) }

    MouseArea { id: tap; anchors.fill: parent; pressAndHoldInterval: 380
                onClicked: card.activated(); onPressAndHold: card.held() }

    Column {
        id: content
        x: 20 * card.ui.u
        y: 18 * card.ui.u
        width: card.width - 40 * card.ui.u
        spacing: 12 * card.ui.u

        Row {
            width: parent.width
            spacing: 16 * card.ui.u
            Rectangle {                                       // icono documental
                width: 52 * card.ui.u; height: width
                radius: 14 * card.ui.u
                color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.08)
                Text {
                    anchors.centerIn: parent
                    text: String.fromCharCode(0xE0CC)          // Lucide file-text
                    font.family: card.ui.iconFamily
                    font.pixelSize: 28 * card.ui.u
                    color: S.corporateBlue
                }
            }
            Column {
                width: parent.width - 68 * card.ui.u - percent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * card.ui.u
                Text {
                    width: parent.width
                    text: card.renditionName
                    color: S.text
                    elide: Text.ElideRight
                    font.family: card.ui.fontFamily
                    font.pixelSize: 19 * card.ui.u
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: card.code.length ? card.code : "Código pendiente"
                    color: S.muted
                    elide: Text.ElideRight
                    font.family: card.ui.fontFamily
                    font.pixelSize: 13 * card.ui.u
                }
                Text {
                    width: parent.width
                    text: card.projectName.length || card.projectCode.length
                          ? [card.projectName, card.projectCode].filter(function(s) { return s.length }).join("  •  ")
                          : card.projectsKnown ? "Sin proyecto" : "Proyecto por cargar · abre la ficha"
                    color: S.muted
                    elide: Text.ElideRight
                    font.family: card.ui.fontFamily
                    font.pixelSize: 15 * card.ui.u
                }
            }
            Text {
                id: percent
                text: card.progressValue === null ? "—" : Math.round(card.progressValue) + "%"
                color: card.progressValue === null ? S.faint : S.corporateBlue
                font.family: card.ui.fontFamily
                font.pixelSize: 19 * card.ui.u
                font.weight: Font.DemiBold
            }
        }
        Text {
            width: parent.width
            text: "Período " + S.period(card.row.periodStart, card.row.periodEnd)
            color: S.muted
            font.family: card.ui.fontFamily
            font.pixelSize: 15 * card.ui.u
        }
        Item {                                                 // barra indicadora (no editable)
            width: parent.width
            height: 16 * card.ui.u
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6 * card.ui.u; radius: height / 2
                color: S.track
            }
            Rectangle {
                visible: card.progressValue !== null
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.max(0, Math.min(100, card.progressValue || 0)) / 100
                height: 6 * card.ui.u; radius: height / 2
                color: S.corporateBlue
            }
            Rectangle {
                visible: card.progressValue !== null
                width: 16 * card.ui.u; height: width; radius: width / 2
                x: Math.max(0, parent.width * Math.max(0, Math.min(100, card.progressValue || 0)) / 100 - width / 2)
                color: "#FFFFFF"
                border.width: 3 * card.ui.u
                border.color: S.corporateBlue
            }
        }
        Text {
            width: parent.width
            text: card.amount(card.row.totalPen, "PEN") + "   •   " + card.amount(card.row.totalUsd, "USD")
                  + "   •   " + (card.expensesKnown ? Number(card.row.expenseCount) + " gastos" : "gastos por cargar")
            color: S.text
            elide: Text.ElideRight
            font.family: card.ui.fontFamily
            font.pixelSize: 16 * card.ui.u
        }
        Row {                                                  // estado de ficha
            spacing: 6 * card.ui.u
            Repeater {
                model: 2
                delegate: Rectangle { width: 12 * card.ui.u; height: width; radius: width / 2; color: card.statusTone }
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: "Estado " + card.ctl.statusLabel(String(card.row.status || "BORRADOR"))
        }
    }
}
