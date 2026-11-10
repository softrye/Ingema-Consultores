import QtQuick
import InGe.CoreFlow 3.0 as CoreFlowModule

// Liquid Glass oficial del Dock para paneles, hojas y menús (2026-11-02).
// Única implementación: GlassSurface (shaders/glass.frag) con el preset ÚNICO
// HomeScreen.liquidGlassMaterial (valores dockGlass*), publicado en InGeCoreFlow.
// Claro: igual que el Dock; oscuro: tinte negro al 12 %. LOW/ULTRA_LOW o sin
// textura lista: el respaldo neutro de GlassSurface (antes DockGlassFallback).
// Se coloca como primer hijo del panel (debajo de textos e iconos).
Item {
    id: panel
    property var glassUi: null                  // backdrop + glassTexture + glassTick (como GlassSurface.ui)
    property real radius: 18
    property real u: 1
    property var material: CoreFlowModule.InGeCoreFlow.liquidGlassMaterial
    // El Dock pasa home.dockGlassTint (transparente también en oscuro).
    property color tint: material ? material.tint : Qt.rgba(0, 0, 0, 0)
    // false: en LOW conserva el vidrio sin refracción (Dock aprobado) en lugar del respaldo.
    property bool lowFallback: true
    // Compatibilidad: el tema, la skin y el movimiento reducido ya los decide el material.
    property bool dark: false
    property bool halloween: false
    property bool reducedMotion: false
    readonly property bool textureReady: surface.textureReady
    readonly property bool fallbackOn: surface.fallbackOn
    // Perfil «Extrema»: gotas al tocar o arrastrar (Dock y botón +) y gel (cápsula -> panel).
    property bool liquidTouch: false
    property real gel: 0
    readonly property bool extremeOn: surface.extreme && !reducedMotion && !surface.fallbackOn

    anchors.fill: parent
    z: -1

    GlassSurface {
        id: surface
        ui: panel.glassUi
        material: panel.material
        tint: panel.tint
        lowFallback: panel.lowFallback
        radius: panel.radius
        margin: 10 * panel.u
        reducedMotion: panel.reducedMotion
        gel: panel.gel
    }

    // ---- Gotas (metaballs): hasta 8, la más reciente primero; se disipan con inercia.
    property var dropState: []
    function publishDrops() {
        var out = []
        for (var i = 0; i < dropState.length; ++i) {
            var d = dropState[i]
            out.push(Qt.vector4d(d.x, d.y, d.r, d.life))
        }
        surface.drops = out
    }
    function spawnDrop(x, y, vx, vy) {
        if (!extremeOn) return
        var list = dropState.slice(0, 7)
        list.unshift({ x: x, y: y, vx: vx, vy: vy, life: 1, r: 2 * u,
                       target: (9 + Math.random() * 7) * u })
        dropState = list
        publishDrops()
    }
    onExtremeOnChanged: if (!extremeOn && dropState.length) { dropState = []; publishDrops() }
    FrameAnimation {
        running: panel.dropState.length > 0
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            var damp = Math.pow(0.03, dt)
            var out = []
            for (var i = 0; i < panel.dropState.length; ++i) {
                var d = panel.dropState[i]
                d.life -= dt / 1.15
                if (d.life <= 0) continue
                // Crece rápido, se encoge al disiparse; inercia del arrastre.
                d.r += (d.target * (0.45 + 0.55 * d.life) - d.r) * Math.min(1, dt * 14)
                d.x += d.vx * dt; d.y += d.vy * dt
                d.vx *= damp; d.vy *= damp
                // Deriva hacia el borde más cercano: la gota se funde con el contorno.
                d.vy += (d.y < panel.height / 2 ? -1 : 1) * 70 * panel.u * dt
                out.push(d)
            }
            panel.dropState = out
            panel.publishDrops()
        }
    }
    Item {                                       // capa de contacto encima del contenido: no roba clics
        parent: panel.parent
        anchors.fill: parent
        z: 1000
        enabled: panel.liquidTouch && panel.extremeOn
        PointHandler {
            id: touch
            property point last: Qt.point(0, 0)
            onActiveChanged: if (active) {
                last = point.position
                panel.spawnDrop(last.x, last.y, 0, 0)
            }
            onPointChanged: {
                if (!active) return
                var p = point.position
                if (Math.abs(p.x - last.x) + Math.abs(p.y - last.y) < 14 * panel.u) return
                last = p
                panel.spawnDrop(p.x, p.y, 0.35 * point.velocity.x, 0.35 * point.velocity.y)
            }
        }
    }
}
