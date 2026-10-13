// Static checks: Revisión (datos reales + Liquid Glass) y exportación Excel/PDF/Android.
// Run: node tests/calicatas/review_export_static.cjs
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const zlib = require("zlib");
const assert = require("assert");

const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const review = read("qml/Mobile/pages/CalicataReview.qml");
const editorPage = read("qml/Mobile/pages/CalicatasEditorPage.qml");
const exporter = read("androidcalicataexporter.cpp");
const bridge = read("android/src/com/ingema/ingeplus/NothingFileBridge.java");
const paths = read("android/res/xml/nothing_file_paths.xml");
const qrc = read("resources.qrc");
const rulesSrc = read("qml/Mobile/lib/CalicataRules.js").replace(".pragma library", "");
const R = vm.createContext({});
vm.runInContext(rulesSrc, R);
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };

check("export images are bounded before decode and reused across all Excel sheets", () => {
    const fill = exporter.slice(exporter.indexOf("bool fillOfficialCalicataTemplate("), exporter.indexOf("bool copyOfficialTemplate("));
    const excel = exporter.slice(exporter.indexOf("QString AndroidCalicataExporter::exportStateToXlsx"), exporter.indexOf("QString AndroidCalicataExporter::exportGenericWorkbookToXlsx"));
    assert.ok(!fill.includes("reportImageAt("), "sheet filling must not decode images");
    assert.ok(excel.includes("ReportImages reportImages;") && excel.includes("prepareReportImages(state, resourcesBasePathFromState(state), &reportImages, &fillError)"));
    assert.ok(exporter.includes("reader.setScaledSize(") && exporter.includes("QImageIOHandler::ScaledSize"));
    assert.ok(exporter.includes("kReportImageMaxEdge = 1600") && exporter.includes("kUnscaledImageMaxPixels"));
    assert.ok(exporter.includes("cache.constFind(source)") && exporter.includes("cache.constFind(embeddedKey)"));
    assert.ok(!exporter.includes("QImage::fromData(QByteArray::fromBase64"), "embedded resources use the same bounded reader");
});
check("PDF finalization is atomic and surfaces pagination/write failures", () => {
    const pdf = exporter.slice(exporter.indexOf("QString AndroidCalicataExporter::exportCalicataToPdf"), exporter.indexOf("bool AndroidCalicataExporter::publishCalicataPdf"));
    assert.ok(pdf.includes("QSaveFile output(outPath)") && pdf.includes("QPdfWriter pdf(&output)"));
    assert.ok(pdf.includes("if (!pdf.newPage())") && pdf.includes("const bool painted = p.end()"));
    assert.ok(pdf.includes("!output.commit()") && !pdf.includes("QFile::remove(outPath)"));
    assert.ok(pdf.includes("const int tableWidth = W - 2 * M") && pdf.includes("columns[i].second ="), "all laboratory columns fit inside the page");
    assert.ok(pdf.includes("QTextLayout layout(") && pdf.includes("line.draw(&p,"), "long observations paginate by text line");
    assert.ok(!pdf.includes("an oversized cell is clipped"), "oversized strata cannot silently lose content");
});
check("QXlsx shares encoded image media across repeated sheet anchors", () => {
    const workbook = read("thirdparty/QXlsx/source/xlsxworkbook.cpp");
    const anchor = read("thirdparty/QXlsx/source/xlsxdrawinganchor.cpp");
    assert.ok(workbook.includes("d->imageMediaCache.constFind(image.cacheKey())"));
    assert.ok(workbook.includes("d->mediaFiles.at(media->index())"), "canonical shared media, not duplicate PNG buffers");
    assert.ok(anchor.includes("m_drawing->workbook->imageMedia(img)"));
});
check("dedicated Dock review is disabled while field interpretation keeps the global AI", () => {
    assert.ok(!review.includes("review.aiRequested()") && !review.includes('Accessible.name: "Analizar con InGe AI"'));
    assert.ok(review.includes("review.aiText") && review.includes("review.aiFindings"));
    assert.ok(read("qml/Mobile/Main.qml").includes('dockCommandRouter.dispatchGlobal("inge.core")'), "global AI capability preserved in the action bar");
    assert.ok(!form.includes("function onGlobalCapabilityRequested(capabilityId)"), "ficha cannot consume the dedicated assistant action");
    assert.ok(form.includes("CoreRemote.interpretCalicata(state)"), "field interpretation uses the existing global AI");
    const host = read("main_mobile.cpp");
    assert.ok(host.includes("dockContextController.setIngeCoreAvailable(false)"), "host disables the dedicated review capability");
});
check("offscreen review cards release glass captures and AI animation", () => {
    assert.ok(review.includes("property Flickable viewport: null") && form.includes("viewport: vFlick"));
    assert.ok(review.includes("card.inViewport") && review.includes("review.viewport.contentY"));
    assert.ok(review.includes("visible: cardTokens.shown") && review.includes("revealAnim.stop()"));
    assert.ok(review.includes("running: analysisCard.glassShown && review.aiBusy"));
});

const fixture = () => ({
    header: { projectId: "11111111-1111-4111-8111-111111111111", codigo: "C-1", projectName: "P",
              fecha_inicio: "2026-09-01", fecha_fin: "2026-09-02", length_m: "1.5", width_m: "1.0",
              requested_depth_m: "2.5", final_depth_m: "2.00", water_table_status: "NO_ENCONTRADO",
              zona: "18L", utm_x: "500000", utm_y: "8500000", datum: "WGS84", latitude: "-13", longitude: "-75" },
    cortes: [
        { de: "0", a: "0.6", sucs: "OL", descripcion: "Suelo orgánico negro", excavabilidad: 2, estabilidad: 2 },
        { de: "0.6", a: "1.4", sucs: "SM", wl: "30", lp: "20", descripcion: "Arena limosa húmeda", excavabilidad: 3, estabilidad: 1, tipo_muestra: "MA" },
        { de: "1.4", a: "2.0", sucs: "GW", descripcion: "grava", excavabilidad: 1, estabilidad: 0 }
    ],
    images: { foto1_path: "a.jpg", foto2_path: "b.jpg" }
});

// ---------------------------------------------------------------- Bloque 1: datos reales
check("validator names photo slots exactly as Fotos (Zona de ejecución / Interior / Acopios)", () => {
    const titles = /photoSlotTitles: \[([^\]]+)\]/.exec(form)[1];
    for (const t of ["Zona de ejecución", "Interior de calicata", "Acopios"]) assert.ok(titles.includes(t) && rulesSrc.includes('"' + t + '"'), t);
    assert.ok(!rulesSrc.includes("Material extraído") && !rulesSrc.includes('"Entorno"'));
    const issues = R.validateDocument(fixture());
    assert.ok(issues.some(i => i.section === 7 && i.message === "Falta Acopios."), "missing slot 3 named as Acopios");
});
check("review completeness comes from the validator (no invented weights)", () => {
    const st = fixture();
    const s = R.reviewSummary(st);
    const by = k => s.components.find(c => c.key === k);
    assert.strictEqual(by("photos").percent, 67);
    assert.strictEqual(by("photos").status, "blocker");
    assert.strictEqual(by("lab").percent, 33);              // 1 de 3 estratos con ensayos
    assert.strictEqual(by("lab").gated, false);             // laboratorio informa, no bloquea
    assert.strictEqual(s.pendingCount, 1);
    assert.strictEqual(s.percent, Math.round((100 + 100 + 100 + 67 + 100) / 5));
    st.images.foto3_path = "c.jpg";
    const done = R.reviewSummary(st);
    assert.strictEqual(done.pendingCount, 0);
    assert.strictEqual(done.complete, true);
});
check("review facts are computed from the ficha (profile, volume, duration, excavability)", () => {
    const f = R.reviewFacts(fixture());
    assert.strictEqual(f.finalDepth, 2);
    assert.strictEqual(f.segments.length, 3);
    assert.strictEqual(f.predominantCode, "SM");
    assert.strictEqual(f.volume, 3);                         // 1.5 × 1.0 × 2.0
    assert.strictEqual(f.durationDays, 2);
    assert.strictEqual(f.reachedPercent, 80);                // 2.00 / 2.50
    // Excavabilidad ponderada por espesor: (75·0.6 + 100·0.8 + 50·0.6) / 2.0
    assert.strictEqual(f.excavabilityIndex, Math.round((75 * 0.6 + 100 * 0.8 + 50 * 0.6) / 2.0));
    // Rendimiento real (volumen ÷ días) y avance (profundidad ÷ días).
    assert.strictEqual(f.productivity, 1.5);
    assert.strictEqual(f.advanceRate, 1);
    // Riesgo operativo determinista: estabilidad "Baja" en el estrato 3 -> Alto, con motivo.
    assert.strictEqual(f.operationalRisk, 2);
    assert.ok(f.operationalRiskReasons.some(r => /estabilidad baja en 0\.60 m/.test(r)));
    const safe = fixture(); safe.cortes.forEach(c => { c.estabilidad = 2; });
    assert.strictEqual(R.reviewFacts(safe).operationalRisk, 0);
    safe.header.water_table_status = "NO_EVALUADO";
    assert.strictEqual(R.reviewFacts(safe).operationalRisk, -1, "unknown water -> no claim");
    const partial = fixture(); partial.cortes[2].estabilidad = undefined; partial.cortes[1].estabilidad = 2;
    assert.strictEqual(R.reviewFacts(partial).operationalRisk, -1, "stability not recorded everywhere -> no claim");
    const wet = fixture(); wet.cortes.forEach(c => { c.estabilidad = 3; });
    Object.assign(wet.header, { water_table_status: "ENCONTRADO", water_table_depth: "1.2" });
    assert.strictEqual(R.reviewFacts(wet).operationalRisk, 2);
    assert.strictEqual(f.location.text, "18L · 500000.00 E / 8500000.00 N");
    assert.strictEqual(f.location.datum, "WGS84");
    const empty = R.reviewFacts({ header: {}, cortes: [] });
    assert.ok(isNaN(empty.volume) && isNaN(empty.excavabilityIndex) && isNaN(empty.durationDays), "no data -> no metric");
    assert.ok(isNaN(empty.productivity) && isNaN(empty.advanceRate) && empty.operationalRisk === -1 && empty.location.text === "");
});
check("recommendations only when data supports them; conclusion is factual", () => {
    const st = fixture();
    const recs = R.reviewRecommendations(st).map(r => r.text);
    assert.ok(recs.some(t => /ensayos de laboratorio en 2 estratos/.test(t)));
    assert.ok(recs.some(t => /descripción de campo del estrato 3/.test(t)));
    assert.ok(recs.some(t => /Estabilidad registrada «Baja» en 1 estrato/.test(t)));
    st.header.water_table_status = "NO_EVALUADO";
    assert.ok(R.reviewRecommendations(st).some(r => /nivel freático/.test(r.text) && r.section === 3));
    const text = R.reviewConclusion(R.reviewSummary(fixture()), R.reviewFacts(fixture()));
    assert.ok(text.startsWith("Calicata de 2.00 m con 3 estratos registrados.") && !/IA|probable|recomienda continuar/i.test(text));
    // Datos faltantes -> conclusión limitada; nunca afirma estabilidad/seguridad.
    assert.ok(text.endsWith("Conclusión limitada por datos faltantes: no se emite juicio sobre estabilidad ni seguridad geotécnica."));
    assert.ok(!/es estable|segura|seguro/i.test(text.replace("seguridad geotécnica", "")));
});
check("FormPage refreshes review data from one snapshot on entry and after edits", () => {
    const apply = form.slice(form.indexOf("function _applyReview(state)"), form.indexOf("function sectionPosition("));
    for (const k of ["Rules.reviewSummary(state, issues)", "Rules.reviewFacts(state)", "Rules.reviewRecommendations(state, facts)", "Rules.reviewConclusion(", "root.stratumColorFor("])
        assert.ok(apply.includes(k), k);
    assert.ok(/function reviewForExport\(\)[\s\S]{0,200}_applyReview\(exportState\(\)\)/.test(form));
    assert.ok(/id: reviewRefresh[\s\S]{0,300}root\._applyReview\(root\.exportState\(\)\)/.test(form));
    assert.ok(form.includes('root.requestAssistedReview("interpretation")'), "InGe AI remains reachable from the interpretation field");
    assert.ok(form.includes("onIssueSelected: function(issue) { root.openReviewIssue(issue) }"));
});

// ---------------------------------------------------------------- Bloque 4: diseño de Revisión
check("Revisión: Liquid Glass of the system, one surface per card, static ambient", () => {
    assert.ok(review.includes("FlowCore.LiquidGlassSurface {") && review.includes("readonly property Item glassBackdrop: ambient"));
    assert.strictEqual((review.match(/FlowCore\.LiquidGlassSurface \{/g) || []).length, 1, "one card component, no nested glass");
    assert.ok(review.includes("liveCapture: false"));
    assert.ok(!/Button \{|ComboBox|TabBar|Slider \{/.test(review), "no generic Qt controls");
    assert.ok(!/text: "[✓!›‹⋮]"/.test(review), "no font glyph icons");
});
check("Revisión: sections, real values and actionable pending items", () => {
    for (const t of ["Estado de la calicata", "Elementos pendientes (", "Resumen de la calicata", "Perfil estratigráfico",
                     "Rendimiento de excavación", "Completitud por componente", "Análisis y conclusiones", "Recomendaciones", "Observaciones"])
        assert.ok(review.includes(t), t);
    const shown = review.split("\n").filter(l => /\btext:/.test(l)).join("\n");
    assert.ok(!/"[^"]*\b(85|80|2\.5 h|3\.2 m|Alta|Bajo)\b[^"]*"/.test(shown), "no preview values hardcoded in visible text");
    assert.ok(review.includes("review.summary.percent") && review.includes("review.facts.segments") && review.includes("review.facts.excavabilityIndex"));
    assert.ok(review.includes("review.issueSelected(issue)") && review.includes("review.sectionSelected("));
});
check("Revisión has no export buttons: exports stay in the Dock (unchanged)", () => {
    assert.ok(!/Exportar|exportRequested|ExcelExporter/.test(review), "no export in screen");
    assert.ok(!form.includes("onExportRequested: root.requestExportExcel()"));
    assert.ok(/stage === 5\)\s*\n\s*actions\.push\(\{id: "export", label: "Exportar"/.test(editorPage), "Dock keeps Exportar");
    assert.ok(editorPage.includes('command: "calicatas.exportPdf"'));
});

// ---------------------------------------------------------------- Bloque 2: exportación
check("Android: Abrir = ACTION_VIEW directo (sin chooser); Compartir = ACTION_SEND con chooser", () => {
    assert.ok(!exporter.includes("jboolean(true), jboolean(share));"), "open no longer forces the chooser");
    assert.strictEqual((exporter.match(/jboolean\(share\), jboolean\(share\)\);/g) || []).length, 2);
    assert.ok(bridge.includes("new Intent(share ? Intent.ACTION_SEND : Intent.ACTION_VIEW)") && bridge.includes("if (chooser || share)"));
    assert.ok(bridge.includes('"application/pdf"') && bridge.includes("spreadsheetml.sheet"), "MIME xlsx/pdf");
    assert.ok(paths.includes('<files-path name="inge_drive_mirrors" path="inge-drive/" />'), "export dir served by FileProvider");
    assert.ok(/QStandardPaths::AppDataLocation[\s\S]{0,300}"\/inge-drive\/"/.test(exporter), "export dir under files/inge-drive");
});
// Proportional-depth behavior is exercised by proportional-depth.cjs and
// the production XLSX regression in checks.cpp; paging is no longer the contract.
check("PDF: same resources as the ficha (embedded photos/logos, default logos) and complete header", () => {
    // Fuente única de imágenes (Excel y PDF): embebida, misma resolución que la ficha
    // (carpeta de la ficha + base de recursos), logos por defecto, logo quitado = error.
    assert.ok(!exporter.includes("pdfStateImage") && !exporter.includes("pdfResolve"), "no second PDF-only resolver");
    const img = exporter.slice(exporter.indexOf("ReportImage reportImage(const QVariantMap &state"), exporter.indexOf("bool fillOfficialCalicataTemplate("));
    assert.ok(img.includes('"embedded_resources"') && img.includes(':/images/ICONO_LOGO_MTC.jpeg') && img.includes(':/images/INGEMA_LOGO_COMPLETO.png'));
    assert.ok(img.includes('"logo_proyecto_removed"') && img.includes("Completa los logos del informe o selecciona los predeterminados."));
    assert.ok(img.includes("imagePathFromState(state, key, sourceJsonPathFromState(state), photoIndex)") && img.includes("resolveImageSource(stored, QString(), resourcesBase)"));
    assert.ok(/if \(stored\.isEmpty\(\)\)\s*\n\s*return result;\s*\/\/ hueco vacío/.test(img), "empty photo slot = blank, not an error");
    assert.ok(img.includes("No se encuentra el archivo de %1"), "unreadable registered image is a named error");
    const pdf = exporter.slice(exporter.indexOf("QString AndroidCalicataExporter::exportCalicataToPdf"), exporter.indexOf("bool AndroidCalicataExporter::publishCalicataPdf"));
    assert.ok(pdf.indexOf("prepareReportImages(state, resourcesBase, &reportImages, &imageError)") >= 0 && pdf.indexOf("prepareReportImages(") < pdf.indexOf("QPdfWriter pdf("), "images checked before the file is created");
    assert.ok(/setLastError\(imageError\);\s*\n\s*return \{\};/.test(pdf));
    assert.ok(pdf.includes("const QImage &photo = reportImages[i + 1];") && pdf.includes("drawImage(reportImages[0]"));
    assert.ok(pdf.includes('QStringLiteral("Página %1").arg(pageNumber)') && pdf.includes("drawFooter();\n    const bool painted = p.end();"), "page numbers + running header");
    assert.ok(pdf.includes('waterTable = QStringLiteral("No encontrado")'));
    const fill = exporter.slice(exporter.indexOf("bool fillOfficialCalicataTemplate("), exporter.indexOf("bool copyOfficialTemplate("));
    assert.ok(fill.includes("QImage &image = reportImages[slot]") && !fill.includes("las tres fotografías requeridas"));
    // El usuario ve el motivo real del fallo (Excel y PDF).
    assert.ok(form.includes('var reason = String(ExcelExporter.lastError || "")') && read("qml/Mobile/pages/CalicatasEditorPage.qml").includes("String(ExcelExporter.lastError || \"\") : \"\""));
    assert.ok(pdf.includes("Largo × ancho (m)") && pdf.includes('"datum"') && pdf.includes('{"depth_m", "final_depth_m"}'));
    assert.ok(pdf.includes('QStringLiteral("Zona de ejecución"), QStringLiteral("Interior de calicata"), QStringLiteral("Acopios")'));
});

// ---------------------------------------------------------------- Bloque 3: Liquid Glass optimizado
check("Liquid Glass: bounded cost (≤6 taps, frozen static backdrops, low-cost nested)", () => {
    const pages = ["qml/Mobile/pages/CalicataFormPage.qml", "qml/Mobile/pages/CalicataReview.qml",
                   "qml/Mobile/pages/CalicatasEditorPage.qml", "qml/Mobile/pages/CalicataPointPicker.qml"];
    for (const p of pages) {
        const src = read(p);
        const re = /(?:FlowCore\.)?LiquidGlassSurface \{([\s\S]*?)\n\s*\}/g;
        let m;
        while ((m = re.exec(src))) {
            const taps = /frostTaps:\s*(\d+)/.exec(m[1]);
            assert.ok(taps && Number(taps[1]) <= 6, p + " frostTaps");
            // Captura viva solo justificada; si no, congelada (liveCapture false / ligada a frozen).
            if (!/liveCapture:/.test(m[1]))
                assert.fail(p + " surface without explicit capture mode");
            if (/liveCapture:\s*true/.test(m[1]))
                assert.ok(/Captura viva justificada/.test(m[1]), p + " live capture must be justified");
        }
    }
    // Cada PhotoGlassBar declara congelado o justifica la captura viva.
    for (const bar of form.split("PhotoGlassBar {").slice(1).map(x => x.slice(0, 900))) {
        const head = bar.slice(0, bar.search(/\n\s*(?:RowLayout|ColumnLayout|Item|Text|Repeater|Rectangle) \{/) >>> 0 || 900);
        assert.ok(/frozen:/.test(head) || /Captura viva justificada/.test(head), "PhotoGlassBar capture mode: " + head.slice(0, 80));
    }
    // El material sigue siendo de bajo coste; la captura se renueva al volver de cámara/galería.
    assert.ok(/frozen: false\s*\n\s*lowCost: !photoCard\.info\.has/.test(form));
    assert.ok(form.includes("readonly property bool lowCostGlass: glassBar.lowCost"));
    assert.ok(/surfaceName: "calicata-photo-empty"/.test(form) && /frozen: false\s*\n\s*lowCost: true\s*\n\s*surfaceName: "calicata-photo-empty"/.test(form));
    assert.ok(/readonly property bool shown: glassBar\.visible[^]*?Qt\.application\.state === Qt\.ApplicationActive/.test(form));
});
console.log(`OK ${passed} checks`);
