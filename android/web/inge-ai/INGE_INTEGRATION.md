# Gemini Live Web Console en InGe+

Código real de https://github.com/google-gemini/live-api-web-console, commit
`0a4542fe0e39d07956ea7af5de45d7c81fde8960`, licencia Apache-2.0 (LICENSE).
Los componentes, cliente, contextos, hooks, AudioRecorder, AudioStreamer y worklets
son del proyecto. Se conservan los módulos usados por la integración actual;
la entrada de producción es `src/inge/main.tsx`. App, ControlTray y useLiveAPI
están adaptados. Los módulos de demostración sin conexión con esta entrada ni
con sus tests se retiraron durante la limpieza del árbol fuente.

Cambios InGe+: empaquetado Vite, credenciales efímeras solicitadas al puente nativo,
chat por Supabase, controles en español, tema/material/duraciones recibidos del
InGeCoreFlow existente, gestión de permisos y cierre por cambio de cuenta. Se importa
literalmente el recurso `android/assets/cesium/ui/inge-earth-ui.css`; las superficies
web no capturan ni refractan el framebuffer de Qt/Flutter. Utilizan el material web
existente y los tokens del Dock; no se afirma que el shader QML se ejecute en WebView.
Los módulos de cámara, gráficos Altair y ajustes del ejemplo no forman parte
del árbol activo. No se permiten acciones que modifiquen fichas desde el chat.

El SDK 2.27.0 todavía elige una RPC Constrained experimental para tokens efímeros.
El cliente de la consola conserva sus eventos y audio, con un adaptador de transporte
que utiliza la RPC v1beta documentada y espera setupComplete antes de enviar audio.
El SDK oficial sí se usa en el servidor para emitir el token y traducir sus restricciones.

Requisito local: Node.js >=22.12 y npm. Al compilar Android, CMake ejecuta
`prepare-dependencies.mjs` y `npm run build`, generando `android/assets/inge-ai`.
La preparación verifica los paquetes contra package-lock.json y los reutiliza;
solo si faltan paquetes o sus versiones difieren ejecuta npm install incremental.
No elimina node_modules con npm ci. Serializa preparaciones concurrentes y detiene
el proceso si npm falla o modifica realmente el lockfile. No configurar claves .env.

En Qt Creator ejecuta Run CMake y después Build/Run. La reparación EBUSY no requiere
borrar el build ni las dependencias, ni cambiar el kit o la firma Android.

El backend requiere la migración `20261005210000_inge_gemini_quota.sql` y la función
`supabase/functions/inge-ai-gemini`. La clave permanente existe únicamente como
secreto GEMINI_API_KEY de Supabase. El SDK web recibe un token de voz de un uso.

La compilación Android de validación de la limpieza se realizó en una copia
temporal fuera del proyecto. Deben comprobarse en teléfono: texto,
micrófono denegado/aceptado,
audio real, desconexión, botón atrás, segundo plano, cambio de cuenta y regresión
Login/Home/Calicatas/Drive. Un test unitario no verifica una sesión Live real.
