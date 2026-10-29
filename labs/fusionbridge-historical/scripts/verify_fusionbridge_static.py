"""Read-only integration checks. These are not an Android build or runtime test."""
from pathlib import Path
import hashlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"
checks = 0


def read(name):
    return (ROOT / name).read_text(encoding="utf-8")


def check(value, message):
    global checks
    if not value:
        raise AssertionError(message)
    checks += 1


def balanced(source, name):
    # Lexical sanity only. Strip comments/strings before checking delimiters.
    tokens = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/', "", source)
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for token in tokens:
        if token in "([{":
            stack.append(token)
        elif token in ")]}":
            if not stack or stack.pop() != pairs[token]:
                raise AssertionError(f"unbalanced {name}")
    check(not stack, f"unclosed delimiter {name}")


manifest = ET.fromstring(read("android/AndroidManifest.xml"))
check(sum(p.get(ANDROID + "name") == "com.google.earth" for p in manifest.findall("queries/package")) == 1,
      "Earth must have one narrow package visibility query")
app = manifest.find("application")
launchers = [a for a in app.findall("activity")
             if any(x.get(ANDROID + "name") == "android.intent.action.MAIN"
                    for x in a.findall("intent-filter/action"))]
check(len(launchers) == 1, "single launcher")
service = next((s for s in app.findall("service")
                if s.get(ANDROID + "name") == "com.ingema.ingeplus.fusionbridge.EarthLifecycleController"), None)
check(service is not None, "projection service packaged")
check(service.get(ANDROID + "foregroundServiceType") == "mediaProjection", "correct FGS type")
check(service.get(ANDROID + "exported") == "false", "internal service")
permissions = {p.get(ANDROID + "name") for p in manifest.findall("uses-permission")}
check({"android.permission.FOREGROUND_SERVICE", "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"}
      <= permissions, "projection service permissions")
check(not {"android.permission.SYSTEM_ALERT_WINDOW", "android.permission.QUERY_ALL_PACKAGES",
           "android.permission.INJECT_EVENTS", "android.permission.CAPTURE_VIDEO_OUTPUT"} & permissions,
      "no privileged capture, input or overlays")

home = read("qml/Mobile/HomeScreen.qml")
activity = read("android/src/com/ingema/ingeplus/InGeQtActivity.java")
cpp = read("src/fusionbridge/FusionBridgeController.cpp")
entry = read("android/src/com/ingema/ingeplus/fusionbridge/FusionBridgeNative.java")
for path in ["qml/Mobile/HomeScreen.qml", "permissionhelper.h", "permissionhelper.cpp",
             "android/src/com/ingema/ingeplus/InGeQtActivity.java"]:
    check(not re.search(r"MapLibre|OpenFreeMap|window\.InGeEarth\.command|Perms\.earthCommand", read(path), re.I),
          f"retired navigation references in {path}")
check(not (ROOT / "android/assets/ingeearth").exists(), "retired assets must not be packaged")
check('onRequestOpenEarth' in home and 'openEarthAt' in home and 'earthReturnPage' in home,
      "Calicatas navigation retained")
check('dockCtx.publishContext("earth", "earth/fusionbridge"' in home, "existing contextual Dock")
check('Perms.openEarthViewer' not in home and 'showEarthViewer' not in cpp, "no Cesium fallback")
cmake = read("CMakeLists.txt")
check('add_subdirectory(src/fusionbridge)' in cmake, "module compiled by main project")
check('target_link_libraries(AppCalicatasMobile PRIVATE InGeFusionBridgeNative)' in cmake, "same executable")
check(cmake.count('/EarthSurfaceHost.qml"') == 1, "one QML packaging entry")
main = read("main_mobile.cpp")
check(main.count('setContextProperty("FusionBridge"') == 1, "single context registration")
check(main.count('FusionBridgeController fusionBridge;') == 1, "single controller")
check('engine.addImageProvider(QStringLiteral("fusionbridge")' in main, "Qt frame provider")
check('nativeFrame(' in entry and '_FusionBridgeNative_nativeFrame(' in cpp, "frame JNI counterpart")
check('nativeClear(' in entry and '_FusionBridgeNative_nativeClear(' in cpp, "clear JNI counterpart")
for method, signature in [("open", "(J)V"), ("close", "()V"), ("requestCaptureProbe", "(J)V"),
                          ("command", "(Ljava/lang/String;)V"), ("snapshotJson", "()Ljava/lang/String;")]:
    check(f'"{method}", "{signature}"' in cpp, f"JNI signature {method}")
    check(re.search(rf"public static \w+ {method}\(", entry) is not None, f"Java entry {method}")
for hook in ["onHostResume", "onHostPause", "onHostDestroyed", "onActivityResult"]:
    check(f"FusionBridgeNative.{hook}(" in activity, f"Activity hook {hook}")
for path in list((ROOT / "src/fusionbridge").glob("*.*")) + list((ROOT / "android/src/com/ingema/ingeplus/fusionbridge").glob("*.java")) + [ROOT / "qml/Mobile/EarthSurfaceHost.qml", ROOT / "qml/Mobile/HomeScreen.qml"]:
    if path.suffix not in [".cpp", ".h", ".java", ".qml"]:
        continue
    balanced(path.read_text(encoding="utf-8"), path.name)

# Untouched files verified against the actual pre-migration Git snapshot.
for path in ["qml/Mobile/Main.qml", "qml/Mobile/GlassSurface.qml", "qml/Mobile/shaders/glass.frag",
             "authsession.cpp", "authsession.h", "supabaseclient.cpp", "supabaseclient.h",
             "qml/Mobile/flowcore/InGeCoreFlow.qml", "src/dock/DockCommandRouter.cpp",
             "src/dock/DockContextController.cpp", "qml/Mobile/pages/CalicatasEditorPage.qml",
             "qml/Mobile/documents/NothingDocumentsRoot.qml"]:
    before = subprocess.run(["git", "show", "a7f0ea7:" + path], cwd=ROOT, capture_output=True, check=True).stdout
    normalize = lambda data: data.replace(b"\r\n", b"\n")
    check(hashlib.sha256(normalize(before)).digest() == hashlib.sha256(normalize((ROOT / path).read_bytes())).digest(),
          f"protected/shared source changed: {path}")
print(f"FusionBridge STATIC CHECK PASS: {checks} assertions (includes lexical delimiters; no build/ADB)")
