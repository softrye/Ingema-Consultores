# InGe+ IA — Gemini Live Web Console

Integración Android basada en el proyecto Google
[Live API Web Console](https://github.com/google-gemini/live-api-web-console).
La procedencia, el puente nativo y los requisitos del backend están documentados
en [INGE_INTEGRATION.md](INGE_INTEGRATION.md). Se conserva la licencia Apache-2.0
en [LICENSE](LICENSE), junto con los avisos de los recursos reutilizados.

La entrada actual es `src/inge/main.tsx`. Vite empaqueta la consola InGe+, su
cliente Live, los contextos, los controles y los módulos de audio. Los ejemplos
Altair, logger, cámara y pantalla compartida no forman parte de esta integración.

## Desarrollo y compilación

Requiere Node.js >=22.12 y npm. Desde esta carpeta:

```sh
node prepare-dependencies.mjs
npm test
npm run check
npm run build
```

CMake ejecuta la preparación y el build al compilar Android. Vite genera
`android/assets/inge-ai`, que es un producto regenerable; no es el código fuente.
`npm start` inicia Vite para desarrollo, pero las llamadas reales requieren el
puente nativo y una sesión autenticada.

La clave permanente de Gemini permanece en Supabase. No se añade a `.env`, al
código web ni al APK. El navegador recibe únicamente credenciales efímeras para
voz; el chat usa el backend autenticado. Los tests locales no sustituyen las
pruebas de micrófono, audio, permisos y cambio de cuenta en un teléfono.
