# Rendiciones: cierre de intervención, validación física pendiente

No se declara cierre funcional. Trabajo limitado por cuota. Inicio medido: 89% en 5 h y 67% semanal (90% era la estimación del prompt). Último checkpoint: 31% y 58%. Al alcanzar 40% se detuvieron funcionalidades; durante estabilización se rebasó la reserva de 35%. Tiempo aproximado: 20 minutos.

## Cambios de esta intervención

- `src/cpp/renditionlocalstore.cpp`: el fallo de UPDATE/DELETE ya no reactiva CREATE confirmado; respuestas verifican identidad/versiones; CAS sin cambio remoto vuelve a pendiente conservando versión esperada; deduplicación local de adjuntos por URI/hash; protección de contenido PRESENTADA ya cargado frente a pulls posteriores.
- `src/cpp/renditionsynccontroller.cpp`: guardado local comprobado antes de PUSH y antes de avanzar tras confirmaciones; operación desconocida finaliza con error visible.
- `flutter/inge_earth/lib/renditions/v3/renditions_root.dart`: reintento de outbox al reabrir/reanudar y tras desconexión; mensaje de sincronización traducido.
- `flutter/inge_earth/lib/renditions/v3/screens/expense_editor.dart`: edición manual disponible durante análisis, descarte de resultados tardíos al continuar manualmente/guardar, timeout OCR por archivo, confirmación compacta de propuestas sin sucesión de diálogos.
- `flutter/inge_earth/lib/renditions/v3/state/smart_fill.dart`: aviso de revisión automática no disponible.
- `flutter/inge_earth/lib/renditions/renditions_bridge.dart`: errores de comandos y estado convertidos a mensajes humanos; conserva códigos internos para decisiones.
- `tests/renditions/checks.cpp`: regresiones nativas añadidas para UPDATE interrumpido, CREATE confirmado y tombstones DELETE. No ejecutadas: requieren compilar.
- `tests/renditions/smartfill_gold_fixture.py`: PDF sintético para probar bus/Worker, no factura original ni plantilla oficial.
- `flutter/inge_earth/test/renditions_v3_test.dart` y `renditions_received_v2_test.dart`: expectativas ajustadas al dock actual (tres acciones, Resumen visible, selectores vigentes).

Respaldo anterior a edición en `.codex_backups/rendiciones_final_20260914`. Se preservaron modificaciones anteriores del usuario. No se editaron Home, Calicatas, InGe Earth, Auth, CMake ni Worker externo.

## Validación ejecutada

Desde `flutter/inge_earth`, SDK `C:/Users/PC-02/Develop/flutter-3.44.9/flutter/bin`:

```text
flutter test --no-pub test/renditions_closure_test.dart test/renditions_ocr_test.dart test/renditions_edit_test.dart test/renditions_v3_test.dart test/renditions_received_v2_test.dart --reporter expanded
18/18 PASS
dart analyze lib/renditions/renditions_bridge.dart lib/renditions/v3/renditions_root.dart lib/renditions/v3/screens/expense_editor.dart lib/renditions/v3/state/smart_fill.dart
0 errores; 4 avisos informativos de estilo
git diff --check -- <archivos tocados>
sin errores de whitespace; avisos de conversión LF/CRLF
```

Log: `artifacts/rendiciones-final-flutter-tests.log`. Tests Flutter no prueban el C++ modificado ni el comportamiento físico.

Supabase: inspección de RPCs existentes, sin cambios de esquema/RLS/storage. `tests/renditions/closure_delete.sql` se intentó con rollback y devolvió TEST_FIXTURE_MISSING: no existe borrador elegible para esa prueba. No se afirma SERVER_TESTED para borrados.

Se creó únicamente un job sintético de prueba: `codex-renditions-gold-20260914-final`, conservado en el bus. SUCCEEDED, un intento, 2026-09-14 19:12:02–19:12:14 UTC. Resultado: fecha 2026-05-28, RUC 10459805597, E001-884, PEN, subtotal 238.14, IGV 42.86, total 281.00, concepto EPP/herramientas. Sin método de pago inferido. Advertencia por fecha fuera del período. El proveedor quedó en conflicto entre emisor y cliente: requiere confirmación. No equivale a validar Android ni la factura original.

## Limitaciones y siguiente QA

Persisten P0 por verificar: respuesta UPDATE perdida después de commit puede permanecer en conflicto; no se añadió resolución humana completa de CAS. Pull de cabeceras sigue limitado a 50 filas y no reconcilia borrados realizados en otro dispositivo mediante ausencia. No se cerró deduplicación de cabecera tras CREATE con respuesta perdida y pull concurrente. La cancelación manual de revisión descarta la respuesta en UI; el job remoto puede continuar hasta completarse/expirar. Descarga de adjuntos y migraciones no probadas físicamente. Guardas PRESENTADA requieren regresión nativa. El centrado visual de Resumen no se modificó sin evidencia física adicional.

No se inició ExportService ni exportación offline. Búsqueda breve en Documents/RENDICIONES y Templates no identificó plantilla oficial de Rendiciones; Excel/PDF finales pendientes por plantilla. No se inventó formato.

QA manual: A–H del prompt, conflictos entre dispositivos, reinicio con outbox, doble refresh, Worker caído con edición manual, respuesta tardía, factura real E001-884, adjuntos desde segundo dispositivo y PRESENTADA inmutable.

```text
FULL_ANDROID_BUILD=NOT_RUN_USER_REQUEST
APK=NOT_RUN_USER_REQUEST
ADB=NOT_RUN_USER_REQUEST
COMMIT=NOT_RUN_USER_REQUEST
BASE_CLOSURE=PHYSICAL_VALIDATION_PENDING
```
