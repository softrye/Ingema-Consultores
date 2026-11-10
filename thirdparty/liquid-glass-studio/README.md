# liquid-glass-studio (tercero, MIT)

- Origen: `RESOURCES/liquid-glass-studio-main.zip` → `src/shaders/fragment-main.glsl` (Charles Yin, 2024). Licencia: MIT (`LICENSE`).
- Uso en InGe+: `qml/Mobile/shaders/glass.frag` (material único de GlassSurface) incorpora su refracción por ley de Snell
  (`thetaI = asin((1 - profundidad/grosor)^2)`, `thetaT = asin(sin(thetaI)/n)`, desplazamiento `-tan(thetaT - thetaI)` a lo largo de la normal
  del SDF) y su dispersión cromática (`N_R = 0.98`, `N_B = 1.02`).
- Adaptación: GLSL 440 de Qt RHI (qsb); normal por diferencias finitas del SDF de Kirigami; sin glare animado por ratón.
