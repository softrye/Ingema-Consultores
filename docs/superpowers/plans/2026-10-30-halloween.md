# Halloween cute — plan y registro de ejecución

**Objetivo:** completar la especificación adjunta del 30/10/2026 sobre la rama
`codex/fusionbridge-native`, Qt 6.9.3, Android arm64-v8a y Samsung A12 LOW.

**Arquitectura:** arte SVG original, un `HalloweenController` de presentación
alimentado por el único InGeCoreFlow y una `HalloweenLayer` reutilizada dentro
del fondo existente. Un Timer compartido mueve hasta diez sprites y cuenta
uso activo. No cambia comandos, datos, sesión ni sincronización.

**Decisiones:** SVG con rasterización a tamaño acotado; no texturas por frame,
blur adicional, shaders nuevos ni emojis. La opción `auto` resuelve Halloween
entre el 15 y el 31 de octubre; las opciones manuales se conservan. Los sustos
esperan una superficie segura y se cierran al aparecer IME, hojas o trabajo
en curso. Reduce motion conserva solo el aviso pequeño estático.

**Ejecución:** secuencial, en el checkout indicado por el usuario. Hay cambios
previos de múltiples tareas; se preserva una copia de los archivos a tocar en
`C:/InGeBuild/Halloween_20261030/baseline` para auditar exclusivamente esta tarea.

## Fases

- [ ] 1. Pruebas de calendario, reloj activo y seguridad; SVG originales y
  política compartida. Verificar fallo inicial y pruebas verdes. Commit de fase.
- [ ] 2. Controller/capa, integración de fondos, Dock, menús, login y ajustes.
  Persistir sustos (sí) y sonido (no). Registrar recursos QRC/CMake por la
  estrategia existente. Probar QML real y regresión host. Commit de fase.
- [ ] 3. qmllint, CMake, host completo, build arm64, instalación sin borrar datos,
  logcat limpio, arranque, regresión y capturas. Medición de diez minutos y dos
  sustos con thermal inicial/final y frames. Documentar evidencia y riesgos.
  Commit de validación.

## Revisión de condiciones importantes

- Cambiar de Halloween a otra skin restaura todos los tokens y detiene su reloj.
- Background, página oculta y calor elevado detienen decoraciones; no cuentan
  tiempo de background. No recuperar tiempo perdido al volver.
- Teclado, login, confirmación, exportación y sincronización bloquean sustos.
- La capa decorativa no toma eventos; un observador pasivo comunica el dedo.
- Sin sonido por defecto; volumen suave explícito y sin destellos.

## Registro

- Preflight: rama correcta; Samsung SM-A127M conectado; Qt 6.9.3, build Android
  y `C:/InGeBuild/RenditionHost_20261016b` disponibles. Base Halloween sin compilar.
- Referencia Qt: FrameAnimation y PointHandler (observación pasiva),
  https://doc.qt.io/qt-6/qml-qtquick-pointhandler.html.
