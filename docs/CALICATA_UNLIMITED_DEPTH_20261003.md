# Calicatas: profundidad sin tope de entrada — 03/10/2026

Solicitud de Fabián: eliminar el límite de profundidad y mostrar la línea modificada. Fabián realiza la compilación.

## Causa y cambio

`qml/Mobile/pages/CalicataFormPage.qml` imponía dos topes: `depthMaxM: 3.00` para la profundidad objetivo y `allowedDepthM: Math.max(3, totalDepthM + 3)` para Hasta y nivel freático.

Ahora `depthMaxM` es `Number.POSITIVE_INFINITY` y `allowedDepthM` usa esa propiedad. Se retiró el rechazo de profundidades objetivo mayores que 3 m. Los valores introducidos deben seguir siendo números finitos, no negativos y compatibles con los estratos existentes. Se mantienen el paso de 0.05 m de Hasta, la continuidad entre estratos y los límites de las muestras dentro de su estrato.

La lista `depthItems` y su auxiliar `depthIndexOf` no tenían consumidores en las fuentes activas; se retiraron para evitar iterar hasta Infinity. El campo informativo muestra «Sin límite». `depth_max_m` se serializa como `null`, evitando introducir Infinity en JSON; las profundidades reales siguen guardándose como números.

La paginación del exportador sigue siendo de 3 m por hoja. Ese tamaño de página no es un tope de profundidad de la ficha.

## Verificación

- `node tests/calicatas/unlimited-depth.cjs`: inicialmente reprodujo el rechazo de 20 m; después pasó con 20, 500, 10000 y 20,50 m, tanto en profundidad total como en el guardado de Hasta. Incluye nivel freático, números inválidos y límites de intervalos y muestras.
- `node tests/calicatas/p3-strata.cjs`: pasó.
- `node tests/calicatas/review_export_static.cjs`: pasaron las 17 comprobaciones, incluida la paginación Excel para profundidades mayores que 3 m.
- El commit de esta fase contiene únicamente los cambios de esta tarea; los cambios previos de la copia de trabajo se conservan sin incorporarlos.

## Validación pendiente por Fabián

No se ejecutaron CMake, build, instalación ni logcat. Falta comprobar en la app Android la entrada, guardado y reapertura de una ficha de 20 m, los estratos continuos y el Excel exportado. Las pruebas de JavaScript no sustituyen esa comprobación. Tampoco se verificó el rendimiento gráfico o de exportación con profundidades extremadamente grandes.
