.pragma library

// Traduce el perfil EXISTENTE de GraphicsCore a presupuestos del mismo motor RHI.
// Nunca se eligen VERY_HIGH/EXTREME a partir del hardware automáticamente.
function budget(profile, pressure) {
    var key = String(profile || "UNKNOWN").toUpperCase()
    if (pressure) key = "LOW"
    switch (key) {
    case "EXTREME": return { cpuMiB: 192, gpuMiB: 160, parallel: 4, nodes: 160, pixelError: 1.5, maxLevel: 21 }
    case "VERY_HIGH": return { cpuMiB: 128, gpuMiB: 112, parallel: 3, nodes: 120, pixelError: 2.5, maxLevel: 20 }
    case "HIGH": return { cpuMiB: 80, gpuMiB: 72, parallel: 2, nodes: 80, pixelError: 6, maxLevel: 18 }
    case "MEDIUM_HIGH": return { cpuMiB: 64, gpuMiB: 56, parallel: 2, nodes: 64, pixelError: 8, maxLevel: 17 }
    case "MEDIUM": return { cpuMiB: 48, gpuMiB: 40, parallel: 2, nodes: 48, pixelError: 10, maxLevel: 16 }
    case "ULTRA_LOW": return { cpuMiB: 32, gpuMiB: 24, parallel: 1, nodes: 24, pixelError: 18, maxLevel: 14 }
    default: return { cpuMiB: 40, gpuMiB: 32, parallel: 1, nodes: 32, pixelError: 14, maxLevel: 15 }
    }
}
