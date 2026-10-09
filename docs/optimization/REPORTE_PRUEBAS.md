# REPORTE DE PRUEBAS — VERSIÓN optimización InGe+

## Verificaciones de esta continuación

| Prueba | Estado | Qué se comprobó |
|---|---|---|
| Qt 6.9.3 RCC | PASS | resources_mobile_brand.qrc contiene logos/aliases existentes |
| Qt 6.9.3 qmlcachegen | PASS | Main.qml genera bytecode sin error |
| Node p0_device_bugs_static.cjs | PASS | Contratos estáticos de Calicatas sin regresión |
| c_aa01_closure_static.cjs | PASS (9 casos) | Contratos C-AA-01 |
| performance_static.cjs | PASS (14 casos) | Rendimiento estático |
| glass_calicatas_static.cjs | PASS (5 casos) | Materiales QML |
| git diff --check | PASS | No hay errores de whitespace |
| Auditoría de uso QtLocation | PASS estático | Main.qml solo tenía import inactivo; QtLocation se conserva en Desktop |
| Compilación Android arm64-v8a | NOT_RUN | Requiere integración en máquina local |
| Pruebas en Galaxy A12 / Moto G04 | NOT_RUN | No se instaló ningún APK |
| Render Cesium, cámara y GPS | NOT_RUN | Dependen del APK integrado |
| Compatibilidad Android-Web de nombres largo/corto | BLOQUEADO | Requiere adaptar Supabase y Web |

## Pruebas comunicadas por Claude Cloud (no repetidas)

- Línea base: 35 de 36 pruebas estáticas PASS; 1 fallo preexistente.
- Fase A: 19 casos de QML/InGeCoreFlow; escala 15 combinaciones.
- CMake 12 casos; gestión de breakpoints 10 casos; avatares y texturas de vidrio con arneses puntuales.
- Tests Java/C++ con stubs/cabeceras de escritorio; NO equivalen a build de Android Qt 6.9.3.

## Criterio de cierre

El código es candidato a PRE-RELEASE con validación estática. Falta build Release, pruebas de funcionamiento y comprobación de rendimiento en dispositivos reales. No afirmar FPS ni reducción de memoria total sin medir.
