// Liquid Glass en TODO Calicatas (static only; no build, no device).
// node tests/calicatas/glass_calicatas_static.cjs
const fs = require("fs"), path = require("path"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const editor = read("qml/Mobile/pages/CalicatasEditorPage.qml");
const photoEditor = read("qml/Mobile/pages/CalicataPhotoEditor.qml");
const overlay = read("qml/Mobile/pages/CalicataOperationOverlay.qml");
const skin = read("qml/Mobile/pages/CalicataLiquidGlass.qml");
const skinCode = skin.split("\n").filter(l => !/^\s*\/\//.test(l)).join("\n");   // sin comentarios
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };

check("controls render the REAL Dock material (same surface, shader and tokens); the simulated skin is gone", () => {
    assert.ok(!fs.existsSync(path.join(root, "qml/Mobile/pages/CalicataGlassSkin.qml")), "simulated skin removed");
    for (const f of ["CMakeLists.txt", "resources.qrc", "resources_mobile_raw.qrc", "qml/Mobile/pages/CalicataFormPage.qml",
                     "qml/Mobile/pages/CalicatasEditorPage.qml", "qml/Mobile/pages/CalicataPhotoEditor.qml",
                     "qml/Mobile/pages/CalicataOperationOverlay.qml", "qml/Mobile/pages/CalicataReview.qml"])
        assert.ok(!read(f).includes("CalicataGlassSkin"), f);
    assert.ok(read("CMakeLists.txt").includes('"${MOBILE_QML_DIR}/pages/CalicataLiquidGlass.qml"'));
    assert.ok(read("resources.qrc").includes('<file alias="Mobile/pages/CalicataLiquidGlass.qml">qml/Mobile/pages/CalicataLiquidGlass.qml</file>'));
    assert.ok(read("resources_mobile_raw.qrc").includes('<file alias="qml/Mobile/pages/CalicataLiquidGlass.qml">qml/Mobile/pages/CalicataLiquidGlass.qml</file>'));
    // El material es FlowCore.LiquidGlassSurface (liquidglass.frag), sin shader propio.
    assert.ok(skinCode.includes("FlowCore.LiquidGlassSurface {") && skinCode.includes("tokens: glass.primarySurface ? peekTokens : dockTokens"));
    for (const own of ["ShaderEffect {", "fragmentShader", "MultiEffect", "Timer {", "layer.enabled"])
        assert.ok(!skinCode.includes(own), own);
    // Tokens = los del Dock (mismos valores, leídos del propio Dock).
    const dock = read("qml/Mobile/flowcore/GlobalContextDock.qml");
    for (const token of ["glassTint", "rimLight", "rimShade", "rimSheen", "edgeContrast", "glassSaturation", "shadowColor"]) {
        const dockExpr = new RegExp("readonly property (?:color|real) " + token + ": ([^\\n]+)").exec(dock)[1]
            .replace(/onDarkMaterial/g, "D").trim();
        const mineExpr = new RegExp("readonly property (?:color|real) " + token + ": ([^\\n]+)").exec(skinCode)[1]
            .replace(/glass\.dark/g, "D").trim();
        assert.strictEqual(mineExpr, dockExpr, token);
    }
    // Superficies PRIMARIAS = tokens, preset y velo del peek "Información de la calicata".
    const editorSrc = read("qml/Mobile/pages/CalicatasEditorPage.qml");
    const peekBlock = editorSrc.slice(editorSrc.indexOf("id: peekGlassTokens"), editorSrc.indexOf("contentItem: Item {", editorSrc.indexOf("id: peekGlassTokens")));
    const formSrc = read("qml/Mobile/pages/CalicataFormPage.qml");
    const popupBlock = formSrc.slice(formSrc.indexOf("id: popupGlassTokens"), formSrc.indexOf("FlowCore.LiquidGlassSurface {", formSrc.indexOf("id: popupGlassTokens")));
    const primaryBlock = skinCode.slice(skinCode.indexOf("id: peekTokens"), skinCode.indexOf("// Halo de foco"));
    for (const token of ["glassTint", "rimLight", "rimShade", "rimSheen", "edgeContrast", "glassSaturation", "shadowColor"]) {
        const expr = (src, darkRef) => new RegExp("readonly property (?:color|real) " + token + ": ([^\\n]+)").exec(src)[1].split(darkRef).join("D").trim();
        const peek = expr(peekBlock, "infoPeek.dark");
        assert.strictEqual(expr(primaryBlock, "glass.dark"), peek, "adapter primary " + token);
        assert.strictEqual(expr(popupBlock, "root.darkMode"), peek, "popup " + token);
    }
    assert.ok(skinCode.includes("tokens: glass.primarySurface ? peekTokens : dockTokens"));
    // GRIS (causa raíz): Qt premultiplica los colores de un ShaderEffect y liquidglass.frag
    // vuelve a multiplicar por alpha; un fallbackGlass translúcido se pinta como casi negro.
    // En Calicatas el fallback va OPACO (claro/oscuro) y ninguna superficie conserva el translúcido.
    assert.strictEqual((skinCode.match(/fallbackGlass: glass\.dark \? Qt\.rgba\(0\.14, 0\.16, 0\.20, 1\.0\) : Qt\.rgba\(0\.985, 0\.99, 1\.0, 1\.0\)/g) || []).length, 2);
    for (const f of ["CalicataFormPage", "CalicataReview", "CalicataPointPicker", "CalicataLiquidGlass"])
        assert.ok(!/fallbackGlass:[^\n]*Qt\.rgba\(0\.97, 0\.98, 1\.0, 0\.14\)/.test(read("qml/Mobile/pages/" + f + ".qml")), f + " translucent fallback");
    // Único translúcido restante: el peek de referencia (siempre captura), sin tocar.
    assert.strictEqual((editorSrc.match(/fallbackGlass:[^\n]*Qt\.rgba\(0\.97, 0\.98, 1\.0, 0\.14\)/g) || []).length, 1);
    // Los controles también refractan un fondo real (marcado), no el camino sin captura.
    assert.ok(/readonly property Item effectiveBackdrop: !glass\._captureFits \? null\s*\n\s*: glass\.backdrop \? glass\.backdrop : glass\._resolvedBackdrop/.test(skinCode));
    assert.ok(/component GenGlassScrim: Item \{\n\s*id: glassScrim\n[^\n]*\n\s*objectName: "calicataGlassBackdrop"/.test(formSrc));
    assert.ok(/component CalGlassScrim: Item \{\n\s*id: calScrim\n[^\n]*\n\s*objectName: "calicataGlassBackdrop"/.test(editorSrc));
    assert.ok(skinCode.includes("frost: glass.primarySurface ? 8 : 3") && skinCode.includes("lens: glass.primarySurface ? 0.3 : 0.8"));
    const popupGlass = formSrc.slice(formSrc.indexOf("component GenPopupGlass:"), formSrc.indexOf("component GenGlassScrim:"));
    assert.ok(/lens: 0\.3\s*\n\s*frost: 8\s*\n\s*frostTaps: 6\s*\n\s*magnify: 0\s*\n\s*bevel: root\.dp\(14\)/.test(popupGlass), "peek preset");
    // Refracta la capa YA desenfocada de su scrim; tinte ligero (sin placa blanca).
    assert.ok(popupGlass.includes("popupGlass.popupItem.glassBackdropItem") && popupGlass.includes("glassBackdrop: shown ? popupGlass.activeBackdrop : null"));
    assert.ok(popupGlass.includes("Qt.rgba(0.98, 0.99, 1.0, 0.24)") && !popupGlass.includes("0.86") && !popupGlass.includes("1.0, 0.42)"), "light tint, no white plate");
    // Fondo desenfocado del peek detrás de cada emergente.
    const scrim = formSrc.slice(formSrc.indexOf("component GenGlassScrim:"), formSrc.indexOf("component GenDialogTitle:"));
    assert.ok(scrim.includes("live: false") && scrim.includes("blur: 0.62") && scrim.includes("blurMax: 48") && scrim.includes("saturation: 0.30") && scrim.includes("width * 0.5"));
    // Capa desenfocada OPACA (base de página) registrada en el emergente: es lo que refracta su vidrio.
    assert.ok(scrim.includes("Rectangle { anchors.fill: parent; color: root.cPage }") && scrim.includes("glassScrim.popupItem.glassBackdropItem = scrimBlurLayer"));
    for (const id of ["genPopup", "tsDlg", "aiReviewDialog", "replaceDlg", "coordsConfirm", "resourcesPicker", "photoActionsSheet"])
        assert.ok(formSrc.includes("Overlay.modal: GenGlassScrim { popupItem: " + id + " }"), id);
    for (const id of ["overflowPopup", "sectionsPopup", "exportPopup", "confirmCloseTab", "nameMismatchPopup"])
        assert.ok(editorSrc.includes("Overlay.modal: CalGlassScrim { popupItem: " + id + " }"), id);
    // Capturas recortadas dentro de su fondo (Revisión y Fotos ocupan todo su ambiente).
    const reviewSrc = read("qml/Mobile/pages/CalicataReview.qml");
    assert.ok(reviewSrc.includes("Math.max(m, Math.min(p.x, ambient.width - w - m))") && /id: ambient[\s\S]{0,300}radius: 0/.test(reviewSrc));
    assert.ok(formSrc.includes("captureRect: glassBar.captureRect.width > 0 ? glassBar.captureRect : glassBar._clampedCapture"));
    // COMPOSICIÓN (corrección de negros y texto fantasma):
    // - los controles capturan SOLO fondos marcados (ambientes opacos, capas desenfocadas de los
    //   emergentes): nunca otro vidrio ni la ventana con texto nítido (eso queda para hojas);
    assert.ok(/if \(!found && glass\.level === "sheet"\)/.test(skinCode) && !/glass\.level === "control"[^\n]*windowContent/.test(skinCode));
    // - una primaria dentro de otra primaria no recaptura (pasa a control anidado);
    assert.ok(skinCode.includes('if (k.objectName === "calicataGlassPrimary") nested = true')
              && skinCode.includes('readonly property bool primarySurface: glass.level !== "control" && !glass._nested'));
    // - fondo intencional: ambiente opaco marcado (nunca ancestro); la ventana solo para hojas del Overlay;
    assert.ok(skinCode.includes('k.objectName === "calicataGlassBackdrop"')
              && /if \(!found && glass\.level === "sheet"\) \{[\s\S]{0,200}!glass\._isAncestor\(windowContent\)/.test(skinCode));
    // - el rectángulo de captura se recorta dentro del fondo (fuera de él el shader pinta negro);
    assert.ok(skinCode.includes("Math.max(m, Math.min(p.x, b.width - w - m))") && skinCode.includes("Math.max(m, Math.min(p.y, b.height - h - m))"));
    // - las superficies de vidrio y las capas translúcidas NO son fondos capturables.
    assert.ok(form.includes('component GenPopupGlass: Item {\n        id: popupGlass\n        // Superficie primaria') && form.includes('objectName: "calicataGlassPrimary"'));
    assert.ok(/component PhotoGlassBar: Item \{\n\s*id: glassBar\n[^\n]*\n\s*objectName: "calicataGlassPrimary"/.test(form));
    assert.ok(!overlay.includes('objectName: "calicataGlassBackdrop"'), "translucent dim layer is not a backdrop");
    assert.ok(!/objectName: "calicataGlassBackdrop"[\s\S]{0,120}level: "sheet"/.test(editor), "glass sheets are not backdrops");
    assert.ok(form.split('objectName: "calicataGlassBackdrop"').length - 1 === 4, "page ambient, scrolling ambient, full sheet ambient, popup blurred scrim");
    for (const f of [photoEditor, read("qml/Mobile/pages/CalicataReview.qml")])
        assert.ok(f.includes('objectName: "calicataGlassBackdrop"'), "opaque ambient");
    // Una superficie dominante por etapa; las etapas con tarjetas propias no apilan otra.
    const stage = form.slice(form.indexOf("component MobileStageBody:"), form.indexOf("component StageButton:"));
    assert.ok(stage.includes("property bool glassPanel: true") && /CalicataLiquidGlass \{\s*\n\s*visible: sectionCard\.glassPanel[\s\S]{0,200}level: "card"/.test(stage));
    for (const id of ["mobilePhotosSection", "mobileStrataSection", "mobileLaboratoryOverview"])
        assert.ok(new RegExp("id: " + id + "\\n\\s*glassPanel: false").test(form), id);
    // Icono sobre un control de vidrio: solo capa semántica (sin tercera superficie).
    assert.ok(form.includes("id: genShellBadge\n                onGlassControl: true"));
    // Coste acotado: controles 4 taps sin sombra ni captura; primarias 6 taps con sombra.
    assert.ok(skinCode.includes("frostTaps: glass.primarySurface ? 6 : 4") && skinCode.includes("elevation: glass.primarySurface"));
    for (const state of ["property bool pressed", "property bool focused", "property bool error", "property bool selected", "property bool enabledLook"])
        assert.ok(skin.includes(state), state);
    // No es un segundo sistema: no hay otros componentes de vidrio nuevos.
    for (const forbidden of ["LiquidGlassV2", "GlassSystem2", "PremiumGlass", "CalicatasGlassFramework"])
        assert.ok(!fs.readdirSync(path.join(root, "qml/Mobile/pages")).some(f => f.includes(forbidden)), forbidden);
});

check("form: no solid conventional surfaces left (fields, cards, chips, panels)", () => {
    assert.ok(!/^\s*color: root\.(cSurface|cSurfaceAlt|cField|cGenBlueSoft)\s*$/m.test(form));
    assert.ok(!/background: Rectangle \{[^}\n]*color: root\.cSurface/.test(form), "no white popup/dialog backgrounds");
    // Controles compartidos sobre el material.
    for (const comp of ["FieldComboBox", "BoundTextField", "BoundTextArea", "StageButton", "GenRoundIconButton", "GenDialogButton",
                        "GenSearchField", "PrfToolButton", "MobileIconButton"]) {
        const body = form.slice(form.indexOf("component " + comp + ":"), form.indexOf("component ", form.indexOf("component " + comp + ":") + 10));
        assert.ok(body.includes("CalicataLiquidGlass"), comp);
    }
    for (const comp of ["GenIconBadge", "GenFieldShell", "GenChoiceRow", "PrfCard", "PrfSubsection", "PrfSegment", "PrfChip", "PrfTextArea",
                        "MobileStatusChip", "LabActionPill", "MobileReadOnlyField", "MobilePhotoActionTile", "GenGlassCheckBox"]) {
        const at = form.indexOf("component " + comp + ":");
        assert.ok(at >= 0 && form.slice(at, form.indexOf("\n    component ", at + 10)).includes("CalicataLiquidGlass"), comp);
    }
    // El ComboBox ya no abre el desplegable blanco de Basic.
    const combo = form.slice(form.indexOf("component FieldComboBox:"), form.indexOf("component BoundComboBox:"));
    assert.ok(combo.includes("popup: Popup {") && combo.includes('level: "sheet"') && combo.includes("delegate: ItemDelegate {"));
    assert.ok(!/^\s*CheckBox \{/m.test(form), "checkboxes use the glass indicator");
});

check("form: every popup / dialog / sheet uses Liquid Glass", () => {
    const glassPopup = form.slice(form.indexOf("component GenPopupGlass:"), form.indexOf("component GenGlassScrim:"));
    assert.ok(glassPopup.includes("FlowCore.LiquidGlassSurface {") && glassPopup.includes("liveCapture: true") && glassPopup.includes("Captura viva justificada") && glassPopup.includes("frostTaps: 6"));
    const genPopup = form.slice(form.indexOf("component GenPopup: Popup {"), form.indexOf("component GenPopupGlass:"));
    assert.ok(genPopup.includes("background: GenPopupGlass {"));
    for (const id of ["aiReviewDialog", "replaceDlg", "coordsConfirm", "resourcesPicker"]) {
        const at = form.indexOf("id: " + id);
        const block = form.slice(at, at + 1400);
        assert.ok(block.includes("background: GenPopupGlass { popupItem: " + id), id + " glass");
        assert.ok(block.includes("header: GenDialogTitle { text: " + id + ".title }"), id + " header");
    }
    for (const id of ["aiReviewDialog", "resourcesPicker"])
        assert.ok(form.slice(form.indexOf("id: " + id), form.indexOf("id: " + id) + 1400).includes("footer: GenDialogButtonBox"), id + " footer");
    assert.ok(form.slice(form.indexOf("id: tsDlg"), form.indexOf("id: tsDlg") + 600).includes("background: GenPopupGlass { popupItem: tsDlg"));
    const sheet = form.slice(form.indexOf("        id: stratumSheet"), form.indexOf("id: stratumSheetBody"));
    assert.ok(sheet.includes("GenPopupGlass {") && sheet.includes("PhotoGlassAmbient {"));
    assert.ok(form.includes('PhotoGlassAmbient {\n        objectName: "calicataGlassBackdrop"\n        anchors.fill: parent\n    }'), "page ambient behind the glass");
    // Ambiente que se desplaza con el contenido (hermano, nunca ancestro, de la ficha).
    assert.ok(/id: formGlassAmbient\n\s*objectName: "calicataGlassBackdrop"/.test(form) && form.includes("delegate: PhotoGlassAmbient {") && form.includes("rotation: index % 2 === 1 ? 180 : 0"));
});

check("workspace: popups, rows, buttons and menus on the same material; Dock untouched", () => {
    assert.ok(/component CalPopup: Popup \{[\s\S]{0,600}property bool glass: true/.test(editor));
    for (const comp of ["CalButton", "CalRow", "WorkspaceMenuButton", "NavFichaMenuButton"]) {
        const at = editor.indexOf("component " + comp + ":");
        const next = editor.indexOf("\n    component ", at + 10);
        assert.ok(editor.slice(at, next < 0 ? undefined : next).includes("CalicataLiquidGlass"), comp);
    }
    const dock = read("qml/Mobile/flowcore/GlobalContextDock.qml");
    assert.ok(!dock.includes("CalicataLiquidGlass"), "the Dock is not part of this material change");
});

check("photo editor and operation states share the material (no generic Qt controls)", () => {
    for (const comp of ["EdIconButton", "EdPill", "EdSwitch", "EdSection", "EdLogoChoice", "EdTextField"]) {
        const at = photoEditor.indexOf("component " + comp + ":");
        assert.ok(photoEditor.slice(at, photoEditor.indexOf("\n    component ", at + 10)).includes("CalicataLiquidGlass"), comp);
    }
    for (const legacy of ["TabBar", "TabButton", "ComboBox", "RadioButton", "CheckBox", "Switch", "ToolButton", "Slider"])
        assert.ok(!new RegExp("(^|[^A-Za-z.])" + legacy + " \\{").test(photoEditor), legacy);
    assert.ok(overlay.startsWith("pragma ComponentBehavior: Bound"));
    assert.ok(/id: card[\s\S]{0,600}CalicataLiquidGlass \{[\s\S]{0,200}level: "sheet"/.test(overlay), "status card");
    assert.ok(/delegate: Button \{[\s\S]{0,700}background: CalicataLiquidGlass/.test(overlay), "result actions");
});

console.log(`GLASS_CALICATAS_STATIC PASS ${passed} checks`);
