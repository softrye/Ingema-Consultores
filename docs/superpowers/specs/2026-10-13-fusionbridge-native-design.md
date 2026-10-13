# FusionBridge Native — diseño y límites

Solicitud de referencia: P0 del usuario, 2026-10-13. Ejecución secuencial en este
checkout, autorizada explícitamente; sin build Android ni ADB.

## Objetivo
InGe Earth debe alojar el renderizado original de Google Earth instalado por
Google Play, con el Dock existente y una sola APK propia. No sustituirlo por
MapLibre, Cesium, una imagen congelada, otro launcher o un panel flotante.

## Decisiones
1. Respaldar fuentes y verificar hashes antes de modificar. Excluir builds y
   dependencias generadas. La copia es externa al árbol QML.
2. Retirar exclusivamente selección MapLibre, cola JS, APIs PermissionHelper,
   preset antiguo y assets empaquetados. Mantener Cesium inactivo y servicios
   compartidos Android/GPS/documentos. Mantener Calicatas → Earth → Calicatas.
3. Integrar `InGeFusionBridgeNative` mediante CMake y un único objeto de contexto
   QML `FusionBridge`. No alterar Main.qml, GlassSurface.qml, shaders/glass.frag,
   AuthSession, Supabase ni InGeCoreFlow.
4. Detector Android: PackageManager para `com.google.earth`, versión, actividad
   lanzable e inventario de componentes exportados. Un componente exportado NO
   acredita contrato IPC ni permiso de embedding. Sin contrato verificado, la
   integración interactiva permanece BLOCKED.
5. MediaProjection es una prueba opcional, API 34+, consentimiento nuevo por
   sesión y FGS local. No inicia Earth ni un overlay. El usuario selecciona
   Earth en el selector Android y prueba también pantalla dividida. La API no
   entrega identidad pública del paquete capturado: cuadros etiquetados como
   captura diagnóstica de origen no verificado, nunca integración confirmada.
6. ImageReader → RGBA → JNI → proveedor de imágenes Qt → EarthSurfaceHost.qml.
   Resolución máxima 640 px por eje, máximo 4 cuadros/s. No guardar cuadros en
   disco ni red. FLAG_SECURE temporal en InGe+ evita realimentación. Ocultación,
   cuadros negros, revocación, salida y 2,5 s sin cambio eliminan la imagen.
   Ausencia de cambio es un criterio conservador, NO prueba de crash de Earth.
7. Dock → QML → C++ → JNI → EarthInputController. Zoom, pan y rotación rechazan
   explícitamente sin superficie/contrato interactivo. No activar accesibilidad:
   dispatchGesture actúa sobre ventanas de pantalla, no sobre el ImageReader.
8. Cerrar sesión libera VirtualDisplay, ImageReader, callback, MediaProjection,
   notificación y protección temporal. Tokens no se reutilizan. Las respuestas
   tardías no pueden reabrir un módulo ya cerrado.

## Validación
Pruebas locales de política/frescura y comprobaciones estáticas de integración,
registro QML, JNI y manifiesto. Build/instalación/logcat/regresión corresponden
al usuario desde Qt Creator. Ningún criterio recibe PASS_ANDROID en esta sesión.

## Fuentes primarias
- https://developer.android.com/develop/ui/views/layout/activity-embedding
- https://developer.android.com/reference/android/view/SurfaceControlViewHost
- https://developer.android.com/media/grow/media-projection
- https://developer.android.com/reference/android/media/projection/MediaProjection.Callback
- https://developer.android.com/reference/android/accessibilityservice/AccessibilityService

## Incertidumbre explícita
No se ha inspeccionado el paquete instalado ni su manifiesto: ADB está prohibido.
No afirmar que una versión concreta de Earth carezca de opt-in. El inventario
runtime no equivale a un protocolo SurfacePackage documentado. La ruta directa
queda pendiente de evidencia de cooperación y de un adaptador de ese contrato.
