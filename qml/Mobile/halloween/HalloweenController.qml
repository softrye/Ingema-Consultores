import QtQuick
import QtMultimedia
import "HalloweenLogic.js" as Logic
import "../kawaii/KawaiiLogic.js" as KawaiiLogic

// Presentation client of the ONE global InGeCoreFlow. No second motion engine.
Item {
    id: season
    visible: false
    required property var flow
    property string choice: "none"
    property bool foreground: false
    property bool safeSurface: false
    property bool reducedMotion: false
    property bool scaresEnabled: true
    property bool soundEnabled: false
    property date calendarDate: new Date()
    readonly property string resolvedSkin: Logic.resolveSkin(choice, calendarDate)
    readonly property bool seasonEnabled: resolvedSkin === "halloween"
    readonly property bool kawaiiEnabled: resolvedSkin === "ingenieros"
    readonly property bool decorationsEnabled: seasonEnabled || kawaiiEnabled
    property bool guestSurfaceReady: true
    property var kawaiiClock: ({elapsedMs:0,remainingMs:0,serial:0})
    readonly property bool kawaiiGuestVisible: kawaiiEnabled && foreground && safe && guestSurfaceReady && !touchActive
        && motionActive && kawaiiClock.remainingMs>0
    onKawaiiEnabledChanged: kawaiiClock=({elapsedMs:0,remainingMs:0,serial:0})
    readonly property bool motionActive: Logic.motionPermitted(foreground && (seasonEnabled || kawaiiEnabled && safeSurface && !flow.powerSaveMode),
        flow.motionAllowed, reducedMotion, flow.thermalStatus)
    readonly property bool safe: safeSurface && flow.thermalStatus < 2
    property var clockState: ({ activeMs: 0, remainingMs: 0, serial: 0 })
    readonly property int scareSerial: clockState.serial
    readonly property real scareRemainingMs: clockState.remainingMs
    readonly property bool scareVisible: seasonEnabled && scaresEnabled && foreground && safe && scareRemainingMs > 0
    readonly property int scareKind: (scareSerial - 1) % 3
    readonly property bool staticNotice: reducedMotion || !flow.motionAllowed
    property real visualSeconds: 0
    property bool touchActive: false
    property point touchPoint: Qt.point(0.5, 0.5)
    property point gentlePoint: Qt.point(0.5, 0.5)
    property double lastTick: Date.now()
    signal scarePresented(int serial)

    onForegroundChanged: {
        lastTick = Date.now()
        calendarDate = new Date()
        if (!foreground) dismiss()
    }
    onSafeChanged: if (!safe) dismiss()
    onScaresEnabledChanged: if (!scaresEnabled) clockState = ({ activeMs: 0, remainingMs: 0, serial: scareSerial })
    onSeasonEnabledChanged: {
        clockState = ({ activeMs: 0, remainingMs: 0, serial: 0 })
        visualSeconds = 0
        lastTick = Date.now()
    }
    onScareVisibleChanged: if (!scareVisible) chime.stop()
    onSoundEnabledChanged: if (!soundEnabled) chime.stop()

    function dismiss() {
        if (clockState.remainingMs > 0)
            clockState = ({ activeMs: clockState.activeMs, remainingMs: 0, serial: clockState.serial })
    }
    function advance(deltaMs) {
        kawaiiClock=KawaiiLogic.stepGuest(kawaiiClock,deltaMs,kawaiiEnabled && foreground && motionActive,
                                         safe && guestSurfaceReady && !touchActive)
        var previousSerial = clockState.serial
        var next = Logic.stepClock(clockState, deltaMs, foreground && seasonEnabled, safe, scaresEnabled)
        clockState = next
        // Emit from the clock transaction: derived-property notify order cannot
        // decide whether the haptic/sound event is delivered.
        if (next.serial > previousSerial) {
            console.info("INGE_HALLOWEEN_SCARE serial=" + next.serial + " static=" + staticNotice)
            scarePresented(next.serial)
            if (soundEnabled && !staticNotice && chime.status === SoundEffect.Ready) chime.play()
        }
        if (motionActive) {
            visualSeconds += deltaMs / 1000 * 7000 / Math.max(1000, flow.duration(7000))
            var amount = Math.min(1, deltaMs / 450)
            var target = touchActive ? touchPoint : Qt.point(0.5, 0.5)
            gentlePoint = Qt.point(gentlePoint.x + (target.x - gentlePoint.x) * amount,
                                  gentlePoint.y + (target.y - gentlePoint.y) * amount)
        }
    }
    // One timer across every page, every sprite and the active-use schedule.
    Timer {
        interval: season.motionActive ? (season.flow.advancedMotion ? 16 : 50) : season.decorationsEnabled ? 250 : 60000
        running: season.foreground && (season.decorationsEnabled || season.choice === "auto")
        repeat: true
        onRunningChanged: season.lastTick = Date.now()
        onTriggered: {
            var now = Date.now()
            var delta = Math.max(0, Math.min(1000, now - season.lastTick))
            season.lastTick = now
            season.calendarDate = new Date()
            if (season.decorationsEnabled) season.advance(delta)
        }
    }
    SoundEffect {
        id: chime
        source: season.seasonEnabled && season.soundEnabled ? "qrc:/images/halloween/boo.wav" : ""
        volume: 0.15
        loops: 1
    }
}
