import QtQuick 2.15

QtObject {
    id: root

    readonly property int ultra: 0
    readonly property int high: 1
    readonly property int balanced: 2
    readonly property int safe: 3
    readonly property int reducedMotion: 4

    property int profile: high

    readonly property bool isReducedMotion: profile === reducedMotion
    readonly property bool blurEnabled: profile <= balanced
    readonly property bool complexBlurEnabled: profile <= high
    readonly property bool reflectionsEnabled: profile <= high
    readonly property bool secondaryEffectsEnabled: profile <= balanced
    readonly property bool shaderEffectsEnabled: profile <= balanced
    readonly property real blurIntensity:
        profile === ultra ? 1.0
        : (profile === high ? 0.72
           : (profile === balanced ? 0.38 : 0.0))
    readonly property real reflectionIntensity:
        reflectionsEnabled ? (profile === ultra ? 1.0 : 0.55) : 0.0
    readonly property real animationIntensity:
        isReducedMotion ? 0.0 : (profile === safe ? 0.55 : 1.0)

    function setProfile(value) {
        profile = Math.max(ultra, Math.min(reducedMotion, Number(value)))
    }
}
