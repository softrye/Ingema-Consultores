# InGe+ Android v1.1.10-beta.1 — Integración de fuente local y optimización

**Entrega:** revisión integrada de código, sin recompilación en esta sesión.
**Rama:** `feature/android-prime-v1.1.10-beta.1`.
**Base optimizada:** `756745cad9705fdae506eebe0dda2ebe05d06902` (Claude Cloud, 09/10/2026).
**Base Android original:** `9a1ba8c7db22d807dfe500aeec85b73838e3d110`.

## Integración

Se incorporaron archivos locales existentes mediante copia directa y se combinaron por tres vías nueve archivos compartidos con Cloud. No se reimplementaron funciones:
- `InGeQtActivity.java` y `InGeGraphicsCore`: selector Cesium, carga visual única, captura satelital, ciclo de vida, eventos Android y perfiles de hardware.
- `CalicataFormPage.qml`, `CalicatasEditorPage.qml`, `calicatadocument.cpp`, exportador: cabecera tipo de ficha, nombres oficial/corto y lógica de guardado/exportación.
- `inge-map-loading.js`, `inge-earth-picker.js`: coordinador de carga, cámara/teselas y previsualización.
- `FlowGlassSurface.qml`, `main_mobile.cpp`, Flutter y CMake: optimizaciones de memoria/GPU, accesibilidad, recursos y puente entre motores.

Se conserva la optimización Cloud: video Auth reducido a 5.77 MB, rendimiento adaptativo Java/Qt/Flutter, WebView recuperable, gestión de memoria, foto pendiente y recursos Android selectivos.

## APK adjunto, ya compilado

Archivo firmado **preexistente**: `C:\InGeBuild\A37\android-build\build\outputs\apk\release\android-build-release-signed.apk`.
Fecha de compilación: 09/10/2026 14:36 (Galaxy A12).
SHA-256: `8808961801c721b0e87e76b725d6dcb30ecaa40137f47fc8454c39df854d6437`.
**Aviso:** este APK representa la última compilación del proyecto local anterior a la integración Cloud. No contiene la suma recién fusionada de todos los cambios de optimización. No se recompiló por instrucción expresa del usuario.

## ZIP de actualización local

El ZIP contiene archivos finales y hashes SHA-256 del estado local anterior, para sustituir exclusivamente archivos distintos y conservar los demás. Usar `instalar_version.ps1 -CheckOnly` antes de reemplazar. Un archivo local modificado después del inventario hará fallar la comprobación.

No subir secretos, `local.properties`, `.env`, llaves ni directorios generados. Ninguna migración o escritura en Supabase. Ningún cambio en `E1PT04m0/ingeplus`.

## Validación de código

PASS: selector Cesium (9), sistema único de carga (8), P0 Calicatas, C-AA-01 (9), performance (14), Liquid Glass (5), parseo QML y JavaScript.
PENDIENTE: compilación e instalación de la **fuente fusionada** y pruebas completas en Android.
FAIL conocido: `web_lab_parity_static.cjs` exige la eliminación del nombre corto de proyecto, contraria al requerimiento vigente.

El número v1.1.10-beta.1 identifica el código y el paquete de actualización. El APK se proporciona como compilación local histórica, no se declara APK integrado.
