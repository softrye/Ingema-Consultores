# InGeDrive P0 — implementation handoff

TIME_USED_MIN=24.1
TOOL_CALLS=26 orchestration calls; 45 nested operations including failed attempts
CODEX_5H_USAGE_START=23% used
CODEX_5H_USAGE_END=unavailable from tool; user reports about 12% remaining
NOTE_USAGE_IS_SHARED=YES
FILES_READ=

- androidcalicataexporter.cpp
- androidcalicataexporter.h
- appcontext.cpp
- src/cpp/renditionexportservice.h
- src/cpp/renditionrepository.cpp
- src/cpp/renditionlocalstore.cpp
- src/cpp/renditionsynccontroller.cpp
- src/documents/storageprovider.h
- tests/renditions/checks.cpp
- android/res/xml/nothing_file_paths.xml
- src/documents/nothingdocuments.cpp
- src/cpp/renditionattachmentcontract.h
- tests/renditions/CMakeLists.txt
- tests/calicatas/checks.cpp
- tests/calicatas/CMakeLists.txt
- tests/calicatas/auth_link.cpp
- android/src/com/ingema/ingeplus/NothingFileBridge.java
- qml/Mobile/pages/CalicataFormPage.qml
- qml/Mobile/pages/CalicatasEditorPage.qml

FILES_MODIFIED=

- androidcalicataexporter.cpp
- androidcalicataexporter.h
- appcontext.cpp
- src/cpp/renditionexportservice.h
- src/cpp/renditionrepository.cpp
- src/cpp/renditionlocalstore.cpp
- src/cpp/renditionsynccontroller.cpp
- src/documents/storageprovider.h
- tests/renditions/checks.cpp
- android/res/xml/nothing_file_paths.xml

FILES_CREATED=

- docs/sql_proposals/ingedrive_binary_retry_base_versions.sql
- docs/INGEDRIVE_P0_IMPLEMENTATION_20260925.md

PREEXISTING_CONCURRENT_FILES=

- CMakeLists.txt
- android/assets/cesium/index.html
- android/assets/cesium/ui/inge-earth-ui.css
- android/assets/cesium/ui/inge-earth-ui.js
- android/src/com/ingema/ingeplus/InGeQtActivity.java
- flutter/inge_earth/lib/global_navigation_dock.dart
- flutter/inge_earth/lib/home.dart
- flutter/inge_earth/lib/home_dock.dart
- flutter/inge_earth/lib/home_final.dart
- flutter/inge_earth/lib/renditions/v2/renditions_root.dart
- flutter/inge_earth/lib/renditions/v2/widgets/dashboard_widgets.dart
- flutter/inge_earth/lib/renditions/v3/renditions_root.dart
- flutter/inge_earth/lib/renditions/v3/renditions_shell.dart
- flutter/inge_earth/lib/renditions/v3/theme/rendition_theme.dart
- flutter/inge_earth/test/home_final_test.dart
- flutter/inge_earth/test/renditions_received_v2_test.dart
- flutter/inge_earth/test/renditions_v3_test.dart
- main_mobile.cpp
- permissionhelper.cpp
- qml/Mobile/Main.qml
- qml/Mobile/components/FlowIcon.qml
- qml/Mobile/documents/NothingDocumentsRoot.qml
- qml/Mobile/flowcore/FlowGlassSurface.qml
- qml/Mobile/flowcore/FlowTheme.qml
- qml/Mobile/flowcore/GlobalNavigationDock.qml
- qml/Mobile/flowcore/InGeCoreFlow.qml
- qml/Mobile/lib/IconCatalog.js
- qml/Mobile/pages/CalicataFormPage.qml
- qml/Mobile/pages/CalicataPointPicker.qml
- qml/Mobile/pages/CalicatasEditorPage.qml
- qml/Mobile/pages/MapNativePage.qml
- resources_mobile_raw.qrc
- src/cpp/renditionflutterbridge.cpp
- src/cpp/renditionflutterbridge.h
- src/graphics/InGeEarthHostController.cpp
- src/graphics/InGeEarthHostController.h
- src/graphics/InGeGraphicsCore.cpp
- src/graphics/InGeGraphicsCore.h
- flutter/inge_earth/lib/dock_context_client.dart
- qml/Mobile/flowcore/ContextPublisher.qml
- qml/Mobile/flowcore/GlobalContextDock.qml
- src/dock/DockCommandRouter.cpp
- src/dock/DockCommandRouter.h
- src/dock/DockContextController.cpp
- src/dock/DockContextController.h

PHYSICAL_PATH_ROOT_CAUSE=MediaStore label returned as QFile path
PHYSICAL_PATH_FIX=Compatibility return is physical mirror; lastExportResult separates display/physical/logical/remote
DISPLAY_PATH=Descargas/InGePlus/<name> when public copy succeeds
LOCAL_PHYSICAL_PATH=AppData/rendition-exports/<user UUID>/mirror/<operation hash>/<filename>
REMOTE_LOGICAL_PATH=Calicatas/EXCEL/<code>_<content hash>.xlsx
CANONICAL_BUCKET=project-files
LEGACY_BUCKET=IngePlus history/legacy reads untouched; no new exports or attachment writes use it
CALICATAS_EXPORT_FLOW_BEFORE=generate cache -> display label -> structured sync gate -> legacy upload
CALICATAS_EXPORT_FLOW_AFTER=persist intent -> original generator -> atomic complete XLSX -> existing outbox -> reserve/begin/upload/finalize -> SYNCED
CALICATAS_ONLINE_FLOW=Resolve PROJECT space by UUID; upload immutable reserved object; confirm node/version; publication waits for XLSX and portable JSON
CALICATAS_OFFLINE_FLOW=Physical mirror and PENDING_SYNC saved before existing QML network gate
CALICATAS_REMOTE_PATH_PATTERN=project-files/spaces/<spaceId>/nodes/<nodeId>/versions/<versionId>/<server filename>
PERSISTENT_QUEUE_USED=Existing rendition-exports/<uid>/outbox.json; RenditionLocalStore aggregate outbox; Document DriveJournal retained
RESERVATION_EXPIRY_ROOT_CAUSE=Idempotent reserve does not renew expiry; controlled retry omits canonical binary baseline fields
RESERVATION_RETRY_FIX=Existing renew/retry RPCs, durable retry key and same node/version/path; expired retry still BACKEND_BLOCKED
PROCESS_DEATH_RECOVERY=Startup/login restores queue; saved generation intent adopts atomically completed XLSX; stable request keys replay
RENDITIONS_ATTACHMENT_FLOW_BEFORE=Canonical reserve/upload/finalize but external local URI could disappear
RENDITIONS_ATTACHMENT_FLOW_AFTER=QSaveFile mirror + hash + existing outbox -> same reservation -> shared provider -> confirmed attachment ID
RENDITIONS_IDEMPOTENCY=Stable requestId/attachmentId/path, digest duplicate guard, duplicate upload reconciled through finalize
PROJECT_BINDING=Real UUID required; PROJECT space unique index verified; attachment retains expense project/confirmed IDs
BACKEND_MIGRATION_REQUIRED=YES (expired binary retry only)
BACKEND_BLOCKER=retry_document_upload_controlled creates attempts with NULL base_node_version/base_content_version/binary_request_context; canonical begin/finalize require those values. No defaults/INSERT trigger supply them.
SQL_PROPOSAL=docs/sql_proposals/ingedrive_binary_retry_base_versions.sql — NOT EXECUTED
CLAUDE_FILES_TOUCHED=0
DOCK_FILES_TOUCHED=0
EARTH_FILES_TOUCHED=0
STATIC_DIFF_CHECK=PASS
ORPHAN_REFERENCES=No new source unit/QML registration. Static checks only.
COMPILE=NOT_RUN
QT_BUILD=NOT_RUN
GRADLE=NOT_RUN
FLUTTER_BUILD=NOT_RUN
APK=NOT_GENERATED
ADB=NOT_RUN
APP_EXECUTION=NOT_RUN
COMMIT=NOT_CREATED
IMPLEMENTATION_COMPLETE=NO — backend prerequisite and device validation remain
READY_FOR_USER_BUILD=YES — for compilation/validation, not production certification

## Static checks (not runtime tests)

{
  "QXLSX_HELPERS_UNCHANGED": true,
  "PHYSICAL_RETURN_NOT_DISPLAY_LABEL": true,
  "INTENT_PRECEDES_GENERATION": true,
  "ATOMIC_COMPLETED_XLSX": true,
  "CONCURRENT_FILES_EXCLUDED": true,
  "FILEPROVIDER_XML_VALID": true,
  "NO_LEGACY_EXPORT_TRANSPORT": true,
  "NO_AGGRESSIVE_POLLING": true,
  "LEXICAL_CPP_PREPROCESSOR": true,
  "src/cpp/renditionexportservice.h_DELIMITERS": true,
  "src/documents/storageprovider.h_DELIMITERS": true,
  "STATIC_DIFF_CHECK": true
}

## Limits and required follow-up

- Concurrent CalicatasEditorPage still gates its popup on structured sync. The service queues independently and exposes PENDING_SYNC/openLastExport(share); no concurrent QML was edited.
- Native attachment tests now cover mirror survival after deleting picker source/reopening and digest deduplication. Updated but NOT RUN because compilation is prohibited.
- Desktop golden tools remain generation-only. Android always requires a durable operation. Generator/template/formula/photo/classification helpers unchanged against HEAD.
- Files use the project document-space root with server-issued paths; logical module paths stay in metadata. No arbitrary folders or mass migration.
- SQL proposal copies ORIGINAL concurrency baselines into retries. Apply only after coordinated review. Already-created broken attempts need separate audited repair; do not adopt current node versions.
- 403 stops automatic retries. Transient failures retain files and back off 30 seconds to 15 minutes with a single-shot timer. Auth/reconnect/resume/manual triggers reuse the queue.
- Authenticated RLS, network behavior and actual Android open/share are not established by read-only administrator schema inspection.

## User validation matrix

1. Online export: real path, finalized project-files object/version, SYNCED.
2. Offline export: pending operation survives process death before upload and reconnect.
3. Lost responses after reserve/upload/finalize: same node/version/path, no duplicates.
4. After coordinated SQL: expired >15 min reservation retries. Without SQL: visible backend error and preserved mirror.
5. Offline attachment: delete picker original, restart, sync record then attachment; retry five times.
6. Account switch during upload: old callbacks cannot update new account.
7. Open/share physical XLSX offline using existing NothingFileBridge and scoped FileProvider.
8. RLS 403, 5xx, disk-full, missing file and version conflict: no false SYNCED.

## Commands actually used

git status --short; git diff --check; git diff --stat; targeted source reads/rg; Python lexical/preprocessor/XML checks; read-only Supabase catalog/function SELECTs.

## Own diff stat
~~~
 android/res/xml/nothing_file_paths.xml |   3 +
 androidcalicataexporter.cpp            | 206 +++++++++++++----
 androidcalicataexporter.h              |   8 +
 appcontext.cpp                         |   3 +
 src/cpp/renditionexportservice.h       | 408 ++++++++++++++++++++++++---------
 src/cpp/renditionlocalstore.cpp        |  38 ++-
 src/cpp/renditionrepository.cpp        |  45 ++--
 src/cpp/renditionsynccontroller.cpp    |  24 ++
 src/documents/storageprovider.h        |  53 ++++-
 tests/renditions/checks.cpp            |  21 +-
 10 files changed, 617 insertions(+), 192 deletions(-)
~~~

## Complete own diff — review only
~~~diff
diff --git a/android/res/xml/nothing_file_paths.xml b/android/res/xml/nothing_file_paths.xml
index 378fff0..ed6220d 100644
--- a/android/res/xml/nothing_file_paths.xml
+++ b/android/res/xml/nothing_file_paths.xml
@@ -1,6 +1,9 @@
 <?xml version="1.0" encoding="utf-8"?>
 <paths xmlns:android="http://schemas.android.com/apk/res/android">
     <cache-path name="inge_calicata_exports" path="Exportaciones/" />
+    <!-- Durable, account-scoped mirrors; the bridge grants only the selected file. -->
+    <files-path name="inge_drive_mirrors" path="inge-drive/" />
+    <files-path name="inge_export_mirrors" path="rendition-exports/" />
     <cache-path name="inge_camera_captures" path="calicata_camera/" />
     <external-path name="inge_documents" path="Documents/InGePlusProyectos/" />
     <external-files-path name="inge_external_documents" path="Documents/InGePlusProyectos/" />
diff --git a/androidcalicataexporter.cpp b/androidcalicataexporter.cpp
index d830296..04f2139 100644
--- a/androidcalicataexporter.cpp
+++ b/androidcalicataexporter.cpp
@@ -29,6 +29,9 @@
 #include <QPdfWriter>
 #include <QSaveFile>
 #include <QPointer>
+#include <QDesktopServices>
+#include <QCryptographicHash>
+#include <memory>
 #include <QUuid>
 
 #ifdef Q_OS_ANDROID
@@ -1828,6 +1831,17 @@ bool copyFileToMediaStoreDownloads(const QString &sourcePath, const QString &dis
 AndroidCalicataExporter::AndroidCalicataExporter(QObject *parent)
     : QObject(parent)
 {
+#ifdef Q_OS_ANDROID
+    if (appContext() && appContext()->auth()) {
+        const auto clearAccount = [this] {
+            m_exportResult.clear(); m_exportProject.clear(); m_exportLogicalPath.clear();
+            m_publishedFiles.clear(); m_publishedUser.clear(); emit exportResultChanged();
+        };
+        connect(appContext()->auth(), &AuthSession::loggedOut, this, clearAccount);
+        connect(appContext()->auth(), &AuthSession::accountSwitchStarted, this,
+            [clearAccount](const QString &) { clearAccount(); });
+    }
+#endif
 }
 
 QString AndroidCalicataExporter::lastError() const
@@ -1835,65 +1849,109 @@ QString AndroidCalicataExporter::lastError() const
     return m_lastError;
 }
 
+QVariantMap AndroidCalicataExporter::lastExportResult() const
+{
+    auto result = m_exportResult;
+#ifdef Q_OS_ANDROID
+    if (m_exports && !m_exportLogicalPath.isEmpty()) {
+        const auto current = m_exports->resultFor(m_exportProject, m_exportLogicalPath);
+        for (auto it = current.cbegin(); it != current.cend(); ++it) result[it.key()] = it.value();
+    }
+#endif
+    return result;
+}
+
+void AndroidCalicataExporter::retryPendingExports()
+{
+#ifdef Q_OS_ANDROID
+    if (m_exports) m_exports->retry();
+#endif
+}
+
+bool AndroidCalicataExporter::openLastExport(bool share)
+{
+    const auto path = lastExportResult().value("localPhysicalPath").toString();
+    if (path.isEmpty() || !QFileInfo(path).isFile()) {
+        setLastError(QStringLiteral("El mirror del Excel no está disponible.")); return false;
+    }
+#ifdef Q_OS_ANDROID
+    const auto context = QNativeInterface::QAndroidApplication::context();
+    const auto file = QJniObject::fromString(path);
+    const auto result = QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge", "open",
+        "(Landroid/content/Context;Ljava/lang/String;ZZ)Ljava/lang/String;",
+        context.object(), file.object<jstring>(), jboolean(true), jboolean(share));
+    QJniEnvironment env;
+    if (env->ExceptionCheck()) { env->ExceptionClear(); setLastError(QStringLiteral("No se pudo abrir el Excel.")); return false; }
+    if (!result.isValid()) { setLastError(QStringLiteral("Android no respondió al abrir el Excel.")); return false; }
+    setLastError(result.toString()); return result.toString().isEmpty();
+#else
+    Q_UNUSED(share);
+    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
+#endif
+}
+
 bool AndroidCalicataExporter::publishCalicata(const QVariantMap &state, const QString &xlsxPath)
 {
 #ifdef Q_OS_ANDROID
-    // Draft uploads remain possible; final publication uses the shared blockers.
     if (!xlsxPath.isEmpty()) {
-        const QString blocker = CalicataValidation::firstBlocker(state);
+        const auto blocker = CalicataValidation::firstBlocker(state);
         if (!blocker.isEmpty()) { setLastError(blocker); return false; }
     }
-
     const auto header = state.value("header").toMap();
     const auto project = header.value("projectId").toString();
     const auto document = state.value("instance_id").toString();
     auto *ctx = appContext();
     if (!ctx || !ctx->auth()->logged() || QUuid(project).isNull() || QUuid(document).isNull()
-        || (!xlsxPath.isEmpty() && !QFileInfo::exists(xlsxPath))) {
-        setLastError(QStringLiteral("Selecciona un proyecto online e inicia sesión antes de subir."));
+        || (!xlsxPath.isEmpty() && !QFileInfo(xlsxPath).isFile())) {
+        setLastError(QStringLiteral("Selecciona un proyecto e inicia sesión antes de publicar."));
         return false;
     }
-    if (!m_exports) m_exports = RenditionExportService::shared(ctx->supabase(), ctx->auth());
+    m_exports = RenditionExportService::shared(ctx->supabase(), ctx->auth());
     const auto user = ctx->auth()->userId();
     if (m_publishedUser != user) { m_publishedFiles.clear(); m_publishedUser = user; }
-    const auto code = safeFileName(header.value("codigo").toString());
-    const auto version = QDateTime::currentDateTimeUtc().toString("yyyyMMdd_HHmmss_zzz");
-    const auto stem = code + '_' + document + '_' + version;
+    const auto bytes = QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact);
+    const auto hash = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
+    const auto stem = safeFileName(header.value("codigo").toString()) + '_' + document
+        + '_' + QString::fromLatin1(hash.left(20));
     const auto snapshotPath = QDir(defaultExportDir()).filePath(stem + ".calicata.json");
     QSaveFile snapshot(snapshotPath);
-    const auto bytes = QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact);
     if (!snapshot.open(QIODevice::WriteOnly) || snapshot.write(bytes) != bytes.size() || !snapshot.commit()) {
-        setLastError(QStringLiteral("No se pudo preparar la ficha portable para subir."));
-        return false;
+        setLastError(QStringLiteral("No se pudo conservar la ficha portable.")); return false;
+    }
+    const auto remoteEdit = "Calicatas/Edit/" + stem + ".calicata.json";
+    QString remoteExcel;
+    if (!xlsxPath.isEmpty()) {
+        if (m_exportProject == project && (xlsxPath == m_exportResult.value("localPhysicalPath").toString()
+            || xlsxPath == lastExportResult().value("localPhysicalPath").toString())) {
+            remoteExcel = m_exportLogicalPath; // Same operation staged during generation.
+        } else {
+            QFile file(xlsxPath);
+            if (!file.open(QIODevice::ReadOnly)) { setLastError(QStringLiteral("No se pudo leer el XLSX.")); return false; }
+            const auto xlsxHash = QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex();
+            remoteExcel = "Calicatas/EXCEL/" + safeFileName(header.value("codigo").toString())
+                + '_' + QString::fromLatin1(xlsxHash.left(20)) + ".xlsx";
+        }
+        m_publishedFiles[document] = xlsxPath; // Open/share does not wait for connectivity.
     }
     const QPointer<AndroidCalicataExporter> guard(this);
-    const auto failure = [guard, document, user](bool ok, const QString &error) {
-        if (guard && !ok && appContext()->auth()->userId() == user)
-            emit guard->calicataPublishFailed(document,
-                error.contains(QStringLiteral("23505"))
-                ? QStringLiteral("Ya existe una calicata con ese código en este proyecto.")
-                : QStringLiteral("No se pudo subir la calicata. Revisa la conexión y los permisos del proyecto."));
+    const auto notified = std::make_shared<bool>(false);
+    const auto completion = [guard, user, document, project, remoteEdit, remoteExcel, notified](bool ok, const QString &error) {
+        if (!guard || !appContext() || !appContext()->auth()->logged() || appContext()->auth()->userId() != user) return;
+        emit guard->exportResultChanged();
+        if (!ok) { emit guard->calicataPublishFailed(document, error); return; }
+        if (*notified || !guard->m_exports->resultFor(project, remoteEdit).value("success").toBool()) return;
+        if (remoteExcel.isEmpty()) {
+            *notified = true; emit guard->calicataSavedOnline(document); return;
+        }
+        const auto exported = guard->m_exports->resultFor(project, remoteExcel);
+        if (!exported.value("success").toBool()) return;
+        *notified = true;
+        guard->m_publishedFiles[document] = exported.value("localPhysicalPath").toString();
+        emit guard->calicataPublished(document);
     };
-    const auto remoteEdit = "Calicatas/Edit/" + stem + ".calicata.json";
-    if (xlsxPath.isEmpty()) {
-        const bool queued = m_exports->enqueueDocument(snapshotPath, project, remoteEdit,
-            [guard, document, user, failure](bool ok, const QString &error) {
-                if (!guard || appContext()->auth()->userId() != user) return;
-                if (ok) emit guard->calicataSavedOnline(document);
-                else failure(false, error);
-            });
-        setLastError(queued ? QString() : QStringLiteral("No se pudo registrar la ficha en la cola online."));
-        return queued;
-    }
-    if (!m_exports->enqueueDocument(snapshotPath, project, remoteEdit, failure)
-        || !m_exports->enqueueDocument(xlsxPath, project, "Calicatas/EXCEL/" + stem + ".xlsx",
-            [guard, document, user, xlsxPath, failure](bool ok, const QString &error) {
-                if (!guard || appContext()->auth()->userId() != user) return;
-                if (!ok) { failure(false, error); return; }
-                guard->m_publishedFiles[document] = xlsxPath;
-                emit guard->calicataPublished(document);
-            }, remoteEdit)) {
-        setLastError(QStringLiteral("No se pudo registrar la exportación en la cola de subidas. Conserva la ficha y reintenta."));
+    if (!m_exports->enqueueDocument(snapshotPath, project, remoteEdit, completion)
+        || (!xlsxPath.isEmpty() && !m_exports->enqueueDocument(xlsxPath, project, remoteExcel, completion, remoteEdit))) {
+        setLastError(QStringLiteral("No se pudo registrar la publicación; los archivos locales se conservan."));
         return false;
     }
     setLastError({});
@@ -1905,6 +1963,7 @@ bool AndroidCalicataExporter::publishCalicata(const QVariantMap &state, const QS
 #endif
 }
 
+
 bool AndroidCalicataExporter::sharePublishedCalicata(const QString &documentId)
 {
 #ifdef Q_OS_ANDROID
@@ -1958,9 +2017,11 @@ QString AndroidCalicataExporter::safeFileName(QString name) const
 QString AndroidCalicataExporter::defaultExportDir() const
 {
 #ifdef Q_OS_ANDROID
-    const QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
-    if (!cache.isEmpty()) {
-        QDir d(cache);
+    // Pending exports must not live in an OS-evictable cache.
+    const QString staging = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
+    if (!staging.isEmpty()) {
+        const auto user = appContext() && appContext()->auth() ? appContext()->auth()->userId() : QString();
+        QDir d(staging + "/inge-drive/" + (QUuid(user).isNull() ? QStringLiteral("unassigned") : user));
         d.mkpath(QStringLiteral("Exportaciones"));
         return d.filePath(QStringLiteral("Exportaciones"));
     }
@@ -2053,6 +2114,9 @@ QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, con
 {
 #ifdef INGE_HAS_QXLSX
     setLastError(QString());
+    m_exportProject.clear(); m_exportLogicalPath.clear();
+    m_exportResult = {{"success",false},{"syncState","ERROR"}};
+    emit exportResultChanged();
 
     if (state.isEmpty()) {
         setLastError(QStringLiteral("No hay datos de calicata para exportar."));
@@ -2070,6 +2134,17 @@ QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, con
     const QString reportCode = canonicalCalicataCode(header, timestamp);
     const QString outPath = makeOutputPath(
         fileBaseName.trimmed().isEmpty() ? reportCode : fileBaseName);
+#ifdef Q_OS_ANDROID
+    const auto projectId = header.value("projectId", header.value("project_id")).toString();
+    const auto logicalStem = "Calicatas/EXCEL/" + safeFileName(reportCode);
+    auto *exportContext = appContext();
+    if (exportContext && exportContext->auth() && exportContext->supabase())
+        m_exports = RenditionExportService::shared(exportContext->supabase(), exportContext->auth());
+    if (!m_exports || !m_exports->prepareGeneration(outPath, projectId, logicalStem)) {
+        setLastError(QStringLiteral("No se pudo registrar la exportación: selecciona proyecto y cuenta, y verifica espacio local."));
+        return {};
+    }
+#endif
     const QFileInfo outputInfo(outPath);
     const QString outputDir = outputInfo.absolutePath();
     if (!QDir().mkpath(outputDir)) {
@@ -2155,7 +2230,8 @@ QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, con
         return QString();
     }
 
-    if (!xlsx.saveAs(outPath)) {
+    const QString generatingPath = outPath + QStringLiteral(".generating.xlsx");
+    if (!xlsx.saveAs(generatingPath) || !QFile::rename(generatingPath, outPath)) {
         logExportDiagnostics(QStringLiteral("QXlsx saveAs fallo despues de una prueba de escritura exitosa."));
         QFile::remove(outPath);
         removeWorkingTemplate();
@@ -2165,7 +2241,37 @@ QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, con
 
     removeWorkingTemplate();
 
+    m_exportResult = {{"success",false},{"fileName",QFileInfo(outPath).fileName()},
+        {"localPhysicalPath",outPath},{"displayPath",outPath},{"syncState","PENDING_SYNC"},{"error",QString()}};
 #ifdef Q_OS_ANDROID
+    m_exportProject = header.value("projectId", header.value("project_id")).toString();
+    QFile generated(outPath);
+    if (!generated.open(QIODevice::ReadOnly) || generated.size() <= 0) {
+        setLastError(QStringLiteral("El XLSX generado no se puede abrir para sincronizar."));
+        m_exportResult["error"] = lastError(); m_exportResult["syncState"] = "ERROR";
+        emit exportResultChanged(); return {};
+    }
+    const auto hash = QCryptographicHash::hash(generated.readAll(), QCryptographicHash::Sha256).toHex();
+    generated.close();
+    m_exportLogicalPath = logicalStem + '_' + QString::fromLatin1(hash.left(20)) + ".xlsx";
+    m_exportResult["remoteLogicalPath"] = m_exportLogicalPath;
+    auto *context = appContext();
+    if (context && context->auth() && context->supabase())
+        m_exports = RenditionExportService::shared(context->supabase(), context->auth());
+    const QPointer<AndroidCalicataExporter> guard(this);
+    const auto user = context && context->auth() ? context->auth()->userId() : QString();
+    const auto logicalPath = m_exportLogicalPath;
+    if (!m_exports || !m_exports->enqueueDocument(outPath, m_exportProject, logicalPath,
+        [guard, user, logicalPath](bool, const QString &) {
+            if (guard && appContext() && appContext()->auth()->userId() == user
+                && guard->m_exportLogicalPath == logicalPath) emit guard->exportResultChanged();
+        })) {
+        setLastError(QStringLiteral("Excel generado y conservado; no se pudo guardar la cola InGeDrive. Selecciona un proyecto y una cuenta válidos y reintenta."));
+        m_exportResult["syncState"] = "ERROR"; m_exportResult["error"] = lastError();
+        emit exportResultChanged();
+        return {}; // A generated file alone is not a successfully queued export.
+    }
+    m_exports->generationQueued(outPath);
     const QString displayName = QFileInfo(outPath).fileName();
     QString publicHint;
     QString mediaError;
@@ -2174,16 +2280,18 @@ QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, con
             QStringLiteral("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
             &publicHint, &mediaError)) {
         qInfo().noquote() << "Excel de calicata exportado a Descargas:" << publicHint;
-        return publicHint;
+        m_exportResult["displayPath"] = publicHint;
+    } else {
+        m_exportResult["displayWarning"] = mediaError;
     }
-
-    setLastError(QStringLiteral("Se creó el Excel en ruta interna, pero no se pudo publicar en Descargas/InGePlus: ") + mediaError + QStringLiteral(". Ruta interna: ") + outPath);
-    qWarning().noquote() << lastError();
-    return outPath;
 #else
-    qInfo().noquote() << "Excel de calicata exportado:" << outPath;
-    return outPath;
+    // Desktop golden/export tools remain a pure generation entry point. Android
+    // always requires the durable InGeDrive operation above.
+    m_exportResult["syncState"] = "GENERATED";
 #endif
+    emit exportResultChanged();
+    // Compatibility return is ALWAYS a QFile-readable physical path.
+    return lastExportResult().value("localPhysicalPath", outPath).toString();
 
 #else
     Q_UNUSED(state)
diff --git a/androidcalicataexporter.h b/androidcalicataexporter.h
index ea03378..fcd2dd0 100644
--- a/androidcalicataexporter.h
+++ b/androidcalicataexporter.h
@@ -10,11 +10,15 @@ class AndroidCalicataExporter : public QObject
 {
     Q_OBJECT
     Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
+    Q_PROPERTY(QVariantMap lastExportResult READ lastExportResult NOTIFY exportResultChanged)
 
 public:
     explicit AndroidCalicataExporter(QObject *parent = nullptr);
 
     QString lastError() const;
+    QVariantMap lastExportResult() const;
+    Q_INVOKABLE void retryPendingExports();
+    Q_INVOKABLE bool openLastExport(bool share = false);
 
     Q_INVOKABLE QString defaultExportDir() const;
     Q_INVOKABLE QString exportStateToXlsx(const QVariantMap &state, const QString &fileBaseName = QString());
@@ -31,6 +35,7 @@ signals:
     void calicataSavedOnline(const QString &documentId);
     void calicataPublishFailed(const QString &documentId, const QString &message);
     void lastErrorChanged();
+    void exportResultChanged();
 
 private:
     void setLastError(const QString &error);
@@ -41,6 +46,9 @@ private:
     QVariantMap readJsonObject(const QString &jsonPath);
 
     QString m_lastError;
+    QVariantMap m_exportResult;
+    QString m_exportProject;
+    QString m_exportLogicalPath;
     RenditionExportService *m_exports = nullptr;
     QHash<QString, QString> m_publishedFiles;
     QString m_publishedUser;
diff --git a/appcontext.cpp b/appcontext.cpp
index a58314f..85951b8 100644
--- a/appcontext.cpp
+++ b/appcontext.cpp
@@ -3,6 +3,7 @@
 #include "authsession.h"
 #include "clouddocs.h"
 #include "settingshelper.h"
+#include "src/cpp/renditionexportservice.h"
 
 #include <QSettings>
 #include <QDir>
@@ -45,6 +46,8 @@ AppContext::AppContext(QObject *parent)
     m_auth     = new AuthSession(m_supabase, this);
 
     m_docs = new CloudDocs(m_supabase, m_auth, this);
+    // Restore pending exports on login even when the export screen is never opened.
+    RenditionExportService::shared(m_supabase, m_auth);
 
 
     // La restauración de sesión se inicia desde Main.qml para que la UI
diff --git a/src/cpp/renditionexportservice.h b/src/cpp/renditionexportservice.h
index ee94520..de6142c 100644
--- a/src/cpp/renditionexportservice.h
+++ b/src/cpp/renditionexportservice.h
@@ -1,143 +1,335 @@
 #pragma once
-#include "../../clouddocs.h"
-#include "../../authsession.h"
-#include <QTimer>
+#include "../documents/storageprovider.h"
 #include <QSaveFile>
-#include <QJsonDocument>
 #include <QStandardPaths>
 #include <QCryptographicHash>
 #include <QDir>
 #include <QFileInfo>
-#include <functional>
+#include <QMimeDatabase>
+#include <QDateTime>
+#include <QGuiApplication>
+#include <QNetworkInformation>
+#include <QUuid>
+#include <QDebug>
+#include <algorithm>
 
-// Rendiciones export outbox. Uses the existing InGeDrive binary transport.
+// Existing durable outbox for both export domains. No second queue or migration
+// of historical cloud objects. Storage keys are issued only by InGeDrive RPCs.
 class RenditionExportService final : public QObject {
 public:
+    using Completion = std::function<void(bool, const QString &)>;
     static RenditionExportService *shared(SupabaseClient *api, AuthSession *auth) {
         static auto *service = new RenditionExportService(api, auth, auth);
         return service;
     }
     RenditionExportService(SupabaseClient *api, AuthSession *auth, QObject *parent = nullptr)
-        : QObject(parent), m_auth(auth), m_cloud(api, auth, this) {
-        connect(&m_cloud, &CloudDocs::uploadOk, this, [this](const QString &) {
-            const auto completed = m_active;
-            if (m_user == m_auth->userId() && !m_active.isEmpty()) {
-                auto row = m_rows.value(m_active).toMap();
-                row["state"] = "UPLOADED"; m_rows[m_active] = row;
-                if (!save()) {
-                    row["state"] = "ERROR"; m_rows[m_active] = row;
-                    m_active.clear();
-                    finish(completed, false, "No se pudo confirmar la subida en el registro local. Reintenta.");
-                    return;
+        : QObject(parent), m_auth(auth), m_provider(api,auth,this) {
+        connect(auth,&AuthSession::accountSwitchStarted,this,[this](const QString &){ resetAccount(); });
+        connect(auth,&AuthSession::loggedOut,this,[this]{ resetAccount(); });
+        connect(auth,&AuthSession::loggedChanged,this,[this]{ schedule(); });
+        connect(auth,&AuthSession::backendAccessChanged,this,[this]{
+            if(selectAccount()) {
+                const auto old=m_rows;
+                for(auto it=m_rows.begin();it!=m_rows.end();++it) {
+                    auto row=it.value().toMap();
+                    if(row.value("error")=="AUTH_REQUIRED") {row["state"]="PENDING";row["nextRetryAt"]=0;it.value()=row;}
                 }
-                m_active.clear();
-                finish(completed, true, {});
+                if(!save()) m_rows=old;
             }
-            m_active.clear(); tick();
+            schedule();
         });
-        connect(&m_cloud, &CloudDocs::uploadFail, this, [this](const QString &error) {
-            const auto failed = m_active;
-            if (m_user == m_auth->userId() && !m_active.isEmpty()) {
-                auto row = m_rows.value(m_active).toMap();
-                row["state"] = "ERROR"; m_rows[m_active] = row; save();
+        if(auto *app=qobject_cast<QGuiApplication*>(QCoreApplication::instance()))
+            connect(app,&QGuiApplication::applicationStateChanged,this,[this](Qt::ApplicationState state){
+                if(state==Qt::ApplicationActive) schedule();
+            });
+        QNetworkInformation::loadDefaultBackend();
+        if(auto *network=QNetworkInformation::instance())
+            connect(network,&QNetworkInformation::reachabilityChanged,this,[this](QNetworkInformation::Reachability state){
+                if(state==QNetworkInformation::Reachability::Online) schedule();
+            });
+        m_retry.setSingleShot(true);
+        connect(&m_retry,&QTimer::timeout,this,[this]{ tick(); });
+        schedule();
+    }
+    bool enqueue(const QString &path,const QString &project,const QString &rendition,
+                 const QString &version,const QString &format) {
+        if(QUuid(rendition).isNull() || QUuid(version).isNull() || (format!="xlsx" && format!="pdf")) return false;
+        return enqueueDocument(path,project,"Export/Rendiciones/"+rendition+"/"+version+"/"+QFileInfo(path).fileName(),{});
+    }
+    bool enqueueDocument(const QString &path,const QString &project,const QString &logicalPath,
+                         Completion completion,const QString &requiresRemotePath = {}) {
+        if(!selectAccount() || QUuid(project).isNull() || !validPath(logicalPath)) return false;
+        QFile source(path);
+        if(!source.open(QIODevice::ReadOnly) || source.size()<1 || source.size()>50LL*1024*1024) return false;
+        const auto bytes=source.readAll();
+        if(bytes.size()!=source.size()) return false;
+        const QString hash=digest(bytes);
+        const QString id=digest((project+'/'+logicalPath+'/'+hash).toUtf8());
+        if(m_rows.contains(id)) {
+            const auto row=m_rows.value(id).toMap();
+            if(row.value("state")=="UPLOADED") {
+                if(completion) QTimer::singleShot(0,this,[completion]{completion(true,{});});
+            } else {
+                if(completion) m_completions[id].append(std::move(completion));
+                if(row.value("state")=="ERROR") retry(); else schedule();
             }
-            m_active.clear();
-            finish(failed, false, error);
-        });
-        connect(&m_timer, &QTimer::timeout, this, [this] { tick(); });
-        m_timer.start(45000);
-    }
-    bool enqueue(const QString &path, const QString &project, const QString &rendition,
-                 const QString &version, const QString &format) {
-        if (!selectAccount() || project.isEmpty() || rendition.isEmpty() || version.isEmpty()) return false;
-        QFile file(path); if (!file.open(QIODevice::ReadOnly)) return false;
-        const auto hash = QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex();
-        const QString id = QString::fromLatin1(QCryptographicHash::hash(
-            (rendition + version + format + QString::fromLatin1(hash)).toUtf8(), QCryptographicHash::Sha256).toHex());
-        if (m_rows.contains(id)) { tick(); return true; }
-        const auto local = QFileInfo(m_path).absolutePath() + '/' + id + '.' + format;
-        if (!QFile::exists(local) && !QFile::copy(path, local)) return false;
-        m_rows[id] = QVariantMap{{"id",id},{"projectId",project},{"renditionId",rendition},
-            {"versionId",version},{"format",format},{"sha256",QString::fromLatin1(hash)},
-            {"localPath",local},{"remotePath","Export/Rendiciones/" + id + '.' + format},{"state","PENDING"}};
-        if (!save()) { m_rows.remove(id); return false; }
-        tick(); return true;
-    }
-    // Same account-scoped outbox and CloudDocs transport for Calicatas.
-    using Completion = std::function<void(bool, const QString &)>;
-    bool enqueueDocument(const QString &path, const QString &project,
-                         const QString &remotePath, Completion completion,
-                         const QString &requiresRemotePath = {}) {
-        if (!selectAccount() || project.isEmpty() || remotePath.isEmpty()) return false;
-        QFile file(path); if (!file.open(QIODevice::ReadOnly)) return false;
-        const auto bytes = file.readAll();
-        const auto hash = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
-        const auto id = QString::fromLatin1(QCryptographicHash::hash(
-            (project + '/' + remotePath + '/' + QString::fromLatin1(hash)).toUtf8(), QCryptographicHash::Sha256).toHex());
-        if (m_rows.value(id).toMap().value("state") == "UPLOADED") {
-            QTimer::singleShot(0, this, [completion] { completion(true, {}); });
             return true;
         }
-        const auto local = QFileInfo(m_path).absolutePath() + '/' + id + '.' + QFileInfo(path).suffix();
-        if (!QFile::exists(local)) {
-            QSaveFile copy(local);
-            if (!copy.open(QIODevice::WriteOnly) || copy.write(bytes) != bytes.size() || !copy.commit()) return false;
+        const QString directory=QFileInfo(m_path).absolutePath()+"/mirror/"+id;
+        const QString local=directory+'/'+QFileInfo(logicalPath).fileName();
+        if(!QDir().mkpath(directory)) return false;
+        QSaveFile mirror(local);
+        if(!mirror.open(QIODevice::WriteOnly) || mirror.write(bytes)!=bytes.size() || !mirror.commit()) return false;
+        qint64 sequence=1;
+        for(const auto &value:m_rows) sequence=qMax(sequence,value.toMap().value("sequence").toLongLong()+1);
+        QString mime=QMimeDatabase().mimeTypeForFile(path).name();
+        if(path.endsWith(".xlsx",Qt::CaseInsensitive)) mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
+        m_rows[id]=QVariantMap{{"id",id},{"ownerId",m_user},{"projectId",project},{"localPath",local},
+            {"logicalPath",logicalPath},{"remotePath",QString()},{"fileName",QFileInfo(logicalPath).fileName()},
+            {"mimeType",mime},{"size",bytes.size()},{"sha256",hash},{"state","PENDING"},{"syncState","PENDING_SYNC"},
+            {"requestId",uuid()},{"sequence",sequence},{"updatedAt",now()},{"requiresRemotePath",requiresRemotePath}};
+        if(!save()) {m_rows.remove(id);return false;}
+        if(completion) m_completions[id].append(std::move(completion));
+        log(m_rows[id].toMap(),"pending"); schedule(); return true;
+    }
+    // Record generation before writing. The final workbook is atomically renamed
+    // into this path, so recovery never adopts partially generated XLSX bytes.
+    bool prepareGeneration(const QString &path,const QString &project,const QString &logicalStem) {
+        if(!selectAccount() || QUuid(project).isNull() || !validPath(logicalStem+".xlsx")) return false;
+        const QString id="generation-"+digest(path.toUtf8());
+        m_rows[id]=QVariantMap{{"id",id},{"ownerId",m_user},{"projectId",project},{"localPath",path},
+            {"logicalStem",logicalStem},{"state","GENERATING"},{"syncState","PENDING_SYNC"}};
+        if(save()) return true;
+        m_rows.remove(id);return false;
+    }
+    void generationQueued(const QString &path) {
+        const auto old=m_rows;m_rows.remove("generation-"+digest(path.toUtf8()));
+        if(!save()) m_rows=old;
+    }
+    QVariantMap resultFor(const QString &project,const QString &logicalPath) {
+        if(!selectAccount()) return {};
+        QVariantMap found;
+        for(const auto &value:m_rows) {
+            const auto row=value.toMap();
+            if(row.value("projectId")==project && row.value("logicalPath",row.value("remotePath"))==logicalPath
+                && (found.isEmpty() || row.value("sequence").toLongLong()>=found.value("sequence").toLongLong())) found=row;
         }
-        m_rows[id] = QVariantMap{{"id",id},{"projectId",project},{"localPath",local},
-            {"remotePath",remotePath},{"state","PENDING"},{"sha256",QString::fromLatin1(hash)},
-            {"requiresRemotePath",requiresRemotePath}};
-        if (!save()) { m_rows.remove(id); return false; }
-        m_completions[id] = std::move(completion);
-        QTimer::singleShot(0, this, [this] { tick(); });
-        return true;
+        if(found.isEmpty()) return {};
+        return {{"success",found.value("syncState")=="SYNCED"},{"fileName",found.value("fileName")},
+            {"localPhysicalPath",found.value("localPath")},{"localPath",found.value("localPath")},
+            {"remoteLogicalPath",logicalPath},{"remotePath",found.value("remotePath")},
+            {"remoteId",found.value("document_node_id")},{"version",found.value("document_version_id")},
+            {"syncState",found.value("syncState","PENDING_SYNC")},{"error",found.value("error")}};
     }
+    // Explicit retry releases errors after permissions/auth have been repaired.
+    void retry() {
+        if(!selectAccount()) return;
+        const auto old=m_rows;
+        for(auto it=m_rows.begin();it!=m_rows.end();++it) {
+            auto row=it.value().toMap();
+            if(row.value("state")=="ERROR" || row.value("state")=="PENDING") {
+                row["state"]="PENDING";row["nextRetryAt"]=0;it.value()=row;
+            }
+        }
+        if(!save()) {m_rows=old;return;} schedule();
+    }
+    // Aggregate ordering remains in RenditionLocalStore; binary transport is shared.
+    SupabaseStorageProvider *storage() { return &m_provider; }
 private:
-    void finish(const QString &id, bool ok, const QString &error) {
-        auto callback = m_completions.take(id);
-        if (callback) callback(ok, error);
+    static QString uuid() {return QUuid::createUuid().toString(QUuid::WithoutBraces);}
+    static QString now() {return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);}
+    static QString digest(const QByteArray &bytes) {return QString::fromLatin1(QCryptographicHash::hash(bytes,QCryptographicHash::Sha256).toHex());}
+    static bool validPath(const QString &path) {
+        if(path.isEmpty() || path.startsWith('/') || path.contains('\\')) return false;
+        for(const auto &part:path.split('/'))
+            if(part.isEmpty() || part=="." || part==".." || part.contains(QRegularExpression("[\\x00-\\x1f]"))) return false;
+        return QFileInfo(path).fileName().size()<=255;
+    }
+    void resetAccount() {++m_epoch;m_retry.stop();m_active.clear();m_user.clear();m_path.clear();m_rows.clear();m_completions.clear();}
+    void schedule() {QTimer::singleShot(0,this,[this]{tick();});}
+    void log(const QVariantMap &row,const char *state) {
+        qInfo().noquote()<<"INGE_DRIVE_EXPORT owner="<<(row.value("logicalPath").toString().startsWith("Calicatas/")?"calicatas":"renditions")
+            <<"project="<<row.value("projectId").toString()<<"file="<<row.value("id").toString()<<"state="<<state;
     }
     bool selectAccount() {
-        if (!m_auth->logged() || m_auth->userId().isEmpty()) return false;
-        if (m_user == m_auth->userId()) return true;
-        if (!m_active.isEmpty()) return false;
-        m_completions.clear();
-        m_user = m_auth->userId(); m_rows.clear();
-        const auto dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/rendition-exports/" + m_user;
-        if (!QDir().mkpath(dir)) { m_user.clear(); return false; }
-        m_path = dir + "/outbox.json"; QFile file(m_path);
-        if (file.exists()) {
-            if (!file.open(QIODevice::ReadOnly)) { m_user.clear(); return false; }
-            QJsonParseError error; const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
-            if (error.error != QJsonParseError::NoError || !doc.isObject()) { m_user.clear(); return false; }
-            m_rows = doc.toVariant().toMap();
+        if(!m_auth->logged() || QUuid(m_auth->userId()).isNull()) return false;
+        if(m_user==m_auth->userId()) return true;
+        resetAccount();m_user=m_auth->userId();
+        const QString directory=QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/rendition-exports/"+m_user;
+        if(!QDir().mkpath(directory)) {resetAccount();return false;}
+        m_path=directory+"/outbox.json";QFile file(m_path);
+        if(file.exists()) {
+            if(!file.open(QIODevice::ReadOnly)) {resetAccount();return false;}
+            QJsonParseError error;const auto doc=QJsonDocument::fromJson(file.readAll(),&error);
+            if(error.error!=QJsonParseError::NoError || !doc.isObject()) {resetAccount();return false;}
+            m_rows=doc.toVariant().toMap();
         }
-        return true;
+        // Upgrade pending metadata in place. Completed legacy objects remain untouched.
+        for(auto it=m_rows.begin();it!=m_rows.end();++it) {
+            auto row=it.value().toMap();if(row.value("state")=="UPLOADED" || row.value("state")=="GENERATING") continue;
+            if(!row.contains("logicalPath")) {row["logicalPath"]=row.value("remotePath");row["remotePath"]=QString();}
+            if(row.value("requestId").toString().isEmpty()) row["requestId"]=uuid();
+            if(row.value("fileName").toString().isEmpty()) row["fileName"]=QFileInfo(row.value("logicalPath").toString()).fileName();
+            if(row.value("mimeType").toString().isEmpty()) row["mimeType"]=QMimeDatabase().mimeTypeForFile(row.value("localPath").toString()).name();
+            if(!row.contains("size")) row["size"]=QFileInfo(row.value("localPath").toString()).size();
+            row["ownerId"]=m_user;
+            if(row.value("state")=="UPLOADING") row["state"]="PENDING";
+            row["syncState"]=row.value("state")=="ERROR"?"ERROR":row.value("state")=="CONFLICT"?"CONFLICT":"PENDING_SYNC";
+            it.value()=row;
+        }
+        if(!save()) {resetAccount();return false;}return true;
     }
     bool save() {
-        QSaveFile file(m_path); const auto data = QJsonDocument::fromVariant(m_rows).toJson(QJsonDocument::Compact);
-        return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
+        if(m_path.isEmpty()) return false;
+        QSaveFile file(m_path);const auto bytes=QJsonDocument::fromVariant(m_rows).toJson(QJsonDocument::Compact);
+        return file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size() && file.commit();
+    }
+    bool checkpoint(QVariantMap row) {
+        const auto old=m_rows;row["updatedAt"]=now();m_rows[m_active]=row;
+        if(save()) return true;
+        m_rows=old;const auto id=m_active;m_active.clear();notify(id,false,"LOCAL_PERSISTENCE_FAILED");return false;
+    }
+    void notify(const QString &id,bool ok,const QString &error) {
+        const auto callbacks=ok?m_completions.take(id):m_completions.value(id);
+        for(const auto &callback:callbacks) if(callback) callback(ok,error);
+    }
+    void failed(const QString &error,bool retryable) {
+        auto row=m_rows.value(m_active).toMap();
+        const bool retryBaselineMissing=error=="STALE_VERSION" && !row.value("retryKey").toString().isEmpty();
+        const bool conflict=!retryBaselineMissing && (error.contains("CONFLICT") || error.contains("STALE_VERSION"));
+        row["state"]=conflict?"CONFLICT":retryable?"PENDING":"ERROR";
+        row["syncState"]=conflict?"CONFLICT":retryable?"PENDING_SYNC":"ERROR";row["error"]=error;
+        if(retryBaselineMissing) row["error"]="BACKEND_RETRY_BASELINE_OR_VERSION_CONFLICT";
+        const int failures=qMin(10,row.value("failures").toInt()+1);row["failures"]=failures;
+        const int delay=qMin(900000,15000*(1<<qMin(failures,6)));
+        row["nextRetryAt"]=retryable?QDateTime::currentMSecsSinceEpoch()+delay:0;
+        const auto id=m_active;if(!checkpoint(row)) return;
+        log(row,retryable?"pending":"error");m_active.clear();notify(id,false,error);schedule();
+    }
+    void request(const QString &endpoint,const QVariantMap &args,std::function<void(QVariantMap)> done,bool get=false) {
+        const auto epoch=m_epoch;const auto user=m_user;const auto id=m_active;
+        m_provider.request(endpoint,args,get,[this,epoch,user,id,done](QVariantList rows,QString error,bool retryable){
+            if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged() || id!=m_active) return;
+            if(!error.isEmpty()) {failed(error,retryable || error=="UPLOAD_RESERVATION_EXPIRED");return;}
+            if(rows.size()!=1) {failed("INVALID_RESPONSE",false);return;}done(rows.first().toMap());
+        });
     }
     void tick() {
-        if (!m_active.isEmpty() || !selectAccount()) return;
-        for (auto it = m_rows.cbegin(); it != m_rows.cend(); ++it) {
-            const auto row = it.value().toMap(); if (row.value("state") == "UPLOADED") continue;
-            const auto dependency = row.value("requiresRemotePath").toString();
-            if (!dependency.isEmpty()) {
-                bool ready = false;
-                for (const auto &value : m_rows) {
-                    const auto other = value.toMap();
-                    if (other.value("projectId") == row.value("projectId")
-                        && other.value("remotePath") == dependency && other.value("state") == "UPLOADED") ready = true;
-                }
-                if (!ready) continue;
+        if(!selectAccount() || !m_active.isEmpty()) return;
+        // Recover the generation/enqueue crash boundary without a second journal.
+        for(const auto &key:m_rows.keys()) {
+            const auto intent=m_rows.value(key).toMap();
+            if(intent.value("state")!="GENERATING") continue;
+            QFile file(intent.value("localPath").toString());
+            if(!file.open(QIODevice::ReadOnly) || file.size()<1) continue;
+            const auto hash=digest(file.readAll());
+            if(enqueueDocument(file.fileName(),intent.value("projectId").toString(),
+                intent.value("logicalStem").toString()+'_'+hash.left(20)+".xlsx",{})) generationQueued(file.fileName());
+        }
+        QStringList ids=m_rows.keys();
+        std::stable_sort(ids.begin(),ids.end(),[this](const QString &a,const QString &b){return m_rows[a].toMap().value("sequence").toLongLong()<m_rows[b].toMap().value("sequence").toLongLong();});
+        qint64 next=0;
+        for(const auto &id:ids) {
+            auto row=m_rows[id].toMap();const auto state=row.value("state").toString();
+            if(state=="UPLOADED" || state=="ERROR" || state=="CONFLICT" || state=="GENERATING") continue;
+            const auto retryAt=row.value("nextRetryAt").toLongLong();
+            if(retryAt>QDateTime::currentMSecsSinceEpoch()) {next=next==0?retryAt:qMin(next,retryAt);continue;}
+            const auto dependency=row.value("requiresRemotePath").toString();
+            if(!dependency.isEmpty()) {
+                bool ready=false;for(const auto &value:m_rows) {const auto other=value.toMap();
+                    if(other.value("projectId")==row.value("projectId") && other.value("logicalPath",other.value("remotePath"))==dependency && other.value("state")=="UPLOADED") ready=true;}
+                if(!ready) continue;
             }
-            m_active = it.key();
-            m_cloud.uploadFile(row.value("localPath").toString(), row.value("projectId").toString(),
-                               row.value("remotePath").toString(), {}, true);
+            m_active=id;m_recoveryAttempts=0;QFile file(row.value("localPath").toString());
+            if(QUuid(row.value("projectId").toString()).isNull() || !file.open(QIODevice::ReadOnly)
+                || file.size()!=row.value("size").toLongLong() || digest(file.readAll())!=row.value("sha256").toString()) {failed("LOCAL_MIRROR_INVALID",false);return;}
+            row["state"]="UPLOADING";row["syncState"]="UPLOADING";row["error"]=QString();
+            if(!checkpoint(row)) return;
+            log(row,"uploading");
+            if(row.value("spaceId").toString().isEmpty()) {
+                const auto project=row.value("projectId").toString();
+                request("document_spaces?select=id,project_id&space_type=eq.PROJECT&project_id=eq."+project+"&status=eq.ACTIVO&limit=2",{},[this,project](QVariantMap space){
+                    if(QUuid(space.value("id").toString()).isNull() || space.value("project_id")!=project) {failed("PROJECT_SPACE_REQUIRED",false);return;}
+                    auto row=m_rows[m_active].toMap();row["spaceId"]=space.value("id");if(checkpoint(row)) reserve();
+                },true);
+            } else reserve();
             return;
         }
+        if(next>0) m_retry.start(int(qBound<qint64>(1000,next-QDateTime::currentMSecsSinceEpoch(),900000)));
+    }
+    void reserve() {
+        const auto row=m_rows[m_active].toMap();
+        if(!row.value("retryKey").toString().isEmpty()) {retryReservation();return;}
+        request("rpc/reserve_binary_document_upload_v01",{{"p_space_id",row.value("spaceId")},{"p_parent_node_id",QVariant()},
+            {"p_file_name",row.value("fileName")},{"p_mime_type",row.value("mimeType")},{"p_size_bytes",row.value("size")},
+            {"p_idempotency_key",row.value("requestId")}},[this](QVariantMap reservation){acceptReservation(reservation);});
+    }
+    void acceptReservation(const QVariantMap &reservation,bool renewed=false) {
+        auto row=m_rows[m_active].toMap();
+        const auto node=reservation.value("document_node_id").toString(),version=reservation.value("document_version_id").toString();
+        const auto path=reservation.value("storage_path").toString();
+        const QString prefix="spaces/"+row.value("spaceId").toString()+"/nodes/"+node+"/versions/"+version+'/';
+        if(QUuid(node).isNull() || QUuid(version).isNull() || QUuid(reservation.value("attempt_id").toString()).isNull()
+            || reservation.value("bucket")!="project-files" || !path.startsWith(prefix) || path.split('/').size()!=7
+            || !validPath(path) || reservation.value("size_bytes").toLongLong()!=row.value("size").toLongLong()
+            || reservation.value("mime_type")!=row.value("mimeType")
+            || (!row.value("document_version_id").toString().isEmpty() && row.value("document_version_id")!=version)) {failed("INVALID_RESERVATION",false);return;}
+        for(auto it=reservation.cbegin();it!=reservation.cend();++it) row[it.key()]=it.value();
+        row["remotePath"]=path;if(!checkpoint(row)) return;
+        const auto status=row.value("attempt_status").toString();
+        if(status=="FINALIZADO") {finalize();return;}
+        const auto expiry=QDateTime::fromString(row.value("upload_expires_at").toString(),Qt::ISODateWithMs);
+        if(!expiry.isValid()) {failed("INVALID_RESERVATION_EXPIRY",false);return;}
+        if(status=="EXPIRADO" || status=="FALLIDO" || expiry<=QDateTime::currentDateTimeUtc()) {
+            // New attempt key only: document/version/storage path remain identical.
+            if(++m_recoveryAttempts>2) {failed("RESERVATION_EXPIRY_NOT_RECOVERED",false);return;}
+            row["retryKey"]=uuid();if(checkpoint(row)) retryReservation();return;
+        }
+        if(status=="INDETERMINADO") {failed("OBJECT_CONFLICT",false);return;}
+        if(status=="OBJETO_CARGADO") {finalize();return;}
+        if(status!="RESERVADO" && status!="EN_CARGA") {failed("INVALID_ATTEMPT_STATUS",false);return;}
+        if(!renewed && expiry<=QDateTime::currentDateTimeUtc().addSecs(90)) {
+            request("rpc/renew_document_upload_lease_controlled",{{"p_attempt_id",row.value("attempt_id")}},[this,row](QVariantMap lease) mutable {
+                if(lease.value("attempt_id")!=row.value("attempt_id")) {failed("INVALID_LEASE_RESPONSE",false);return;}
+                for(auto it=lease.cbegin();it!=lease.cend();++it) row[it.key()]=it.value();
+                acceptReservation(row,true);
+            });return;
+        }
+        request("rpc/begin_binary_document_upload_v01",{{"p_attempt_id",row.value("attempt_id")}},[this](QVariantMap begun){
+            if(begun.value("attempt_id")!=m_rows[m_active].toMap().value("attempt_id") || begun.value("attempt_status")!="EN_CARGA") {failed("INVALID_BEGIN_RESPONSE",false);return;}
+            upload();
+        });
+    }
+    void retryReservation() {
+        const auto row=m_rows[m_active].toMap();
+        request("rpc/retry_document_upload_controlled",{{"p_document_version_id",row.value("document_version_id")},
+            {"p_idempotency_key",row.value("retryKey")}},[this](QVariantMap reservation){acceptReservation(reservation);});
+    }
+    void upload() {
+        const auto row=m_rows[m_active].toMap();const auto epoch=m_epoch;const auto user=m_user;
+        m_provider.uploadReserved(row.value("localPath").toString(),"project-files",row.value("remotePath").toString(),row.value("mimeType").toString(),
+            [this,epoch,user](bool ok,QString error,bool retryable){
+                if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged()) return;
+                if(!ok) {failed(error,retryable);return;}finalize();
+            });
+    }
+    void finalize() {
+        const auto row=m_rows[m_active].toMap();
+        request("rpc/finalize_binary_document_upload_v01",{{"p_attempt_id",row.value("attempt_id")}},[this](QVariantMap confirmed){
+            auto row=m_rows[m_active].toMap();
+            if(confirmed.value("attempt_status")!="FINALIZADO" || confirmed.value("document_version_id")!=row.value("document_version_id")
+                || confirmed.value("document_node_id")!=row.value("document_node_id")) {failed("INVALID_FINALIZE_RESPONSE",false);return;}
+            for(auto it=confirmed.cbegin();it!=confirmed.cend();++it) row[it.key()]=it.value();
+            row["state"]="UPLOADED";row["syncState"]="SYNCED";row["error"]=QString();
+            const auto id=m_active;if(!checkpoint(row)) return;
+            log(row,"synced");m_active.clear();notify(id,true,{});schedule();
+        });
     }
-    AuthSession *m_auth; CloudDocs m_cloud; QTimer m_timer;
-    QString m_user, m_path, m_active; QVariantMap m_rows;
-    QHash<QString, Completion> m_completions;
+    AuthSession *m_auth;
+    SupabaseStorageProvider m_provider;
+    QTimer m_retry;
+    int m_epoch=0,m_recoveryAttempts=0;
+    QString m_user,m_path,m_active;
+    QVariantMap m_rows;
+    QHash<QString,QList<Completion>> m_completions;
 };
diff --git a/src/cpp/renditionlocalstore.cpp b/src/cpp/renditionlocalstore.cpp
index 4240755..66be36c 100644
--- a/src/cpp/renditionlocalstore.cpp
+++ b/src/cpp/renditionlocalstore.cpp
@@ -18,6 +18,7 @@
 #include <QSet>
 #include <QStandardPaths>
 #include <QUuid>
+#include <QUrl>
 
 namespace {
 constexpr auto LocalOnly = "LOCAL_ONLY";
@@ -748,12 +749,45 @@ QString RenditionLocalStore::addLocalAttachment(
     }
     const QString localId = newUuid();
     const QString requestId = newUuid();
+    // Materialize external/content URIs before enqueuing. URI permissions and
+    // picker cache files need not survive process death; this mirror does.
+    const QUrl sourceUrl(attachment.value(QStringLiteral("localUri")).toString());
+    QFile source(sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : attachment.value(QStringLiteral("localUri")).toString());
+    if (!source.open(QIODevice::ReadOnly) || source.size() != sizeBytes) {
+        setLastError(QStringLiteral("No se pudo conservar el sustento original."));
+        return {};
+    }
+    const auto bytes = source.readAll();
+    const auto sha256 = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
+    for (const auto &entry : attachments) {
+        const auto existing = entry.toMap();
+        if (existing.value(QStringLiteral("archived_at")).toString().isEmpty()
+            && existing.value(QStringLiteral("sha256")).toString() == sha256)
+            return existing.value(QStringLiteral("localId")).toString();
+    }
+    const QString mirrorDirectory = storagePath() + QStringLiteral(".attachments/") + localId;
+    const QString name = QFileInfo(attachment.value(QStringLiteral("fileName")).toString()).fileName();
+    if (name.isEmpty() || name == QLatin1String(".") || name == QLatin1String("..")
+        || bytes.size() != sizeBytes || !QDir().mkpath(mirrorDirectory)) {
+        setLastError(QStringLiteral("No se pudo crear el mirror del sustento.")); return {};
+    }
+    const QString mirrorPath = QDir(mirrorDirectory).filePath(name);
+    QSaveFile mirror(mirrorPath);
+    if (!mirror.open(QIODevice::WriteOnly) || mirror.write(bytes) != bytes.size() || !mirror.commit()) {
+        setLastError(QStringLiteral("No se pudo guardar el sustento para uso offline.")); return {};
+    }
+    local.insert(QStringLiteral("localUri"), mirrorPath);
+    local.insert(QStringLiteral("sha256"), sha256);
+    local.insert(QStringLiteral("projectId"), expense.value(QStringLiteral("projectId")));
     local.insert(QStringLiteral("localId"), localId);
     local.insert(QStringLiteral("remoteId"), QString());
     local.insert(QStringLiteral("requestId"), requestId);
     local.insert(QStringLiteral("phase"), QStringLiteral("RESERVE"));
     local.insert(QStringLiteral("syncState"), QString::fromLatin1(PendingCreate));
     local.insert(QStringLiteral("createdAt"), nowUtc());
+    const auto previousRenditions = m_renditions;
+    const auto previousOutbox = m_outbox;
+    const auto previousSequence = m_nextSequence;
     attachments.append(local);
     expense.insert(QStringLiteral("attachments"), attachments);
     expenses[childIndex] = expense;
@@ -768,7 +802,9 @@ QString RenditionLocalStore::addLocalAttachment(
     upsertOutbox(QStringLiteral("attachment_reserve"), renditionLocalId,
                  draft.value(QStringLiteral("remoteId")).toString(), localId,
                  requestId, payload, QString::fromLatin1(PendingCreate));
-    return persist() ? localId : QString{};
+    if (persist()) return localId;
+    m_renditions = previousRenditions; m_outbox = previousOutbox; m_nextSequence = previousSequence;
+    return {};
 }
 
 bool RenditionLocalStore::updateAttachmentPhase(
diff --git a/src/cpp/renditionrepository.cpp b/src/cpp/renditionrepository.cpp
index 0ee9c84..5c249dd 100644
--- a/src/cpp/renditionrepository.cpp
+++ b/src/cpp/renditionrepository.cpp
@@ -4,6 +4,7 @@
 #include "authsession.h"
 #include "supabaseclient.h"
 #include "renditionattachmentcontract.h"
+#include "renditionexportservice.h"
 
 #include <QFile>
 #include <QJsonDocument>
@@ -604,41 +605,23 @@ void RenditionRepository::uploadReservedAttachment(
         return;
     }
 
-    QNetworkRequest request = client->makeRequest(
-        QUrl(storageObjectUrl(client, bucket, objectPath)), session->accessToken());
-    request.setHeader(QNetworkRequest::ContentTypeHeader,
-                      mimeType.isEmpty() ? QStringLiteral("application/octet-stream") : mimeType);
-    request.setRawHeader("x-upsert", "false");
-    request.setRawHeader("x-ingeplus-platform", "ANDROID");
-    request.setTransferTimeout(60000);
     const quint64 epoch = m_requestEpoch;
-    QNetworkReply *reply = client->nam()->post(request, file.readAll());
     beginRequest();
-    connect(reply, &QNetworkReply::finished, this,
-            [this, reply = QPointer<QNetworkReply>(reply), attachmentId, epoch]() {
-        endRequest();
-        if (!reply)
-            return;
-        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
-        const bool ok = reply->error() == QNetworkReply::NoError
-            && status >= 200 && status < 300;
-        const QString error = reply->errorString();
-        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
-        reply->deleteLater();
-        if (epoch != m_requestEpoch) return;
-        // A lost response may leave the same reserved object uploaded. The
-        // finalize RPC verifies its ownership, size and MIME before marking READY.
-        const bool duplicate = (status == 400 || status == 409)
-            && (body.value(QStringLiteral("error")).toString() == QLatin1String("Duplicate")
-                || body.value(QStringLiteral("code")).toString() == QLatin1String("Duplicate")
-                || body.value(QStringLiteral("message")).toString() == QLatin1String("The resource already exists"));
-        if (!ok && !duplicate) {
-            emit operationFailed(QStringLiteral("attachment_upload"),
-                                 QStringLiteral("ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION"),
-                                 error);
+    const QPointer<RenditionRepository> guard(this);
+    qInfo() << "INGE_DRIVE_ATTACHMENT owner=renditions state=uploading";
+    RenditionExportService::shared(client, session)->storage()->uploadReserved(
+        localFileName(localFilePath), bucket, objectPath, mimeType,
+        [guard, attachmentId, epoch](bool ok, const QString &error, bool retryable) {
+        if (!guard || epoch != guard->m_requestEpoch) return;
+        guard->endRequest();
+        if (!ok) {
+            qInfo() << "INGE_DRIVE_ATTACHMENT owner=renditions state=error";
+            emit guard->operationFailed(QStringLiteral("attachment_upload"),
+                retryable ? QStringLiteral("ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION") : error, error);
             return;
         }
-        emit attachmentUploaded(attachmentId);
+        // The existing domain controller persists FINALIZE, then confirms READY.
+        emit guard->attachmentUploaded(attachmentId);
     });
 }
 
diff --git a/src/cpp/renditionsynccontroller.cpp b/src/cpp/renditionsynccontroller.cpp
index a455ab0..c57be2b 100644
--- a/src/cpp/renditionsynccontroller.cpp
+++ b/src/cpp/renditionsynccontroller.cpp
@@ -4,6 +4,9 @@
 #include "renditionrepository.h"
 #include "renditionattachmentcontract.h"
 #include <QDateTime>
+#include <QGuiApplication>
+#include <QNetworkInformation>
+#include <QTimer>
 
 namespace {
 constexpr auto Conflict = "CONFLICT";
@@ -21,6 +24,20 @@ RenditionSyncController::RenditionSyncController(
     RenditionLocalStore *store, RenditionRepository *repository, QObject *parent)
     : QObject(parent), m_store(store), m_repository(repository)
 {
+    // Reuse the existing persistent domain queue after reconnect/resume.
+    if (auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
+        connect(app, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
+            if (state == Qt::ApplicationActive) synchronize();
+        });
+    QNetworkInformation::loadDefaultBackend();
+    if (auto *network = QNetworkInformation::instance())
+        connect(network, &QNetworkInformation::reachabilityChanged, this, [this](QNetworkInformation::Reachability state) {
+            if (state == QNetworkInformation::Reachability::Online) synchronize();
+        });
+    connect(m_store, &RenditionLocalStore::accountIdChanged, this, [this] {
+        QTimer::singleShot(0, this, &RenditionSyncController::synchronize);
+    });
+    QTimer::singleShot(0, this, &RenditionSyncController::synchronize);
     connect(m_repository, &RenditionRepository::receivedReset, this, [this]() {
         m_current.clear();
         m_locationRefreshLocalId.clear();
@@ -102,6 +119,7 @@ RenditionSyncController::RenditionSyncController(
         if (!m_busy || m_current.value(QStringLiteral("kind")).toString()
                 != QLatin1String("attachment_reserve"))
             return;
+        m_current.insert(QStringLiteral("confirmedAttachmentId"), attachmentId);
         if (!m_store->updateAttachmentPhase(
             m_current.value(QStringLiteral("aggregateLocalId")).toString(),
             m_current.value(QStringLiteral("expenseLocalId")).toString(),
@@ -118,6 +136,12 @@ RenditionSyncController::RenditionSyncController(
         if (!m_busy || m_current.value(QStringLiteral("kind")).toString()
                 != QLatin1String("attachment_reserve"))
             return;
+        const auto attachmentId = field(remote, QStringLiteral("attachmentId"), QStringLiteral("attachment_id"));
+        if (QUuid(attachmentId).isNull()
+            || attachmentId != m_current.value(QStringLiteral("confirmedAttachmentId")).toString()) {
+            failCurrent(QStringLiteral("INVALID_RESPONSE"), QStringLiteral("El servidor no confirmó la identidad del sustento."));
+            return;
+        }
         if (!m_store->updateAttachmentPhase(
             m_current.value(QStringLiteral("aggregateLocalId")).toString(),
             m_current.value(QStringLiteral("expenseLocalId")).toString(),
diff --git a/src/documents/storageprovider.h b/src/documents/storageprovider.h
index 2e42136..60ba53f 100644
--- a/src/documents/storageprovider.h
+++ b/src/documents/storageprovider.h
@@ -2,6 +2,9 @@
 #include <QObject>
 #include <QNetworkReply>
 #include <QJsonDocument>
+#include <QJsonObject>
+#include <QFile>
+#include <QRegularExpression>
 #include <QVariantList>
 #include <QVariantMap>
 #include <QTimer>
@@ -31,13 +34,61 @@ public:
             const auto failure=reply->error(); reply->deleteLater();
             QJsonParseError parse; const auto doc=QJsonDocument::fromJson(raw,&parse);
             if(failure!=QNetworkReply::NoError || status<200 || status>=300) {
-                done({},status==401?"AUTH_REQUIRED":status==403?"FORBIDDEN":"DRIVE_HTTP_"+QString::number(status),
+                const auto message=doc.object().value("message").toString();
+                const auto code=QRegularExpression("^[A-Z][A-Z0-9_]{2,100}$").match(message).hasMatch()
+                    ? message : "DRIVE_HTTP_"+QString::number(status);
+                done({},status==401?"AUTH_REQUIRED":status==403?"FORBIDDEN":code,
                      status==0 || status==408 || status==429 || status>=500); return;
             }
             if(parse.error!=QJsonParseError::NoError || !doc.isArray()) {done({},"INVALID_RESPONSE",false);return;}
             done(doc.toVariant().toList(),{},false);
         });
     }
+    // Shared immutable binary transport. A duplicate is only permission to
+    // reconcile via the domain finalize RPC, never proof that a file is synced.
+    using UploadCompletion=std::function<void(bool,QString,bool)>;
+    void uploadReserved(const QString &localPath,const QString &bucket,const QString &objectPath,
+                        const QString &mime,UploadCompletion done) {
+        if(!m_api || !m_auth || !m_auth->logged() || m_auth->accessToken().isEmpty()) {
+            done(false,"AUTH_REQUIRED",false); return;
+        }
+        const auto parts=objectPath.split('/');
+        if(bucket!="project-files" || parts.contains("..") || parts.contains(".")
+            || parts.contains("") || objectPath.contains('\\')) {
+            done(false,"INVALID_STORAGE_PATH",false); return;
+        }
+        QFile file(localPath);
+        if(!file.open(QIODevice::ReadOnly) || file.size()<1 || file.size()>50LL*1024*1024) {
+            done(false,"LOCAL_FILE_INVALID",false); return;
+        }
+        QStringList encoded;
+        for(const auto &part:parts) encoded.append(QString::fromLatin1(QUrl::toPercentEncoding(part)));
+        auto request=m_api->makeRequest(QUrl(m_api->projectUrl()+"/storage/v1/object/"+bucket+"/"+encoded.join('/')),
+                                        m_auth->accessToken(),60000);
+        request.setHeader(QNetworkRequest::ContentTypeHeader,mime);
+        request.setRawHeader("x-upsert","false");
+        const auto bytes=file.readAll();
+        if(bytes.size()!=file.size()) {done(false,"LOCAL_READ_FAILED",false);return;}
+        auto *reply=m_api->nam()->post(request,bytes);
+        QTimer::singleShot(65000,reply,[reply]{if(reply->isRunning()) reply->abort();});
+        connect(reply,&QNetworkReply::finished,reply,&QObject::deleteLater);
+        connect(reply,&QNetworkReply::finished,this,[reply,bucket,objectPath,done=std::move(done)] {
+            const int status=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
+            QJsonParseError parse;
+            const auto document=QJsonDocument::fromJson(reply->readAll(),&parse);
+            const auto body=document.object();
+            const bool valid=parse.error==QJsonParseError::NoError && document.isObject();
+            const bool duplicate=valid && (status==400 || status==409)
+                && (body.value("error")=="Duplicate" || body.value("code")=="Duplicate"
+                    || body.value("message")=="The resource already exists");
+            const bool uploaded=valid && reply->error()==QNetworkReply::NoError && status>=200 && status<300
+                && body.value("Key").toString()==bucket+"/"+objectPath;
+            if(uploaded || duplicate) { done(true,{},false); return; }
+            done(false,status==401?"AUTH_REQUIRED":status==403?"FORBIDDEN":
+                 status>=200 && status<300?"INVALID_UPLOAD_RESPONSE":"STORAGE_HTTP_"+QString::number(status),
+                 status==0 || status==408 || status==429 || status>=500);
+        });
+    }
 private:
     SupabaseClient *m_api; AuthSession *m_auth;
 };
diff --git a/tests/renditions/checks.cpp b/tests/renditions/checks.cpp
index 49353c5..ba83ce6 100644
--- a/tests/renditions/checks.cpp
+++ b/tests/renditions/checks.cpp
@@ -7,6 +7,8 @@
 #include <QJsonDocument>
 #include <QDir>
 #include <QUuid>
+#include <QTemporaryDir>
+#include <QFileInfo>
 #include <iostream>
 #include <cstdlib>
 void check(bool value, const char *label) { if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); } }
@@ -37,14 +39,25 @@ int main(int argc, char **argv) {
  check(store.expensesFor(local).first().toMap().value("amount")=="20.00","pull preserves pending edit");
  check(store.expensesFor(local).size()==1,"no duplicate expense");
  check(store.markExpenseSynced(local,child,{{"expense_id",eid},{"row_version",2},{"rendition_row_version",3}}),"edit sync");
- auto attachment=store.addLocalAttachment(local,child,{{"localUri","file:///retained.jpg"},{"fileName","retained.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100},{"supportTypeCode","RECEIPT"}});
+ QTemporaryDir attachmentSources;
+ check(attachmentSources.isValid(),"attachment fixture directory");
+ const auto retainedSource=attachmentSources.filePath("retained.jpg");
+ QFile retainedFile(retainedSource);
+ check(retainedFile.open(QIODevice::WriteOnly) && retainedFile.write(QByteArray(100,'a'))==100,"attachment source fixture"); retainedFile.close();
+ QVariantMap attachmentInput{{"localUri",retainedSource},{"fileName","retained.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100},{"supportTypeCode","RECEIPT"}};
+ auto attachment=store.addLocalAttachment(local,child,attachmentInput);
  check(!attachment.isEmpty(),"persist attachment");
+ check(store.addLocalAttachment(local,child,attachmentInput)==attachment,"same bytes reuse attachment identity");
+ const auto retainedMirror=store.attachmentsFor(local,child).first().toMap().value("localUri").toString();
+ check(retainedMirror!=retainedSource && QFileInfo(retainedMirror).size()==100,"attachment copied to persistent mirror");
+ check(QFile::remove(retainedSource),"discard picker original");
  auto path="renditions/"+rid+"/expenses/"+eid+"/attachments/"+aid;
  check(store.updateAttachmentPhase(local,child,attachment,"UPLOAD",{{"attachment_id",aid},{"bucket","project-files"},{"storage_path",path}}),"reserve mapping");
  check(store.updateAttachmentPhase(local,child,attachment,"NEEDS_RECONCILIATION"),"offline retry state");
  check(!store.pendingOperations().isEmpty(),"retry available");
  check(store.updateAttachmentPhase(local,child,attachment,"READY",{{"attachment_id",aid}}),"finalize");
  RenditionLocalStore reopened(scope);
+ check(QFileInfo(reopened.attachmentsFor(local,child).first().toMap().value("localUri").toString()).size()==100,"mirror survives original deletion and store reopen");
  check(QJsonDocument::fromVariant(reopened.rendition(local)).toJson()==QJsonDocument::fromVariant(store.rendition(local)).toJson(),"disk reopen exact serialized state");
  check(reopened.attachmentsFor(local,child).first().toMap().value("objectPath")==path,"path survives disk");
  check(reopened.rendition(local).value("totalPen").toDouble()==20,"persisted total");
@@ -75,7 +88,11 @@ int main(int argc, char **argv) {
  check(interrupted.expensesFor(local).last().toMap().value("requestId")==originalRequest,"request survives process death");
  check(!interrupted.pendingOperations().isEmpty(),"interrupted create replayable");
  check(interrupted.markExpenseSynced(local,pendingChild,{{"expense_id","55555555-5555-4555-8555-555555555555"},{"expense_row_version",1},{"rendition_row_version",4}}),"actual V02 response adopted");
- auto queuedAttachment=interrupted.addLocalAttachment(local,pendingChild,{{"localUri","file:///pending.jpg"},{"fileName","pending.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100}});
+ const auto pendingSource=attachmentSources.filePath("pending.jpg");
+ QFile pendingFile(pendingSource);
+ check(pendingFile.open(QIODevice::WriteOnly) && pendingFile.write(QByteArray(100,'b'))==100,"pending attachment fixture"); pendingFile.close();
+ auto queuedAttachment=interrupted.addLocalAttachment(local,pendingChild,{{"localUri",pendingSource},{"fileName","pending.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100}});
+ check(!queuedAttachment.isEmpty(),"offline attachment staged");
  const auto queued=interrupted.pendingOperations().last().toMap();
  check(queued.value("expenseRemoteId")=="55555555-5555-4555-8555-555555555555","reserve uses confirmed expense UUID");
  const auto attachmentRequest=queued.value("requestId");
~~~
