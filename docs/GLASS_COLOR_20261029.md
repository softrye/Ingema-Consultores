# Velo gris del vidrio

El shader compartido trataba los uniformes QColor de Qt como RGB sin
premultiplicar. `mix(backdrop, tint.rgb, tint.a)` aplicaba alfa dos veces:
blanco al 78 % sobre blanco daba 0.8284, un gris visible.

Se corrige la composición en `qml/Mobile/shaders/glass.frag` para tinte y borde:
fondo × (1 − alfa) + RGB premultiplicado. Se conservan los tintes QML,
refracción, desenfoque, sombras, captura y animaciones existentes.

Contrato oficial de ShaderEffect:
https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html#shader-inputs-and-resources

`node --test --test-reporter=tap tests/renditions/glass_color_contract.cjs`:
dos pruebas numéricas sobre las expresiones reales del shader; ambas fallan
antes y pasan después. Comprueban blanco sobre blanco y composición por canal
de tinte/borde con los valores premultiplicados enviados por Qt.

CMake ya incluye glass.frag en qt_add_shaders; no se modifican QRC ni ABI.
No se ejecutó CMake, qsb, compilación ni instalación, por instrucción del usuario.
La comprobación visual en el A12 queda pendiente de su siguiente compilación.
