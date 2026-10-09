pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../components" as Components
import "../lib/IconCatalog.js" as IconCatalog

// The single physical InGe+ dock. It renders the snapshot active in
// dockContextController and sends taps to dockCommandRouter without knowing
// which surface published it. Geometry, material, motion and the native band
// belong exclusively to this view.
Item {
    id: root
    required property var flow
    property real bottomSafeInset: 0
    property bool keyboardVisible: false
    property Item backdropItem: null
    property bool nativeSurface: false
    // Tone of whatever is actually composited behind the glass. The shell
    // declares it; the dock only derives material and icon contrast from it.
    property bool darkBackdrop: false

    readonly property var controller: dockContextController
    readonly property var router: dockCommandRouter
    readonly property int generation: controller ? controller.generation : 0
    readonly property bool dark: !!flow && flow.darkMode === true
    // Native surfaces may deliver the strip behind the dock through the host.
    // Double buffered: the visible frame stays valid while the next decodes and
    // is promoted only once Ready, so the glass never drops to the fallback.
    property int backdropFront: 0
    property real backdropFrontLuma: -1
    property real backdropIncomingLuma: -1
    property int backdropPending: -1
    readonly property string nativeBackdropSource: nativeSurface && !!controller ? controller.nativeBackdrop : ""
    readonly property Item backdropFrontImage: backdropFront === 0 ? nativeBackdropA : nativeBackdropB
    readonly property bool nativeBackdropReady: nativeSurface && backdropFrontImage.status === Image.Ready
        && backdropFrontImage.source.toString().length > 0
    onNativeBackdropSourceChanged: {
        if (nativeBackdropSource.length === 0) {
            nativeBackdropA.source = ""
            nativeBackdropB.source = ""
            backdropFrontLuma = -1
            backdropPending = -1
            return
        }
        backdropIncomingLuma = controller.nativeBackdropLuma
        backdropPending = backdropFront === 0 ? 1 : 0
        var back = backdropPending === 0 ? nativeBackdropA : nativeBackdropB
        back.source = nativeBackdropSource
    }
    function promoteBackdrop(image, index) {
        if (index !== backdropPending || nativeBackdropSource.length === 0)
            return
        if (image.status === Image.Error) {
            backdropPending = -1
            return
        }
        if (image.status !== Image.Ready)
            return
        backdropPending = -1
        backdropFrontLuma = backdropIncomingLuma
        var previous = backdropFront === 0 ? nativeBackdropA : nativeBackdropB
        backdropFront = index
        // Keep at most one decoded frame once the swap is done.
        if (previous !== image)
            previous.source = ""
    }

    readonly property real backdropLuma: nativeBackdropReady && backdropFrontLuma >= 0
        ? backdropFrontLuma : ((dark || darkBackdrop) ? 0.15 : 0.9)
    readonly property string backdropTone: backdropLuma < 0.38 ? "dark" : (backdropLuma < 0.62 ? "mid" : "light")
    // Hysteresis around the threshold keeps glyphs from flickering on mid tones.
    property bool onDarkMaterial: false
    function updateMaterialTone() {
        if (backdropLuma < 0.5)
            onDarkMaterial = true
        else if (backdropLuma > 0.6)
            onDarkMaterial = false
    }
    onBackdropLumaChanged: updateMaterialTone()
    readonly property Item glassBackdrop: nativeSurface ? (nativeBackdropReady ? backdropFrontImage : null)
                                                        : backdropItem
    readonly property string glassMode: !shown ? "hidden"
        : (nativeSurface ? (nativeBackdropReady ? "native-backdrop" : "native-fallback") : "qml-backdrop")
    onGlassModeChanged: Qt.callLater(logGlassState)
    onOnDarkMaterialChanged: Qt.callLater(logGlassState)
    function logGlassState() {
        console.info("INGE_DOCK_GLASS_MODE mode=" + glassMode
                     + " nativeSurface=" + nativeSurface + " darkBackdrop=" + darkBackdrop
                     + " backdropAvailable=" + (glassBackdrop !== null)
                     + " backdropTone=" + backdropTone
                     + " iconTone=" + (onDarkMaterial ? "light" : "dark"))
    }
    readonly property bool transitionPending: !!controller && controller.transitionPending
    // Earth (the only dark native surface) shares the GPU with Cesium: same
    // material, fewer frost samples and no soft shadow pass. The safe profile
    // (LOW/ULTRA_LOW devices, battery saver, heat or a user pick) and Android
    // low-RAM devices get the same on every surface.
    readonly property bool deviceLowCostGlass: !!flow
        && (flow.lowMemoryMode || flow.performance.profile >= flow.performance.safe)
    readonly property bool lowCostGlass: (nativeSurface && darkBackdrop) || deviceLowCostGlass
    // The Dock refracts live page content (text): full resolution normally,
    // half resolution with the low-cost material (3-5 live passes per frame
    // while scrolling on a tiler GPU).
    readonly property real lowCostCaptureScale: lowCostGlass ? 0.5 : 1.0
    onLowCostGlassChanged: {
        if (lowCostGlass)
            console.info("INGE_DOCK_GLASS_PROFILE profile=low reason="
                         + (deviceLowCostGlass ? "device" : "earth")
                         + " mainTaps=4 selectedTaps=2 searchTaps=2 aiTaps=2")
    }

    readonly property var visibleActions: {
        var source = controller ? controller.actions : []
        var result = []
        for (var i = 0; i < source.length; ++i)
            if (source[i].visible)
                result.push(source[i])
        return result
    }
    // A published "search" action is presented as the accessory above the
    // capsule; every other action lives inside the capsule.
    readonly property var searchAction: {
        for (var i = 0; i < visibleActions.length; ++i)
            if (visibleActions[i].id === "search")
                return visibleActions[i]
        return null
    }
    readonly property var mainActions: visibleActions.filter(function(action) {
        return action.id !== "search"
    })
    readonly property int selectedIndex: {
        for (var i = 0; i < mainActions.length; ++i)
            if (mainActions[i].selected)
                return i
        return -1
    }
    readonly property bool coreAvailable: !!controller && controller.ingeCoreAvailable
    readonly property bool shown: !keyboardVisible && visibleActions.length > 0

    // ---- Hierarchical actions (long press) --------------------------------
    // The published tree may be deep, but exactly one branch is drawn: the
    // children of the last node of menuPath. menuPath holds stable action ids
    // and is re-resolved on every context change, so a republished tree keeps
    // the open branch while it still exists and closes it otherwise.
    // Native surfaces are drawn above the Qt window except in the dock band,
    // so the floating menu is limited to QML surfaces.
    property var menuPath: []
    property int menuGeneration: -1
    property real menuAnchorX: 0
    property int menuDirection: 1
    readonly property int menuHoldInterval: 380
    // Actions whose command opens a peek panel (press depth only).
    readonly property var peekActionIds: ["information"]
    readonly property bool menuAvailable: shown && !nativeSurface
    readonly property bool menuOpen: menuGeneration === generation && menuPath.length > 0 && menuNode !== null
    readonly property string menuOwnerId: menuPath.length > 0 ? String(menuPath[0]) : ""
    readonly property var menuNode: {
        var list = visibleActions
        var node = null
        for (var i = 0; i < menuPath.length; ++i) {
            node = null
            for (var k = 0; k < list.length; ++k) {
                if (String(list[k].id) === String(menuPath[i]) && list[k].visible && list[k].enabled) {
                    node = list[k]
                    break
                }
            }
            if (!node)
                return null
            list = visibleChildren(node)
        }
        return node
    }
    readonly property var menuEntries: menuNode ? visibleChildren(menuNode) : []
    // Never write menuPath from a notification emitted while menuNode is
    // evaluating. Resolve/validate after the binding graph has settled.
    onMenuNodeChanged: Qt.callLater(validateMenu)
    onMenuEntriesChanged: Qt.callLater(validateMenu)
    onGenerationChanged: Qt.callLater(validateMenu)
    function validateMenu() {
        if (menuPath.length > 0 && (menuGeneration !== generation
                || menuNode === null || menuEntries.length === 0))
            closeMenu()
    }
    onMenuAvailableChanged: { if (!menuAvailable) closeMenu() }
    onTransitionPendingChanged: { if (transitionPending) closeMenu() }
    onMenuOpenChanged: {
        if (controller && controller.ownerId === "documents")
            console.info(menuOpen ? "INGE_DOC_DOCK_MORE_OPEN" : "INGE_DOC_DOCK_MORE_CLOSE")
    }

    function visibleChildren(action) {
        var source = action && action.children ? action.children : []
        var result = []
        for (var i = 0; i < source.length; ++i)
            if (source[i].visible !== false)
                result.push(source[i])
        return result
    }

    function haptic(intent) {
        if (flow && typeof flow.triggerHaptic === "function")
            flow.triggerHaptic(intent)
    }

    function openMenu(actionId, anchorItem) {
        if (!menuAvailable || transitionPending || !router || router.busy)
            return false
        var p = anchorItem ? anchorItem.mapToItem(root, anchorItem.width / 2, 0) : Qt.point(width / 2, 0)
        menuAnchorX = p.x
        menuDirection = 1
        menuGeneration = generation
        menuPath = [String(actionId)]
        if (!menuOpen) {
            menuPath = []
            return false
        }
        haptic("medium")
        console.info("INGE_DOCK_MENU open action=" + actionId + " generation=" + generation)
        return true
    }

    function pushMenu(actionId) {
        menuDirection = 1
        menuPath = menuPath.concat([String(actionId)])
        haptic("selection")
    }

    function popMenu() {
        if (menuPath.length <= 1) {
            closeMenu()
            return
        }
        menuDirection = -1
        menuPath = menuPath.slice(0, menuPath.length - 1)
        haptic("selection")
    }

    function closeMenu() {
        if (menuPath.length === 0)
            return
        menuPath = []
    }

    // Android Back: one level per press, then closes. Returns true if consumed.
    function handleBack() {
        if (menuPath.length === 0)
            return false
        popMenu()
        return true
    }

    function activateMenuEntry(entry) {
        if (!entry || entry.enabled !== true || !router || menuGeneration !== generation)
            return
        // Inside a menu an entry with children navigates one level down.
        if (visibleChildren(entry).length > 0) {
            pushMenu(entry.id)
            return
        }
        var dispatchGeneration = generation
        closeMenu()
        if (router.dispatch(String(entry.id), dispatchGeneration))
            haptic("light")
    }

    // Geometry (dp).
    readonly property real mainHeight: 54
    readonly property real slotSize: 46
    readonly property real iconSize: 22
    readonly property real actionGap: 8
    readonly property real sidePadding: 10
    readonly property real selectedSize: 46
    readonly property real searchHeight: 26
    readonly property real searchMinWidth: 78
    readonly property real searchGap: 10
    readonly property real coreSize: 49
    readonly property real coreGap: 16
    readonly property real bottomGap: 8
    readonly property int motionDuration: flow && flow.motionAllowed ? 400 : 0

    // LiquidTabBar.swift: selection identity is shared across layouts.
    // glass_spring.dart LgSpring.smooth: response=.40, dampingFraction=1,
    // unit mass, stiffness=(2*pi/response)^2. Approximate its normalized
    // critically damped step with four cubic Hermite segments, once only.
    readonly property var motionCurve: criticalSpringCurve()
    function criticalSpringCurve() {
        var a = 2 * Math.PI
        var norm = 1 - (1 + a) * Math.exp(-a)
        function position(t) { return (1 - (1 + a * t) * Math.exp(-a * t)) / norm }
        function slope(t) { return a * a * t * Math.exp(-a * t) / norm }
        var curve = []
        for (var i = 0; i < 4; ++i) {
            var t0 = i / 4
            var t1 = (i + 1) / 4
            var step = (t1 - t0) / 3
            curve.push(t0 + step, position(t0) + slope(t0) * step,
                       t1 - step, position(t1) - slope(t1) * step,
                       t1, position(t1))
        }
        return curve
    }

    readonly property real mainWidth: sidePadding * 2
                                      + Math.max(1, mainActions.length) * slotSize
                                      + Math.max(0, mainActions.length - 1) * actionGap
    readonly property real groupWidth: capsule.width + coreGap + coreSize
    readonly property real capsuleY: searchAction ? searchHeight + searchGap : 0
    readonly property real visualBandHeight:
        capsuleY + mainHeight + bottomGap + bottomSafeInset
    readonly property real reservedHeight: shown ? visualBandHeight : 0

    // Material tokens consumed by the glass shader. The backdrop provides the
    // colour; tint and rim only shape it. fallbackGlass is used where the
    // backdrop is a native surface Qt cannot sample (Flutter, Earth WebView).
    // Tintes del material derivados de INGEMA Deep por alpha (identidad sin
    // opacar el vidrio). Blur, rim, refraccion y shader no cambian.
    readonly property color glassTint: onDarkMaterial ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
    readonly property color fallbackGlass: onDarkMaterial ? Qt.rgba(0.30, 0.33, 0.38, 0.18) : Qt.rgba(0.97, 0.98, 1.0, 0.14)
    readonly property real rimLight: onDarkMaterial ? 0.30 : 0.34
    readonly property real rimShade: onDarkMaterial ? 0.08 : 0.07
    readonly property real rimSheen: onDarkMaterial ? 0.06 : 0.03
    readonly property real edgeContrast: onDarkMaterial ? 0.0 : 0.05
    readonly property real glassSaturation: 1.22
    readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, onDarkMaterial ? 0.22 : 0.10)
    // Iconografia INGEMA: Deep en reposo, Blue activo; en material oscuro
    // blanco y el tinte derivado de Blue (contraste >= 6:1).
    property color iconColor: onDarkMaterial ? "#eef2f6" : root.flow.colors.ingemaDeep
    property color iconActiveColor: onDarkMaterial ? root.flow.colors.ingemaBlueTint : root.flow.colors.ingemaBlue
    property color secondaryTextColor: onDarkMaterial ? Qt.rgba(0.93, 0.95, 0.97, 0.82) : Qt.rgba(0.0824, 0.102, 0.1882, 0.78)
    property color coreColor: onDarkMaterial ? root.flow.colors.ingemaBlueTint : root.flow.colors.ingemaBlue
    Behavior on iconColor { ColorAnimation { duration: 180 } }
    Behavior on iconActiveColor { ColorAnimation { duration: 180 } }
    Behavior on secondaryTextColor { ColorAnimation { duration: 180 } }
    Behavior on coreColor { ColorAnimation { duration: 180 } }

    // One icon family inside the dock (heroicons outline).
    readonly property var heroAliases: ({
        "profile.user": "user",
        "system.back": "chevron-left",
        "system.forward": "chevron-right",
        "action.edit": "pencil-square",
        "action.addStratum": "layers",
        "action.filter": "filter",
        "status.sync": "sync",
        "nav.map": "map"
    })

    function iconSource(name) {
        var hero = heroAliases[String(name || "")] || IconCatalog.heroSemanticIcons[String(name || "")]
        return IconCatalog.heroiconSvg(hero, hero === "home" ? 1.4 : 1.5)
    }

    function opticalSize(name) {
        // Wide/complex outlines need less mass than the narrow user outline.
        return name === "nav.home" || name === "nav.settings" ? 21 : iconSize
    }

    function slotX(index) {
        return sidePadding + index * (slotSize + actionGap)
    }

    height: reservedHeight
    visible: shown

    function syncNativeBand() {
        if (controller)
            controller.setNativeBand(0)
    }
    onReservedHeightChanged: syncNativeBand()

    // Scalar geometry only; Java reuses its Path/Region/Runnable while the
    // existing QML animation moves the apertures. No native animation engine.
    function syncNativeGeometry() {
        if (!controller || !group || !capsule || !searchAccessory)
            return
        var ratio = Screen.devicePixelRatio
        controller.setNativeGeometry(group.x * ratio,
            shown && visible ? capsule.width * ratio : 0,
            mainHeight * ratio, (bottomGap + bottomSafeInset) * ratio,
            coreSize * ratio, coreGap * ratio,
            searchAccessory.opacity > 0 ? searchMinWidth * ratio : 0,
            searchHeight * ratio, searchGap * ratio)
    }
    onVisibleChanged: syncNativeGeometry()
    onBottomSafeInsetChanged: syncNativeGeometry()
    onWidthChanged: syncNativeGeometry()
    readonly property real materialPosition: group.x + capsule.width + height + width + y

    // Keyed by action.id so persistent actions keep their delegate and the
    // list transitions express ENTER / EXIT / MOVE.
    ListModel { id: actionModel }

    function syncActions() {
        var next = mainActions
        for (var i = actionModel.count - 1; i >= 0; --i) {
            var keep = false
            for (var k = 0; k < next.length; ++k) {
                if (String(next[k].id) === actionModel.get(i).actionId) {
                    keep = true
                    break
                }
            }
            if (!keep)
                actionModel.remove(i)
        }
        for (var j = 0; j < next.length; ++j) {
            var action = next[j]
            var entry = {
                actionId: String(action.id),
                label: String(action.label),
                icon: String(action.icon),
                actionEnabled: action.enabled === true,
                actionSelected: action.selected === true,
                badge: String(action.badge || ""),
                hasCommand: String(action.command || "").length > 0,
                hasChildren: visibleChildren(action).length > 0
            }
            var index = -1
            for (var m = 0; m < actionModel.count; ++m) {
                if (actionModel.get(m).actionId === entry.actionId) {
                    index = m
                    break
                }
            }
            if (index < 0) {
                actionModel.insert(j, entry)
            } else {
                if (index !== j)
                    actionModel.move(index, j, 1)
                actionModel.set(j, entry)
            }
        }
    }
    onMainActionsChanged: syncActions()
    Component.onCompleted: {
        updateMaterialTone()
        syncActions()
        syncNativeBand()
        syncNativeGeometry()
    }

    // One glass engine for every dock surface: local backdrop capture (item
    // rect + small margin) refracted, frosted and lit by liquidglass.frag.
    // Host-provided strip behind the dock on native surfaces (bottom 160 css px
    // of the page, full width, same as the capture).
    component BackdropFrame: Image {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 160
        z: -1
        fillMode: Image.Stretch
        smooth: true
        cache: false
        asynchronous: false
    }
    BackdropFrame {
        id: nativeBackdropA
        visible: root.nativeSurface && root.backdropFront === 0 && status === Image.Ready
        onStatusChanged: root.promoteBackdrop(nativeBackdropA, 0)
    }
    BackdropFrame {
        id: nativeBackdropB
        visible: root.nativeSurface && root.backdropFront === 1 && status === Image.Ready
        onStatusChanged: root.promoteBackdrop(nativeBackdropB, 1)
    }

    Item {
        id: group
        width: root.groupWidth
        height: root.visualBandHeight - root.bottomSafeInset
        x: Math.round((root.width - root.groupWidth) / 2)
        onXChanged: root.syncNativeGeometry()

        Item {
            id: capsule
            y: root.capsuleY
            width: root.mainWidth
            height: root.mainHeight
            onWidthChanged: root.syncNativeGeometry()
            Behavior on width { NumberAnimation { duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve } }

            MouseArea { anchors.fill: parent }
            LiquidGlassSurface { id: capsuleGlass; anchors.fill: parent; tokens: root; frost: 4.5; lowCostTaps: 4; captureScale: root.lowCostCaptureScale; surfaceName: "main" }

            // Single persistent selection lens: the same glass, slightly
            // stronger. It travels by action.id.
            LiquidGlassSurface {
                id: selection
                surfaceName: "selected"
                tokens: root
                captureScale: root.lowCostCaptureScale
                strength: 1.2
                lens: 2.2
                frost: 2.5
                magnify: 0.06
                elevation: false
                width: root.selectedSize
                height: root.selectedSize
                y: (root.mainHeight - height) / 2
                x: root.slotX(Math.max(0, root.selectedIndex)) + (root.slotSize - width) / 2
                opacity: root.selectedIndex >= 0 ? 1.0 : 0.0
                // Fully faded selection stops capturing and shading.
                visible: opacity > 0
                Behavior on x { NumberAnimation { duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve } }
                Behavior on opacity { NumberAnimation { duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve } }
            }

            ListView {
                id: actionList
                x: root.sidePadding
                y: (root.mainHeight - root.slotSize) / 2
                width: capsule.width - root.sidePadding * 2
                height: root.slotSize
                orientation: ListView.Horizontal
                spacing: root.actionGap
                interactive: false
                model: actionModel

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                    NumberAnimation { property: "scale"; to: 0.96; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                }
                displaced: Transition {
                    NumberAnimation { property: "x"; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                }
                move: Transition {
                    NumberAnimation { property: "x"; duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve }
                }

                delegate: Item {
                    id: slot
                    required property string actionId
                    required property string label
                    required property string icon
                    required property bool actionEnabled
                    required property bool actionSelected
                    required property string badge
                    required property bool hasCommand
                    required property bool hasChildren
                    property bool exiting: false
                    ListView.onRemove: exiting = true
                    readonly property bool canTap: !exiting && actionEnabled && !root.transitionPending && !root.router.busy

                    width: root.slotSize
                    height: root.slotSize

                    Item {
                        anchors.fill: parent
                        opacity: slot.actionEnabled ? 1.0 : 0.38
                        // Deeper 3D Touch press only for the action that opens a peek
                        // (Calicatas "information" -> calicatas.info); the rest keep 0.97.
                        scale: tap.pressed ? (root.peekActionIds.indexOf(slot.actionId) >= 0
                                              ? root.flow.compactPressScale : 0.97) : 1.0
                        Behavior on scale { NumberAnimation { duration: root.peekActionIds.indexOf(slot.actionId) >= 0 ? 70 : 90; easing.type: Easing.OutQuad } }

                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: root.opticalSize(slot.icon)
                            height: width
                            anchors.verticalCenterOffset: slot.icon === "nav.home" ? -0.3 : 0
                            flow: root.flow
                            name: slot.icon
                            sourceOverride: root.iconSource(slot.icon)
                            active: slot.actionSelected
                            scale: 1
                            pulseOnActive: false
                            tintColor: root.iconColor
                            activeTintColor: root.iconActiveColor
                            inactiveOpacity: 1
                        }

                        // Discreet affordance: this action holds more actions.
                        Rectangle {
                            visible: slot.hasChildren
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 4
                            height: 4
                            radius: 2
                            color: root.menuOwnerId === slot.actionId ? root.iconActiveColor
                                                                      : root.secondaryTextColor
                            opacity: 0.55
                        }

                        Rectangle {
                            visible: slot.badge.length > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: Math.max(16, badgeText.implicitWidth + 6)
                            height: 16
                            radius: 8
                            color: root.iconActiveColor
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: slot.badge
                                color: "#ffffff"
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Tap runs the primary command; a branch without command
                    // opens its children. Press-and-hold always opens them
                    // (Android equivalent of 3D Touch). A handled hold does
                    // not also emit clicked.
                    MouseArea {
                        id: tap
                        property int pressGeneration: -1
                        anchors.fill: parent
                        enabled: slot.canTap
                        pressAndHoldInterval: root.menuHoldInterval
                        onPressed: pressGeneration = root.generation
                        onPressAndHold: function(mouse) {
                            if (slot.hasChildren && pressGeneration === root.generation)
                                root.openMenu(slot.actionId, slot)
                            else
                                mouse.accepted = false
                        }
                        onClicked: {
                            if (slot.hasCommand)
                                root.router.dispatch(slot.actionId, pressGeneration)
                            else if (slot.hasChildren && pressGeneration === root.generation)
                                root.openMenu(slot.actionId, slot)
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: slot.label
                    Accessible.description: slot.hasChildren ? qsTr("Mantén pulsado para más acciones") : ""
                    Accessible.checkable: true
                    Accessible.checked: slot.actionSelected
                    Accessible.onPressAction: {
                        if (!slot.canTap)
                            return
                        if (slot.hasCommand)
                            root.router.dispatch(slot.actionId, root.generation)
                        else if (slot.hasChildren)
                            root.openMenu(slot.actionId, slot)
                    }
                }
            }
        }

        // Search accessory, centred on the main capsule.
        Item {
            id: searchAccessory
            readonly property bool available: root.searchAction !== null
                                              && root.searchAction.enabled === true
            width: root.searchMinWidth
            height: root.searchHeight
            x: Math.round(capsule.x + capsule.width / 2 - width / 2)
            y: root.capsuleY - root.searchHeight - root.searchGap
            opacity: root.searchAction ? 1 : 0
            visible: opacity > 0
            onOpacityChanged: root.syncNativeGeometry()
            Behavior on opacity { NumberAnimation { duration: root.motionDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.motionCurve } }
            scale: (0.96 + 0.04 * opacity) * (searchTap.pressed ? 0.97 : 1.0)
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

            MouseArea { anchors.fill: parent }
            LiquidGlassSurface { anchors.fill: parent; tokens: root; strength: 0.55; lens: 0.8; frost: 3; elevation: false; captureScale: root.lowCostCaptureScale; surfaceName: "search" }

            Row {
                id: searchRow
                anchors.centerIn: parent
                spacing: 5
                opacity: searchAccessory.available ? 1.0 : 0.45

                Components.FlowIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    flow: root.flow
                    name: "action.search"
                    sourceOverride: root.iconSource("action.search")
                    pulseOnActive: false
                    tintColor: root.secondaryTextColor
                    inactiveOpacity: 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Buscar")
                    color: root.secondaryTextColor
                    font.pixelSize: 11
                }
            }

            MouseArea {
                id: searchTap
                property int pressGeneration: -1
                anchors.fill: parent
                enabled: searchAccessory.available && !root.transitionPending && !root.router.busy
                onPressed: pressGeneration = root.generation
                onClicked: {
                    if (root.searchAction)
                        root.router.dispatch(root.searchAction.id, pressGeneration)
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: root.searchAction ? root.searchAction.label : qsTr("Buscar")
        }

        // InGe Core: global capability, separate from any context.
        Item {
            id: coreAccessory
            width: root.coreSize
            height: root.coreSize
            x: capsule.x + capsule.width + root.coreGap
            y: root.capsuleY + (root.mainHeight - height) / 2
            scale: coreTap.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

            MouseArea { anchors.fill: parent }
            LiquidGlassSurface { anchors.fill: parent; tokens: root; strength: 0.7; frost: 4; magnify: 0.03; elevation: false; captureScale: root.lowCostCaptureScale; surfaceName: "ai" }

            Components.FlowIcon {
                anchors.centerIn: parent
                width: 22
                height: 22
                flow: root.flow
                name: "action.search"
                sourceOverride: IconCatalog.heroiconSvg("sparkles")
                pulseOnActive: false
                tintColor: root.coreColor
                inactiveOpacity: 1
                opacity: root.coreAvailable ? 1.0 : 0.55
            }

            MouseArea {
                id: coreTap
                anchors.fill: parent
                enabled: root.coreAvailable && !root.router.busy
                onClicked: root.router.dispatchGlobal("inge.core")
            }

            Accessible.role: Accessible.Button
            Accessible.name: root.coreAvailable ? qsTr("Abrir InGe Core")
                                                : qsTr("InGe Core no disponible")
        }
    }

    // ---- Context menu layer ------------------------------------------------
    // Spans the whole shell (the dock is anchored to the shell bottom) so a
    // tap anywhere outside the panel closes the menu. Only one branch panel.
    Item {
        id: menuLayer
        readonly property real edgeMargin: 12
        readonly property real rowHeight: 50
        readonly property real headerHeight: 42
        readonly property real verticalPadding: 6
        // Extra gap above an entry that starts a group (see startsGroup).
        readonly property real groupGap: 9
        readonly property int menuMotion: root.flow && root.flow.motionAllowed ? 240 : 0
        // Panel open/close and branch swap timings (opacity/scale/translate only).
        readonly property int openMotion: root.flow && root.flow.motionAllowed ? 200 : 0
        readonly property int closeMotion: root.flow && root.flow.motionAllowed ? 150 : 0
        readonly property int swapMotion: root.flow && root.flow.motionAllowed ? 95 : 0
        // Entries kept while the panel fades out after the path is cleared.
        property var shownEntries: []
        property string shownTitle: ""
        property int shownDepth: 0
        // True between the outgoing and incoming halves of a branch swap.
        property bool branchSwapPending: false
        readonly property bool entriesHaveIcons: {
            for (var i = 0; i < shownEntries.length; ++i)
                if (String(shownEntries[i].icon || "").length > 0)
                    return true
            return false
        }
        // The controller only forwards semantic keys (no colours/geometry), so
        // row styling derives from them: close-type icons open the closing
        // group (gap + divider) and a few action icons get a soft accent chip.
        readonly property var closeIcons: ["calgen.close", "system.close", "calicatas.closeTab"]
        function startsGroup(entries, i) {
            return i > 0 && i < entries.length && closeIcons.indexOf(String(entries[i].icon || "")) >= 0
        }
        function accentFor(entry) {
            var dark = root.onDarkMaterial
            // Acentos de identidad INGEMA (InGe Drive incluido): Blue para
            // acciones, Navy para carpetas y Green para confirmacion/sincronia.
            var c = root.flow.colors
            if (root.controller && root.controller.ownerId === "documents")
                return String(dark ? c.ingemaBlueTint : c.ingemaBlue)
            switch (String(entry.icon || "")) {
            case "action.add": return String(dark ? c.ingemaBlueTint : c.ingemaBlue)
            case "documents.folder": return String(dark ? c.ingemaPaperSecondary : c.ingemaNavy)
            case "action.check": return String(dark ? c.ingemaGreenTint : c.ingemaGreen)
            case "status.sync": return String(dark ? c.ingemaGreenTint : c.ingemaGreen)
            default: return ""
            }
        }
        readonly property int groupBreaks: {
            var n = 0
            for (var i = 1; i < shownEntries.length; ++i)
                if (startsGroup(shownEntries, i))
                    ++n
            return n
        }

        x: 0
        y: -root.y
        width: root.width
        height: root.parent ? root.parent.height : root.height
        z: 20
        visible: menuPanel.opacity > 0.001

        function refresh() {
            if (!root.menuOpen || branchSwapPending)
                return
            shownEntries = root.menuEntries
            shownTitle = String(root.menuNode.label || "")
            shownDepth = root.menuPath.length
        }
        // Midpoint of branchSwap: the outgoing level has faded out.
        function applyBranch() {
            branchSwapPending = false
            refresh()
        }
        Connections {
            target: root
            function onMenuEntriesChanged() { Qt.callLater(menuLayer.refresh) }
            function onMenuPathChanged() {
                Qt.callLater(menuLayer.refreshBranch)
            }
        }
        function refreshBranch() {
                var wasDepth = menuLayer.shownDepth
                // Level change inside an already visible panel: fade/slide the
                // current level out, swap entries, slide the new level in.
                if (root.menuOpen && wasDepth > 0 && wasDepth !== root.menuPath.length
                        && menuPanel.opacity > 0.5) {
                    menuLayer.branchSwapPending = true
                    branchSwap.restart()
                    return
                }
                menuLayer.refresh()
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.menuOpen ? (root.onDarkMaterial ? 0.16 : 0.07) : 0
            Behavior on opacity { NumberAnimation { duration: menuLayer.menuMotion; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.menuOpen
            onPressed: function(mouse) { root.closeMenu(); mouse.accepted = true }
        }

        Item {
            id: menuPanel
            readonly property int rowCount: menuLayer.shownEntries.length
            readonly property real header: menuLayer.shownDepth > 1 ? menuLayer.headerHeight : 0
            readonly property real maxHeight: Math.max(menuLayer.rowHeight * 2,
                root.y - 8 - (menuLayer.edgeMargin + 56))
            readonly property bool growsLeft: root.menuAnchorX > menuLayer.width / 2
            width: Math.min(264, menuLayer.width - menuLayer.edgeMargin * 2)
            height: Math.min(maxHeight, header + rowCount * menuLayer.rowHeight
                             + menuLayer.groupBreaks * menuLayer.groupGap + menuLayer.verticalPadding * 2)
            // Born next to the pressed icon; flips to grow leftwards near the
            // right edge and is clamped inside the screen gutters.
            x: Math.max(menuLayer.edgeMargin,
                        Math.min(menuLayer.width - width - menuLayer.edgeMargin,
                                 growsLeft ? root.menuAnchorX + 28 - width : root.menuAnchorX - 28))
            y: root.y - 10 - height
            // Open: opacity 0→1, scale 0.975→1, +8→0 (200 ms OutCubic).
            // Close (any route: entry, Back, tap outside, context change clears
            // menuPath): opacity →0, scale →0.985, →+5 (150 ms).
            opacity: root.menuOpen ? 1 : 0
            transform: [
                Scale {
                    origin.x: Math.max(0, Math.min(menuPanel.width, root.menuAnchorX - menuPanel.x))
                    origin.y: menuPanel.height
                    xScale: root.menuOpen ? 1 : (menuPanel.opacity > 0.5 ? 0.985 : 0.975)
                    yScale: xScale
                    Behavior on xScale { NumberAnimation { duration: root.menuOpen ? menuLayer.openMotion : menuLayer.closeMotion; easing.type: Easing.OutCubic } }
                },
                Translate {
                    y: root.menuOpen ? 0 : (menuPanel.opacity > 0.5 ? 5 : 8)
                    Behavior on y { NumberAnimation { duration: root.menuOpen ? menuLayer.openMotion : menuLayer.closeMotion; easing.type: Easing.OutCubic } }
                }
            ]
            Behavior on opacity { NumberAnimation { duration: root.menuOpen ? menuLayer.openMotion : menuLayer.closeMotion; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: menuLayer.openMotion; easing.type: Easing.OutCubic } }

            // Swallows presses inside the panel so they never reach the scrim.
            MouseArea { anchors.fill: parent }

            // Menu instance only: calmer lens/frost than before; Dock defaults untouched.
            LiquidGlassSurface {
                anchors.fill: parent
                tokens: root
                captureScale: root.lowCostCaptureScale
                cornerRadius: 22
                strength: 0.75
                lens: 0.25
                frost: 6
                lowCostTaps: 4
                surfaceName: "menu"
                positionKey: menuPanel.x + menuPanel.y
                visible: menuLayer.visible
            }
            // Legibility veil over the same material (no second glass engine).
            Rectangle {
                anchors.fill: parent
                radius: 22
                color: root.onDarkMaterial ? Qt.rgba(0.0824, 0.102, 0.1882, 0.46) : Qt.rgba(0.98, 0.99, 1.0, 0.62)
                border.width: 1
                border.color: root.onDarkMaterial ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.45)
            }

            Item {
                id: branchContent
                anchors.fill: parent
                anchors.topMargin: menuLayer.verticalPadding
                anchors.bottomMargin: menuLayer.verticalPadding
                clip: true
                property real slide: 0

                // Más ⇄ main: current level out (opacity →0, x →∓12), entries
                // swapped at the midpoint, new level in (x ±12 →0). ~190 ms total.
                SequentialAnimation {
                    id: branchSwap
                    ParallelAnimation {
                        NumberAnimation { target: branchContent; property: "opacity"; to: 0.0; duration: menuLayer.swapMotion; easing.type: Easing.InCubic }
                        NumberAnimation { target: branchContent; property: "slide"; to: -12 * root.menuDirection; duration: menuLayer.swapMotion; easing.type: Easing.InCubic }
                    }
                    ScriptAction { script: menuLayer.applyBranch() }
                    ParallelAnimation {
                        NumberAnimation { target: branchContent; property: "opacity"; from: 0.0; to: 1.0; duration: menuLayer.swapMotion; easing.type: Easing.OutCubic }
                        NumberAnimation { target: branchContent; property: "slide"; from: 12 * root.menuDirection; to: 0; duration: menuLayer.swapMotion; easing.type: Easing.OutCubic }
                    }
                }

                // Branch header: current level, one tap goes back one level.
                Item {
                    id: branchHeader
                    x: branchContent.slide
                    width: parent.width
                    height: menuPanel.header
                    visible: height > 0

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Components.FlowIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            flow: root.flow
                            name: "system.back"
                            sourceOverride: root.iconSource("system.back")
                            pulseOnActive: false
                            tintColor: root.secondaryTextColor
                            inactiveOpacity: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: menuPanel.width - 60
                            text: menuLayer.shownTitle
                            color: root.secondaryTextColor
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        height: 1
                        color: Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 0.14)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.popMenu()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Volver a %1").arg(menuLayer.shownTitle)
                    Accessible.onPressAction: root.popMenu()
                }

                Flickable {
                    id: entryFlick
                    x: branchContent.slide
                    y: branchHeader.height
                    width: parent.width
                    height: parent.height - branchHeader.height
                    contentHeight: entryColumn.height
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Column {
                        id: entryColumn
                        width: entryFlick.width

                        Repeater {
                            model: menuLayer.shownEntries
                            delegate: Item {
                                id: entryRow
                                required property var modelData
                                required property int index
                                readonly property bool entryEnabled: modelData.enabled === true
                                readonly property bool entryBranch: root.visibleChildren(modelData).length > 0
                                readonly property bool entryDestructive: modelData.destructive === true
                                readonly property string accentHex: menuLayer.accentFor(modelData)
                                readonly property real groupTop: menuLayer.startsGroup(menuLayer.shownEntries, entryRow.index)
                                                                 ? menuLayer.groupGap : 0
                                readonly property color labelColor: entryDestructive
                                    ? (root.onDarkMaterial ? "#ff8a80" : "#c9302c") : root.iconColor
                                // Soft chip tint from accentFor(); destructive entries use
                                // their red label colour, the rest stay neutral.
                                readonly property color chipColor: entryDestructive ? labelColor
                                    : (accentHex.length > 0 ? accentHex : root.iconColor)
                                width: entryColumn.width
                                height: menuLayer.rowHeight + groupTop

                                Rectangle {
                                    visible: entryRow.groupTop > 0
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    y: Math.round(entryRow.groupTop / 2)
                                    height: 1
                                    color: Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 0.16)
                                }

                                Item {
                                    id: entryBody
                                    y: entryRow.groupTop
                                    width: parent.width
                                    height: menuLayer.rowHeight
                                    scale: entryTap.pressed ? 0.985 : 1
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        anchors.topMargin: 1
                                        anchors.bottomMargin: 1
                                        radius: 12
                                        color: root.iconColor
                                        opacity: entryTap.pressed ? 0.08 : 0
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12
                                        // The current choice (selected, not selectable) stays legible.
                                        opacity: entryRow.entryEnabled ? 1.0
                                                 : (entryRow.modelData.selected === true ? 0.85 : 0.38)

                                        Rectangle {
                                            visible: menuLayer.entriesHaveIcons
                                            width: 32
                                            height: 32
                                            radius: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Qt.rgba(entryRow.chipColor.r, entryRow.chipColor.g, entryRow.chipColor.b,
                                                           entryRow.accentHex.length > 0 || entryRow.entryDestructive ? 0.14 : 0.07)
                                            Components.FlowIcon {
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                visible: String(entryRow.modelData.icon || "").length > 0
                                                flow: root.flow
                                                name: String(entryRow.modelData.icon || "")
                                                sourceOverride: root.iconSource(entryRow.modelData.icon)
                                                pulseOnActive: false
                                                tintColor: entryRow.chipColor
                                                inactiveOpacity: 1
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: entryRow.width - (menuLayer.entriesHaveIcons ? 44 : 0) - 12 - 40
                                            text: String(entryRow.modelData.label || entryRow.modelData.id)
                                            color: entryRow.labelColor
                                            font.pixelSize: 15
                                            font.weight: entryRow.entryBranch ? Font.Normal : Font.Medium
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Trailing mark: chevron for a sub-branch, check for the selected entry.
                                    Components.FlowIcon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        height: 16
                                        visible: entryRow.entryBranch || entryRow.modelData.selected === true
                                        opacity: entryRow.entryEnabled || entryRow.modelData.selected === true ? 0.8 : 0.3
                                        flow: root.flow
                                        name: entryRow.entryBranch ? "system.forward" : "action.check"
                                        sourceOverride: root.iconSource(entryRow.entryBranch ? "system.forward" : "action.check")
                                        pulseOnActive: false
                                        tintColor: entryRow.entryBranch ? root.secondaryTextColor : root.iconActiveColor
                                        inactiveOpacity: 1
                                    }
                                }

                                Rectangle {
                                    visible: entryRow.index < menuLayer.shownEntries.length - 1
                                             && !menuLayer.startsGroup(menuLayer.shownEntries, entryRow.index + 1)
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: menuLayer.entriesHaveIcons ? 56 : 12
                                    anchors.rightMargin: 12
                                    height: 1
                                    color: Qt.rgba(root.iconColor.r, root.iconColor.g, root.iconColor.b, 0.08)
                                }

                                MouseArea {
                                    id: entryTap
                                    anchors.fill: parent
                                    enabled: root.menuOpen && entryRow.entryEnabled
                                    onClicked: root.activateMenuEntry(entryRow.modelData)
                                }

                                Accessible.role: entryRow.entryBranch ? Accessible.ButtonMenu : Accessible.MenuItem
                                Accessible.name: String(entryRow.modelData.label || entryRow.modelData.id)
                                Accessible.checkable: entryRow.modelData.selected === true
                                Accessible.checked: entryRow.modelData.selected === true
                                Accessible.onPressAction: {
                                    if (root.menuOpen && entryRow.entryEnabled)
                                        root.activateMenuEntry(entryRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
