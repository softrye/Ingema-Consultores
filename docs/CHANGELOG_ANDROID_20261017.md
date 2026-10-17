# InGe+ Android — Release de presentación (17/10/2026)
**Versión del paquete:** 1.1.13-native-location · **versionCode:** 122 · **Android:** arm64-v8a
**Base comparativa:** APK presentada el 14/10/2026.
**Compilación:** Release firmada con APK Signature Scheme v3; Qt Creator y Gradle completaron exitosamente el 17/10/2026.
**Estado:** release candidato de presentación. La compilación e instalación se confirmaron; no se certifican todos los flujos E2E.

## Rendiciones — interfaz y gastos
- **NEW:** Home de rendiciones con tarjetas, filtros por proyecto y estado.
- **UPDATE:** Formulario Nuevo gasto organizado en General, Comprobante, Pago e importe y Sustentos.
- **NEW:** Herramientas contextuales del Dock, comprobantes, cálculo del IGV con confirmación y gestión de sustentos.
- **NEW:** Borradores Working, recuperación, Archivero y Papelera en InGeDrive.

## Sincronización y diagnósticos
- **FIX:** Detección real de desconexión y reintentos del outbox sin confundir transporte con conflictos CAS.
- **UPDATE:** Auras ya existentes: estado normal, aviso técnico localizado y fallo real; sin indicador nuevo de sincronización.
- **NEW:** Panel Estado de Rendiciones; separación de incidentes reales frente a gastos incompletos.
- **FIX:** Mensajes intrusivos repetidos y apertura del detalle cuando no hay red.

## InGe IA
- **NEW:** Chat global con historial por subapp y contexto para Home, Calicatas, Rendiciones e InGe Earth.
- **NEW:** Propuestas editables de gastos y transferencia a Nuevo gasto con confirmación del usuario.
- **NEW:** Herramientas contextuales de Calicatas y distancia/coordenadas/GPS de Earth.
- **FIX:** Backend Gemini v5: límites HTTP 429, reducción de reintentos y espera controlada.

## Compatibilidad Web–Android
- **FIX:** Visualización y persistencia del nombre de rendición (displayName) manteniendo el código RDC como identificador.
- **UPDATE:** Creación remota mediante create_my_rendition_draft_v03 con nombre validado.
- **FIX:** Proyectos visibles desde el listado inicial y filtro Tus proyectos sin abrir cada ficha (RPC actualizada en Supabase DEV).
- **FIX:** Firma C++ de createRendition alineada con su declaración.

## Liquid Glass / InGe Earth / estabilidad
- **UPDATE:** Contraste y esmerilado del Dock global sobre contenido claro/oscuro.
- **UPDATE:** Eliminación de captura gráfica duplicada del Dock de Earth.
- **FIX:** Ajustes C++20, Gradle y tests de compatibilidad.
- **TEST:** 18 pruebas de backend Gemini aprobadas; verificaciones estáticas QML y contratos.

## No habilitado / pendiente
- El buscador global Web permanece **solo investigado**, sin activación en Android.
- El gesto horizontal swipe entre secciones de Nuevo gasto **no está implementado**.
- Queda pendiente validar en el equipo el registro guiado por IA y otros flujos completos.
- La actualización de proyectos del listado se aplicó en Supabase DEV; no implica cambios en producción.

**APK firmada SHA-256:** `E031334290215F2077DF8DDC8B1095BFC77F17AA18DA583CF58FE0FEE94D1661`
**Compilación local:** `C:\InGeBuild\QtCreator_Android_arm64_Release\android-build-AppCalicatasMobile\build\outputs\apk\release\android-build-AppCalicatasMobile-release-signed.apk`

> No se adjunta registro bruto de compilación ni material de firma.