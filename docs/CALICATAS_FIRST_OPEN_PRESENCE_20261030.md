# Calicatas: initial presence and media

## Evidence and Android changes

The user saw presence and all three photos appear only after reopening the Web
page. Read-only Supabase inspection confirmed three existing PHOTO records; the
latest media change was 2026-10-26, before this test. ADB then recorded
`INGE_LIVE_PRESENCE ... people=2`. This proves eventual delivery, not reliable
initial synchronization, and does not establish the Web root cause.

Android had no media/presence reconciliation in the form's Component.onCompleted.
It relied on docChanged and a remote-load callback that only reconciled if the
Loader item already existed. A form created after hydration could miss both.
The fix schedules initial reconciliation after importing the document, and
coalesces subsequent document/account/cloud-identity changes through one 0 ms
timer. It also reconciles on return to the foreground and after sync succeeds.
Existing local photos and pending uploads retain their download guards.

A failed initial TCP/TLS connection only called socket.abort(), relying on a
disconnected signal even when the socket had never connected. The error handler
now explicitly releases the failed socket and invokes the existing backoff.
The diagnostic contains only the socket error number. No new transport, polling,
AuthSession changes, database changes, or public-channel fallback was introduced.

The Supabase protocol confirms `config.private=true` is correct; it was retained:
https://supabase.com/docs/guides/realtime/protocol

## Validation

- `node --test tests/calicatas/first_open_presence.cjs`: six checks; four initial
  failures observed before fixing startup and socket recovery; all now pass.
- `node tests/calicatas/health_glass_logos.cjs`: 17 checks pass.
- `node tests/calicatas/photos_static.cjs`: 28 checks pass.
- `node tests/calicatas/photo_local_preview.cjs`: six checks pass.
- Read-only `adb -s R58T11RBQLN logcat -d -v brief -t 9000`, filtered for live/media.
- Read-only Supabase SQL counted photos and inspected max(updated_at).

No CMake, compilation, installation, app restart, logout, or business-data edits.
Device validation of this source change remains pending the user's build. Tests
execute QML startup/reconciliation JavaScript and inspect the native recovery
contract; they do not exercise the compiled Qt socket or server authorization.

After building, open the same ficha with different accounts in both orders:
Android then Web, and Web then Android, without refreshing either page. Verify
both rosters, three existing photos, field viewing/editing markers, leaving and
re-entering, foreground return, and recovery after temporarily losing network.
Confirm pending local photo edits remain untouched. This working tree also
contains earlier uncommitted work; build the full working tree as usual.

## Message for Juan Pablo (draft; not sent)

Juan Pablo, al abrir la misma calicata en Web y Android, inicialmente no aparecian
los otros usuarios y Android no mostraba las fotos existentes. Al cerrar y abrir
la pagina Web aparecieron ambos usuarios y las tres fotos. Debe funcionar desde
la primera apertura, sin recargar.

En Android corregi una carrera entre la carga de la ficha y la creacion del
formulario, y la recuperacion de una conexion inicial fallida. Aun falta probar
mi cambio compilado. Revisa en Web el arranque con sesion restaurada y UUID de
calicata disponible, setAuth antes de subscribe, track al recibir SUBSCRIBED y la
lectura de presence_state/presence_diff. Comprueba que los efectos no cancelen
el canal inicial ni conserven una suscripcion fallida como si estuviera activa.

Contrato compartido: canal privado calicata:<calicatas.id>, config.private=true,
presence.key=userId y meta {userId,name,field,joinedAt}; field null significa
viendo. Verifica tambien carga inicial de medios desde Supabase y reconciliacion
al suscribirse/reconectar: no debe depender de recibir un broadcast nuevo para
mostrar fotos ya guardadas. Mantener RLS y no sobrescribir ediciones pendientes.

Validar con dos cuentas distintas abriendo en ambos ordenes, sin recargar,
incluyendo reconexion y cambio de ficha. El sintoma esta confirmado; la causa
concreta en Web todavia debe investigarse.
