# Correcciones de Dock y revisión (2026-10-29)

## Dock: primera captura

La regresión del Dock fue introducida por la espera de `textureReady` del cambio anterior. Se retenía `glassTexture=null` hasta `scheduledUpdateCompleted` mientras todos sus consumidores estaban ocultos. En Qt 6.9.3, `scheduleUpdate()` sólo solicita trabajo: la textura se crea en el ciclo de render o al consultar su texture provider. Un productor invisible, sin consumidores visibles, no puede usarse como barrera de arranque de sus propios consumidores.

Se corrigieron las condiciones de HomeScreen y RenditionsApp para exponer el ShaderEffectSource con fuente y dimensiones válidas antes de la primera captura. La protección interna de GlassSurface ante fuente nula sigue activa. No se cambiaron tamaño, tinte, bisel, sombra, iconos, separadores, material ni animaciones del Dock.

Fuentes: `qml/Mobile/HomeScreen.qml` y `qml/Mobile/renditions/RenditionsApp.qml`. Prueba nueva: `tests/renditions/dock_glass_bootstrap.cjs`. Se comprobaron dos fallos de arranque antes de corregirlos; después pasan sus tres casos, los contratos existentes del Dock y la suite QML de estabilidad (12/12, sin avisos).

Comandos ejecutados (sin compilación):

```text
node --test tests/renditions/dock_glass_bootstrap.cjs tests/renditions/dock_first_tap_static.cjs tests/calicatas/health_glass_logos.cjs
C:/Qt/6.9.3/mingw_64/bin/qmltestrunner.exe -input tests/renditions/qml/tst_render_stability.qml -o artifacts/renditions-flicker-20261029/qml-dock-restored.txt,txt
git diff --cached --check
```

No se compiló ni instaló. La comprobación visual del A12 queda pendiente del build del usuario. La prueba de bindings verifica el arranque lógico; la suite offscreen no demuestra el resultado de OpenGL/Mali.
