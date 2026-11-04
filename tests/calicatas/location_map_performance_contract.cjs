// InGe+ Calicatas location map - performance & single-document contract.
// Static only; user compiles and validates real Android frame timing.
"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const root=path.join(__dirname,"..","..");
const read=(name)=>fs.readFileSync(path.join(root,name),"utf8");
const topo=read("qml/Mobile/pages/CalicatasTopoMap.qml");
const home=read("qml/Mobile/pages/CalicatasHome.qml");
const location=read("qml/Mobile/pages/CalicataUbicacionView.qml");
const editor=read("qml/Mobile/pages/CalicataMapEditor.qml");
const form=read("qml/Mobile/pages/CalicataFormPage.qml");
const workspace=read("qml/Mobile/pages/CalicatasEditorPage.qml");
const gps=read("permissionhelper.cpp");
let count=0;
function ok(description,condition){assert.ok(condition,description);++count;console.log("PASS",description)}
ok("QtLocation engine lifecycle follows active page, not visibility or app pause",
    /readonly property bool running: active && width > 0 && height > 0/.test(topo)
    && /active: map.running && !map._reloading/.test(topo)
    && !/active: map.everActive &&/.test(topo));
ok("Home QtLocation renderer remains behind list but deactivates in an open calicata",
    home.includes('home.editor.homeMode')
    &&home.includes('active: home.visible && !!home.editor && home.editor.homeMode')
    &&home.includes('enabled: active && home.view === "map"')
    &&home.includes('scale: 1 // QtLocation GPU surface'));
ok("gesture camera is pulled one-way, no center/zoom writeback loop",
    !topo.includes("onCenterLatChanged: _pushCamera()")
    &&!topo.includes("onCenterLonChanged: _pushCamera()")
    &&!topo.includes("onZoomChanged: _pushCamera()")
    &&topo.includes("onZoomLevelChanged: map._pullCamera()"));
ok("explicit camera setter and no frame-by-frame zoom tween",
    topo.includes('CAMERA_SET reason=explicit')
    &&topo.includes('zoomAround(clampZoom(target),anchor.x,anchor.y)')
    &&!topo.includes('NumberAnimation { id: zoomAnim'));
ok("native map's copyright remains independently attributed and texture cache preserved",
    topo.includes("copyrightsVisible: false")
    &&topo.includes('osm.mapping.cache.disk.size')
    &&topo.includes('osm.mapping.cache.texture.size'));
ok("preview card stable during editing and no onPointChanged perpetual recenter",
    location.includes("onHasPointChanged:")
    &&location.includes("initializeCamera(docKey)")
    &&!location.includes("onPointChanged: _placeCamera()")
    &&location.includes("view.form.stageIndex === 1")
    &&location.includes("ubicacionMapOpen"));
ok("fullscreen reparent deferred to Hero completion; no GPU-resize every frame",
    editor.includes("if (t >= 0.999 && open")
    &&editor.includes("_adoptMap()")
    &&editor.includes("onFinished: if (editor.t < 0.001) {")
    &&!editor.includes('clip: t < 0.999')
    &&editor.includes("clip: false"));
ok("one fullscreen map, ONE real Dock override, without per-frame shape",
    editor.includes("flow.dockOverride = entry")
    &&editor.includes('command: "map.coordinates", tapCommand: true')
    &&!editor.includes("ShaderEffectSource")
    &&!editor.includes("layer.enabled")
    &&!editor.includes("ShapePath.DashLine")
    &&!editor.includes("id: compass")
    &&!editor.includes("id: scaleBar"));
ok("map tools dispatch through the real vertical Dock; lower buttons remain",
    editor.includes('id: "map.gps", command: "map.gps"')
    &&editor.includes('id: "map.coordinates", command: "map.coordinates"')
    &&editor.includes('text: "Fijar ubicación"')
    &&editor.includes('text: "Cancelar"'));
ok("manual coordinate sheet scrolls above keyboard",
    editor.includes("Flickable {")
    &&editor.includes("contentHeight: sheetCol.implicitHeight")
    &&editor.includes("keyboardInset")
    &&editor.includes("Qt.inputMethod.keyboardRectangle"));
ok("all original location fields moved into the full editor",
    editor.includes('id: fieldSide')
    &&editor.includes('id: fieldProgresiva')
    &&editor.includes('id: fieldTramo')
    &&editor.includes('id: fieldZ')
    &&editor.includes('text: editor.form && editor.form.elevationBusy ? "Consultando…" : "Obtener altitud"')
    &&editor.includes('editor.requestAltitudeAtCross()'));
ok("UTM zone includes band and protects against legacy numeric-only zone",
    editor.includes('Rules.utmToGeoForDatum(fieldE.text,fieldN.text,z,datum)')
    &&editor.includes('fieldZone.text=numericZone ? (actual ? z+String(actual.band) : z)')
    &&editor.includes('"18L"')
    &&editor.includes("function changeDatum(nextDatum)")
    &&editor.includes('zoneOk: /^(?:[1-9]|[1-5][0-9]|60)[C-HJ-NP-X]$/i'));
ok("same location document and one commit signal, reject cross-tab writes",
    editor.includes("property string documentId")
    &&editor.includes("signal commitLocation(var draft)")
    &&form.includes("ubicacionMap.documentId !== root._docInstanceId(root.doc)")
    &&form.includes('INGE_CALICATA_MAP_COMMIT_REJECTED'));
ok("no standalone section 2 fields and existing form setter paths preserved",
    !form.slice(form.indexOf("id: mobileLocationSection"),
                form.indexOf("id: mobilePhotosSection")).includes("GenFieldShell")
    &&form.includes("root._setProgresiva(")
    &&form.includes("root._manualCoordinatesChanged()")
    &&form.includes("root._changeDatum(")
    &&form.includes("root.acceptMapPoint("));
ok("road reference is read-only in the closed view",
    location.includes('"Sin referencia vial"')
    &&location.includes('view.openMap("coordinates")')
    &&location.includes('id: mapCard'));
ok("Dock stage navigation deferred until after touch dispatch",
    workspace.includes('Qt.callLater(function() {\n                if (formLoader.item===form && !root.homeMode) form.goNextStage()')
    &&workspace.includes('Qt.callLater(function() {\n                if (formLoader.item===form && !root.homeMode) form.goPreviousStage()'));
ok("native GPS QML publication rate limited but one-shot remains immediate",
    gps.includes("now - m_lastPublishedWallClockMs < 1000")
    &&gps.includes("!m_immediateRequestPending")
    &&gps.includes("rawFixes % 100 == 0")
    &&gps.includes("kMinimumDeadbandMeters"));
ok("same plugin/Map, no new animation engine or cloud schema",
    topo.includes('name: "osm"')&&editor.includes("readonly property var hero:")
    &&form.includes("Elevation.manualHeaderPatch("));

console.log("PASS",count,"source-level contracts; Android 60 FPS/commit/surface lifecycle remain unverified until user build");
