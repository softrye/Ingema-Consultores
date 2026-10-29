# Prueba de Rendiciones — Samsung A12, 29/10/2026

## Alcance y entorno

Prueba sobre la instalación del usuario actualizada a las 15:40:51, versión
1.1.13-native-location, proceso 6678. No ejecuté CMake, build ni instalación.
La sesión permaneció abierta: sin force-stop, reinicio ni logout en esta reanudación.
Evidencia privada local: `artifacts/usabilidad_rendiciones_20261029/` (no incluida en Git).
La prueba anterior de las 11:52 corresponde a otra instalación y no acredita esta versión.

## Resultados de esta reanudación (15:44–15:52)

| Caso | Resultado y evidencia |
| --- | --- |
| Crear rendición QA | Correcto: QA_USAB_1545 / RDC-2026-000043, proyecto QA_CONTINUITY_20261013; 63-creada.png. |
| Rellenar gasto | Concepto, monto 36.50, proveedor, categoría Otros, Otro sustento, número QA-1545, Efectivo; campos conservados al alternar pestañas. |
| Adjuntar imagen | Correcto localmente: PNG sintético QA_USAB_20261029.png; 80-documentos.png. No acredita subida al servidor. |
| Guardar y sincronizar | Fallo: permite guardar Otro sustento sin justificación; expense_create devuelve HTTP 400, RENDITION_EXPENSE_JUSTIFICATION_REQUIRED; 72-error-sync.png. |
| Corregir gasto rechazado | Bloqueado: añadir justificación devuelve «La creación del gasto ya fue enviada. Reintenta el mismo payload antes de editarlo»; 76-sync-corregido.png. |
| Eliminar gasto QA rechazado | Se confirmó la eliminación, pero el editor volvió al mismo error y el gasto permaneció; 77 y 78. |
| Presentar / cambio desde Dock | Presentar deshabilitado por 2 pendientes; transición desde Dock devuelve RENDITION_VALIDATION_ERROR; 68 y 82. |
| PDF/Excel: teléfono, InGe Drive, Google Drive | No ejecutables en esta QA: Exportar deshabilitado hasta presentar; 80-documentos.png. No se acreditan destinos. |
| Archivar | Confirmado sobre QA; no desaparece de activos, persiste rechazo de sincronización; 86–88. Recuperación no acreditada. |
| Papelera | No ejecutada: se conserva la QA con su gasto rechazado y copia local para investigar; no se tocaron otras rendiciones. |
| Home → Rendiciones → Home | Navegación y sesión conservadas; vidrio del Dock visible; 84-home.png y qa-retorno-home.mp4. |
| Menús Dock | Abren y cierran; contraste pobre: texto de fondo visible detrás del menú; 69-menu.png. |

## Defectos confirmados y evidencia de código

1. **P1: rechazo no corregible.** Validación local no impide guardar Otro sustento
   sin justificación; `ExpenseEditor.qml` presenta la justificación como opcional.
   Tras el rechazo, `renditionlocalstore.cpp` (guardia en torno a línea 683)
   bloquea cambiar el payload si `attempts > 0`, incluso tras rechazo definitivo.
   La pantalla Estado recomienda corregir un dato que luego no permite guardar.
2. **P1: textura inválida al volver a Home.** 14 avisos exactos
   `ShaderEffect: Texture t1 is not assigned a valid texture provider (std::nullptr_t)`
   en el proceso, concentrados en 15:50:41.615, coincidiendo con la vuelta a Home.
   Evidencia: 89-texture-times.log. Productor concreto pendiente de aislar;
   no se atribuye sin evidencia a una instancia específica de GlassSurface.
3. **P2: botones del selector de carpetas recortados.** «Sub...» y Cancelar
   rebasa el borde derecho; 62-carpeta.png.
4. **P2: errores poco utilizables.** Código de justificación cortado horizontalmente
   en Estado y RENDITION_VALIDATION_ERROR sin explicación en el diálogo.

## Límites y comandos

Se usaron `adb devices`, `adb shell input tap/text/keyevent/keycombination/swipe`,
`adb shell screencap`, `adb pull`, `adb shell screenrecord`,
`adb shell dumpsys package`, `adb logcat -d --pid=6678 -v brief/threadtime`,
`rg`/lecturas de fuente y `ffmpeg` para hoja de contacto del video.
Logs persistidos filtrados, sin credenciales. No errores ReferenceError/TypeError,
FATAL EXCEPTION o ANR en el segmento del proceso consultado; esto no acredita
ausencia global de ANR. No medición publish/s ni recreación de delegados:
diagnóstico no habilitado. Una hoja cada 2 segundos no descarta parpadeos breves.
No se declara regresión completa ni problema resuelto. Fondos/cambio, transiciones
con versión presentada, exportaciones y Papelera necesitan nueva validación tras
resolver el rechazo. El dato de prueba y su borrador corregido permanecen locales.
