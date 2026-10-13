import QtQuick 2.15

QtObject {
    id: root

    property var core
    property var durationTokens
    property var easingTokens
    property var springTokens

    readonly property string pressSoft: "press.soft"
    readonly property string pressStandard: "press.standard"
    readonly property string pressStrong: "press.strong"
    readonly property string enterFade: "enter.fade"
    readonly property string enterScale: "enter.scale"
    readonly property string enterBubble: "enter.bubble"
    readonly property string exitFade: "exit.fade"
    readonly property string exitScale: "exit.scale"
    readonly property string navigationForward: "navigation.forward"
    readonly property string navigationBackward: "navigation.backward"
    readonly property string stateLoading: "state.loading"
    readonly property string stateSuccess: "state.success"
    readonly property string stateWarning: "state.warning"
    readonly property string stateError: "state.error"
    readonly property string tabSelect: "tab.select"
    readonly property string tabOpen: "tab.open"
    readonly property string tabClose: "tab.close"
    readonly property string cardExpand: "card.expand"
    readonly property string cardCollapse: "card.collapse"
    readonly property string sheetPresent: "sheet.present"
    readonly property string sheetDismiss: "sheet.dismiss"
    readonly property string dialogPresent: "dialog.present"
    readonly property string dialogDismiss: "dialog.dismiss"

    function policy(intent) {
        var name = String(intent || "")
        var result = {
            duration: core.normalDuration,
            easing: core.easeStandard,
            scale: 1.0,
            translation: 0.0,
            opacity: 1.0,
            spring: springTokens.standardSpring,
            damping: springTokens.standardDamping
        }

        if (name === pressSoft) {
            result.duration = core.fastDuration
            result.easing = core.easeOut
            result.scale = 0.985
        } else if (name === pressStandard) {
            result.duration = core.fastDuration
            result.easing = core.easeOut
            result.scale = core.pressScale
        } else if (name === pressStrong) {
            result.duration = core.instantDuration
            result.easing = core.easeOut
            result.scale = core.compactPressScale
        } else if (name === enterFade || name === exitFade) {
            result.duration = core.normalDuration
            result.opacity = 0.0
        } else if (name === enterScale || name === exitScale) {
            result.duration = core.normalDuration
            result.scale = core.revealStartScale
            result.opacity = 0.0
        } else if (name === enterBubble) {
            result.duration = core.quickBubbleOpenDuration
            result.easing = core.easeOvershoot
            result.scale = core.quickBubbleStartScale
            result.translation = core.quickBubbleStartOffset
            result.opacity = 0.0
        } else if (name === navigationForward || name === navigationBackward) {
            result.duration = core.pageInDuration
            result.easing = core.easeEmphasized
            result.translation = name === navigationForward
                    ? core.pageOffset : -core.pageOffset
            result.opacity = 0.0
        } else if (name === stateLoading) {
            result.duration = core.pulseDuration
        } else if (name === stateSuccess
                   || name === stateWarning
                   || name === stateError) {
            result.duration = core.successDuration
            result.easing = core.easeOvershoot
            result.scale = 1.025
        } else if (name === tabSelect || name === tabOpen
                   || name === tabClose) {
            result.duration = core.normalDuration
            result.easing = core.easeOut
        } else if (name === cardExpand || name === cardCollapse) {
            result.duration = core.cardRevealDuration
            result.easing = core.easeEmphasized
        } else if (name === sheetPresent || name === sheetDismiss) {
            result.duration = core.sheetDuration
            result.easing = name === sheetPresent ? core.easeOvershoot : core.easeIn
            result.translation = core.pageOffset
            result.opacity = 0.0
        } else if (name === dialogPresent || name === dialogDismiss) {
            result.duration = core.dialogDuration
            result.easing = name === dialogPresent ? core.easeOvershoot : core.easeIn
            result.scale = core.sheetStartScale
            result.opacity = 0.0
        }

        if (!core.motionAllowed) {
            result.duration = core.accessibility.reducedMotion ? 70 : 0
            result.scale = 1.0
            result.translation = 0.0
            result.opacity = name.indexOf("enter.") === 0
                    || name.indexOf("exit.") === 0 ? 0.0 : 1.0
            result.easing = Easing.Linear
        }

        return result
    }
}
