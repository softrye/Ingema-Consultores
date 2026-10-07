#include "calicataexcelexporter.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QProcess>
#include <QStandardPaths>
#include <QUuid>
#include <QDate>
#include <QDateTime>
#include "xlsxdocument.h"
#include "xlsxcellrange.h"
#include <QDebug>
#include <QCoreApplication>
#include <QEventLoop>
#include <QJsonObject>
#include <QJsonArray>
#include <QStringList>
#include <QtMath>


namespace {
constexpr int kBaseRow = 22;
constexpr int kRowsPerMeter = 20;
constexpr int kMaxDataRow = 81;

const QString kObsCell    = QStringLiteral("AH84");
const QString kPhoto1Addr = QStringLiteral("Calicata|AU21:BC41");
const QString kPhoto2Addr = QStringLiteral("Calicata|AU43:BC61");
const QString kPhoto3Addr = QStringLiteral("Calicata|AU63:BC82");
}


// ------------------------------------------------------------
// Helpers generales
// ------------------------------------------------------------
static QString jsonValueToString(const QJsonValue& v);
static QString readWidgetValueText(const QJsonObject& root, const QString& objectName);

static QString comboText(const QJsonObject& comboBoxes, const QString& key)
{
    const QJsonValue v = comboBoxes.value(key);
    if (v.isObject()) return v.toObject().value("text").toString();
    return v.toString();
}

static QString lineText(const QJsonObject& lineEdits, const QString& key)
{
    const QJsonValue v = lineEdits.value(key);
    if (v.isObject()) return v.toObject().value("text").toString();
    return v.toString();
}

static double toDoubleSmart(QString s)
{
    s = s.trimmed();
    s.replace(',', '.');
    bool ok = false;
    const double d = s.toDouble(&ok);
    return ok ? d : 0.0;
}


static QStringList parseSucsCodes2(QString sucsRaw)
{
    QString s = sucsRaw.trimmed().toUpper();
    s.remove(' ');

    // Caso común: "GC-GM" o "GC/GM"
    QStringList parts = s.split(QRegularExpression("[-/]"), Qt::SkipEmptyParts);

    QStringList out;
    for (QString p : parts) {
        p = p.trimmed().toUpper();
        if (p.isEmpty()) continue;

        // SUCS típico: 1-2 letras (a veces 3 si alguien escribe raro)
        if (QRegularExpression("^[A-Z]{1,3}$").match(p).hasMatch()) {
            out << p;
            if (out.size() >= 2) break;
        }
    }

    // Fallback: si viene raro (ej "GCGM"), extrae tokens
    if (out.isEmpty()) {
        QRegularExpression re("[A-Z]{1,2}");
        auto it = re.globalMatch(s);
        while (it.hasNext() && out.size() < 2) {
            out << it.next().captured(0);
        }
    }

    return out;
}



static void addCortesLayoutAndValues(const QJsonObject& calicataRoot,
                                     const QString& sheetName,
                                     QJsonObject& outCells,
                                     QJsonObject& outMerges)
{
    const QJsonArray cortes = calicataRoot.value("cortes").toArray();
    if (cortes.isEmpty()) return;

    const int baseRow = kBaseRow;
    const int rowsPerMeter = kRowsPerMeter;

    auto depthToRow = [&](double m) -> int {
        return baseRow + qRound(m * rowsPerMeter);
    };

    // Columnas a mergear verticalmente por corte (además de la descripción J:P)
    const QStringList mergeCols = {
        "AD","AE","AF","AG","AH","AI","AJ","AK","AL","AM","AN","AO","AP"
    };

    for (int i = 0; i < cortes.size(); ++i) {
        const QJsonObject corte = cortes.at(i).toObject();
        const QJsonObject comboBoxes = corte.value("combo_boxes").toObject();
        const QJsonObject lineEdits  = corte.value("line_edits").toObject();
        const QJsonObject textEdits  = corte.value("text_edits").toObject();

        const double de = toDoubleSmart(comboText(comboBoxes, "txtDE"));
        const double a  = toDoubleSmart(comboText(comboBoxes, "txtA"));
        if (a <= de) continue;

        int r1 = depthToRow(de);
        int r2 = depthToRow(a) - 1;

        if (r1 < kBaseRow)   r1 = kBaseRow;
        if (r2 > kMaxDataRow) r2 = kMaxDataRow;
        if (r2 < r1) continue;

        // --- MERGE descripción (modo "desc") ---
        const QString descRange = QString("J%1:P%2").arg(r1).arg(r2);
        outMerges.insert(QString("%1|%2").arg(sheetName, descRange), "desc");

        // --- MERGE columnas de datos (modo "center") ---
        for (const QString& col : mergeCols) {
            const QString rng = QString("%1%2:%1%3").arg(col).arg(r1).arg(r2);
            outMerges.insert(QString("%1|%2").arg(sheetName, rng), "center");
        }

        // =========================================================
        // ✅ NUEVO: MERGE PERFIL SUCS (E:I o E:G + H:I)
        // =========================================================
        const QString sucsRaw = lineText(lineEdits, "txtSUCS");
        const QStringList sucsCodes = parseSucsCodes2(sucsRaw);

        if (sucsCodes.size() >= 2) {
            // SUCS compuesto -> 2 bloques
            const QString leftRng  = QString("E%1:G%2").arg(r1).arg(r2);
            const QString rightRng = QString("H%1:I%2").arg(r1).arg(r2);

            outMerges.insert(QString("%1|%2").arg(sheetName, leftRng),  "center");
            outMerges.insert(QString("%1|%2").arg(sheetName, rightRng), "center");
        } else {
            // SUCS simple (o vacío) -> 1 bloque completo
            const QString fullRng = QString("E%1:I%2").arg(r1).arg(r2);
            outMerges.insert(QString("%1|%2").arg(sheetName, fullRng), "center");
        }

        // --- CELDAS ---
        // Descripción
        const QString desc = textEdits.value("txtDescripcion").toString();
        if (!desc.trimmed().isEmpty()) {
            outCells.insert(QString("%1|J%2").arg(sheetName).arg(r1), desc);
        }

        // Tipo
        const QString tipo = lineText(lineEdits, "txtTipo");
        if (!tipo.trimmed().isEmpty())
            outCells.insert(QString("%1|AD%2").arg(sheetName).arg(r1), tipo);

        // Intervalo DE-A (formato 0.00-0.20)
        const QString intervalo = QString("%1-%2")
                                      .arg(de, 0, 'f', 2)
                                      .arg(a,  0, 'f', 2);
        outCells.insert(QString("%1|AE%2").arg(sheetName).arg(r1), intervalo);

        // AASHTO / SUCS (texto)
        const QString aashto = lineText(lineEdits, "txtAASHTO");
        const QString sucs   = lineText(lineEdits, "txtSUCS");
        if (!aashto.trimmed().isEmpty())
            outCells.insert(QString("%1|AG%2").arg(sheetName).arg(r1), aashto);
        if (!sucs.trimmed().isEmpty())
            outCells.insert(QString("%1|AH%2").arg(sheetName).arg(r1), sucs);

        // Granulometría
        auto putIf = [&](const QString& key, const QString& addr) {
            const QString v = lineText(lineEdits, key);
            if (!v.trimmed().isEmpty())
                outCells.insert(QString("%1|%2%3").arg(sheetName, addr).arg(r1), v);
        };

        putIf("txtGranuloMax",    "AI");
        putIf("txtGranulo2mm",    "AJ");
        putIf("txtGranulo0_4mm",  "AK");
        putIf("txtGranulo0_08mm", "AL");

        // Plasticidad + humedad natural
        putIf("txtWL",      "AN");
        putIf("txtLP",      "AO");
        putIf("txtHumedad", "AP");
    }
}


static QString absFromJsonPath(const QString& p, const QString& jsonAbsPath)
{
    QString t = p.trimmed();
    if (t.isEmpty()) return QString();

    // Normaliza separadores
    t = QDir::cleanPath(QDir::fromNativeSeparators(t));

    // Excel COM no puede leer recursos Qt
    if (t.startsWith(":/")) return QString();

    // Si ya es absoluta, listo
    if (QDir::isAbsolutePath(t))
        return QDir::cleanPath(t);

    // Base inicial: carpeta del JSON
    QString base = QFileInfo(jsonAbsPath).dir().absolutePath();

    // Subir varios niveles buscando el archivo
    for (int i = 0; i < 10; ++i) {
        const QString cand = QDir::cleanPath(QDir(base).absoluteFilePath(t));
        if (QFileInfo::exists(cand))
            return cand;

        const QString parent = QDir(base).absoluteFilePath("..");
        const QString baseClean = QDir::cleanPath(base);
        const QString parentClean = QDir::cleanPath(parent);
        if (parentClean == baseClean) break;
        base = parent;
    }

    // Fallback (para debug)
    return QDir::cleanPath(QDir(QFileInfo(jsonAbsPath).dir().absolutePath()).absoluteFilePath(t));
}


static QJsonObject buildExcelImagesFromCalicataJson(const QJsonObject& root,
                                                    const QString& calicataJsonPath)
{
    const QJsonObject imgs = root.value("images").toObject();

    const QString logoMtcPath  = absFromJsonPath(imgs.value("logo_mtc_path").toString(), calicataJsonPath);
    const QString logoProyPath = absFromJsonPath(imgs.value("logo_proyecto_path").toString(), calicataJsonPath);

    const QString foto1Path = absFromJsonPath(imgs.value("foto1_path").toString(), calicataJsonPath);
    const QString foto2Path = absFromJsonPath(imgs.value("foto2_path").toString(), calicataJsonPath);
    const QString foto3Path = absFromJsonPath(imgs.value("foto3_path").toString(), calicataJsonPath);

    QJsonObject excelImages;

    if (!logoMtcPath.isEmpty())  excelImages.insert("Calicata|B1:O12",   logoMtcPath);
    if (!logoProyPath.isEmpty()) excelImages.insert("Calicata|P1:AF12",  logoProyPath);

    if (!foto1Path.isEmpty()) excelImages.insert(kPhoto1Addr, foto1Path);
    if (!foto2Path.isEmpty()) excelImages.insert(kPhoto2Addr, foto2Path);
    if (!foto3Path.isEmpty()) excelImages.insert(kPhoto3Addr, foto3Path);


    return excelImages;
}

static QString ensureExcelFilePath(QString outPath, const QString& defaultFileName)
{
    QFileInfo fi(outPath);

    // Si te pasan una carpeta (existe y es dir), crea un archivo dentro
    if (fi.exists() && fi.isDir()) {
        outPath = QDir(outPath).filePath(defaultFileName);
        fi = QFileInfo(outPath);
    }

    // Si no tiene extensión, usa la del default (p.ej. .xlsx o .xlsm)
    if (fi.suffix().isEmpty()) {
        const QString defExt = QFileInfo(defaultFileName).suffix();
        if (!defExt.isEmpty())
            outPath += "." + defExt;
        else
            outPath += ".xlsx";
    }

    return outPath;
}

static QString getStr(const QJsonObject& o, const char* key)
{
    return jsonValueToString(o.value(QString::fromUtf8(key)));
}

static QString pickValue(const QJsonObject& root,
                         const QJsonObject& header,
                         const char* headerKey,
                         const char* rootKey,
                         const char* widgetObjectName)
{
    QString s = getStr(header, headerKey);

    if (s.trimmed().isEmpty() && rootKey)
        s = getStr(root, rootKey);

    if (s.trimmed().isEmpty() && widgetObjectName)
        s = readWidgetValueText(root, QString::fromUtf8(widgetObjectName));

    return s;
}

static bool validateJsonFile(const QString& jsonPath, QString* err)
{
    QFile f(jsonPath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No pude abrir JSON:\n" + jsonPath;
        return false;
    }
    const auto doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject()) {
        if (err) *err = "JSON inválido (no es objeto):\n" + jsonPath;
        return false;
    }
    return true;
}

static QString jsonValueToString(const QJsonValue& v)
{
    if (v.isNull() || v.isUndefined())
        return QString();

    if (v.isString())
        return v.toString();

    if (v.isDouble())
        return QString::number(v.toDouble());

    if (v.isBool())
        return v.toBool() ? "true" : "false";

    if (v.isObject()) {
        const QJsonObject o = v.toObject();

        // patrón combos: { index: N, text: "..." }
        if (o.contains("text") && o.value("text").isString())
            return o.value("text").toString();

        // otros patrones posibles
        if (o.contains("value")) {
            const auto vv = o.value("value");
            if (vv.isString()) return vv.toString();
            if (vv.isDouble()) return QString::number(vv.toDouble());
        }
        if (o.contains("currentText") && o.value("currentText").isString())
            return o.value("currentText").toString();

        if (o.contains("date") && o.value("date").isString())
            return o.value("date").toString();

        // fallback: intenta un campo común
        if (o.contains("display") && o.value("display").isString())
            return o.value("display").toString();

        return QString();
    }

    return QString();
}

static QJsonValue findKeyRecursive(const QJsonValue& root, const QString& key, int depthLeft = 8)
{
    if (depthLeft <= 0)
        return QJsonValue();

    if (root.isObject()) {
        const QJsonObject obj = root.toObject();
        if (obj.contains(key))
            return obj.value(key);

        for (auto it = obj.begin(); it != obj.end(); ++it) {
            const QJsonValue found = findKeyRecursive(it.value(), key, depthLeft - 1);
            if (!found.isUndefined() && !found.isNull())
                return found;
        }
    } else if (root.isArray()) {
        const QJsonArray arr = root.toArray();
        for (const QJsonValue& v : arr) {
            const QJsonValue found = findKeyRecursive(v, key, depthLeft - 1);
            if (!found.isUndefined() && !found.isNull())
                return found;
        }
    }

    return QJsonValue();
}

static QJsonValue findInSection(const QJsonObject& root, const QString& sectionName, const QString& key)
{
    const QJsonValue secV = root.value(sectionName);
    if (!secV.isObject())
        return QJsonValue();

    const QJsonObject sec = secV.toObject();
    if (!sec.contains(key))
        return QJsonValue();

    return sec.value(key);
}

static QString readWidgetValueText(const QJsonObject& root, const QString& objectName)
{
    // 1) directo en raíz
    if (root.contains(objectName))
        return jsonValueToString(root.value(objectName));

    // 2) donde realmente lo guardas
    const QJsonObject ui = root.value("ui_state").toObject();

    static const QStringList sections = {
        "line_edits",
        "text_edits",
        "plain_text_edits",
        "combo_boxes",
        "date_edits",
        "double_spin_boxes",
        "spin_boxes",
        "check_boxes"
    };

    // helper: intenta en una "base" (ui_state)
    for (const QString& sec : sections) {
        const QJsonObject secObj = ui.value(sec).toObject();
        if (!secObj.isEmpty() && secObj.contains(objectName))
            return jsonValueToString(secObj.value(objectName));
    }

    // 3) recursiva dentro de ui_state
    {
        const QJsonValue rec = findKeyRecursive(QJsonValue(ui), objectName);
        if (!rec.isUndefined() && !rec.isNull())
            return jsonValueToString(rec);
    }

    // 4) último recurso: recursiva en todo el root
    {
        const QJsonValue rec = findKeyRecursive(QJsonValue(root), objectName);
        if (!rec.isUndefined() && !rec.isNull())
            return jsonValueToString(rec);
    }

    return QString();
}


static QString formatDateForExcel(const QString& raw)
{
    const QString t = raw.trimmed();
    if (t.isEmpty())
        return QString();

    // intenta ISO (yyyy-MM-dd) o ISO datetime
    QDate d = QDate::fromString(t, Qt::ISODate);
    if (!d.isValid()) {
        const QDateTime dt = QDateTime::fromString(t, Qt::ISODate);
        if (dt.isValid())
            d = dt.date();
    }

    // intenta formatos comunes UI
    if (!d.isValid())
        d = QDate::fromString(t, "dd/MM/yyyy");
    if (!d.isValid())
        d = QDate::fromString(t, "d/M/yyyy");

    // si parseó, fuerza dd/MM/yyyy
    if (d.isValid())
        return d.toString("dd/MM/yyyy");

    // si no, deja tal cual
    return t;
}

// ------------------------------------------------------------
// Plantilla
// ------------------------------------------------------------
QString CalicataExcelExporter::templateResourcePath()
{
    // OJO: ajusta si tu .qrc tiene otra ruta
    return QStringLiteral(":/templates/Calicata_Formato.xlsx");
}

static bool copyQrcToFile(const QString& qrcPath, const QString& dstPath)
{
    QDir().mkpath(QFileInfo(dstPath).absolutePath());
    QFile::remove(dstPath);

    QFile in(qrcPath);
    if (!in.open(QIODevice::ReadOnly))
        return false;

    QFile out(dstPath);
    if (!out.open(QIODevice::WriteOnly))
        return false;

    out.write(in.readAll());
    return true;
}

static void exportSucsPngsToDisk(const QString& baseDir)
{
    QDir dir(baseDir);
    dir.mkpath("SUCS");

    // IMPORTANTE: agrega "GM" si lo usas en "GC-GM" (en tu Excel aparece GC-GM)
    const QStringList codes = {
        "CL","GC","GP","GW","MH","ML","OL","SC","SM","SP","SW","GM"
    };

    for (const QString& c : codes) {
        const QString qrc = QString(":/SUCS/%1.png").arg(c);     // <- según tu resources.qrc
        const QString dst = dir.filePath(QString("SUCS/%1.png").arg(c));
        const bool ok = copyQrcToFile(qrc, dst);
        if (!ok) {
            qDebug().noquote() << "SUCS COPY FAIL:" << qrc << "->" << dst;
        }
    }

    qDebug().noquote() << "SUCS exported to:" << dir.filePath("SUCS");
}


bool CalicataExcelExporter::copyTemplateTo(const QString& outExcelPath, QString* outError)
{
    const QString defaultName = QFileInfo(templateResourcePath()).fileName();
    const QString outXlsx = ensureExcelFilePath(outExcelPath, defaultName);

    QDir().mkpath(QFileInfo(outXlsx).absolutePath());

    if (QFile::exists(outXlsx)) {
        if (!QFile::remove(outXlsx)) {
            if (outError) *outError =
                    "El archivo Excel destino ya existe y NO se pudo borrar.\n"
                    "Cierra el archivo si está abierto en Excel o cambia el nombre.\n\n"
                    "Destino:\n" + outXlsx;
            return false;
        }
    }

    QFile tpl(templateResourcePath());
    if (!tpl.exists()) {
        if (outError) *outError =
                "No se encontró la plantilla en recursos:\n" + templateResourcePath();
        return false;
    }

    if (!tpl.copy(outXlsx)) {
        if (outError) *outError =
                "No se pudo copiar la plantilla:\n" + tpl.errorString() +
                "\n\nPlantilla:\n" + templateResourcePath() +
                "\nDestino:\n" + outXlsx;
        return false;
    }

    return true;
}

// ------------------------------------------------------------
// Construir "excel.cells" para header + observaciones
// ------------------------------------------------------------
static QJsonObject buildExcelCellsFromCalicataJson(const QJsonObject& root)
{
    const QJsonObject header = root.value("header").toObject();

    const QString supervisor = pickValue(root, header, "supervisor", "supervisor", "txtSupervisor");
    const QString maquina    = pickValue(root, header, "maquina",    "maquina",    "txtMaquina");
    const QString ladoVia    = pickValue(root, header, "lado_via",   "lado_via",   "comboLadoVia");

    const QString utmX       = pickValue(root, header, "utm_x",      "utm_x",      "txtUTMX");
    const QString utmY       = pickValue(root, header, "utm_y",      "utm_y",      "txtUTMY");
    const QString zona       = pickValue(root, header, "zona",       "zona",       "txtZona");

    // PK y CALICATA: usa header si existe, si no usa progresiva o txtProgresiva
    QString pk       = pickValue(root, header, "pk",      "progresiva", "txtProgresiva");
    QString calicata = pickValue(root, header, "calicata","progresiva", "txtProgresiva");

    // Si tu timestamp tiene calicata y arriba no salió nada:
    if (calicata.trimmed().isEmpty()) {
        const QJsonObject ts = root.value("timestamp").toObject();
        calicata = getStr(ts, "calicata");
    }

    // Fechas (de tu JSON real)
    const QString fIniRaw = pickValue(root, header, "fecha_inicio", "fecha_inicio", "dateEdit");
    const QString fFinRaw = pickValue(root, header, "fecha_fin",    "fecha_fin",    "dateEdit_2");

    const QString fIni = formatDateForExcel(fIniRaw);
    const QString fFin = formatDateForExcel(fFinRaw);

    // ✅ Observaciones: en tu JSON NO es txtObservaciones, es root["observaciones"]
    QString obs = root.value("observaciones").toString();
    if (obs.trimmed().isEmpty())
        obs = readWidgetValueText(root, "txtObservaciones"); // fallback por si un día lo guardas así

    QJsonObject cells;

    // (Tus celdas originales)
    cells.insert("AJ9",  supervisor);
    cells.insert("AJ10", maquina);
    cells.insert("AJ11", ladoVia);

    cells.insert("AT9",  utmX);
    cells.insert("AT10", utmY);

    cells.insert("AW10", zona);
    cells.insert("AY9",  calicata);

    // Si quieres también PK en alguna celda (ajusta la dirección si es otra)
    // Ejemplo: si la celda al lado de "P.K.:" es AU9 o similar:
    // cells.insert("AU9", pk);

    // Si realmente estas celdas corresponden a fecha (si no, bórralas)
    cells.insert("AU8", fIni.isEmpty() ? QString() : QString("Fecha inicio: %1").arg(fIni));
    cells.insert("AU9", fFin.isEmpty() ? QString() : QString("Fecha fin: %1").arg(fFin));

    // Observaciones (OJO: esta celda AH73 puede no ser la correcta)
    cells.insert(kObsCell, obs);
    return cells;
}

static bool writeAugmentedJsonToTemp(const QString& originalJsonPath,
                                     const QJsonObject& originalRoot,
                                     const QJsonObject& excelCells,
                                     const QJsonObject& excelImages,
                                     const QJsonObject& excelMerges,   // NUEVO
                                     QString* outTempJsonPath,
                                     QString* err)
{
    const QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    const QString tempJsonPath =
        QDir(tempDir).filePath(QString("calicata_exceldata_%1.json")
                                   .arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));

    QJsonObject newRoot = originalRoot;

    QJsonObject excelObj = newRoot.value("excel").toObject();
    excelObj.insert("sheetName", "Calicata");

    // ✅ BASE REAL del JSON original (no del TEMP)
    excelObj.insert("baseDir", QFileInfo(originalJsonPath).dir().absolutePath());

    // (Opcional) ayuda a debug
    excelObj.insert("sourceJson", QFileInfo(originalJsonPath).absoluteFilePath());

    // ---- cells ----
    QJsonObject cellsObj = excelObj.value("cells").toObject();
    for (auto it = excelCells.begin(); it != excelCells.end(); ++it) {
        cellsObj.insert(it.key(), it.value());
    }
    excelObj.insert("cells", cellsObj);

    // ---- images ----
    QJsonObject imgsObj = excelObj.value("images").toObject();
    for (auto it = excelImages.begin(); it != excelImages.end(); ++it) {
        imgsObj.insert(it.key(), it.value());
    }
    excelObj.insert("images", imgsObj);

    // ---- merges ----
    QJsonObject mergesObj = excelObj.value("merges").toObject();
    for (auto it = excelMerges.begin(); it != excelMerges.end(); ++it) {
        mergesObj.insert(it.key(), it.value());
    }
    excelObj.insert("merges", mergesObj);

    newRoot.insert("excel", excelObj);

    QFile f(tempJsonPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (err) *err = "No pude crear JSON temporal para exportación:\n" + tempJsonPath;
        return false;
    }

    f.write(QJsonDocument(newRoot).toJson(QJsonDocument::Indented));
    f.flush();
    f.close();

    if (outTempJsonPath)
        *outTempJsonPath = tempJsonPath;

    // ❌ ya NO va:
    // Q_UNUSED(originalJsonPath);

    return true;
}






static bool findCellByText(QXlsx::Document& xlsx,
                           const QString& sheet,
                           const QString& needle,
                           int r1, int c1, int r2, int c2,
                           int& outR, int& outC)
{
    xlsx.selectSheet(sheet);

    for (int r = r1; r <= r2; ++r)
    {
        for (int c = c1; c <= c2; ++c)
        {
            QVariant v = xlsx.read(r, c);
            if (!v.isValid()) continue;

            const QString s = v.toString().trimmed();
            if (s.compare(needle, Qt::CaseInsensitive) == 0)
            {
                outR = r;
                outC = c;
                return true;
            }
        }
    }
    return false;
}

static void writeNextToLabel(QXlsx::Document& xlsx,
                             const QString& sheet,
                             const QString& label,
                             const QVariant& value)
{
    int r = 0, c = 0;
    if (findCellByText(xlsx, sheet, label, 1, 1, 80, 120, r, c))
        xlsx.write(r, c + 1, value);
}

// ----------------------------------------------------

void CalicataExcelExporter::llenarHeaderYObservaciones(QXlsx::Document& xlsx,
                                                       const QString& sheet,
                                                       const QJsonObject& root)
{
    const QJsonObject header = root.value("header").toObject();

    const QString supervisor = header.value("supervisor").toString();
    const QString maquina    = header.value("maquina").toString();
    const QString ladoVia    = header.value("lado_via").toString();
    const QString xutm       = header.value("utm_x").toString();
    const QString yutm       = header.value("utm_y").toString();
    const QString zona       = header.value("zona").toString();
    const QString pk         = header.value("pk").toString();
    const QString calicata   = header.value("calicata").toString();

    // Observaciones: ideal guardarlo como root["observaciones"]
    const QString obs = root.value("observaciones").toString();

    writeNextToLabel(xlsx, sheet, "Supervisor:", supervisor);
    writeNextToLabel(xlsx, sheet, "Máquina:",    maquina);
    writeNextToLabel(xlsx, sheet, "Lado de la Vía:", ladoVia);

    writeNextToLabel(xlsx, sheet, "P.K.:", pk);
    writeNextToLabel(xlsx, sheet, "X UTM:", xutm);
    writeNextToLabel(xlsx, sheet, "Y UTM:", yutm);
    writeNextToLabel(xlsx, sheet, "Zona:",  zona);

    // OJO: en tu plantilla la celda dice "CALICATA" sin ":" (según tu captura)
    // Si en tu Excel el label es "CALICATA" (no "Calicata:"), usa ese:
    writeNextToLabel(xlsx, sheet, "CALICATA", calicata);

    // Observaciones: depende de cómo esté rotulado en tu plantilla.
    // Prueba con "Observaciones:" o "OBSERVACIONES":
    if (!obs.isEmpty())
    {
        int r = 0, c = 0;
        if (findCellByText(xlsx, sheet, "Observaciones:", 1, 1, 200, 200, r, c) ||
            findCellByText(xlsx, sheet, "OBSERVACIONES",   1, 1, 200, 200, r, c))
        {
            // muchas plantillas tienen observaciones en una celda grande debajo o al lado
            xlsx.write(r, c + 1, obs);
        }
    }
}


#ifdef Q_OS_WIN
static QString buildPowerShellScript(QString* err = nullptr)
{
    QFile f(":/scripts/export_excel.ps1"); // prefix=/scripts y alias=export_excel.ps1
    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No pude abrir el script embebido :/scripts/export_excel.ps1";
        return QString();
    }

    const QByteArray bytes = f.readAll();
    const QString script = QString::fromUtf8(bytes);

    if (script.trimmed().isEmpty()) {
        if (err) *err = "El script :/scripts/export_excel.ps1 está vacío (o se leyó vacío).";
        return QString();
    }

    return script;
}

static bool exportViaExcelPowerShell(const QString& outExcel,
                                     const QString& jsonPath,
                                     QString* err)
{
    // ✅ FORZAR Windows PowerShell 5.1 (powershell.exe) para COM con Excel
    QString psExe = QStandardPaths::findExecutable("powershell.exe");

    if (psExe.isEmpty()) {
        const QString sysRoot = qEnvironmentVariable("SystemRoot");
        const QString cand = QDir(sysRoot).filePath("System32/WindowsPowerShell/v1.0/powershell.exe");
        if (QFileInfo::exists(cand))
            psExe = cand;
    }

    if (psExe.isEmpty()) {
        if (err) *err =
                "No encontré powershell.exe (Windows PowerShell 5.1).\n"
                "Para automatizar Excel por COM, usa PowerShell 5.1 (no pwsh).\n";
        return false;
    }

    // --- leer script desde recursos (con error claro) ---
    QString scriptErr;
    const QString psScript = buildPowerShellScript(&scriptErr);
    if (psScript.trimmed().isEmpty()) {
        if (err) *err = "No se pudo obtener el script PowerShell.\n" + scriptErr;
        return false;
    }

    const QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    const QString scriptPath =
        QDir(tempDir).filePath(QString("calicata_export_%1.ps1")
                                   .arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));

    // Crear script temporal
    {
        QFile sf(scriptPath);
        if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            if (err) *err = "No pude crear el script PowerShell temporal:\n" + scriptPath;
            return false;
        }

        const QByteArray outBytes = psScript.toUtf8();
        if (sf.write(outBytes) != outBytes.size()) {
            if (err) *err = "No pude escribir completamente el script temporal:\n" + scriptPath;
            return false;
        }

        sf.flush();
        sf.close();
    }

    QProcess p;

    QStringList args;
    args << "-NoLogo"
         << "-NoProfile"
         << "-NonInteractive"
         << "-ExecutionPolicy" << "Bypass"
         << "-STA"
         << "-File" << QDir::toNativeSeparators(scriptPath)
         << "-xlsx" << QDir::toNativeSeparators(outExcel)
         << "-json" << QDir::toNativeSeparators(jsonPath);

    qDebug().noquote() << "PS:" << psExe << args;

    p.start(psExe, args);

    if (!p.waitForStarted(8000)) {
        if (err) *err = "No pude iniciar PowerShell:\n" + p.errorString();
        return false;
    }

    while (p.state() != QProcess::NotRunning) {
        p.waitForFinished(100);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    }

    const QString stdOut = QString::fromLocal8Bit(p.readAllStandardOutput()).trimmed();
    const QString stdErr = QString::fromLocal8Bit(p.readAllStandardError()).trimmed();

    if (!stdOut.isEmpty()) qDebug().noquote() << "[PS STDOUT]\n" << stdOut;
    if (!stdErr.isEmpty()) qDebug().noquote() << "[PS STDERR]\n" << stdErr;

    const bool ok = (p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0);

    if (ok) QFile::remove(scriptPath);

    if (!ok) {
        if (err) {
            *err = "Falló la automatización de Excel por PowerShell.\n";
            *err += "\nScript:\n" + scriptPath + "\n";
            if (!stdErr.isEmpty()) *err += "\nSTDERR:\n" + stdErr + "\n";
            if (!stdOut.isEmpty()) *err += "\nSTDOUT:\n" + stdOut + "\n";
            *err += "\nCódigo de salida: " + QString::number(p.exitCode());
        }
        return false;
    }

    return true;
}
#endif // Q_OS_WIN






bool CalicataExcelExporter::exportFromCalicataFile(const QString& calicataJsonPath,
                                                   const QString& outExcelPath,
                                                   QString* err)
{
    if (!validateJsonFile(calicataJsonPath, err))
        return false;

    QFile f(calicataJsonPath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No pude abrir JSON:\n" + calicataJsonPath;
        return false;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();

    if (!doc.isObject()) {
        if (err) *err = "JSON inválido (no es objeto):\n" + calicataJsonPath;
        return false;
    }

    const QJsonObject root = doc.object();

    qDebug().noquote() << "ROOT excel_title =" << root.value("excel_title").toString();
    qDebug().noquote() << "HEADER excel_title =" << root.value("header").toObject().value("excel_title").toString();

    // 1) Copiar plantilla
    if (!copyTemplateTo(outExcelPath, err))
        return false;

    const QString defaultName = QFileInfo(templateResourcePath()).fileName();
    const QString outExcel = ensureExcelFilePath(outExcelPath, defaultName);

    // 2) Construir celdas + imágenes
    QJsonObject excelCells = buildExcelCellsFromCalicataJson(root);
    QJsonObject excelMerges; // NUEVO

    // agrega merges + valores (descripción y columnas) según DE/A
    addCortesLayoutAndValues(root, "Calicata", excelCells, excelMerges);

    const QJsonObject excelImages = buildExcelImagesFromCalicataJson(root, calicataJsonPath);

    qDebug().noquote() << "excelMerges =" << QJsonDocument(excelMerges).toJson(QJsonDocument::Indented);


    qDebug().noquote() << "excelCells ="  << QJsonDocument(excelCells).toJson(QJsonDocument::Indented);
    qDebug().noquote() << "excelImages =" << QJsonDocument(excelImages).toJson(QJsonDocument::Indented);


    for (auto it = excelImages.begin(); it != excelImages.end(); ++it) {
        const QString cell = it.key();
        const QString path = it.value().toString();
        qDebug().noquote() << "IMG" << cell << "=>" << path
                           << "exists=" << QFileInfo::exists(path);
    }

    // 3) JSON temporal aumentado
    QString tempJsonPath;
    if (!writeAugmentedJsonToTemp(calicataJsonPath, root, excelCells, excelImages, excelMerges, &tempJsonPath, err))
        return false;

    // ✅ Exportar SUCS del .qrc al MISMO folder del JSON temporal (porque PowerShell busca SUCS al lado del JSON)
    exportSucsPngsToDisk(QFileInfo(calicataJsonPath).dir().absolutePath());

#ifdef Q_OS_WIN
    const bool ok = exportViaExcelPowerShell(outExcel, tempJsonPath, err);
    QFile::remove(tempJsonPath);
    return ok;
#else
    QFile::remove(tempJsonPath);
    if (err) *err =
            "Este exportador (mantener plantilla con objetos/macros/gráficos) requiere Windows + Microsoft Excel.\n"
            "En otros sistemas, tendrías que generar un Excel nuevo sin esos objetos (otra estrategia).";
    return false;
#endif
}

