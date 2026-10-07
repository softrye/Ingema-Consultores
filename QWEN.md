# InGe Repair Agent

Trabajas directamente sobre:
C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo

Tu misiÃ³n es resolver errores reales de InGe+ mediante ingenierÃ­a verificable, no mediante una cadena de BAT improvisados.

## Flujo obligatorio

AUDITAR -> REPRODUCIR -> CAUSA RAÃZ -> BACKUP/DIFF -> CAMBIO MÃNIMO -> VALIDAR -> BUILD -> ADB/LOGCAT -> RUNTIME -> VERIFICAR

## Rutas

Repo:
C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo

Qt Android Release:
C:\Users\PC-02\Documents\InGePlus_Builds\Qt_6_9_3_Android_arm64_Release_Manual

Android generado:
C:\Users\PC-02\Documents\InGePlus_Builds\Qt_6_9_3_Android_arm64_Release_Manual\android-build-AppCalicatasMobile

Flutter:
C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo\flutter\inge_earth

ADB:
C:\Users\PC-02\AppData\Local\Android\Sdk\platform-tools\adb.exe

Package:
com.ingema.ingeplus

Earth Activity:
com.ingema.ingeplus.InGeEarthFlutterActivity

## Arquitectura

InGe+ Qt/QML
-> Flutter Add-to-App
-> Flutter UI
-> CesiumJS / WebView como renderer activo V1

Cesium Native / Filament / Vulkan permanecen como backend experimental/futuro.

## Reglas

- Lee los archivos reales antes de editar.
- Reproduce o confirma el fallo antes de proponer cambios.
- Inspecciona fuente y copias generadas.
- Usa `gradlew tasks --all` antes de asumir nombres de tareas.
- Distingue warnings de errores fatales.
- Usa `releaseCompileClasspath` / `releaseRuntimeClasspath` cuando sea un problema de dependencias.
- Usa Dart/Flutter analyze cuando corresponda.
- Para runtime Android usa ADB, PID, Activity real, dumpsys y logcat.
- No analices logs de otra aplicaciÃ³n como si fueran InGe+.
- Antes de cambios importantes crea backup o checkpoint.
- Modifica lo mÃ­nimo necesario.
- No abras Qt Creator desde scripts.
- No uses git push, git reset --hard ni git clean -fd.
- No leas ni imprimas credenciales de keystore.
- No toques Cesium Native / Filament / Vulkan salvo evidencia directa.
- No declares Ã©xito solo porque compile.

## Ã‰xito de InGe Earth

Debe verificarse en dispositivo:
- abre desde InGe+;
- Activity correcta;
- UI ocupa la pantalla correctamente;
- globo visible;
- giro y pinch funcionan;
- buscador funciona;
- CAPAS / PUNTOS / UBICAR / MEDIR / VISTA funcionan;
- Back vuelve correctamente;
- sin pantalla GraphicsCore tÃ©cnica;
- sin crash fatal en logcat.

Comienza siempre auditando y utilizando evidencia.

<!-- BEGIN_INGE_CONTEXT_DISCIPLINE_V2 -->
## Disciplina obligatoria de contexto para modelo local 32K

El modelo tiene 32768 tokens de contexto. Debes trabajar de forma selectiva.

1. NO leas archivos grandes completos por defecto.
2. Para main.dart, cesium_js_renderer.dart, index.html, Gradle y logs:
   - primero usa bÃºsqueda por sÃ­mbolo/error;
   - limita resultados;
   - lee Ãºnicamente rangos pequeÃ±os alrededor de coincidencias.
3. Si un archivo es grande, no hagas Read completo salvo necesidad demostrada.
4. No vuelvas a leer un archivo ya entendido sin una razÃ³n concreta.
5. No listes Ã¡rboles completos del repositorio.
6. Usa `git status --short --untracked-files=no` en vez de salidas masivas.
7. Usa `git diff --name-only` y luego diff por archivo.
8. Nunca leas repair_backups, repair_ai, build, .gradle, .dart_tool, node_modules o logs completos.
9. Limita logcat a tags/patrones relacionados con el fallo actual.
10. Antes de pasar de AUDITORIA a FIX, de FIX a BUILD y de BUILD a RUNTIME, actualiza `.qwen/WORKING_STATE.md` con:
    - evidencia;
    - causa probable/confirmada;
    - archivos tocados;
    - comandos verificados;
    - siguiente paso.
11. Cuando el indicador de contexto se acerque a 50%, deja de abrir archivos nuevos grandes y consolida el estado en WORKING_STATE.md.
12. Tras una nueva sesiÃ³n, lee QWEN.md y WORKING_STATE.md y continÃºa desde ese estado; no repitas la auditorÃ­a completa.
13. Una bÃºsqueda o comando que pueda devolver cientos/miles de lÃ­neas debe limitarse desde el propio comando.
14. El objetivo es reparar InGe Earth con evidencia de build y runtime, no acumular contexto.
<!-- END_INGE_CONTEXT_DISCIPLINE_V2 -->
