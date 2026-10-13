# FusionBridge Native Implementation Plan

> Ejecución autorizada por el usuario: secuencial en el checkout principal.
> Aplicar superpowers:executing-plans. No delegar, compilar Android ni usar ADB.

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
- [ ] Retirar elección de motor/cola/insets JS de InGeQtActivity, conservando Cesium inactivo.
- [ ] Retirar openEarthViewer/earthCommand/closeEarthViewer de PermissionHelper.
- [ ] Retirar flujo y herramientas MapLibre de Home; conservar entradas Calicatas.
- [ ] Retirar android/assets/ingeearth del empaquetado; conservar fuentes web históricas con aviso.
- [ ] Buscar referencias activas, revisar diff y crear commit de fase.

## Fase 2 — módulo nativo
- [ ] Escribir y ejecutar prueba de frescura/cancelación/rechazo antes del módulo.
- [ ] Añadir detector y diagnósticos de componentes sin inventar IPC.
- [ ] Añadir servicio MediaProjection: consentimiento, protección recursiva,
  resize, visibilidad, límite de recursos, cierre idempotente.
- [ ] Añadir EarthFrameBridge y EarthInputController con rechazo explícito.
- [ ] Añadir FusionBridgeController y proveedor RGBA Qt; registrar solo contexto QML.
- [ ] Añadir EarthSurfaceHost.qml al único módulo InGe.Mobile; reutilizar Dock.
- [ ] Verificar estáticamente manifiesto/JNI/CMake/QML y pruebas de política.
- [ ] Documentar límites, matriz FB-01…FB-12 y pruebas manuales; commit de fase.

## Fase 3 — entrega
- [ ] Revisar diff, archivos protegidos y recursos compartidos contra el respaldo.
- [ ] Informar IMPLEMENTED/CODE_READY/BLOCKED y comandos ejecutados.
- [ ] Entregar pasos Qt Creator/regresión sin declarar PASS_ANDROID.
