# Diagnóstico de emulador — 04-11-2026 (sin compilación)

## Evidencia visual / Paso 0
Archivo exacto revisado: `C:\Users\PC-02\AppData\Local\Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState\Recordings\20261104-1450-02.2540915.mp4` (15,424 s).
Se extrajeron 12 fotogramas mediante ffmpeg; mosaico temporal: `%LOCALAPPDATA%\Temp\inge_original_12_frames.jpg`.
Video adjunto adicional: `20261104-1452-41.6753354.mp4` (31,317 s); otros 12 fotogramas inspeccionados.
Hallazgo: panel «Estado de Calicatas», 4 incidencias bloqueantes. Todas «No se pudo recuperar o sincronizar un medio», código CAL-MEDIA-READ, causa HTTP_400; primera General · Logos y tres de Fotos. No se ven errores distintos en ese recorrido.

## 1. OAuth Google
- `android/AndroidManifest.xml`: InGeQtActivity singleTop; callback separado exported, VIEW BROWSABLE `com.ingema.ingeplus://login-callback`.
- `android/src/com/ingema/ingeplus/InGeOAuthCallbackActivity.java`: recibe esquema/host exactos, entrega URI antes de CLEAR_TOP/SINGLE_TOP y finish(). `InGeQtActivity.java`: onNewIntent y entrega estática presentes.
- `authsession.cpp`: `redirect_to` coincide, code_challenge S256 y POST grant_type=pkce presentes. Al volver sin callback, el temporizador antiguo emitía OAUTH_CANCELLED sin evidencia de `access_denied`.
- Ajuste de `authsession.cpp`: espera hasta 5 s el retorno tardío y registra OAUTH_CALLBACK_MISSING, no falsa cancelación. El error externo DEEPLINK/Google/Supabase permanece PENDIENTE hasta prueba en dispositivo. No se declarará Google Sign-In reparado con este solo ajuste.
- `docs/google_signin_setup.md` exige Client ID/secret web en Supabase, URL HTTPS `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/callback` en Google Cloud y redirect custom de Android en Supabase. La configuración externa **no se verificó**.

## 2. Ubicación
- Logcat histórico: `INGE_LOCATION_PICKER_OPEN engine=none` y `CalicataPointPicker.qml:57:5 Unable to assign [undefined] to bool`.
- En worktree **ya modificado por otro ingeniero**: `qml/Mobile/pages/CalicataPointPicker.qml` usa `CalicatasTopoMap`, `layer=topo`, `mapSupported: true` booleano y registra `engine=topo`. No se sobrescribió.
- Validar con build/logcat del usuario; no fue probado en dispositivo.

## 3. Cuatro incidencias Calicatas
- Logcat segunda calicata: HYDRATE_OK, luego aura error, panel con 4 CAL-MEDIA-READ / HTTP_400.
- `calicatacloudservice.cpp` `readCalicataState` usa RPC `get_my_calicata_media_read_state_v01` para preflight de logos y fotos. Un único fallo de lectura puede afectar a varios slots.
- La migración local `supabase/migrations/20261102144156_calicata_purged_media_read_state_v01.sql` figura en **historial remoto** de Supabase; no se aplicó ninguna migración ni se reescribió Storage.
- Los callbacks de `CalicataFormPage.qml` ya comprueban `instanceId`, evitando adopción obvia de la calicata anterior. No hay prueba de que el problema sea arrastre de pestaña.
- Cambio mínimo `calicatacloudservice.cpp`: traza `INGE_CAL_MEDIA_READ_STATE_RPC_FAILED httpStatus=... qtNetworkError=... backendCode=...` exclusivamente si falla ese RPC. No imprime tokens, payload, identificadores ni rutas. **La raíz exacta del HTTP 400 aún no está verificada**: hace falta el código backend del siguiente logcat o respuesta HTTP sanitizada. Se conservan las cuatro incidencias legítimas; no se silencian.

## 4. LIVE revalidate
- Código existente `calicatacloudservice.cpp` impide adoptar una `serverRevision` menor que la versión local confirmada; `CalicatasEditorPage.qml` carga solamente si está SYNCED y sin edición pendiente.
- `remoteRevision=0` del evento no se utiliza como base de escritura, sino señal para leer snapshot remoto y validar versión real. No se modificó: requiere validación en dispositivo con reconexión.

## 5. Rendiciones HTTP
- Logcat muestra `http=500 networkError=401`, que en Qt significa **HTTP 500** y **QNetworkReply::InternalServerError (valor numérico 401)**, NO HTTP 401. No es prueba de JWT expirado.
- Worktree existente: `src/cpp/renditionrepository.cpp` usa `httpStatus` / `qtNetworkError`, refresca token si expira y reintenta una única vez ante HTTP 401 genuino; `authsession.cpp` implementa single-flight refresh.
- `src/cpp/renditionconnectivity.h` clasifica status HTTP 401 como Auth, no servidor caído. Error HTTP 500 del servidor sigue pendiente de diagnosticar (no debe disfrazarse como refresh del JWT).
- No se modificaron Rendiciones ni Dock.

## Verificación
- `node --test tests/calicatas/media_purge_read.cjs tests/calicatas/first_open_presence.cjs`: **11/11 PASS**.
- `git diff --check -- authsession.cpp calicatacloudservice.cpp`: **PASS**, con avisos de normalización LF/CRLF no bloqueantes.
- No compilación, APK, instalación, pruebas logcat postcorrección, certificados Google Cloud ni permisos live de Supabase/Storage.
- Worktree con cambios previos de otros ingenieros; no se hizo commit para no incorporar modificaciones ajenas accidentalmente.

## Para verificar después de compilar
1. OAuth: filtrar `INGE_OAUTH_CALLBACK_RECEIVED|OAUTH_EXCHANGE_STARTED|OAUTH_RESULT`. Si no hay callback, verificar en dashboards redirect URL, proveedores y consent screen. No registrar code/verifier.
2. Ubicación: al abrir selector debe salir `engine=topo`; no binding undefined ni pantalla sin motor.
3. Segunda calicata: inspeccionar nuevas `INGE_CAL_MEDIA_READ_STATE_RPC_FAILED`; confirmar HTTP, error de Qt y backend code. Comparar con las 4 incidencias; conservar archivos y no resubir medios sin confirmación.
4. Reconnect: `remoteRevision=0` no debe sobrescribir campos locales ni disparar conflictos ficticios.
5. Rendiciones: observar `httpStatus` real y `qtNetworkError` por separado; probar 401 real con refresh serializado y distinguir 500 backend. Probar reconexión.
