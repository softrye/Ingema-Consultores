# Calicatas: color manual de la web

Fuente revisada: `C:/Users/PC-02/Downloads/ingeplus-main (2).zip`, únicamente `src/components/calicatas/CalicataLiveColor.tsx`, `colorCanvas.ts` y su prueba. No se extrae ni ejecuta el proyecto web completo.

La web ofrece presets, lienzo bidimensional de saturación/brillo, barra de matiz y HEX. Se portan sus conversiones RGB/HSV a CalicataRules, con el mismo redondeo y representación #RRGGBB en mayúsculas. El selector Android reemplaza la lista de presets y el HEX separado por una sola paleta accesible desde «Color»; conserva presets y limpiar.

Se reutilizan GenPopup, CalicataSurface, BoundTextField, InGeCoreFlow y setStratumColor. No cambia el documento, sincronización, patrón SUCS ni exportadores. El selector se vincula al ID local/remoto del estrato, no a un índice que pueda cambiar por Realtime. Durante el arrastre se previsualiza localmente; al soltar se persiste mediante la ruta existente. Cerrar sin editar no republica un color anterior sobre un cambio remoto. Un HEX inválido se rechaza y permite corregirlo antes de «Listo».

Validación: `node tests/calicatas/manual_color_picker.cjs` pasa los ejemplos del ZIP, presets, extremos, giro del matiz y HEX canónico. `qmllint -I C:/Qt/6.9.3/mingw_64/qml -I qml/Mobile qml/Mobile/pages/CalicataFormPage.qml` sale 0 con avisos de análisis de tipos/imports desde fuente; no se declara lint limpio. `git diff --check` sin errores propios.

Sin compilar, instalar, ADB ni suites completas. Pendiente en dispositivo: abrir Color, arrastrar lienzo y matiz, escribir HEX, aplicar preset, limpiar, cerrar/reabrir y comprobar el perfil y la sincronización. La presencia visual remota de la paleta que existe en la web no se añade en este encargo; se mantiene la sincronización del valor ya existente.
