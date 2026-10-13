import QtQuick 2.15

QtObject {
    // Identidad corporativa oficial INGEMA.
    // Fuente normativa: Manual Corporativo Ingema 2025,
    // "05 Elementos graficos > Colores". Unica fuente de verdad de color de
    // marca para QML; FlowTheme deriva de aqui toda la semantica Light/Dark.
    // Equivalentes: flutter/inge_earth/lib/ingema_brand.dart y
    // android/web/inge-ai/src/inge/liquid-glass.scss (--ingema-*).
    readonly property color ingemaDeep: "#151A30"   // RGB 21, 26, 48
    readonly property color ingemaNavy: "#1C2D50"   // RGB 28, 45, 80
    readonly property color ingemaBlue: "#0654A2"   // RGB 6, 84, 162
    readonly property color ingemaGreen: "#486426"  // RGB 72, 100, 38

    // Derivados (mezcla de un color oficial con blanco/negro). No son colores
    // de marca nuevos: solo ajustan contraste WCAG sobre fondos oscuros.
    readonly property color ingemaDeepShade: "#111527"  // Deep + 18 % negro
    readonly property color ingemaBlueTint: "#8FB2D5"   // Blue + 55 % blanco (6.2:1 sobre Navy)
    readonly property color ingemaGreenTint: "#ADB99D"  // Green + 55 % blanco (6.6:1 sobre Navy)
    readonly property color ingemaBlueWash: "#EBF1F8"   // Blue 8 % sobre blanco
    readonly property color ingemaGreenWash: "#EDF0E9"  // Green 10 % sobre blanco
    // Escala de texto: Deep aplanado sobre blanco (ink*) y blanco aplanado
    // sobre Deep (paper*). Para superficies con modo propio (InGeDrive).
    readonly property color ingemaInkSecondary: "#575A6A"
    readonly property color ingemaInkTertiary: "#656876"
    readonly property color ingemaPaperSecondary: "#C2C3C9"
    readonly property color ingemaPaperTertiary: "#989AA4"

    // Nombres historicos conservados para consumidores existentes; los de
    // identidad resuelven a la paleta INGEMA.
    readonly property color navy950: ingemaDeepShade
    readonly property color navy900: ingemaDeep
    readonly property color navy800: ingemaNavy
    readonly property color navy700: ingemaNavy

    readonly property color blue800: ingemaNavy
    readonly property color blue700: ingemaBlue
    readonly property color blue600: ingemaBlue
    readonly property color blue100: "#DCE7F2"  // Blue 14 % sobre blanco
    readonly property color blue050: "#F0F5F9"  // Blue 6 % sobre blanco

    readonly property color cyan500: ingemaBlueTint
    readonly property color teal600: ingemaBlue
    readonly property color green600: ingemaGreen
    // Semanticos de interfaz (no identidad): se conservan por accesibilidad.
    readonly property color purple500: "#9A57E8"
    readonly property color amber500: "#FDAC11"
    readonly property color red600: "#DC3545"

    readonly property color white: "#FFFFFF"
    readonly property color grey050: "#F3F5F8"
    readonly property color grey100: "#E8EDF3"
    readonly property color grey200: "#D6DEE8"
    readonly property color grey400: "#98A3B3"
    readonly property color grey600: "#667085"
    readonly property color grey800: "#1F2937"
    readonly property color black: "#000000"
}
