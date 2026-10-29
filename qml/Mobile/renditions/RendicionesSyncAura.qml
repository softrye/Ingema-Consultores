import QtQuick
import QtQuick.Shapes
import "RStyle.js" as S

// Auras ambientales del fondo blanco de Rendiciones: DOS luces independientes,
// siempre presentes y en movimiento mientras Rendiciones está visible. Sus
// colores representan sólo el estado real de sincronización:
//   synced  -> A azul corporativo #0654A2 + B verde corporativo #486426
//   error   -> A azul marino #1C2D50      + B rojo de alerta #B42334
//   offline -> MISMA identidad roja que error (sin red o servidor inaccesible);
//              modo propio para no confundir desconexión con conflicto en el código
//   attention -> A azul corporativo + B amarillo de atención #F2B21B: incidencia
//              localizada y corregible (gasto incompleto, sustento pendiente...)
//   Prioridad (la decide RenditionsApp con el modelo de diagnóstico): rojo >
//   amarillo > verde; el amarillo nunca tapa un error y el verde nunca tapa nada.
//   unknown / pending / syncing -> A azul corporativo + B gris pizarra neutro
//              (dos luces distinguibles, sin anunciar éxito ni error)
//
// «Pelea»: dos diagonales que se cruzan en X (coordenadas relativas a la
// pantalla). A va de arriba-izquierda a abajo-derecha y vuelve; B, en
// oposición de fase, va de abajo-izquierda a arriba-derecha y vuelve. Cuando
// una está arriba la otra está abajo (separación, ~45 % del ciclo); ambas
// avanzan hacia el centro, se superponen (~30 %), cruzan sus posiciones
// (oposición) y se separan de nuevo; dos encuentros por ciclo. Todas las funciones usan cos/sin de t y 2t, con t en [0, 2π]:
// el final del ciclo coincide exactamente con el inicio (sin saltos).
//
// Coste: dos Shape con gradiente radial creados una sola vez; por cuadro sólo
// cambian x, y y opacity (sin blur, sin partículas, sin timers JS). Gama baja:
// mismo recorrido, ciclo más lento. Movimiento reducido o app en segundo
// plano: estático. No recibe toques.
Item {
    id: aura
    property string mode: "unknown"           // unknown | syncing | pending | synced | attention | error | offline
    property bool running: true
    property bool reducedMotion: false
    property bool lowCost: false
    enabled: false

    readonly property bool animate: running && visible && !reducedMotion
                                    && Qt.application.state === Qt.ApplicationActive
    readonly property bool error: mode === "error" || mode === "offline"   // rojo
    readonly property bool synced: mode === "synced"
    readonly property bool attention: mode === "attention"                 // amarillo
    readonly property color neutralTint: "#7F90AB"            // gris pizarra (estado no confirmado)
    readonly property color primaryTint: error ? S.navy : S.corporateBlue
    readonly property color secondaryTint: error ? S.syncErrorRed
                                         : attention ? S.warning
                                         : synced ? S.corporateGreen
                                         : neutralTint
    // Opacidad base de cada luz (no es solo-lectura: tiene Behavior).
    property real intensity: error ? 0.72 : attention ? 0.66 : synced ? 0.70 : 0.58
    Behavior on intensity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    // Fase única 0..2π. Ciclo completo 12 s (error 10 s; gama baja ×1.4).
    property real t
    NumberAnimation on t {
        from: 0; to: Math.PI * 2
        duration: (aura.error ? 10000 : 12000) * (aura.lowCost ? 1.4 : 1)
        loops: Animation.Infinite
        running: aura.animate
    }

    // Diámetro relativo a la pantalla real: regiones amplias en cualquier móvil.
    readonly property real size: Math.max(180, Math.max(width, height) * 0.58)
    // Desfase de B: en error se acerca más a A (más superposición y oposición).
    property real lag: error ? 0.18 : 0.42
    Behavior on lag { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    component Blob: Shape {
        id: blob
        property color tint: S.corporateBlue
        Behavior on tint { ColorAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: blob.width / 2; centerY: blob.height / 2
                focalX: blob.width / 2; focalY: blob.height / 2
                centerRadius: blob.width / 2
                focalRadius: 0
                GradientStop { position: 0.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.90) }
                GradientStop { position: 0.35; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.62) }
                GradientStop { position: 0.70; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.22) }
                GradientStop { position: 1.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: blob.width; y: 0 }
            PathLine { x: blob.width; y: blob.height }
            PathLine { x: 0; y: blob.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // Aura A: centro (0.20, 0.17) -> (0.50, 0.45+) -> (0.80, 0.73) -> centro -> inicio.
    Blob {
        id: primaryBlob
        width: aura.size; height: aura.size
        tint: aura.primaryTint
        x: aura.width * (0.50 - 0.30 * Math.cos(aura.t)) - width / 2
        y: aura.height * (0.45 - 0.28 * Math.cos(aura.t) + 0.06 * Math.sin(2 * aura.t)) - height / 2
        opacity: aura.intensity * (aura.error ? 0.85 + 0.15 * Math.sin(2 * aura.t)
                                              : 0.92 + 0.08 * Math.sin(2 * aura.t))
    }
    // Aura B (oposición de fase): centro (0.20, 0.73) -> (0.50, 0.45) -> (0.80, 0.17)
    // -> centro -> inicio. Se dibuja encima de A: en el cruce se mezclan los colores.
    Blob {
        id: secondaryBlob
        width: aura.size; height: aura.size
        tint: aura.secondaryTint
        x: aura.width * (0.50 + 0.30 * Math.cos(aura.t + Math.PI + aura.lag)) - width / 2
        y: aura.height * (0.45 - 0.28 * Math.cos(aura.t + Math.PI + aura.lag) - 0.06 * Math.sin(2 * aura.t)) - height / 2
        opacity: aura.intensity * (aura.error ? 0.85 - 0.15 * Math.sin(2 * aura.t)
                                              : 0.88 + 0.08 * Math.cos(2 * aura.t))
    }
}
