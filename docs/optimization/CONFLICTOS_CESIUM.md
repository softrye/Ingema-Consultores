# CONFLICTOS_CESIUM — IMPORTANTE: no aplicar directamente

Se compararon SHA-256 de los archivos locales con la base Git `9a1ba8c` y con los archivos de Claude Cloud.

Ruta local: `C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo`

**9 archivos divergen**, lo que impide aplicar directamente el ZIP sobre la versión Cesium local:

| Archivo que requiere merge de 3 vías | Riesgo |
|---|---|
| `CMakeLists.txt` | Dependencias/build y recursos de Cesium |
| `android/src/com/ingema/ingeplus/InGeQtActivity.java` | WebView, GPS, miniatura Satélite |
| `flutter/inge_earth/pubspec.yaml` | Recursos Flutter y configuración |
| `main_mobile.cpp` | Qt/Flutter, eventos de memoria |
| `qml/Mobile/flowcore/FlowGlassSurface.qml` | Vidrio y optimización GPU |
| `qml/Mobile/pages/CalicataFormPage.qml` | Formulario, título, nombre largo/corto |
| `qml/Mobile/pages/CalicatasEditorPage.qml` | Selector y ficha |
| `src/graphics/InGeGraphicsCore.cpp` | Puente Java/Cesium/QML |
| `src/graphics/InGeGraphicsCore.h` | Contratos de puente JNI |

Además se identificaron 16 archivos equivalentes a la base y 7 archivos nuevos/ausentes antes del cierre Fase D. Estos conteos corresponden al estado de verificación anterior a empaquetar.

## Protocolo seguro

1. Respaldar el proyecto local completo. Su directorio `.git` está incompleto.
2. Extraer VERSIÓN a una carpeta temporal; ejecutar `instalar_version.ps1 -CheckOnly`.
3. Si reporta CONFLICT, no usar el instalador y no forzar sobrescrituras.
4. Realizar merge manual por archivo comparando base, Claude Cloud y el proyecto local. Preservar el visor Cesium, capturas satelitales, modo selector, testificación y nombre corto/largo.
5. Validar después con Qt Creator arm64-v8a, Galaxy A12, GPS, fotos, Excel, sincronización y estados de revisión documental.
6. Conservar el ZIP como insumo de integración, no como parche de aplicación directa.

No ejecutar `git reset --hard`, ni reemplazar directorios completos, ni reconstruir `.git` sin un respaldo verificable.
