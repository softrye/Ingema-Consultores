# InGe+ IA: integración del proyecto Gemini Live

## Alcance

Se incorporó el código real de `google-gemini/live-api-web-console`, commit
`0a4542fe0e39d07956ea7af5de45d7c81fde8960`, con LICENSE Apache-2.0.
Está en `android/web/inge-ai`. App, ControlTray, contexto, hook, cliente,
AudioRecorder, AudioStreamer y worklets se utilizan en la integración Android.
La consola abre desde la capacidad `inge.core` del único Dock global.

Antes, ese botón estaba deshabilitado y la función Gemini era una prueba privada
de una sola frase. Ahora el código permite chat con historial reciente y voz
bidireccional, transcripción, silencio, cierre y ampliación del panel.
El chat es conversacional: no ejecuta cambios en fichas ni exportaciones.
La interpretación de Calicatas conserva su flujo existente.

## Integración

`GeminiAssistant` es un transporte hijo del CoreRemote existente: reutiliza
SupabaseClient y AuthSession y no crea otro motor InGeCoreFlow. JWT y claves públicas
de Supabase permanecen en C++; el WebView recibe únicamente un token Live efímero.
Cambiar cuenta, salir, pulsar atrás o enviar la app a segundo plano cancela consultas
y destruye el contexto web, deteniendo micrófono, audio y sockets.
El micrófono se solicita después de pulsar Hablar. Denegarlo produce un aviso real.

La interfaz importa literalmente `android/assets/cesium/ui/inge-earth-ui.css`.
Main publica colores, material y duraciones del InGeCoreFlow único. No hay otro
reloj de animación. WebView no puede muestrear el framebuffer de Qt/Flutter: utiliza
el material web existente, no se declara ejecución del shader QML en el navegador.

Se actualizó el SDK a `@google/genai@2.27.0`. Su emisor servidor convierte las
restricciones al esquema real `bidiGenerateContentSetup`. Su transporte web aún
elige una RPC Constrained experimental; el cliente de la consola utiliza un
adaptador explícito de la RPC v1beta documentada con `access_token` y espera
`setupComplete` antes de audio. No se hacen intentos con modelos alternativos.

## Backend desplegado

Proyecto Supabase `aalmeaqhhlhzwwzsbbxz`, función `inge-ai-gemini`, versión 3 ACTIVE,
`verify_jwt=true`. Verifica además el usuario con Auth; rechaza invitado y anonimato.
Usa el secreto GEMINI_API_KEY existente, sin imprimirlo ni enviarlo al dispositivo.
Texto: gemini-3.8-flash / Interactions con store=false e historial textual acotado.
Voz: gemini-3.8-live, token de un uso, inicio en un minuto y expiración en diez minutos.

Migración aplicada: `20261005210000_inge_gemini_quota.sql`. RLS activa, sin acceso
directo a la tabla desde clientes; RPC consume cuota de auth.uid() atómicamente.
Límites por minuto y cuenta: 20 chats y 3 autorizaciones Live. Los errores de
autenticación, proveedor, red y cuota se muestran, sin respuestas simuladas.

## Verificación realizada sin generar artefactos

- `npm run check --prefix android/web/inge-ai`: TypeScript noEmit, exit 0.
- `node --test supabase/functions/inge-ai-gemini/handler.test.mjs`: 6 pruebas pasan.
- `npm test --prefix android/web/inge-ai`: 7 pruebas pasan (puente, protocolo Live,
  cancelación y transformación real del SDK con transporte simulado).
- qmllint 6.9.3 de Main: exit 0, cero errores de sintaxis; success=false por avisos
  de imports/metadatos existentes, más el acceso contextual InGeAssistant añadido.
- SQL real: RPC accesible a authenticated, no a anon; tabla sin escritura de
  authenticated y con RLS. Prueba de cuota 3 autorizadas/4.ª rechazada, ROLLBACK:
  no se conservaron consumos ni modificaciones de cuentas.
- HTTP real sin sesión al endpoint desplegado: 401. Esto verifica la barrera del
  gateway, no una nueva sesión de chat/voz ni el arranque del SDK dentro de Deno.
- git diff --check del alcance sin errores.

## Compilación manual y límites

Por petición explícita del usuario NO se ejecutaron CMake, Vite build, Gradle,
build Android, instalación, ADB ni logcat. Se instalaron dependencias sin scripts
y se ejecutaron pruebas/revisión de tipos sin emitir recursos. Node local: 24.19.0.
CMake tiene el target `inge_ai_web_assets`: cuando el usuario compile Android,
ejecutará la preparación verificada de dependencias y npm run build y empaquetará
los recursos en assets/inge-ai. El paso npm ci original fue reemplazado al corregir
EBUSY; véase INGE_GEMINI_EBUSY_FIX_20261005.md.
La generación manual equivalente se describe en INGE_INTEGRATION.md.

Pendiente de validación por el usuario: construir e instalar, comprobar texto/voz
reales y disponibilidad/cuota de ambos modelos en su proyecto Google, permisos,
teclado, fondo, botón atrás, multicuenta y regresión Login/Home/Calicatas/Drive.
No se declara la tarea validada en Android ni rendimiento del WebView medido.

El repositorio ya contenía numerosos cambios anteriores. El commit de esta fase
incluye exclusivamente sus archivos nuevos y sus cambios, mediante staging de
los hunks propios en CMake/Manifest/Activity; los cambios anteriores quedan intactos
y fuera de ese commit. El funcionamiento del checkout completo depende también
de esas fuentes previas del Dock y los recursos Glass que el usuario ya tenía.
