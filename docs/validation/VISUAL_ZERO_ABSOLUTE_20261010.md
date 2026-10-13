# InGe+ — Visual Zero absoluto (Android)

Fecha de cierre de fuente: 2026-10-10. Alcance: proyecto local AppCalicatasDemo, target Android/Mobile; no incluye el target Desktop legado, los recursos internos de Cesium ni las pantallas del sistema operativo.

## Fuente de verdad y respaldo

Fuente local: C:\\Users\\PC-02\\Documents\\InGePlus\\AppCalicatasDemo

Respaldo anterior a los cambios de Claude: C:\\Users\\PC-02\\Documents\\InGePlus\\_backups\\visual_zero_absolute_local_20261010

Rama del repositorio Ingema Consultores: feature/visual-zero-absolute-20261010

Checkpoint Claude publicado: 740b3137eb11de72a72fc391d712d015184a0613

## Inventario

- Antes (archivo SIZE_BEFORE.txt de la copia de Claude): 2.414 archivos, 122.192.136 bytes.
- Después (misma política de excluir builds y carpetas generadas): 997 archivos, 84.552.919 bytes.
- Diferencia: 1.417 archivos y 37.639.217 bytes menos (30,8 % por bytes).
- QML Mobile: solo Main.qml estructural y 8 bibliotecas JS de dominio; no quedan formularios QML visibles.
- Flutter Dart: 9 archivos fuente de lógica/servicios; main.dart no invoca runApp.
- Earth: Cesium y archivos engine/ conservados, capas UI personalizadas y pantallas de carga retiradas.
- InGe IA: sin consola React/WebView; GeminiAssistant::kEnabled = false.

## Integración realizada tras el checkpoint

1. CMake Mobile utiliza siempre resources_mobile_brand.qrc, no resources.qrc del target de escritorio, para evitar empaquetar QML eliminados.
2. La inicialización de RemoteExecutor arranca después de crear la raíz QML (QTimer::singleShot), sin esperar un frameSwapped de una interfaz vacía.
3. Corrección de estilo Dart en validación de rendiciones sin cambiar las reglas de negocio.

## Pruebas

- CMake Qt 6.9.3/MinGW Windows: configure PASS.
- AppCalicatasMobile Windows: compilación y enlace PASS, 104/104 pasos.
- Flutter analyze --no-pub: PASS, 0 issues.
- Flutter test --no-pub: PASS, 18/18.
- Node equivalencia/lógica: form 6, workspace 4, account 3, photo 2, Earth 7 PASS.
- Android APK compilación e instalación: NOT_RUN.
- Integración con backend remoto / dispositivos: NOT_RUN.

**Alcance del PASS:** confirma código fuente y verificación nativa Windows, no disponibilidad operativa en Android. La app se encuentra intencionalmente sin interfaz de usuario ni Login, hasta crear un sistema visual nuevo. Conservar servicios y compilación no implica que sea utilizable sin UI.

## Seguridad del cambio

No se aplicaron migraciones Supabase, no se modificó el proyecto Web y no se fusionó main. Los recursos retirados por Claude están en REMOVED_FROM_TREE del respaldo.
