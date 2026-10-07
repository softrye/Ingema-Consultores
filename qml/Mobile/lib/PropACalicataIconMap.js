.pragma library
// FASE 5.4 — Cierre UI general refinado con recursos reales
// Fuente: InGePlus_UI_Resources_PropuestaA_Final_FASE4_COMPLETO.zip
// Regla QA: no emojis, no placeholders inventados, no iconos genericos.
// Regla QA 5.4: editable tecnico final queda pendiente para fase posterior.

function rootPath(path) { return "qrc:/ui/ingeplus/propuesta_a/" + path }
function rawIcon(name) { return "qrc:/raw/qml/Mobile/icons/" + name }
function themeName(darkMode) { return darkMode ? "dark" : "light" }
function themeDir(darkMode) { return darkMode ? "02_icons_dark" : "01_icons_light" }
function png3(category, base, darkMode) {
    var t = themeName(darkMode)
    return rootPath(themeDir(darkMode) + "/" + category + "/png_3x/" + base + "_" + t + "@3x.png")
}
function actionAsset(base) { return "qrc:/ui/v2/actions/" + base + ".svg" }
function svg(category, base, darkMode) {
    var t = themeName(darkMode)
    return rootPath(themeDir(darkMode) + "/" + category + "/svg/" + base + "_" + t + ".svg")
}
function icon(name, darkMode) {
    var map = {
        "logo_mtc_icon": ["calicatas", "ic_cal_logo_mtc"],
        "logo_project_icon": ["calicatas", "ic_cal_logo_project"],
        "strata": ["calicatas", "ic_cal_strata"],
        "camera": ["calicatas", "ic_cal_camera"],
        "gallery": ["calicatas", "ic_cal_gallery"],
        "photo_f1": ["calicatas", "ic_cal_photo_f1"],
        "photo_f2": ["calicatas", "ic_cal_photo_f2"],
        "photo_f3": ["calicatas", "ic_cal_photo_f3"],
        "excel": ["calicatas", "ic_cal_export_excel"],
        "pdf": ["calicatas", "ic_cal_export_pdf"],
        "editable": ["calicatas", "ic_cal_editable_file"],
        "coordinates": ["calicatas", "ic_cal_coordinates"],
        "project": ["calicatas", "ic_cal_project"],
        "code": ["calicatas", "ic_cal_code"],
        "date": ["calicatas", "ic_cal_date"],
        "depth": ["calicatas", "ic_cal_depth"]
    }
    var actionMap = {
        "strata": "ic_action_add_stratum",
        "camera": "ic_action_camera",
        "gallery": "ic_action_add_photo",
        "excel": "ic_action_export",
        "pdf": "ic_action_export"
    }
    if (actionMap[name]) return actionAsset(actionMap[name])
    var x = map[name] || map["editable"]
    return png3(x[0], x[1], darkMode)
}
function action(name, darkMode) {
    var map = {
        "save": "ic_action_save_draft",
        "saveDraft": "ic_action_save_draft",
        "export": "ic_action_export",
        "addPhoto": "ic_action_add_photo",
        "addStratum": "ic_action_add_stratum",
        "camera": "ic_action_camera",
        "delete": "ic_action_delete",
        "edit": "ic_action_edit"
    }
    return actionAsset(map[name] || map["saveDraft"])
}
function status(name, darkMode) {
    return png3("status", name === "offline" ? "ic_status_offline" : "ic_status_online", darkMode)
}
function gps(active, darkMode) {
    return png3("map", active ? "ic_map_gps_active" : "ic_map_gps_inactive", darkMode)
}
function logoMtcDefault() { return rawIcon("Logo_MTC.jpeg") }
function logoEmpresaDefault() { return "qrc:/images/INGEMA_LOGO_COMPLETO.png" }
function logoProyectoDefault() { return "qrc:/images/INGEMA_LOGO_COMPLETO.png" }
function logoIngema(darkMode) { return rootPath("00_branding/logo_ingema/" + (darkMode ? "logo_ingema_full_dark.png" : "logo_ingema_full_light.png")) }
function logoIngePlus(darkMode) { return rootPath("00_branding/logo_ingeplus/" + (darkMode ? "logo_ingeplus_full_dark.png" : "logo_ingeplus_full_light.png")) }
function anim(name) { return rootPath("04_animations/feedback/" + name + ".json") }
