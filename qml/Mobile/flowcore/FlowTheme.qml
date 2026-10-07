import QtQuick 2.15

QtObject {
    id: root

    readonly property int light: 0
    readonly property int dark: 1
    readonly property int liquidGlass: 2

    property int mode: light
    property bool glassEnabled: false
    property var colors
    // Paleta corporativa INGEMA (FlowColors). El respaldo local evita leer
    // un objeto indefinido antes de que InGeCoreFlow asigne "colors".
    readonly property FlowColors defaultColors: FlowColors {}
    readonly property var brand: colors ? colors : defaultColors

    readonly property bool isDark: false
    readonly property bool isGlass: false
    readonly property string key: "light"
    readonly property string displayName: "Normal"

    // Identidad INGEMA expuesta como tokens semanticos de marca.
    readonly property color brandDeep: brand.ingemaDeep
    readonly property color brandNavy: brand.ingemaNavy
    readonly property color brandBlue: brand.ingemaBlue
    readonly property color brandGreen: brand.ingemaGreen

    // Semantic system palette. Light keeps the existing neutral backgrounds;
    // Dark is built on INGEMA Deep (#151A30) with Navy (#1C2D50) surfaces.
    // Derived values are documented in docs/INGEMA_DESIGN_SYSTEM_APP_20261006.md.
    readonly property color backgroundPrimary: isDark ? brand.ingemaDeep : "#FAFAFA"
    readonly property color backgroundSecondary: isDark ? "#182440" : "#F4F4F2"
    readonly property color backgroundTertiary: isDark ? brand.ingemaNavy : "#ECECEA"
    readonly property color backgroundGrouped: isDark ? brand.ingemaDeepShade : "#F4F4F2"

    // Content surfaces stay opaque in Glass mode. Only explicit
    // FlowGlassSurface instances sample/blur their background.
    readonly property color surfacePrimary: isDark ? brand.ingemaNavy : "#FDFDFD"
    readonly property color surfaceSecondary: isDark ? "#2A3A5A" : "#F4F4F2"
    readonly property color surfaceElevated: isDark ? "#334262" : "#FFFFFF"
    readonly property color surfaceOverlay: isGlass
        ? (isDark ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.90) : Qt.rgba(0.96, 0.98, 0.98, 0.91))
        : (isDark ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.98) : Qt.rgba(0.99, 0.99, 0.98, 0.98))

    // Light: INGEMA Deep and its alpha steps over white (WCAG >= 4.5:1 on
    // the light backgrounds except disabled). Dark: white steps over Deep.
    readonly property color textPrimary: isDark ? "#F6F6F7" : brand.ingemaDeep
    readonly property color textSecondary: isDark ? brand.ingemaPaperSecondary : brand.ingemaInkSecondary
    readonly property color textTertiary: isDark ? brand.ingemaPaperTertiary : brand.ingemaInkTertiary
    readonly property color textDisabled: isDark ? "#696C7B" : "#A6A8B0"
    readonly property color iconPrimary: textPrimary
    readonly property color iconSecondary: textSecondary
    readonly property color iconMuted: textTertiary
    readonly property color iconAccent: accent
    readonly property color iconDisabled: textDisabled

    // accent = seleccion, foco, enlaces e iconos activos (legible sobre el
    // fondo). En Dark se usa el tinte derivado de INGEMA Blue porque #0654A2
    // sobre Navy/Deep no alcanza contraste de texto.
    readonly property color accent: isDark ? brand.ingemaBlueTint : brand.ingemaBlue
    readonly property color accentSecondary: isDark ? brand.ingemaGreenTint : brand.ingemaGreen

    // Accion primaria rellena: INGEMA Blue en ambos modos, texto blanco (7.5:1).
    readonly property color actionPrimary: brand.ingemaBlue
    readonly property color actionPrimaryText: "#FFFFFF"
    // Nombre que usan Main.qml, FlowButton y NothingButton: sin él reciben
    // undefined ("Unable to assign [undefined] to QColor").
    readonly property color onActionPrimary: actionPrimaryText

    // Estructura (encabezados y barras institucionales): INGEMA Navy.
    readonly property color structure: brand.ingemaNavy
    readonly property color structureText: "#FFFFFF"

    readonly property color link: accent
    readonly property color success: isDark ? brand.ingemaGreenTint : brand.ingemaGreen
    readonly property color warning: isDark ? "#E9B95F" : "#9A6300"
    readonly property color error: isDark ? "#FF8A91" : "#B83B45"
    readonly property color destructive: error

    readonly property color separator: isDark ? "#374665" : "#E8EAEE"
    readonly property color border: isGlass ? glassBorder : (isDark ? "#404F6C" : "#DFE2E6")
    readonly property color focus: accent
    readonly property color overlay: isDark ? Qt.rgba(0.0667, 0.0824, 0.1529, 0.40) : Qt.rgba(0.0824, 0.102, 0.1882, 0.18)
    readonly property color scrim: isDark ? Qt.rgba(0.0667, 0.0824, 0.1529, 0.68) : Qt.rgba(0.0824, 0.102, 0.1882, 0.47)

    // One centralized material scale derived from the licensed donor systems.
    // Idle Glass changes material only. Light keeps luminous white bases for
    // legibility; Dark bases and every tint derive from INGEMA Deep/Navy/Blue
    // by alpha. Blur, highlights, specular and opacity steps are unchanged.
    readonly property color glassClear: isDark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.46) : Qt.rgba(0.94, 0.96, 0.98, 0.48)
    readonly property color glassRegular: isDark ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.58) : Qt.rgba(0.97, 0.97, 0.98, 0.62)
    readonly property color glassEmphasized: isDark ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.72) : Qt.rgba(0.99, 0.99, 0.99, 0.74)
    readonly property color glassFill: glassRegular
    readonly property color glassTint: isDark ? Qt.rgba(0.0235, 0.3294, 0.6353, 0.09) : Qt.rgba(0.0235, 0.3294, 0.6353, 0.05)
    readonly property color glassBorder: isDark ? Qt.rgba(0.86, 0.94, 0.97, 0.34) : Qt.rgba(1, 1, 1, 0.86)
    readonly property color glassHighlight: isDark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.88)
    readonly property color glassSpecular: isDark ? Qt.rgba(0.86, 0.97, 1, 0.46) : Qt.rgba(1, 1, 1, 0.98)
    readonly property color glassInnerLight: isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.44)
    readonly property color glassShadow: isDark ? Qt.rgba(0.0667, 0.0824, 0.1529, 0.62) : Qt.rgba(0.0824, 0.102, 0.1882, 0.14)
    readonly property real glassOpacity: isGlass ? 0.92 : 1.0
    readonly property real glassBlur: isGlass ? 0.76 : 0.34
    readonly property real glassSaturation: isGlass ? 0.22 : 0.04
    readonly property real glassRefraction: isGlass ? 0.08 : 0.0
    readonly property real glassChromaticDispersion: isGlass ? 0.012 : 0.0
    readonly property real glassThickness: isGlass ? 30.0 : 12.0

    // Compatibility aliases used by the current QML pages.
    readonly property color background: backgroundPrimary
    readonly property color backgroundBase: backgroundPrimary
    readonly property color surface: surfacePrimary
    readonly property color field: isDark ? "#182440" : "#F7F7F5"
    readonly property color search: isGlass ? glassRegular : field
    readonly property color sheet: isGlass ? surfaceOverlay : surfaceElevated
    readonly property color selected: isDark ? Qt.rgba(0.561, 0.698, 0.835, 0.24) : Qt.rgba(0.0235, 0.3294, 0.6353, 0.12)
    readonly property color pressed: isDark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0.0824, 0.102, 0.1882, 0.08)
    readonly property color disabled: textDisabled
    readonly property color textMuted: textTertiary
    readonly property color divider: separator
    readonly property color glassSurface: glassRegular
    readonly property color surfaceGlass: glassRegular
    readonly property color shadow: glassShadow

    readonly property color successContainer: isDark ? "#24302D" : brand.ingemaGreenWash
    readonly property color warningContainer: isDark ? "#3A2F18" : "#F7EEDC"
    readonly property color errorContainer: isDark ? "#40242A" : "#F7E7E8"
    readonly property color infoContainer: isDark ? "#102B52" : brand.ingemaBlueWash

    function setMode(value) {
        mode = light
        glassEnabled = false
    }

    function setGlassEnabled(value) {
        glassEnabled = false
    }
}
