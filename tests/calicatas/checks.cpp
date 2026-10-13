#include "calicatadocument.h"
#include "androidcalicataexporter.h"
#include "calicatasyncpolicy.h"
#include <QDate>
#include <QUuid>
#include <QGuiApplication>
#include <QJSEngine>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QImage>
#include <QDebug>
#include <QStandardPaths>
#include <cmath>
#include "xlsxdocument.h"

int main(int argc, char **argv) {
    qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &message) {
        QFile log("outputs/calicatas-p0/checks-runtime.log");
        if (log.open(QIODevice::WriteOnly | QIODevice::Append)) log.write(message.toUtf8() + '\n');
    });
    QGuiApplication app(argc, argv);
    app.setApplicationName("CalicatasP0Checks");
    QStandardPaths::setTestModeEnabled(true);
    int failures = 0, passes = 0;
    auto check = [&](bool ok, const char *name) {
        if (ok) ++passes; else ++failures;
        qInfo().noquote() << (ok ? "PASS" : "FAIL") << name;
    };
    QFile js("qml/Mobile/lib/CalicataRules.js"); js.open(QIODevice::ReadOnly);
    QString code = QString::fromUtf8(js.readAll()); code.remove(".pragma library");
    QJSEngine engine;
    check(!engine.evaluate(code).isError(), "Rules evaluated in Qt JS engine");
    auto eval = [&](const QString &expression) { return engine.evaluate(expression); };
    for (const char *input : {"0.20", "0,20", ".20", "0.2"})
        check(eval(QString("normalizeDecimalText('%1', DEPTH_METERS, false)").arg(input)).toString() == "0.20", input);
    check(eval("isNaN(parseDecimalSafe('85+745')) && isNaN(parseDecimalSafe('1,2.3'))").toBool(), "strict parser rejects ambiguous input");
    check(eval("normalizeDecimalText('85+745', CHAINAGE_PK, false)").toString() == "85+745", "PK preserved");
    check(eval("normalizeDecimalText('12,5', PERCENTAGE, false)").toString() == "12.50", "lab decimal");
    check(eval("plasticityIndex('30.50','22.25')").toString() == "8.25", "IP numeric");
    check(eval("plasticityIndex('NP','NP')").toString() == "NP", "NP preserved");
    check(eval("boundaryError([{a:'0.20'},{a:'0.85'},{a:'2.00'}],0,'20',2).length > 0").toBool(), "20 m rejected");
    check(eval("boundaryError([{a:'0.20'},{a:'0.85'},{a:'2.00'}],0,'0.20',2) === ''").toBool(), "valid boundary");
    check(eval("boundaryError([{a:'0.20'},{a:'0.85'}],0,'0.90',2).length > 0").toBool(), "neighbor preserved");
    check(eval("sucsCodes.length === 25 && aashtoCodes.length === 12 && patternCodes('CL')[0] === 'CL'").toBool(), "catalogues CL and duals");
    check(eval("compatibleSecondary('OH').length === 0 && compatibleSecondary('CH').length === 0 && compatibleSecondary('MH').length === 0").toBool(), "OH CH MH incompatible duals impossible");
    check(eval("compatibleSecondary('GW').join(',') === 'GM,GC' && compatibleSecondary('CL').join(',') === 'ML'").toBool(), "secondary selectors derive canonical duals");
    check(eval("sucsCodes.every(function(p) { return compatibleSecondary(p).every(function(s) { return canonicalSucs(p + '-' + s).length > 0 }) })").toBool(), "every selectable dual is canonical");
    check(eval("gpsFixValid(-16,-71,8,90000,100000,90000,false,25)").toBool(), "stationary GPS 10 seconds accepted");
    check(!eval("gpsFixValid(-16,-71,26,99000,100000,90000,true,25)").toBool(), "GPS accuracy rejected");
    check(!eval("gpsFixValid(-16,-71,8,69000,100000,90000,false,25)").toBool(), "stale GPS rejected");
    for (const auto &code : eval("sucsCodes").toVariant().toStringList()) {
        for (const auto &part : code.split('-')) {
            const QString suffix = (part == "CH" || part == "OH" || part == "Pt") ? ".svg" : ".png";
            check(QFile::exists(":/SUCS/" + part + suffix), "catalogue pattern resource exists");
        }
    }
    QString id, photo;
    {
        CalicataDocument model;
        check(model.header().value("status") == "BORRADOR", "new document is BORRADOR");
        check(model.header().value("water_table_status") == "NO_EVALUADO", "new groundwater is not evaluated");
        check(!model.selectProject({{"projectId", "C-01"}}), "project display code is not UUID");
        check(model.selectProject({{"projectId", "a42abcde-1234-4321-8765-123456789012"}, {"projectName", "Contract test"}}), "project UUID saved in document");
        const auto stable = model.instanceId();
        auto h = model.header(); h["calicataId"] = "C-01"; h["utm_x"] = "123,50";
        h["water_table_status"] = "ENCONTRADO"; h["water_table_depth"] = "0";
        model.setHeader(h);
        check(model.header().value("calicataId") == stable, "form cannot replace stable UUID");
        check(model.header().value("utm_x") == "123.50", "coordinate comma normalized");
        check(model.header().value("water_table_present").toBool() && model.header().value("water_table_depth") == "0", "water depth zero is found");
        check(!model.transitionStatus("APROBADO"), "draft cannot skip review");
        check(model.transitionStatus("EN_REVISION") && model.transitionStatus("REVISADO")
              && model.transitionStatus("APROBADO") && model.transitionStatus("EXPORTADO"), "controlled review transitions");
        check(model.transitionStatus("ARCHIVADO"), "logical archive saved");
        CalicataDocument restored;
        check(restored.loadDraftById(stable) && restored.header().value("status") == "ARCHIVADO"
              && restored.header().value("calicataId") == stable, "archive retains payload and UUID");
        model.clearDraft();
    }
    const QString userFolder = "InGePlusP0Checks-" + QString::number(QCoreApplication::applicationPid());
    {
        CalicataDocument doc; doc.setProjectsFolderLabel(userFolder); id = doc.instanceId();
        doc.setHeader({{"codigo", "P0-CL"}, {"requested_depth_m", "2.00"}, {"maquina", "Manual"}, {"custom", "keep"}});
        auto header=doc.header(); header.insert("calicata","divergent"); header.insert("pk","85+745"); header.insert("progresiva","different"); header.insert("fecha_inicio","00/00/0000");
        doc.setHeader(header);
        check(doc.header().value("calicata")=="P0-CL" && doc.header().value("progresiva")=="85+745", "canonical aliases cannot diverge");
        check(doc.header().value("fecha_inicio").toString().isEmpty(), "unset date stays empty");
        doc.setCortes({QVariantMap{{"id", "stable-1"}, {"de", "0.00"}, {"a", "0.20"}, {"sucs", "CL"}, {"material_origin", "Relleno antrópico"}, {"aashto", "A-6"}, {"wl", "12.50"}}});
        QImage img(240,160,QImage::Format_RGB32); img.fill(Qt::blue);
        QDir().mkpath("outputs/calicatas-p0"); img.save("outputs/calicatas-p0/photo-test.png");
        for (int i = 1; i <= 3; ++i) {
            QUrl url = doc.persistStampedPhotoToCache(i, QUrl::fromLocalFile(QDir::current().absoluteFilePath("outputs/calicatas-p0/photo-test.png")));
            check(!url.isEmpty() && doc.setPhotoFromCache(i,url), "photo persisted");
            if (i == 1) photo = url.toLocalFile();
        }
        check(doc.saveDraft() && !doc.dirty(), "atomic draft saved and clean");
        doc.prepareForClose();
    }
    check(QFile::exists(photo), "photo survives close and destructor");
    {
        CalicataDocument restored; restored.setProjectsFolderLabel(userFolder);
        check(restored.loadDraftById(id), "restore draft");
        check(restored.header().value("maquina") == "Manual" && restored.header().value("custom") == "keep", "excavation and unknown header restored");
        const auto layer = restored.cortes().first().toMap();
        check(layer.value("sucs") == "CL" && layer.value("material_origin") == "Relleno antrópico" && layer.value("id") == "stable-1", "CL origin stable identity restored");
        for (int i=1;i<=3;++i) check(QFile::exists(restored.cachedPhotoUrl(i).toLocalFile()), "photo restored");
        const auto portable = restored.portableState({});
        check(portable.value("embedded_resources").toMap().size() == 3, "portable state embeds three original photos");
        const auto portablePath = QDir::current().absoluteFilePath("outputs/calicatas-p0/portable.calicata.json");
        QFile portableFile(portablePath);
        check(portableFile.open(QIODevice::WriteOnly), "open portable snapshot");
        portableFile.write(QJsonDocument::fromVariant(portable).toJson()); portableFile.close();
        CalicataDocument recovered;
        check(recovered.load(QUrl::fromLocalFile(portablePath)), "load portable cloud snapshot");
        check(recovered.header() == restored.header() && recovered.cortes() == restored.cortes(), "portable data and unknown fields preserved");
        for (int i=1;i<=3;++i) {
            const QImage actual(recovered.cachedPhotoUrl(i).toLocalFile());
            const QImage expected(restored.cachedPhotoUrl(i).toLocalFile());
            check(!actual.isNull() && actual == expected, "portable photo pixels preserved");
        }
        const auto originalHeader = recovered.header();
        auto corrupt = portable;
        corrupt["embedded_resources"] = QVariantMap{{"foto1_path", "invalid image"}};
        QFile invalidFile(QDir::current().absoluteFilePath("outputs/calicatas-p0/invalid.calicata.json"));
        invalidFile.open(QIODevice::WriteOnly); invalidFile.write(QJsonDocument::fromVariant(corrupt).toJson()); invalidFile.close();
        check(!recovered.load(QUrl::fromLocalFile(invalidFile.fileName())) && recovered.header() == originalHeader,
              "corrupt portable image rejected without replacing document");
    }
    if (argc > 1) {
        QFile fixture(QString::fromLocal8Bit(argv[1])); fixture.open(QIODevice::ReadOnly);
        auto state = QJsonDocument::fromJson(fixture.readAll()).object().toVariantMap();
        AndroidCalicataExporter exporter;
        auto path = exporter.exportStateToXlsx(state, "P0-Golden-output");
        check(!path.isEmpty(), "production QXlsx export");
        qInfo().noquote() << "XLSX_OUTPUT=" << path << exporter.lastError();
        QFile result("outputs/calicatas-p0/export-path.txt"); result.open(QIODevice::WriteOnly);result.write(path.toUtf8());
        auto finRow = [](QXlsx::Document &workbook) {
            for (int row = 82; row <= workbook.dimension().lastRow(); ++row)
                if (workbook.read(row, 17).toString().startsWith("FIN DE LA CALICATA")) return row;
            return 0;
        };
        auto sumHeights = [](QXlsx::Document &workbook, int first, int last) {
            double points = 0;
            for (int row = first; row <= last; ++row) points += workbook.rowHeight(row);
            return points;
        };
        // Production export, not a separately generated simulation. Total depth
        // remains independent from the last described layer and row geometry.
        for (double total : {3.0, 60.0, 1000.0}) {
            auto scaled = state;
            auto header = scaled.value("header").toMap();
            header["requested_depth_m"] = total;
            header["final_depth_m"] = 3.0;
            scaled["header"] = header;
            auto layer = state.value("cortes").toList().value(0).toMap();
            layer["de"] = "0.00"; layer["a"] = "3.00";
            layer["descripcion"] = "Descripción editable de prueba";
            layer["tipo_muestra"] = "MA";
            layer["sucs"] = "CL";
            layer["g2"] = "55%";
            layer.remove("muestra_desde"); layer.remove("muestra_hasta");
            scaled["cortes"] = QVariantList{layer};
            const auto scaledPath = exporter.exportStateToXlsx(scaled, QString("profile-%1m").arg(total));
            check(!scaledPath.isEmpty(), "scaled production export succeeds");
            QXlsx::Document workbook(scaledPath);
            check(workbook.load() && workbook.sheetNames() == QStringList{"Calicata"}, "one original worksheet at every depth");
            const int end = finRow(workbook);
            check(end > 0 && workbook.read(end - 1, 3).toDouble() == total, "axis ends at entered depth");
            bool midpoint = false;
            for (int row = 21; row < end; ++row)
                midpoint |= workbook.read(row, 3).toDouble() == total / 2;
            check(midpoint, "midpoint uses total depth");
            check(workbook.read("AE22").toString() == "0.00-3.00" && workbook.read("BE1").toString().isEmpty(),
                  "native interval and total stay independent without off-page ledger");
            check(workbook.read("J22").toString().contains("Descripción editable de prueba")
                  && workbook.read("AD22").toString() == "MA" && workbook.read("AH22").toString() == "CL",
                  "description, sample and classification are actual form cells");
            check(std::abs(workbook.read("AJ22").toDouble() - .55) < 1e-10,
                  "native laboratory percentage remains a numeric Excel value");
            QXlsx::Document original("Templates/Calicata_Formato.xlsx");
            check(original.load(), "original template available for geometry comparison");
            check(std::abs(sumHeights(workbook, 1, end + 7) - sumHeights(original, 1, 89)) < .02,
                  "subdivided rows preserve total printed height");
            check(std::abs(sumHeights(workbook, 22, end - 1) - sumHeights(original, 22, 81)) < .02,
                  "profile height is unchanged");
            int contactRow = end;
            for (const auto &range : workbook.currentWorksheet()->mergedCells())
                if (range.firstRow() == 22 && range.firstColumn() == 10 && range.lastColumn() == 16)
                    contactRow = range.lastRow() + 1;
            check(std::abs(sumHeights(workbook, 22, contactRow - 1)
                           / sumHeights(workbook, 22, end - 1) - 3 / total) < 1e-5,
                  "native merged description occupies the real proportional stratum height");
            bool blankTail = true;
            for (int row = contactRow; row < end; ++row)
                blankTail &= workbook.read(row, 10).toString().isEmpty() && workbook.read(row, 34).toString().isEmpty();
            check(blankTail, "undescribed tail remains blank without reducing entered depth");
        }
        auto many = state;
        auto manyHeader = many.value("header").toMap();
        manyHeader["requested_depth_m"] = 100.0;
        many["header"] = manyHeader;
        QVariantList layers;
        for (int i = 0; i < 100; ++i)
            layers.append(QVariantMap{{"de", double(i)}, {"a", double(i + 1)},
                {"descripcion", QString("Estrato editable %1").arg(i + 1)}, {"sucs", "CL"}});
        many["cortes"] = layers;
        const auto manyPath = exporter.exportStateToXlsx(many, "native-100-strata");
        check(!manyPath.isEmpty(), "more than sixty strata export without pagination");
        QXlsx::Document manyBook(manyPath);
        int count = 0;
        for (int row = 22; row <= manyBook.dimension().lastRow(); ++row)
            count += manyBook.read(row, 10).toString().contains("Estrato editable ");
        check(count == 100 && manyBook.sheetNames() == QStringList{"Calicata"},
              "every stratum remains editable inside one native worksheet");
        check(std::abs(manyBook.read(finRow(manyBook) - 1, 3).toDouble() - 100) < 1e-10,
              "many-strata axis retains entered depth");
        auto overDepth = state;
        auto limitHeader = overDepth.value("header").toMap();
        limitHeader["requested_depth_m"] = 3.0;
        overDepth["header"] = limitHeader;
        auto escaped = state.value("cortes").toList().value(0).toMap();
        escaped["de"] = "0.00"; escaped["a"] = "3.05";
        overDepth["cortes"] = QVariantList{escaped};
        check(exporter.exportStateToXlsx(overDepth, "invalid-over-depth").isEmpty(),
              "export refuses an interval beyond entered depth");
    }
    {
        // ===== C-AB-01 · ERROR 3: carril de escrituras por ficha (calicatasyncpolicy.h) =====
        using namespace CalicataSync;
        Lane lane;
        // A. autosave A en vuelo + autosaves B y C -> una sola escritura; B/C coalescen.
        check(lane.requestSync("autosave") == Lane::Request::Started, "A: autosave A arranca");
        check(lane.requestSync("autosave") == Lane::Request::Coalesced
              && lane.requestSync("autosave") == Lane::Request::Coalesced, "A: autosaves B/C se coalescen");
        check(lane.busy() && lane.queuedSync() == "autosave" && lane.generation() == 1, "A: una sola escritura en vuelo");
        // B. Guardar con autosave en vuelo -> espera; la sync pendiente pasa a 'save'.
        check(lane.requestSync("save") == Lane::Request::Coalesced && lane.queuedSync() == "save", "B: Guardar espera su turno");
        bool statusRan = false;
        lane.defer([&statusRan] { statusRan = true; });
        auto next = lane.release();
        check(next.syncReason == "save" && !next.operation && !lane.busy(), "B: al terminar sale la sync coalescida primero");
        check(lane.requestSync(next.syncReason) == Lane::Request::Started && lane.generation() == 2, "B: snapshot más reciente en una 2.ª sync");
        next = lane.release();
        check(next.syncReason.isEmpty() && bool(next.operation), "B: luego el cambio de estado en orden");
        if (next.operation) next.operation();
        check(statusRan, "B: el cambio de estado se ejecuta");
        // C. éxito 22 -> 23: la siguiente escritura usa 23 aunque el documento siga en 22.
        check(expectedRevision(22, 23) == 23 && expectedRevision(24, 23) == 24, "C: revisión esperada = max(documento, confirmada)");
        // D. 40001 por escritura propia no verificada -> rebase + reintento único.
        const QVariantMap base{{"code", "C-AB-01"}, {"easting", 661554}, {"title", QString()}};
        QVariantMap server = base; server["title"] = "Ficha"; server["row_version"] = 24;
        const QVariantMap ownLive{{"title", "Ficha"}};
        check(rootMatches(server, base, ownLive), "D: la fila remota coincide con lo propio (base + live)");
        check(classifyStale(23, 24, 1, true, false) == Stale::Rebase, "D: salto explicado por escritura propia -> rebase");
        check(classifyStale(23, 24, 1, true, true) == Stale::RealConflict, "D: nunca un segundo reintento");
        // E. cambio externo real -> conflicto real, sin sobrescribir.
        QVariantMap external = server; external["easting"] = 661600;
        check(!rootMatches(external, base, ownLive), "E: columna cambiada por otro cliente");
        check(classifyStale(23, 24, 1, false, false) == Stale::RealConflict, "E: fila distinta -> conflicto real");
        check(classifyStale(23, 26, 1, true, false) == Stale::RealConflict, "E: más saltos que escrituras propias -> conflicto real");
        check(classifyStale(23, 24, 0, true, false) == Stale::RealConflict, "E: sin escrituras propias pendientes -> conflicto real");
        // Atribución de un cambio live propio (valor ya vigente => +1 del servidor).
        check(attributeLiveWrite(23, 23, 24, true, true) == LiveWrite::OwnNoopBump, "live: +1 propio adoptado");
        check(attributeLiveWrite(23, 23, 23, true, true) == LiveWrite::Unchanged, "live: sin salto");
        check(attributeLiveWrite(23, 24, 25, true, true) == LiveWrite::Unexplained, "live: externo previo nunca se adopta");
        check(attributeLiveWrite(23, 23, 24, true, false) == LiveWrite::Unexplained, "live: otra columna cambió -> no se adopta");
        check(sameValue(QVariant(661554), QVariant("661554.00")) && !sameValue(QVariant("A"), QVariant("B")), "valores PostgREST");
    }
    {
        // ===== C-AB-01 · ERROR 2: fecha de ficha + hora manual / hora fijada por foto =====
        CalicataDocument photoDoc;
        photoDoc.setHeader({{"codigo", "C-AB-01"}, {"fecha_inicio", "2026-03-13"}, {"hora_inicio", "20:06:33"}});
        photoDoc.setImages({{"foto1_capture", QVariantMap{{"captured_at", "2026-10-07T09:42:18"}, {"captured_source", "EXIF"},
                                                          {"system_time", "09:42:18"}, {"system_at", "2026-10-07T09:42:18"}}}});
        auto meta = photoDoc.photoMetadata(1);
        check(meta.value("date").toString() == "13/03/2026" && meta.value("time").toString() == "20:06:33",
              "A: fecha ficha 13/03/26 + hora manual 20:06:33");
        auto h = photoDoc.header(); h["hora_inicio"] = QString(); photoDoc.setHeader(h);
        meta = photoDoc.photoMetadata(1);
        check(meta.value("date").toString() == "13/03/2026" && meta.value("time").toString() == "09:42:18",
              "B: hora vacía -> hora del sistema fijada para la foto (09:42:18)");
        check(photoDoc.photoMetadata(1).value("time").toString() == "09:42:18", "C: regenerar más tarde conserva la hora fijada");
        check(meta.value("date").toString() != QDate::currentDate().toString("dd/MM/yyyy"),
              "D: la fecha del sistema nunca reemplaza la fecha de la ficha");
    }
    {
        // ===== Cross-device (P0-6) / roundtrip (19): fila remota -> ficha -> rótulo de foto =====
        const QString project = QStringLiteral("7fb77795-9986-4b99-8b59-55f1266891d4");
        CalicataDocument deviceB;
        deviceB.setHeader({{"projectId", project}});
        deviceB.applyRemoteSnapshot({{"id", QUuid::createUuid().toString(QUuid::WithoutBraces)}, {"project_id", project},
                                     {"code", "C-AB-01"}, {"progresiva", "00+620"}, {"start_date", "2026-03-13"},
                                     {"start_time", "20:06:33"}, {"altitude_m", 747}, {"altitude_source", "MANUAL"},
                                     {"altitude_mode", "MANUAL"}, {"altitude_vertical_reference", "unknown"}, {"row_version", 2}}, {});
        const auto h = deviceB.header();
        check(h.value("codigo").toString() == "C-AB-01" && h.value("pk").toString() == "00+620",
              "pull: código y progresiva separados");
        check(h.value("fecha_inicio").toString() == "2026-03-13" && h.value("hora_inicio").toString() == "20:06:33",
              "pull: fecha y hora de la ficha");
        check(h.value("utm_z").toString() == "747" && h.value("altitude_mode").toString() == "MANUAL"
              && h.value("altitude_source").toString() == "MANUAL", "pull: Z 747 manual con su origen");
        deviceB.setImages({{"foto1_capture", QVariantMap{{"system_time", "09:14:25"}, {"captured_source", "APP"}}}});
        auto meta = deviceB.photoMetadata(1);
        check(meta.value("date").toString() == "13/03/2026" && meta.value("time").toString() == "20:06:33"
              && meta.value("altitude").toString() == "747", "foto en B: 13/03/26 20:06:33 · 747");
        // B pasa a automática; A (otro pull) recibe valor + origen + confianza.
        CalicataDocument deviceA;
        deviceA.setHeader({{"projectId", project}});
        deviceA.applyRemoteSnapshot({{"id", h.value("remoteCalicataId")}, {"project_id", project}, {"code", "C-AB-01"},
                                     {"altitude_m", 706.4}, {"altitude_source", "DEM"}, {"altitude_mode", "AUTOMATICA"},
                                     {"altitude_confidence", "ALTA"}, {"altitude_vertical_reference", "terrain_msl"},
                                     {"altitude_evidence", QVariantList{QVariantMap{{"id", "copernicus_glo30"}, {"value", 706.4}}}},
                                     {"start_time", QVariant()}, {"row_version", 3}}, {});
        const auto a = deviceA.header();
        check(a.value("utm_z").toDouble() == 706.4 && a.value("altitude_source").toString() == "DEM"
              && a.value("altitude_confidence").toString() == "ALTA" && a.value("altitude_evidence").toList().size() == 1,
              "pull en A: nueva Z automática con origen, confianza y evidencias");
        // Sin hora en la ficha: cada foto usa su hora fijada (no la hora actual).
        deviceA.setImages({{"foto1_capture", QVariantMap{{"system_time", "09:14:25"}}}});
        check(deviceA.photoMetadata(1).value("time").toString() == "09:14:25", "hora vacía => hora fijada de ESA foto");
    }
    qInfo() << "TOTAL" << passes << "PASS" << failures << "FAIL";
    return failures ? 1 : 0;
}
