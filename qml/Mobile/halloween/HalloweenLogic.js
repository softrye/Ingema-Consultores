.pragma library

function resolveSkin(choice, date) {
    if (choice !== "auto") return choice
    return date.getMonth() === 9 && date.getDate() >= 15 ? "halloween" : "none"
}

function motionPermitted(active, coreAllowed, reduced, thermal) {
    return active && coreAllowed && !reduced && thermal < 2
}

// Pure policy: the shell supplies the real visibility, IME and operation state.
function stepClock(previous, deltaMs, active, safe, enabled) {
    var s = { activeMs: previous.activeMs, remainingMs: previous.remainingMs, serial: previous.serial }
    if (!active || !safe || !enabled) s.remainingMs = 0
    if (!enabled) { s.activeMs = 0; return s }
    if (!active) return s
    s.activeMs += Math.max(0, deltaMs)
    s.remainingMs = Math.max(0, s.remainingMs - Math.max(0, deltaMs))
    if (s.activeMs >= 300000 && safe && s.remainingMs === 0) {
        s.activeMs = 0
        s.remainingMs = 1800
        ++s.serial
    }
    return s
}
