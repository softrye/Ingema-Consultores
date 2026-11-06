.pragma library
function stepGuest(previous, deltaMs, enabled, safe) {
    var s={elapsedMs:previous.elapsedMs,remainingMs:previous.remainingMs,serial:previous.serial}
    if (!enabled) { s.elapsedMs=0; s.remainingMs=0; return s }
    if (!safe) { s.remainingMs=0; return s }
    var dt=Math.max(0,deltaMs)
    if (s.remainingMs>0) { s.remainingMs=Math.max(0,s.remainingMs-dt); return s }
    s.elapsedMs+=dt
    var wait=s.serial===0?25000:45000+(s.serial*7919%30000)
    if (s.elapsedMs>=wait) { s.elapsedMs=0; s.remainingMs=8000; ++s.serial }
    return s
}
