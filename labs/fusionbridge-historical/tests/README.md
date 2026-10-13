# Verificación local de FusionBridge

Estos comandos no construyen Android ni necesitan ADB. `javac` compila
únicamente tres clases Java puras y el arnés, sin SDK Android.

Desde la raíz del repositorio:

```powershell
python scripts/verify_fusionbridge_static.py
& 'C:/Program Files/Android/Android Studio/jbr/bin/javac.exe' -d '../_backups/fusionbridge_native_20261013_before/host-tests' android/src/com/ingema/ingeplus/fusionbridge/EarthFramePolicy.java android/src/com/ingema/ingeplus/fusionbridge/EarthInputController.java android/src/com/ingema/ingeplus/fusionbridge/EarthSessionPolicy.java tests/fusionbridge/FramePolicyTest.java
& 'C:/Program Files/Android/Android Studio/jbr/bin/java.exe' -cp '../_backups/fusionbridge_native_20261013_before/host-tests' com.ingema.ingeplus.fusionbridge.FramePolicyTest
git diff --check
```

Resultados de la sesión: 61 comprobaciones estáticas y 25 comprobaciones de
política JVM. La política se verificó primero con el módulo ausente (fallo), y
después contra las clases reales: sesión cerrada, visibilidad desconocida,
negro, repetición, caducidad exacta a 2500 ms, orden temporal, revocación,
generación anterior, rechazo explícito de controles sin canal y recuperación
de anfitrión perdido sin depender del texto de diagnóstico.

El comprobador estático comprueba referencias/registro/manifiesto y equilibrio
léxico, NO sintaxis completa, compilación, frames Android o efectos geográficos.
Los hashes de archivos compartidos se comparan con el commit base `a7f0ea7`.

Se ejecutaron además los 46 scripts CJS existentes de solo lectura: 32 pasaron
y 14 fallaron. Se excluyó `web_sucs_symbols.cjs` porque genera/modifica assets.
La lista completa de fallos y su causa está en
`docs/FUSIONBRIDGE_NATIVE_20261013.md`. No se alteraron tests antiguos para
convertir esos fallos en éxitos.
