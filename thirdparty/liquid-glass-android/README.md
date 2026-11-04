# Liquid-Glass-Android (tercero, MIT)

- Origen: `RESOURCES/Liquid-Glass-Android-main.zip` → `liquidglass/src/main/java/com/example/liquidglass/GlassLensRenderer.kt`
  (shader AGSL `LENS_AGSL`). (c) 2025-2026 pandadog. Licencia: MIT (`LICENSE`).
- Uso en InGe+: `qml/Mobile/shaders/glass.frag`, rama `specular >= 0.95` (material del Dock), portada de AGSL a GLSL 440 (qsb):
  perfil de bisel por potencia inversa (falloff 2), refracción hacia dentro por la normal del SDF, dispersión 0.10,
  vibrancy 1.4, lóbulos especulares pow 4.5 (filo de 2 px y halo interior), cobertura AA de 1,5 px.
- Valores del Dock = adaptativos del recurso para un control de 58 dp: bisel min(48, 0.3·lado corto) ≈ 17 dp,
  refracción min(160, 0.7·lado·min(1, lado/110 dp)) ≈ 21 dp.
- Omitido: segunda forma con smooth-min, relieve táctil y recorte de vista (no aplican a GlassSurface).
