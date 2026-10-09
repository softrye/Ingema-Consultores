# Estado de los 42 hallazgos (2026-10-09)

Base: `9a1ba8c`. IMPLEMENTADO significa cambios en codigo con comprobaciones parciales, nunca PASS fisico en Android.

| Area | Hallazgo | Estado | Evidencia |
|---|---|---|---|
| layout | `breakpoint-cambia-con-teclado` | IMPLEMENTADO / SIN APK | 5b3f407/5dfe43c |
| layout | `minimos-texto-tactil-360dp` | IMPLEMENTADO / SIN APK | b86045c/dccf8f3 |
| layout | `fuente-unica-escala-flowmetrics` | PARCIAL | 4ce62a5; otras metricas pendientes |
| layout | `escala-texto-sistema-y-usuario` | IMPLEMENTADO / SIN APK | 4ce62a5 |
| layout | `dock-geometria-fija-y-holguras` | PENDIENTE | No abordado |
| layout | `safe-area-cuatro-lados` | PENDIENTE | No abordado |
| layout | `imagenes-densidad-sourcesize` | PARCIAL | 32a4ad3; otros recursos pendientes |
| layout | `orientacion-telefono-sin-diseno` | PENDIENTE | No abordado |
| gpu | `tier-no-llega-a-qml` | IMPLEMENTADO / SIN APK | 61744b3 |
| gpu | `refresh-ignora-budget` | IMPLEMENTADO / SIN APK | a733e8e/a2bd2e9 |
| gpu | `dock-glass-capturas-vivas` | IMPLEMENTADO / SIN APK | a8ea406 |
| gpu | `calicata-glass-memoria` | IMPLEMENTADO / SIN APK | a8ea406 |
| gpu | `glass-surface-layer-sombra` | PARCIAL | a245800; sombras pendientes |
| gpu | `flowicon-layer-por-icono` | PARCIAL | 7b27781; capas restantes |
| gpu | `avatar-sin-sourcesize` | IMPLEMENTADO / SIN APK | 8d4c810 |
| memory_startup | `avatar-decodificacion-completa` | IMPLEMENTADO / SIN APK | 8d4c810 |
| memory_startup | `earth-webview-retenida-sin-renderer-gone` | IMPLEMENTADO / SIN APK | 00f6d2a/76aa04d |
| memory_startup | `presion-memoria-y-tier-no-llegan-a-qt` | IMPLEMENTADO / SIN APK | 61744b3/76aa04d |
| memory_startup | `build-debug-flutter-jit` | PARCIAL | d8392c2; Debug sigue en JIT |
| memory_startup | `calicatas-creacion-sincrona` | PENDIENTE | No abordado |
| memory_startup | `arranque-arboles-qml-ocultos` | PARCIAL | 32a4ad3; resto pendientes |
| memory_startup | `exportacion-sincrona-hilo-gui` | PENDIENTE | No abordado |
| memory_startup | `polling-jni-flutter` | PENDIENTE | No abordado |
| memory_startup | `arranque-frio-y-peso-binario` | PARCIAL | 5c2fd38/Fase D; sin medicion |
| build | `android-debug-por-defecto` | PARCIAL | d8392c2; Debug por defecto |
| build | `flutter-aar-debug-jit` | PARCIAL | d8392c2; Debug en JIT |
| build | `qrc-escritorio-en-android` | IMPLEMENTADO / SIN APK | Fase D |
| build | `video-auth-1440p` | IMPLEMENTADO / SIN APK | 6b8df05/b82f713 |
| build | `qml-aot-bloqueado` | PENDIENTE | No abordado |
| build | `plugins-qt-sin-uso` | IMPLEMENTADO / SIN APK | Fase D |
| build | `imagenes-sobredimensionadas-duplicadas` | PARCIAL | 6b8df05/32a4ad3; otros recursos |
| build | `gradle-release-sin-r8-ni-baseline` | PENDIENTE | No abordado |
| build | `flags-enlazador-nativo` | PENDIENTE | No abordado |
| android_platform | `budget-android-no-llega-a-inGeCoreFlow` | IMPLEMENTADO / SIN APK | 61744b3 |
| android_platform | `termico-ahorro-bateria-estaticos` | IMPLEMENTADO / SIN APK | 61744b3 |
| android_platform | `refresco-ignora-presupuesto` | IMPLEMENTADO / SIN APK | a733e8e |
| android_platform | `gps-earth-no-se-apaga` | IMPLEMENTADO / SIN APK | cbbbcad/a2bd2e9 |
| android_platform | `memoria-earth-webview-sin-ontrimmemory` | IMPLEMENTADO / SIN APK | 76aa04d |
| android_platform | `camara-muerte-proceso-pierde-foto` | IMPLEMENTADO / SIN APK | ba7741a |
| android_platform | `flutter-init-sincrona-hilo-ui` | IMPLEMENTADO / SIN APK | 5c2fd38 |
| android_platform | `barras-sistema-edge-to-edge-noche` | PENDIENTE | No abordado |
| android_platform | `manifest-permisos-almacenamiento-cleartext` | PENDIENTE | No abordado |

Resumen: {'IMPLEMENTADO / SIN APK': 21, 'PARCIAL': 10, 'PENDIENTE': 11}

No se tocaron contratos Android-Web ni se probó un APK integrado. Mantener los hallazgos pendientes en el backlog.
