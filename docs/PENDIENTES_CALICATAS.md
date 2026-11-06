# Pendientes de Calicatas

Actualizado: 06/11/2026. Ambos puntos implementados en código; queda la validación en la app compilada por el usuario. No se compila ni se usa ADB en este encargo.

- [ ] **Validar selectores compactos y de selección directa** (solicitado el 05/11/2026).
  - [x] Popup compartido con ancho máximo 360 dp, alto máximo 400 dp y hasta seis filas visibles. Las filas conservan al menos 48 dp; listas largas con desplazamiento e indicador.
  - [x] Un toque aplica y cierra; se retiran «Cancelar»/«Seleccionar». X, Atrás o exterior cancelan. Callback consumido una sola vez para evitar doble escritura.
  - [x] Se conserva «Sin seleccionar» y se desplaza inicialmente hasta la opción actual.
  - [ ] Comprobar en dispositivo/emulador: Humedad, Consistencia/densidad, Estabilidad, Excavabilidad y demás selectores compartidos; teclado, pantalla pequeña, fuentes grandes y tema oscuro.

- [ ] **Validar clasificación y representación del patrón** (observado el 05/11/2026).
  - [x] Diagnóstico: «GP · A-1-a» combina SUCS y AASHTO. Un solo patrón GP es correcto; AASHTO no añade una segunda trama SUCS.
  - [x] UI explícita «SUCS: … · AASHTO: …», campo «Símbolo / patrón SUCS» y explicación de patrón simple, doble o segundo SUCS pendiente, también en Laboratorio.
  - [x] GP-GM adoptado guarda primary_sucs/is_composite/secondary_sucs en una sola operación; pruebas de JSON y proyección comprueban dos capas con sus recursos SVG. Se conservan AASHTO, color y segundo valor oculto al volver a simple.
  - [x] Dos códigos iguales no se dibujan como dos tramas: se indica compuesto incompleto y se pide otro SUCS distinto, sin borrar datos.
  - [ ] Tras compilar: adoptar GP-GM desde Laboratorio, guardar/reabrir y sincronizar; comprobar las dos tramas. Verificar GP con A-1-a como simple y compuesto sin segundo SUCS como incompleto.

## Verificación del 06/11/2026

- `node tests/calicatas/pending_selectors_patterns.cjs`: salida 0 (selección, cancelación, doble toque, adopción, serialización y patrones).
- `node tests/calicatas/sucs_calculated_symbols.cjs`: salida 0 (regresión de cálculo SUCS).
- qmllint de CalicataFormPage.qml, Qt 6.9.3: salida 0 con avisos de imports/tipos no resueltos al analizar desde fuente; no se declara lint limpio.
- `git diff --check`: sin errores propios. No se cambian servidores, almacenamiento, Excel/PDF, mapas, Earth, Login ni el motor de animación.

Evidencia de transporte revisada sin modificar: calicatacloudservice.cpp lee los tres campos desde laboratorio y los envía en el RPC; CalicataFormPage._liveLabFields conserva la clasificación separada de AASHTO. Las pruebas no sustituyen una sincronización real.
