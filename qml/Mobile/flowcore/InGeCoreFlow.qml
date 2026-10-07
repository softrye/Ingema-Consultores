pragma Singleton
import QtQuick 2.15
import InGe 1.0

// INGEMA Flow Core
// Motor central de animaciones, transiciones y microinteracciones de InGe+.
// FINAL: movimiento coherente, breve y de bajo costo para Android.
// V29: interacción de texto segura; nombres visuales y correos intactos.
// V31: gestos táctiles, física de desplazamiento, criterio adaptativo y
// superficies translúcidas sin blur pesado.
// V32: Deep Press, menús contextuales tipo globo y respuesta progresiva.
QtObject {
    id: core

    // InGeCoreFlow 3.0 foundation. These objects are owned by this singleton,
    // so every CoreFlow component consumes the same visual and motion state.
    readonly property string coreFlowVersion: "3.1.0-redesign"
    readonly property FlowColors colors: FlowColors {}
    readonly property FlowTypography typography: FlowTypography {}
    readonly property FlowSpacing spacing: FlowSpacing {}
    readonly property FlowRadius radius: FlowRadius {}
    readonly property FlowElevation elevation: FlowElevation {}
    readonly property FlowMetrics metrics: FlowMetrics {}
    readonly property FlowOpacity opacityTokens: FlowOpacity {}
    readonly property FlowDuration durationTokens: FlowDuration {}
    readonly property FlowEasing easingTokens: FlowEasing {}
    readonly property FlowSpring springTokens: FlowSpring {}
    readonly property FlowVariant variant: FlowVariant {}
    readonly property FlowState states: FlowState {}
    readonly property FlowAccessibility accessibility: FlowAccessibility {}
    readonly property FlowPerformance performance: FlowPerformance {}
    readonly property FlowTheme theme: FlowTheme {
        colors: core.colors
    }
    readonly property FlowMotion motion: FlowMotion {
        core: core
        durationTokens: core.durationTokens
        easingTokens: core.easingTokens
        springTokens: core.springTokens
    }
    readonly property var haptics: FlowHaptics
    // Published by the shell: secondary surfaces reuse the actual Dock material.
    property Item glassMaterial: null
    readonly property var graphicsCore: GraphicsCore
    readonly property string graphicsBackend: graphicsCore.graphicsBackend
    readonly property bool vulkanAvailable: graphicsCore.vulkanAvailable
    readonly property bool earthAvailable: graphicsCore.earthAvailable
    readonly property bool earthActive: graphicsCore.earthActive
    readonly property string earthState: graphicsCore.earthState
    readonly property string renderProfile: graphicsCore.renderProfile
    readonly property int themeMode: theme.mode
    readonly property bool darkMode: theme.isDark
    readonly property bool liquidGlass: theme.isGlass
    readonly property string themeName: theme.displayName

    // Interruptores globales.
    property bool enabled: true
    property bool reduceMotion: false
    // 0 = sin movimiento, 1 = discreto, 2 = completo.
    property int motionLevel: 2
    // 0 = ahorro, 1 = equilibrado, 2 = premium.
    property int performanceLevel: 2

    function openEarth() {
        return graphicsCore.openEarth()
    }
    function closeEarth() { graphicsCore.closeEarth() }
    function setRenderProfile(profile) {
        return graphicsCore.setRenderProfile(profile)
    }

    readonly property bool motionAllowed:
        enabled
        && !reduceMotion
        && !accessibility.reducedMotion
        && !performance.isReducedMotion
        && motionLevel > 0
    readonly property real motionFactor:
        motionAllowed
        ? (motionLevel >= 2 ? 1.0 : 0.68) * performance.animationIntensity
        : 0.0
    readonly property real performanceFactor:
        lowMemoryMode
        ? 0.80
        : (performance.profile === performance.safe
           ? 0.82
           : (performance.profile <= performance.high ? 1.08 : 1.0))

    // Duraciones base.
    readonly property int instantDuration: duration(70)
    readonly property int fastDuration: duration(105)
    readonly property int normalDuration: duration(180)
    readonly property int slowDuration: duration(240)
    readonly property int emphasizedDuration: duration(260)

    // V50: fuente global unica para la geometria del teclado Android/IME.
    // imeViewportHeight lo publica el unico ApplicationWindow real. Cuando
    // adjustResize ya redujo la ventana, keyboardRectangle queda fuera de ese
    // viewport y el solapamiento es cero, evitando un segundo reajuste.
    property real imeViewportHeight: 0.0
    // Acceso indexado: Qt 6.9 expone estas propiedades en runtime, aunque la
    // metadata estatica de QObject usada por qmllint no las enumera.
    readonly property bool imeVisible: Qt.inputMethod["visible"] === true
    readonly property rect imeKeyboardRectangle:
        Qt.inputMethod["keyboardRectangle"] || Qt.rect(0, 0, 0, 0)
    readonly property real imeHeight: {
        if (!imeVisible || imeViewportHeight <= 0.0
                || imeKeyboardRectangle.height <= 0.0)
            return 0.0
        var keyboardTop = Math.max(0.0, imeKeyboardRectangle.y)
        return Math.max(0.0, Math.min(imeViewportHeight,
                                      imeViewportHeight - keyboardTop))
    }
    readonly property real availableContentHeight:
        Math.max(0.0, imeViewportHeight - imeHeight)
    readonly property real imeFieldMargin: 20.0
    readonly property int imeScrollDuration: motionAllowed ? duration(190) : 0

    // Navegación y revelado.
    readonly property int pageOutDuration: duration(105)
    readonly property int pageInDuration: duration(230)
    readonly property int revealDuration: duration(230)
    readonly property int cardRevealDuration: duration(240)
    readonly property int staggerDuration: duration(42)
    readonly property int sheetDuration: duration(240)
    readonly property int dialogDuration: duration(260)

    // Retroalimentación.
    readonly property int rippleDuration: duration(390)
    readonly property int rippleFadeDuration: duration(250)
    readonly property int successDuration: duration(380)
    readonly property int successHoldDuration: motionAllowed ? 720 : 0
    readonly property int shakeDuration: duration(55)
    readonly property int pulseDuration: duration(170)

    // Escalas y distancias.
    readonly property real pressScale: motionAllowed ? 0.965 : 1.0
    readonly property real compactPressScale: motionAllowed ? 0.948 : 1.0
    readonly property real cardPressScale: motionAllowed ? 0.975 : 1.0
    readonly property real activeIconScale: motionAllowed ? 1.085 : 1.0
    readonly property real pageOffset: motionAllowed ? (motionLevel >= 2 ? 28.0 : 16.0) : 0.0
    readonly property real pageOutScale: motionAllowed ? 0.992 : 1.0
    readonly property real pageInScale: motionAllowed ? 0.982 : 1.0
    readonly property real revealStartScale: motionAllowed ? 0.965 : 1.0
    readonly property real cardRevealOffset: motionAllowed ? 14.0 : 0.0
    readonly property real sheetStartScale: motionAllowed ? 0.972 : 1.0
    readonly property real focusScale: motionAllowed ? 1.012 : 1.0

    // -----------------------------------------------------------------
    // InGeCoreFlow V31 — Gestos, física y criterio adaptativo.
    // -----------------------------------------------------------------
    readonly property string engineVersion: "3.5.0"
    readonly property string gesturePolicyVersion: "1.3"
    readonly property string deepPressPolicyVersion: "1.1"

    property bool gestureNavigationEnabled: true
    property bool adaptiveMotionEnabled: true
    property bool translucentSurfacesEnabled: true
    property bool lowMemoryMode: false

    // 0 = sobrio, 1 = equilibrado, 2 = fluido.
    property int motionPersonality: 2

    readonly property bool interactiveMotionAllowed:
        motionAllowed && gestureNavigationEnabled

    readonly property bool refinedMotionAllowed:
        motionAllowed
        && performance.secondaryEffectsEnabled
        && !lowMemoryMode

    // Física táctil común para Flickable/ListView/GridView.
    readonly property int touchPressDelay:
        motionAllowed ? (motionPersonality >= 2 ? 70 : 95) : 0

    readonly property real flickDeceleration:
        lowMemoryMode
        ? 3900.0
        : (motionPersonality >= 2 ? 2650.0 : 3150.0)

    readonly property real maximumFlickVelocity:
        lowMemoryMode
        ? 1900.0
        : (motionPersonality >= 2 ? 2850.0 : 2350.0)

    readonly property real compactMaximumFlickVelocity:
        Math.max(1500.0, maximumFlickVelocity * 0.82)

    readonly property real scrollIndicatorOpacity:
        motionAllowed ? 0.78 : 0.56


    // -----------------------------------------------------------------
    // Deep Press V32
    //
    // En dispositivos sin sensor de presión real se activa mediante una
    // pulsación sostenida breve. El API queda preparado como capacidad
    // común del motor, no como lógica exclusiva de Ajustes.
    // -----------------------------------------------------------------
    property bool deepPressEnabled: true
    property bool quickBubbleEnabled: true

    readonly property int deepPressHoldDuration:
        duration(motionPersonality >= 2 ? 390 : 460)

    readonly property real deepPressCancelDistance: 17.0
    readonly property real deepPressReadyScale:
        motionAllowed ? 1.045 : 1.0

    readonly property real deepPressPressedScale:
        motionAllowed ? 0.965 : 1.0

    readonly property real deepPressGlowOpacity:
        refinedMotionAllowed ? 0.26 : 0.14

    readonly property int deepPressResetDuration: duration(140)
    readonly property int quickBubbleOpenDuration: duration(265)
    readonly property int quickBubbleCloseDuration: duration(145)
    readonly property int quickBubbleItemDuration: duration(190)
    readonly property int quickBubbleItemStagger: duration(34)
    readonly property real quickBubbleStartScale:
        motionAllowed ? 0.78 : 1.0

    readonly property real quickBubbleStartOffset:
        motionAllowed ? 18.0 : 0.0

    readonly property real quickBubblePointerSize: 15.0
    readonly property real quickBubbleMaximumWidth: 258.0
    readonly property real quickBubbleMinimumWidth: 218.0
    readonly property real quickBubbleActionHeight: 50.0
    readonly property real quickBubbleCornerRadius: 22.0

    function deepPressPolicy(contextName, importance) {
        var context = originalText(contextName, "default").toLowerCase()
        var priority = Math.max(0, Math.min(2, Math.round(Number(importance) || 1)))
        var hold = deepPressHoldDuration
        var maximumActions = 4
        var strength = 0.96

        if (context === "navigation" || context === "bottomnav") {
            hold = duration(390)
            maximumActions = 4
            strength = 0.98
        } else if (context === "card" || context === "document") {
            hold = duration(470)
            maximumActions = 5
            strength = 0.94
        } else if (context === "map") {
            hold = duration(520)
            maximumActions = 3
            strength = 0.93
        }

        if (priority <= 0 || lowMemoryMode) {
            maximumActions = Math.min(maximumActions, 3)
            strength = Math.min(strength, 0.95)
        }

        return {
            enabled: deepPressEnabled,
            holdDuration: hold,
            cancelDistance: deepPressCancelDistance,
            maximumActions: maximumActions,
            surfaceStrength: strength,
            readyScale: deepPressReadyScale,
            pressedScale: deepPressPressedScale
        }
    }

    function quickBubblePlacement(anchorX, anchorY, bubbleWidth,
                                  bubbleHeight, viewportWidth,
                                  viewportHeight) {
        var margin = 12.0
        var pointerGap = quickBubblePointerSize + 7.0
        var x = Number(anchorX) - Number(bubbleWidth) / 2.0
        var y = Number(anchorY) - Number(bubbleHeight) - pointerGap

        x = Math.max(margin,
                     Math.min(Number(viewportWidth) - Number(bubbleWidth) - margin,
                              x))

        if (y < margin)
            y = Math.min(Number(viewportHeight) - Number(bubbleHeight) - margin,
                         Number(anchorY) + pointerGap)

        return Qt.point(x, Math.max(margin, y))
    }

    function quickBubblePointerX(anchorX, bubbleX, bubbleWidth) {
        var local = Number(anchorX) - Number(bubbleX)
        return Math.max(24.0,
                        Math.min(Number(bubbleWidth) - 24.0, local))
    }

    // Cierre táctil de paneles/hojas.
    readonly property real dismissDragThreshold: 86.0
    readonly property real dismissVelocityThreshold: 720.0
    readonly property int dismissReboundDuration: duration(180)

    // Compatibilidad para componentes antiguos; el material real vive en
    // FlowTheme y se activa únicamente con Idle Glass.
    readonly property real glassOpacityLight: theme.glassOpacity
    readonly property real glassOpacityDark: theme.glassOpacity

    readonly property real glassHighlightOpacity:
        translucentSurfacesEnabled && refinedMotionAllowed ? 0.34 : 0.18

    readonly property color glassBorderLight: theme.glassBorder
    readonly property color glassBorderDark: theme.glassBorder
    readonly property color glassHighlightLight: theme.glassHighlight
    readonly property color glassHighlightDark: theme.glassHighlight

    // Criterio: decide cuánto movimiento corresponde a cada contexto.
    function motionPolicy(contextName, importance) {
        var context = originalText(contextName, "default").toLowerCase()
        var priority = Math.max(0, Math.min(2, Math.round(Number(importance) || 1)))
        var allow = motionAllowed
        var distance = pageOffset
        var alpha = 1.0
        var scaleAmount = 0.0
        var baseDuration = normalDuration

        if (context === "map" || context === "gps") {
            distance = pageOffset * 0.48
            alpha = 0.98
            scaleAmount = 0.004
            baseDuration = fastDuration
        } else if (context === "form" || context === "input") {
            distance = pageOffset * 0.58
            alpha = 0.985
            scaleAmount = 0.006
            baseDuration = normalDuration
        } else if (context === "overlay" || context === "sheet" || context === "dialog") {
            distance = pageOffset
            alpha = 0.94
            scaleAmount = 0.018
            baseDuration = sheetDuration
        } else if (context === "navigation" || context === "page") {
            distance = pageOffset
            alpha = 0.90
            scaleAmount = 0.018
            baseDuration = pageInDuration
        } else if (context === "feedback" || context === "success") {
            distance = 10.0
            alpha = 1.0
            scaleAmount = 0.025
            baseDuration = successDuration
        }

        if (priority <= 0 || lowMemoryMode) {
            distance *= 0.68
            scaleAmount *= 0.60
            baseDuration = Math.min(baseDuration, normalDuration)
        } else if (priority >= 2 && refinedMotionAllowed) {
            distance *= 1.08
            scaleAmount *= 1.10
        }

        return {
            animate: allow,
            duration: allow ? baseDuration : 0,
            distance: allow ? distance : 0,
            opacity: alpha,
            scaleAmount: allow ? scaleAmount : 0,
            translucent: translucentSurfacesEnabled
        }
    }













    function shouldDismissSheet(distanceY, velocityY) {
        return Number(distanceY) >= dismissDragThreshold
                || Number(velocityY) >= dismissVelocityThreshold
    }

    function glassSurfaceColor(isDark, strength) {
        // En Light/Dark normal una superficie es sólida. La translucidez no se
        // filtra a todas las tarjetas: FlowGlassSurface la habilita sólo cuando
        // theme.isGlass es verdadero.
        return theme.surfaceElevated
    }

    function pageColor() {
        return theme.background
    }

    function surfaceColor(elevated) {
        if (theme.isGlass)
            return elevated ? theme.surfaceElevated : theme.glassSurface
        return elevated ? theme.surfaceElevated : theme.surface
    }

    function fieldColor() {
        return theme.field
    }

    function stateContainer(intent) {
        var key = originalText(intent, "info").toLowerCase()
        if (key === "success" || key === "saved" || key === "synced")
            return theme.successContainer
        if (key === "warning" || key === "pending" || key === "draft")
            return theme.warningContainer
        if (key === "error" || key === "danger")
            return theme.errorContainer
        return theme.infoContainer
    }

    function glassBorderColor(isDark) {
        if (theme.isGlass)
            return theme.glassBorder
        return isDark ? glassBorderDark : glassBorderLight
    }

    function scrimColor(isDark, strength) {
        var s = Math.max(0.0, Math.min(1.0, Number(strength)))
        if (!isFinite(s))
            s = 1.0
        // Scrims derivados de INGEMA Deep (#151A30) por alpha.
        return isDark
                ? Qt.rgba(0.0667, 0.0824, 0.1529, 0.58 * s)
                : Qt.rgba(0.0824, 0.102, 0.1882, 0.46 * s)
    }

    function setThemeMode(mode) {
        theme.setGlassEnabled(false)
        theme.setMode(theme.light)
        return theme.light
    }

    function cycleThemeMode() {
        return setThemeMode(theme.light)
    }

    function setPerformanceProfile(profile) {
        performance.setProfile(profile)
    }

    function triggerHaptic(intent) {
        if (!haptics || !haptics.enabled)
            return false
        return haptics.trigger(String(intent || "selection"))
    }

    function motionPolicyFor(intent) {
        return motion.policy(intent)
    }

    function scrollVelocity(contentExtent, viewportExtent) {
        var content = Math.max(0.0, Number(contentExtent) || 0.0)
        var viewport = Math.max(1.0, Number(viewportExtent) || 1.0)
        var ratio = Math.max(1.0, content / viewport)
        return Math.min(maximumFlickVelocity,
                        compactMaximumFlickVelocity + Math.min(700.0, ratio * 95.0))
    }

    // Primera experiencia premium: duraciones y amplitudes específicas.
    readonly property int experienceSceneDuration: duration(460)
    readonly property int experienceNarrationDelay: duration(520)
    readonly property int experienceMorphDuration: duration(620)
    readonly property int experienceStagger: duration(86)
    readonly property real experienceParallax: motionAllowed ? (performanceLevel >= 2 ? 22.0 : 12.0) : 0.0
    readonly property real experienceDepthScale: motionAllowed ? 0.965 : 1.0

    // Identidad visual del movimiento: alias de la paleta INGEMA (FlowColors).
    readonly property color navy: colors.ingemaNavy
    readonly property color blue: colors.ingemaBlue
    readonly property color interfaceBlue: colors.ingemaBlue
    readonly property color cyan: colors.ingemaBlueTint
    readonly property color teal: colors.ingemaBlue
    readonly property color green: colors.ingemaGreen
    readonly property color amber: "#FDAC11"
    readonly property color rippleLight: "#2A0654A2"
    readonly property color rippleDark: "#3D8FB2D5"

    // Easing común.
    readonly property int easeIn: Easing.InCubic
    readonly property int easeOut: Easing.OutCubic
    readonly property int easeStandard: Easing.InOutCubic
    readonly property int easeEmphasized: Easing.OutQuart
    readonly property int easeOvershoot: motionAllowed ? Easing.OutBack : Easing.Linear

    function duration(baseMs) {
        if (!motionAllowed)
            return 0
        var base = Number(baseMs)
        var motion = Number(motionFactor)
        var performanceScale = Number(performanceFactor)
        if (!isFinite(base) || base < 0)
            base = 0
        if (!isFinite(motion) || motion < 0)
            motion = 0
        if (!isFinite(performanceScale) || performanceScale < 0)
            performanceScale = 1
        return Math.max(1, Math.round(base * motion * performanceScale))
    }

    function stagger(index, step) {
        if (!motionAllowed)
            return 0
        var safeIndex = Math.max(0, Number(index) || 0)
        var safeStep = Number(step)
        if (!isFinite(safeStep) || safeStep < 0)
            safeStep = staggerDuration
        return Math.round(safeIndex * safeStep)
    }

    function pageDirection(fromPage, toPage) {
        return Number(toPage) >= Number(fromPage) ? 1 : -1
    }

    function clampPage(value, minimum, maximum) {
        var n = Number(value)
        if (!isFinite(n))
            return minimum
        n = Math.round(n)
        return Math.max(minimum, Math.min(maximum, n))
    }

    function clampMotionLevel(value) {
        var n = Number(value)
        if (!isFinite(n))
            return 2
        return Math.max(0, Math.min(2, Math.round(n)))
    }

    function clampPerformanceLevel(value) {
        var n = Number(value)
        if (!isFinite(n))
            return 1
        return Math.max(0, Math.min(2, Math.round(n)))
    }

    function rippleDiameter(width, height) {
        var w = Math.max(0, Number(width) || 0)
        var h = Math.max(0, Number(height) || 0)
        return Math.ceil(Math.sqrt(w * w + h * h) * 2.05)
    }

    function safeOpacity(value) {
        var n = Number(value)
        if (!isFinite(n))
            return 1.0
        return Math.max(0.0, Math.min(1.0, n))
    }

    // -----------------------------------------------------------------
    // Interacción de texto segura.
    //
    // Esta capa forma parte de InGeCoreFlow para que el contenido visible
    // use una única política sin modificar los datos originales.
    //
    // Regla crítica:
    // - Nombres: pueden corregirse visualmente.
    // - Correos: se muestran exactamente como fueron recibidos.
    // - emailLookupKey(): solo sirve para comparación interna; nunca debe
    //   guardarse ni mostrarse como sustituto del correo original.
    // -----------------------------------------------------------------
    property bool textCorrectionEnabled: true
    property bool capitalizePersonNames: true
    readonly property bool preserveEmailExactly: true
    readonly property string textPolicyVersion: "1.0"

    function originalText(value, fallbackValue) {
        if (value === undefined || value === null)
            return fallbackValue === undefined || fallbackValue === null
                    ? "" : String(fallbackValue)
        return String(value)
    }

    function hasVisibleText(value) {
        var raw = originalText(value, "")
        return raw.replace(/^\s+|\s+$/g, "").length > 0
    }

    function looksLikeEmail(value) {
        var raw = originalText(value, "")
        var at = raw.indexOf("@")
        return at > 0 && at < raw.length - 1
    }

    function displayEmailExact(value, fallbackValue) {
        var raw = originalText(value, "")
        if (raw.replace(/^\s+|\s+$/g, "").length === 0)
            return originalText(fallbackValue, "")
        return raw
    }

    function emailLookupKey(value) {
        // Uso exclusivo para comparación o búsqueda interna.
        // No reemplaza el dato original y no debe mostrarse en la interfaz.
        return originalText(value, "")
                .replace(/^\s+|\s+$/g, "")
                .toLowerCase()
    }

    function normalizeNameSegment(segment) {
        var raw = originalText(segment, "")
        if (raw.length === 0)
            return ""

        var upper = raw.toUpperCase()
        var lower = raw.toLowerCase()

        // Si el usuario ya escribió una combinación interna de mayúsculas
        // y minúsculas, se conserva (por ejemplo: McDonald).
        if (raw !== upper && raw !== lower)
            return raw.charAt(0).toUpperCase() + raw.substring(1)

        return lower.charAt(0).toUpperCase() + lower.substring(1)
    }

    function normalizeNameWord(word) {
        var raw = originalText(word, "")
        var result = ""
        var segment = ""

        for (var i = 0; i < raw.length; ++i) {
            var ch = raw.charAt(i)
            if (ch === "-" || ch === "'") {
                result += normalizeNameSegment(segment)
                result += ch
                segment = ""
            } else {
                segment += ch
            }
        }

        result += normalizeNameSegment(segment)
        return result
    }

    function displayPersonName(value, fallbackValue) {
        var raw = originalText(value, "")
        if (raw.replace(/^\s+|\s+$/g, "").length === 0)
            raw = originalText(fallbackValue, "")

        // Protección adicional: aunque una pantalla llame por error al
        // formateador de nombres, un correo jamás será capitalizado.
        if (looksLikeEmail(raw))
            return displayEmailExact(raw, fallbackValue)

        var compact = raw
                .replace(/^\s+|\s+$/g, "")
                .replace(/\s+/g, " ")

        if (!textCorrectionEnabled || !capitalizePersonNames)
            return compact

        var words = compact.split(" ")
        var result = []

        for (var i = 0; i < words.length; ++i) {
            if (words[i].length > 0)
                result.push(normalizeNameWord(words[i]))
        }

        return result.join(" ")
    }

    function personInitials(value, maximumLetters) {
        var formatted = displayPersonName(value, "")
        if (formatted.length === 0 || looksLikeEmail(formatted))
            return ""

        var limit = Math.max(1, Math.min(3, Math.round(Number(maximumLetters) || 2)))
        var words = formatted.split(/\s+/)
        var initials = ""

        for (var i = 0; i < words.length && initials.length < limit; ++i) {
            if (words[i].length > 0)
                initials += words[i].charAt(0).toUpperCase()
        }

        if (initials.length === 0)
            initials = formatted.substring(0, limit).toUpperCase()

        return initials
    }

    function displayText(value, role, fallbackValue) {
        var safeRole = originalText(role, "plain").toLowerCase()

        if (safeRole === "email" || safeRole === "correo")
            return displayEmailExact(value, fallbackValue)

        if (safeRole === "person" || safeRole === "name"
                || safeRole === "nombre" || safeRole === "personname")
            return displayPersonName(value, fallbackValue)

        return originalText(value, fallbackValue)
    }
}
