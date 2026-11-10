import QtQuick
import "RStyle.js" as S

// Caja editable de Rendiciones: mismo sistema de edición del Home (sin widgets).
// Pulsación larga = modo edición (las cajas vibran) + menú de la caja; en edición,
// arrastrar reordena y el botón ··· abre tamaño (Compacto / Ancho) y presentación
// (Completa / Solo icono). El estado y el guardado viven en [owner] (RenditionExpenses).
Item {
    id: tile
    property var ui
    property var owner
    property string kind: ""                       // metrics | drafts
    property string key: ""
    property int order: 0
    property bool longPressEnters: true            // false: el contenido gestiona su propia pulsación larga
    default property alias content: holder.data
    readonly property bool editing: !!owner && owner.editMode
    readonly property bool dragging: !!owner && owner.dragKey === kind + ":" + key
    readonly property bool reduced: !!ui && ui.reducedMotion === true
    // 3D Touch: mientras se mantiene el dedo la caja "se hunde" (presión 0..1 en
    // 380 ms, como el Deep Press del Home); al completarse hace "pop" con háptica,
    // se eleva y las demás cajas se atenúan mientras su menú está abierto.
    readonly property bool focused: !!owner && owner.focusKey === kind + ":" + key
    readonly property bool dimmed: !!owner && owner.focusKey.length > 0 && !focused
    property real pressure: 0
    // Acomodo autónomo (RPackedLayout): ancho/posición los asigna el contenedor.
    property bool iconPresentation: false
    property bool fillRow: false                   // ocupa la altura de su fila (cajas de icono)
    property real minRowHeight: 76 * (ui ? ui.u : 1)
    property real rowHeight: 0
    property bool placedOnce: false
    height: fillRow && rowHeight > 0 ? rowHeight : holder.childrenRect.height
    Behavior on x { enabled: tile.placedOnce && !tile.reduced && !tile.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: tile.placedOnce && !tile.reduced && !tile.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    function relayoutParent() { if (parent && parent.schedule !== undefined) parent.schedule() }
    onHeightChanged: relayoutParent()
    onOrderChanged: relayoutParent()
    onVisibleChanged: relayoutParent()
    onIconPresentationChanged: relayoutParent()
    z: dragging || focused ? 10 : 0
    scale: dragging ? 1.05 : focused ? 1.03 : 1 - 0.06 * pressure
    opacity: dimmed ? 0.45 : 1
    Behavior on scale { enabled: !tile.reduced && tile.pressure === 0; NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    Behavior on opacity { enabled: !tile.reduced; NumberAnimation { duration: 180 } }
    NumberAnimation {
        id: pressRamp
        target: tile; property: "pressure"; from: 0; to: 1
        duration: 380; easing.type: Easing.OutQuad
    }
    function beginPress() { if (!reduced && !editing) pressRamp.restart() }
    function releasePressure() { pressRamp.stop(); pressure = 0 }
    function deepPress() {
        pressRamp.stop(); pressure = 0
        if (owner.app && owner.app.haptic) owner.app.haptic("medium")
        owner.openTileMenu(tile)                   // menú 3D Touch: acciones + diseño
    }

    property real wobble: 0
    rotation: editing && !dragging && !reduced ? wobble : 0
    SequentialAnimation on wobble {
        running: tile.editing && !tile.dragging && !tile.reduced
        loops: Animation.Infinite
        NumberAnimation { to: tile.order % 2 ? 1.2 : -1.2; duration: 140 + (tile.order % 3) * 25; easing.type: Easing.InOutSine }
        NumberAnimation { to: tile.order % 2 ? -1.2 : 1.2; duration: 140 + (tile.order % 3) * 25; easing.type: Easing.InOutSine }
    }

    MouseArea {                                      // fuera de edición: Deep Press entra a editar
        anchors.fill: parent
        z: -1
        enabled: !tile.editing && tile.longPressEnters
        pressAndHoldInterval: 380
        onPressed: if (!tile.reduced) pressRamp.restart()
        onReleased: tile.releasePressure()
        onCanceled: tile.releasePressure()
        onPressAndHold: tile.deepPress()
    }
    Item { id: holder; width: parent.width }
    MouseArea {                                      // en edición: arrastrar reordena, tocar abre opciones
        anchors.fill: parent
        z: 100
        enabled: tile.editing
        preventStealing: true
        property bool moved: false
        onPressed: { moved = false; tile.owner.dragKey = tile.kind + ":" + tile.key }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            moved = true
            tile.owner.dragOver(tile, mapToItem(tile.parent, mouse.x, mouse.y))
        }
        onReleased: tile.owner.endDrag()
        onCanceled: tile.owner.endDrag()
        onClicked: if (!moved) tile.owner.openTileMenu(tile)
    }
    Rectangle {                                      // indicador de opciones (como el Home)
        visible: tile.editing
        z: 101
        width: 30 * tile.ui.u; height: width; radius: width / 2
        x: -6 * tile.ui.u; y: -6 * tile.ui.u
        color: S.glass(0.96)
        border.width: 1; border.color: S.border
        Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0B6); color: S.text
               font.family: tile.ui.iconFamily; font.pixelSize: 16 * tile.ui.u }
    }
}
