# FusionBridge Native Implementation Plan

> Ejecución autorizada por el usuario: secuencial en el checkout principal.
> Aplicar superpowers:executing-plans. No trabajo en paralelo, compilación Android ni ADB.

**Goal:** retirar MapLibre y entregar un módulo nativo verificable sin simular Earth.
**Architecture:** detector Android, controlador C++ único, prueba MediaProjection
con consentimiento y host visual Qt. Entrada interactiva bloqueada sin contrato.
**Tech Stack:** Qt 6.9.3, C++, QML, JNI, Java, MediaProjection API 34+.
**Spec:** ../specs/2026-10-13-fusionbridge-native-design.md

## Restricciones globales
Una APK, mismo package, mismo Dock y un solo InGeCoreFlow. No tocar archivos
protegidos, datos locales, correo, Login ni Supabase. No usar fallback de motor.

## Riesgos a verificar
- Cancelar consentimiento o cerrar Earth antes del resultado no reabre captura.
- Regresar de Earth a Calicatas conserva coordenadas y destino de retorno.
- Ocultación/revocación/no cambio limpia el cuadro y no aparenta conexión.
- Salir/reentrar libera recursos y requiere nuevo token.
- Captura no permite controlar otra app; ningún envío se anuncia como éxito.

## Fase 0 — respaldo
- [x] Copia completa de fuentes externa con manifest SHA-256 verificado.
- [x] Diagnosticar Git incompleto; conservarlo en respaldo e iniciar historia base.
- [x] Escribir diseño y plan desde la solicitud autorizada.

## Fase 1 — retirada MapLibre
- [x] Retirar elección de motor/cola/insets JS de InGeQtActivity, conservando Cesium inactivo.
- [x] Retirar openEarthViewer/earthCommand/closeEarthViewer de PermissionHelper.
- [x] Retirar flujo y herramientas MapLibre de Home; conservar entradas Calicatas.
- [x] Retirar android/assets/ingeearth del empaquetado; conservar fuentes web históricas con aviso.
- [x] Buscar referencias activas, revisar diff y crear commit de fase.

## Fase 2 — módulo nativo
- [x] Escribir y ejecutar prueba de frescura/cancelación/rechazo antes del módulo.
- [x] Añadir detector y diagnósticos de componentes sin inventar IPC.
- [x] Añadir servicio MediaProjection: consentimiento, protección recursiva,
  resize, visibilidad, límite de recursos, cierre idempotente.
- [x] Añadir EarthFrameBridge y EarthInputController con rechazo explícito.
- [x] Añadir FusionBridgeController y proveedor RGBA Qt; registrar solo contexto QML.
- [x] Añadir EarthSurfaceHost.qml al único módulo InGe.Mobile; reutilizar Dock.
- [x] Verificar estáticamente manifiesto/JNI/CMake/QML y pruebas de política.
- [x] Documentar límites, matriz FB-01…FB-12 y pruebas manuales; commit de fase.

## Fase 3 — entrega
- [x] Revisar diff, archivos protegidos y recursos compartidos contra el respaldo.
- [x] Informar IMPLEMENTED/CODE_READY/BLOCKED y comandos ejecutados.
- [x] Entregar pasos Qt Creator/regresión sin declarar PASS_ANDROID.

## Evidencia de cierre de código

61 verificaciones estáticas, 25 checks JVM, suite CJS 32/46 con 14 fallos de
entradas preexistentes contrastadas contra Git. No hay build/instalación/logcat:
esa fase está reservada al usuario. La conexión directa e input a Earth
permanecen BLOCKED, no son pendientes ocultos detrás de esta lista de código.

Ruling: implementación secuencial en el checkout principal. Revisión final
de solo lectura mediante un revisor, esperada antes de continuar, siguiendo
requesting-code-review. No hubo ejecución de tareas en paralelo ni worktree.

Ruling: los cuadros de la prueba son de origen no verificado — MediaProjection
no acredita aquí la identidad del paquete seleccionado; no declarar Earth
incrustado ni control geográfico exitoso.

Ruling: no alterar 14 tests/entradas antiguos para ocultar fallos — sus causas
se registran en el informe; no son evidencia de regresión Android aprobada.

Revisión final: P2 de recreación Activity con Qt retenido corregido. Marcador
de pérdida independiente de diagnósticos, recuperación tras resume con
generación nueva y consentimiento nuevo. Cinco checks JVM adicionales y
revisión del delta sin nuevos hallazgos concretos; Android sigue pendiente.
