// Calicatas: todos los controles usan el MISMO material plano (CalicataSurface);
// emergentes con GenPopupSurface/GenScrim (ficha) y CalScrim (espacio de trabajo).
// Sustituye a glass_calicatas_static.cjs: misma cobertura funcional, sin vidrio.
const fs = require("fs"), path = require("path"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const editor = read("qml/Mobile/pages/CalicatasEditorPage.qml");
const photoEditor = read("qml/Mobile/pages/CalicataPhotoEditor.qml");
const overlay = read("qml/Mobile/pages/CalicataOperationOverlay.qml");
const surface = read("qml/Mobile/pages/CalicataSurface.qml");
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };
const compBody = (src, comp) => {
    const at = src.indexOf("component " + comp + ":");
    assert.ok(at >= 0, comp);
    const next = src.indexOf("\n    component ", at + 10);
    return src.slice(at, next < 0 ? undefined : next);
};

check("CalicataSurface: flat material with every state the controls use", () => {
    for (const t of ["ShaderEffect", "MultiEffect", "Behavior", "Animation", "backdrop", "Loader"])
        assert.ok(!surface.includes(t), t);
    for (const prop of ["dark", "accent", "danger", "tone", "level", "pressed", "focused", "error", "selected", "enabledLook"])
        assert.ok(new RegExp("property (bool|color|string) " + prop + "\\b").test(surface), prop);
    assert.ok(surface.includes("opacity: enabledLook ? 1 : 0.48") && surface.includes("border.color: error ? danger"));
});

check("form: shared controls use the flat material (no solid conventional surfaces left)", () => {
    assert.ok(!/^\s*color: root\.(cSurface|cSurfaceAlt|cField|cGenBlueSoft)\s*$/m.test(form));
    for (const comp of ["FieldComboBox", "BoundTextField", "BoundTextArea", "StageButton", "GenRoundIconButton", "GenDialogButton",
                        "GenSearchField", "PrfToolButton", "MobileIconButton", "GenIconBadge", "GenFieldShell", "GenChoiceRow", "PrfCard",
                        "PrfSubsection", "PrfSegment", "PrfChip", "PrfTextArea", "MobileStatusChip", "LabActionPill",
                        "MobileReadOnlyField", "MobilePhotoActionTile", "GenCheckBox"])
        assert.ok(compBody(form, comp).includes("CalicataSurface"), comp);
    const combo = form.slice(form.indexOf("component FieldComboBox:"), form.indexOf("component BoundComboBox:"));
    assert.ok(combo.includes("popup: Popup {") && combo.includes('level: "sheet"') && combo.includes("delegate: ItemDelegate {"));
    assert.ok(!/^\s*CheckBox \{/m.test(form), "checkboxes use the shared indicator");
});

check("form: every popup / dialog / sheet uses the flat surface and dim", () => {
    const genPopup = form.slice(form.indexOf("component GenPopup: Popup {"), form.indexOf("component GenPopupSurface:"));
    assert.ok(genPopup.includes("background: GenPopupSurface {"));
    for (const id of ["aiReviewDialog", "replaceDlg", "coordsConfirm", "resourcesPicker"]) {
        const at = form.indexOf("id: " + id);
        const block = form.slice(at, at + 1400);
        assert.ok(block.includes("background: GenPopupSurface { popupItem: " + id), id + " surface");
        assert.ok(block.includes("Overlay.modal: GenScrim { popupItem: " + id), id + " dim");
        assert.ok(block.includes("header: GenDialogTitle { text: " + id + ".title }"), id + " header");
    }
    for (const id of ["aiReviewDialog", "resourcesPicker"])
        assert.ok(form.slice(form.indexOf("id: " + id), form.indexOf("id: " + id) + 1400).includes("footer: GenDialogButtonBox"), id + " footer");
    assert.ok(form.slice(form.indexOf("id: tsDlg"), form.indexOf("id: tsDlg") + 600).includes("background: GenPopupSurface { popupItem: tsDlg"));
    const sheet = form.slice(form.indexOf("        id: stratumSheet"), form.indexOf("id: stratumSheetBody"));
    assert.ok(sheet.includes("GenPopupSurface {"));
});

check("workspace: popups, rows, buttons and menus on the same flat material", () => {
    assert.ok(!/component CalPopup: Popup \{[\s\S]{0,600}property bool glass/.test(editor));
    for (const comp of ["CalButton", "CalRow", "WorkspaceMenuButton", "NavFichaMenuButton"])
        assert.ok(compBody(editor, comp).includes("CalicataSurface"), comp);
    assert.ok(/component CalPopup: Popup \{[\s\S]{0,1600}Overlay\.modal: Rectangle \{[\s\S]{0,200}background: Rectangle \{/.test(editor));
});

check("photo editor and operation states share the material (no generic Qt controls)", () => {
    for (const comp of ["EdIconButton", "EdPill", "EdSwitch", "EdSection", "EdLogoChoice", "EdTextField"])
        assert.ok(compBody(photoEditor, comp).includes("CalicataSurface"), comp);
    for (const legacy of ["TabBar", "TabButton", "ComboBox", "RadioButton", "CheckBox", "Switch", "ToolButton", "Slider"])
        assert.ok(!new RegExp("(^|[^A-Za-z.])" + legacy + " \\{").test(photoEditor), legacy);
    assert.ok(overlay.startsWith("pragma ComponentBehavior: Bound"));
    assert.ok(/id: card[\s\S]{0,600}CalicataSurface \{[\s\S]{0,200}level: "sheet"/.test(overlay), "status card");
    assert.ok(/delegate: Button \{[\s\S]{0,700}background: CalicataSurface/.test(overlay), "result actions");
});

console.log(`SURFACE_CALICATAS_STATIC PASS ${passed} checks`);
