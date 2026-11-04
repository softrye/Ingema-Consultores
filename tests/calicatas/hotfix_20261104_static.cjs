// Regresión estructural de incidentes observados el 04/11/2026.
// No compila, ejecuta QML ni accede a credenciales/Storage.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "../..");
const read = (name) => fs.readFileSync(path.join(root, name), "utf8");

const auth = read("authsession.cpp");
const header = read("authsession.h");
const java = read("android/src/com/ingema/ingeplus/InGeQtActivity.java");
const manifest = read("android/AndroidManifest.xml");
const picker = read("qml/Mobile/pages/CalicataPointPicker.qml");
const topo = read("qml/Mobile/pages/CalicatasTopoMap.qml");
const cloud = read("calicatacloudservice.cpp");
const rendition = read("src/cpp/renditionrepository.cpp");
const schema = read("supabase/migrations/20261104162000_rendition_working_storage_lock_scope_v01.sql");

// 1) OAuth callback no se cancela en el primer Active mientras llega el intent.
assert.match(java, /protected void onNewIntent\(Intent intent\)/);
assert.match(java, /deliverOAuthCallback\(data\.toString\(\)\)/);
assert.match(auth, /m_oauthAwaitingCallback/);
assert.match(auth, /QTimer::singleShot\(2500/);
assert.doesNotMatch(auth.slice(auth.indexOf("void AuthSession::consumePlatformOAuthCallback()"),
                              auth.indexOf("void AuthSession::signInWithGoogle()")),
                   /OAUTH_CANCELLED/);
assert.match(auth, /grant_type/);
assert.match(auth, /pkce/);
assert.match(manifest, /com\.ingema\.ingeplus/);

// 2) Mapa topo existente en picker y coordenada real al tocar.
assert.match(picker, /readonly property bool mapSupported:\s*true/);
assert.match(picker, /CalicatasTopoMap\s*\{/);
assert.match(picker, /topoLayer:\s*true/);
assert.match(picker, /onBackgroundTapped:\s*function\(lat, lon\)/);
assert.doesNotMatch(picker, /GraphicsCore\.openEarthPicker\(/);
assert.match(topo, /signal backgroundTapped\(real latitude, real longitude\)/);
assert.match(topo, /\.toCoordinate\(/);

// 3) El filtro de bucket antecede al lock; no altera los permisos.
const guard = schema.indexOf("if p_bucket <> 'project-files'");
const lock = schema.indexOf("perform pg_advisory_xact_lock(6041106)");
assert.ok(guard >= 0 && lock > guard);
assert.match(schema, /private\.rendition_content_editable_v05/);
assert.match(cloud, /STORAGE_RESOURCE_LOCKED/);
assert.match(cloud, /storageObjectMissing\(http, object\)/);

// 4) El servidor nunca pisa una versión local más reciente con revision 0.
assert.match(cloud, /serverRevision < localRevision/);
assert.ok(cloud.indexOf("serverRevision < localRevision") <
          cloud.indexOf("target->applyRemoteSnapshot(authoritativeRoot, localCortes)"));

// 5) Refresh de JWT serializado; HTTP 500 nunca dispara intercambio por el valor 401 de Qt.
assert.match(header, /m_rpcTokenRefreshInFlight/);
assert.match(auth, /if \(m_rpcTokenRefreshInFlight\) return/);
assert.match(rendition, /if \(status == 401 && !tokenRefreshAttempted\)/);
assert.match(rendition, /httpStatus=/);
assert.match(rendition, /qtNetworkError=/);
assert.match(rendition, /refreshAccessTokenForRpc/);
assert.match(rendition, /onSuccess = std::move\(onSuccess\)/);
console.log("PASS 20261104: OAuth, picker topo, bloqueo Storage, Live y RPC JWT (solo análisis estático).");
