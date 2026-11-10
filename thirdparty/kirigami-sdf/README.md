# Kirigami SDF (tercero, MIT)

- Origen: `RESOURCES/kirigami-master.zip` → `src/primitives/shaders/sdf.glsl` (KDE Kirigami).
- Autores: Arjen Hiemstra (2020) e Inigo Quilez (2017). Licencia: MIT (`LICENSE-MIT.txt`).
- Uso en InGe+: `sdf_rounded_rectangle` se incorpora en `qml/Mobile/shaders/glass.frag`
  (material único GlassSurface: Dock, botón «+», panel del Dock). Única modificación:
  sin calificadores `lowp`, porque en GLES 3.0 las distancias en píxeles necesitan precisión
  completa.
