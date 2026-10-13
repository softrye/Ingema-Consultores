# InGe+ Android

Fuentes actuales del host Android Qt 6.9.3, C++, QML y Flutter. El target principal es `AppCalicatasMobile`, para `arm64-v8a`.

## Arquitectura y dependencias

- `CMakeLists.txt` y `main_mobile.cpp`: host, servicios, JNI y registro QML.
- `qml/Mobile/Main.qml`: entrada QML; módulo `InGe.Mobile` y un único InGeCoreFlow.
- `android/src/`: actividades, puentes Flutter, Google Drive y WebView de IA.
- `flutter/inge_earth/`: Home, autenticación, InGe Earth y Rendiciones. CMake genera su AAR desde las fuentes y el lockfile.
- `android/web/inge-ai/`: integración real de Gemini Live, adaptada para Android. Entrada: `src/inge/main.tsx`. Conserva cliente, audio, worklets y licencias; los módulos del demo que no se importaban fueron retirados.
- `src/`, fuentes C++ raíz, `Templates/` y `SUCS/`: documentos, sincronización, Calicatas y exportación.
- `supabase/`: funciones, contratos SQL, migraciones y rollback. No ejecutar SQL de pruebas contra producción.
- `thirdparty/QXlsx/`: dependencia compilada desde fuente.
- `flutter/inge_earth/` y `android/assets/cesium/`: cartografía y experiencia InGe Earth sobre Cesium.

## Compilación

Abrir `CMakeLists.txt` en Qt Creator con Qt 6.9.3 Android arm64-v8a. El kit local actual utiliza NDK `27.2.12479018`, SDK Android y el JBR de Android Studio. También requiere Flutter 3.44.9 y Node.js >=22.12 con npm.

Usar un directorio de compilación **fuera** del repositorio, por ejemplo `C:/InGeBuild/A37`. CMake usa las bibliotecas OpenSSL externas del SDK Android y la cartografía se concentra en InGe Earth/Cesium.

El CMake actual genera el AAR en `flutter/inge_earth/build/` y los recursos web en `android/assets/inge-ai/`, aunque el directorio CMake sea externo. Son salidas regenerables. Para validar sin generar nada dentro del árbol original, compilar una copia temporal de las fuentes actuales fuera del proyecto, con los mismos archivos y lockfiles. No usar APK extraídas ni fuentes de un build anterior.

No borrar `.qtcreator/`, `android/local.properties` ni archivos `.env` locales por su nombre: contienen configuración del kit o del producto. No registrar ni publicar sus valores. Las claves de firma permanecen fuera del repositorio.

## Documentación y comprobaciones

- [Contrato actual de Calicatas Web ↔ Android](docs/CALICATAS_CONVERGENCIA_WEB_ANDROID_20261007.md).
- [Exportación híbrida](docs/CALICATAS_EXPORTACION_HIBRIDA_20261006.md).
- [Media y sincronización](docs/CALICATAS_MEDIA_BACKEND_P0_20261002.md).
- [Integración Gemini Live](docs/INGE_GEMINI_LIVE_INTEGRATION_20261005.md).
- [Diseño INGEMA](docs/INGEMA_DESIGN_SYSTEM_APP_20261006.md).
- [Material Liquid Glass](docs/LIQUID_GLASS_GLOBAL_20261001.md).
- [Arnés de Calicatas](tests/calicatas/README.md).

`tests/` conserva pruebas estáticas Node, contratos SQL, fixtures y arneses CMake del código real. Flutter mantiene sus pruebas en `flutter/inge_earth/test/`; la consola web expone `npm test` y `npm run check`. Los resultados históricos de documentos no certifican una revisión nueva.

`resources.qrc`, `resources_mobile_ui_v2.qrc` y el QRC de Propuesta A contienen recursos activos. `resources_mobile_raw.qrc` no se enlaza al APK: se conserva por una prueba estática vigente. No borrar recursos registrados, fuentes, shaders ni licencias por ser antiguos o idénticos a otro archivo.
