#include "calicatavalidation.h"
#include "androidcalicataexporter.h"
#include "src/cpp/renditionsnapshotexporter.h"
#include "src/cpp/renditionexportservice.h"
#include "appcontext.h"

#include <QDateTime>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QVariant>
#include <QVariantList>
#include <QColor>
#include <QDebug>
#include <QCoreApplication>
#include <QLocale>
#include <QBuffer>
#include <QUrl>
#include <QImage>
#include <QImageReader>
#include <QImageIOHandler>
#include <QHash>
#include <QPageSize>
#include <QPainter>
#include <QTextLayout>
#include <QPdfWriter>
#include <QSaveFile>
#include <QPointer>
#include <QDesktopServices>
#include <QCryptographicHash>
#include <memory>
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
#include <QUuid>

#ifdef Q_OS_ANDROID
#  include <QJniObject>
#  include <QJniEnvironment>
#endif

#ifdef INGE_HAS_QXLSX
#  include "xlsxdocument.h"
#  include "xlsxformat.h"
#  include "xlsxcell.h"
#  include "xlsxcellformula.h"
#endif

namespace {

constexpr int kExcelDpm96 = 3780; // qRound(96.0 / 0.0254)

QString vstr(const QVariant &v)
{
    if (!v.isValid() || v.isNull())
        return QString();

    const int t = v.typeId();
    if (t == QMetaType::Bool)
        return v.toBool() ? QStringLiteral("Sí") : QStringLiteral("No");

    if (t == QMetaType::QString || t == QMetaType::QByteArray ||
        t == QMetaType::Int || t == QMetaType::UInt || t == QMetaType::LongLong ||
        t == QMetaType::ULongLong || t == QMetaType::Double || t == QMetaType::Float)
        return v.toString();

    if (v.canConvert<QString>() && !v.canConvert<QVariantMap>() && !v.canConvert<QVariantList>())
        return v.toString();

    return QString::fromUtf8(QJsonDocument::fromVariant(v).toJson(QJsonDocument::Compact));
}

QString cleanNumberText(QString s)
{
    s = s.trimmed();
    s.replace(QStringLiteral("%"), QString());
    s.replace(QStringLiteral("m s.n.m."), QString(), Qt::CaseInsensitive);
    s.replace(QStringLiteral("m.s.n.m."), QString(), Qt::CaseInsensitive);
    s.replace(QStringLiteral("±"), QString());
    s.replace(QStringLiteral(","), QStringLiteral("."));
    return s.trimmed();
}

bool isSimpleNumber(const QVariant &v, double *out = nullptr)
{
    if (!v.isValid() || v.isNull())
        return false;

    if (v.typeId() == QMetaType::Double || v.typeId() == QMetaType::Float ||
        v.typeId() == QMetaType::Int || v.typeId() == QMetaType::UInt ||
        v.typeId() == QMetaType::LongLong || v.typeId() == QMetaType::ULongLong) {
        if (out) *out = v.toDouble();
        return true;
    }

    const QString s = cleanNumberText(v.toString());
    if (s.isEmpty())
        return false;
    if (s.contains(QStringLiteral("/")))
        return false;
    if (s.compare(QStringLiteral("NP"), Qt::CaseInsensitive) == 0)
        return false;

    bool ok = false;
    const double d = QLocale::c().toDouble(s, &ok);
    if (ok && out) *out = d;
    return ok;
}

#ifdef INGE_HAS_QXLSX

QXlsx::Format fmtBase()
{
    QXlsx::Format f;
    f.setFontName(QStringLiteral("Arial"));
    f.setFontSize(8);
    f.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    return f;
}

QXlsx::Format fmtTitle()
{
    QXlsx::Format f = fmtBase();
    f.setFontBold(true);
    f.setFontSize(12);
    f.setFontColor(QColor(Qt::white));
    f.setPatternBackgroundColor(QColor(QStringLiteral("#0D47A1")));
    f.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    f.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    return f;
}

QXlsx::Format fmtDark()
{
    QXlsx::Format f = fmtBase();
    f.setFontBold(true);
    f.setFontColor(QColor(Qt::white));
    f.setPatternBackgroundColor(QColor(QStringLiteral("#062A66")));
    f.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    f.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    return f;
}

QXlsx::Format fmtHeader()
{
    QXlsx::Format f = fmtBase();
    f.setFontBold(true);
    f.setPatternBackgroundColor(QColor(QStringLiteral("#D9EAF7")));
    f.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    f.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    return f;
}

QXlsx::Format fmtLabel()
{
    QXlsx::Format f = fmtBase();
    f.setFontBold(true);
    f.setPatternBackgroundColor(QColor(QStringLiteral("#F2F6FC")));
    return f;
}

QXlsx::Format fmtValue()
{
    QXlsx::Format f = fmtBase();
    f.setTextWrap(true);
    return f;
}

QXlsx::Format fmtCentered()
{
    QXlsx::Format f = fmtBase();
    f.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    f.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    return f;
}

QXlsx::Format fmtGray()
{
    QXlsx::Format f = fmtCentered();
    f.setPatternBackgroundColor(QColor(QStringLiteral("#808080")));
    return f;
}

QXlsx::Format fmtSmall()
{
    QXlsx::Format f = fmtBase();
    f.setFontSize(7);
    f.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    return f;
}

void writeMerged(QXlsx::Document &xlsx, const QString &range, const QString &value, const QXlsx::Format &fmt)
{
    xlsx.mergeCells(range, fmt);
    const QString start = range.section(QLatin1Char(':'), 0, 0);
    xlsx.write(start, value, fmt);
}

void writeAny(QXlsx::Document &xlsx, int row, int col, const QVariant &value, const QXlsx::Format &fmt)
{
    double d = 0.0;
    if (isSimpleNumber(value, &d))
        xlsx.write(row, col, d, fmt);
    else
        xlsx.write(row, col, vstr(value), fmt);
}

void setupColumns(QXlsx::Document &xlsx)
{
    for (int c = 1; c <= 53; ++c)
        xlsx.setColumnWidth(c, 4.2);

    xlsx.setColumnWidth(1, 4.0);    // A
    xlsx.setColumnWidth(2, 5.0);    // B
    xlsx.setColumnWidth(3, 6.0);    // C
    xlsx.setColumnWidth(4, 6.0);    // D
    xlsx.setColumnWidth(5, 6.0);    // E
    xlsx.setColumnWidth(6, 7.0);    // F
    xlsx.setColumnWidth(7, 7.0);    // G
    xlsx.setColumnWidth(8, 7.0);    // H
    xlsx.setColumnWidth(9, 7.0);    // I
    xlsx.setColumnWidth(10, 8.0);   // J
    xlsx.setColumnWidth(11, 10.0);  // K
    xlsx.setColumnWidth(12, 16.0);  // L
    xlsx.setColumnWidth(13, 17.0);  // M
    xlsx.setColumnWidth(14, 5.0);   // N

    for (int c = 15; c <= 28; ++c)
        xlsx.setColumnWidth(c, 4.0);

    for (int c = 29; c <= 38; ++c)
        xlsx.setColumnWidth(c, 6.0);

    for (int c = 39; c <= 53; ++c)
        xlsx.setColumnWidth(c, 5.2);

    xlsx.setRowHeight(1, 14);
    xlsx.setRowHeight(2, 20);
    xlsx.setRowHeight(3, 20);
    xlsx.setRowHeight(4, 22);
    xlsx.setRowHeight(5, 22);
    xlsx.setRowHeight(6, 20);
    for (int r = 13; r <= 21; ++r)
        xlsx.setRowHeight(r, 18);
    for (int r = 22; r <= 82; ++r)
        xlsx.setRowHeight(r, 18);
}

QVariantMap headerFromState(const QVariantMap &state)
{
    QVariantMap header = state.value(QStringLiteral("header")).toMap();
    if (header.isEmpty() && state.contains(QStringLiteral("excel")))
        header = state.value(QStringLiteral("excel")).toMap().value(QStringLiteral("header")).toMap();
    return header;
}

QVariantList cortesFromState(const QVariantMap &state)
{
    QVariantList cortes = state.value(QStringLiteral("cortes")).toList();
    if (cortes.isEmpty()) {
        const QVariantMap excel = state.value(QStringLiteral("excel")).toMap();
        cortes = excel.value(QStringLiteral("cortes")).toList();
    }
    return cortes;
}

QString hval(const QVariantMap &h, const QString &key, const QString &fallback = QString())
{
    const QString v = vstr(h.value(key)).trimmed();
    return v.isEmpty() ? fallback : v;
}


#ifdef Q_OS_ANDROID
QByteArray readAndroidUriBytes(const QString &uriString)
{
    QByteArray data;
    if (uriString.isEmpty())
        return data;

    QJniObject context;
    QJniObject activityThread = QJniObject::callStaticObjectMethod(
        "android/app/ActivityThread",
        "currentActivityThread",
        "()Landroid/app/ActivityThread;");

    if (activityThread.isValid()) {
        context = activityThread.callObjectMethod(
            "getApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid()) {
        context = QJniObject::callStaticObjectMethod(
            "android/app/ActivityThread",
            "currentApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid())
        return data;

    QJniObject resolver = context.callObjectMethod("getContentResolver", "()Landroid/content/ContentResolver;");
    if (!resolver.isValid())
        return data;

    QJniObject juriString = QJniObject::fromString(uriString);
    QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri",
        "parse",
        "(Ljava/lang/String;)Landroid/net/Uri;",
        juriString.object<jstring>());

    if (!uri.isValid())
        return data;

    QJniObject in = resolver.callObjectMethod(
        "openInputStream",
        "(Landroid/net/Uri;)Ljava/io/InputStream;",
        uri.object<jobject>());

    if (!in.isValid())
        return data;

    QJniEnvironment env;
    jbyteArray buffer = env->NewByteArray(64 * 1024);
    while (true) {
        jint n = in.callMethod<jint>("read", "([B)I", buffer);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            data.clear();
            break;
        }
        if (n <= 0)
            break;
        QByteArray chunk(n, Qt::Uninitialized);
        env->GetByteArrayRegion(buffer, 0, n, reinterpret_cast<jbyte *>(chunk.data()));
        // A content URI may point to an arbitrarily large file. Keep compressed
        // bytes bounded as well as decoded pixels (report images only).
        if (data.size() + n > 32 * 1024 * 1024) {
            data.clear();
            break;
        }
        data.append(chunk);
    }
    env->DeleteLocalRef(buffer);
    in.callMethod<void>("close", "()V");
    return data;
}
#endif

constexpr int kReportImageMaxEdge = 1600;
constexpr qint64 kUnscaledImageMaxPixels = 8 * 1024 * 1024;
constexpr qint64 kReportImageMaxBytes = 32 * 1024 * 1024;

QImage readReportImage(QImageReader &reader)
{
    reader.setAutoTransform(true);
    const QSize original = reader.size();
    if (original.isEmpty() || qint64(original.width()) * original.height() > 32 * 1024 * 1024)
        return {};
    // JPEG can subsample during decoding. Other handlers must fit the bounded
    // temporary pixel budget; setScaledSize alone can allocate the full image.
    if (qint64(original.width()) * original.height() > kUnscaledImageMaxPixels
        && !reader.supportsOption(QImageIOHandler::ScaledSize))
        return {};
    if (original.width() > kReportImageMaxEdge || original.height() > kReportImageMaxEdge)
        reader.setScaledSize(original.scaled(kReportImageMaxEdge, kReportImageMaxEdge, Qt::KeepAspectRatio));
    QImage image = reader.read();
    if (image.width() > kReportImageMaxEdge || image.height() > kReportImageMaxEdge)
        image = image.scaled(kReportImageMaxEdge, kReportImageMaxEdge, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return image;
}

bool loadImageFromSource(const QString &source, QImage *out)
{
    if (!out)
        return false;

    QString s = source.trimmed();
    if (s.isEmpty() || s.compare(QStringLiteral("Sin foto"), Qt::CaseInsensitive) == 0)
        return false;

    QImage img;

#ifdef Q_OS_ANDROID
    if (s.startsWith(QStringLiteral("content://"), Qt::CaseInsensitive)) {
        const QByteArray bytes = readAndroidUriBytes(s);
        if (!bytes.isEmpty()) {
            QBuffer buffer;
            buffer.setData(bytes);
            if (buffer.open(QIODevice::ReadOnly)) {
                QImageReader reader(&buffer);
                img = readReportImage(reader);
                if (!img.isNull()) {
                    *out = img;
                    return true;
                }
            }
        }
    }
#endif

    QUrl url(s);
    QString path;
    if (url.isValid() && url.isLocalFile())
        path = url.toLocalFile();
    else if (s.startsWith(QStringLiteral("qrc:/"), Qt::CaseInsensitive))
        path = QStringLiteral(":") + url.path();
    else if (s.startsWith(QStringLiteral(":/")))
        path = s;
    else
        path = s;

    if (!path.isEmpty()) {
        if (QFileInfo(path).size() > kReportImageMaxBytes)
            return false;
        QImageReader reader(path);
        img = readReportImage(reader);
        if (!img.isNull()) {
            *out = img;
            return true;
        }
    }

    return false;
}

QImage scaledForExcel(QImage img, int maxW = 480, int maxH = 360)
{
    if (img.isNull())
        return img;
    if (img.width() > maxW || img.height() > maxH)
        img = img.scaled(maxW, maxH, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    img.setDotsPerMeterX(kExcelDpm96);
    img.setDotsPerMeterY(kExcelDpm96);
    return img;
}

bool insertImageAtExcelCell(QXlsx::Document &xlsx, int row, int col, QImage image)
{
    if (row < 1 || col < 1 || image.isNull())
        return false;

    image.setDotsPerMeterX(kExcelDpm96);
    image.setDotsPerMeterY(kExcelDpm96);
    return xlsx.insertImage(row - 1, col - 1, image) >= 0;
}

void writePhotoBox(QXlsx::Document &xlsx,
                   const QString &range,
                   int imageRow,
                   int imageCol,
                   const QString &title,
                   const QString &source)
{
    QXlsx::Format h = fmtHeader();
    QXlsx::Format value = fmtValue();

    QImage img;
    if (loadImageFromSource(source, &img)) {
        writeMerged(xlsx, range, title, h);
        insertImageAtExcelCell(xlsx, imageRow, imageCol, scaledForExcel(img));
    } else {
        writeMerged(xlsx, range, title + QStringLiteral("\nSin imagen adjunta"), value);
    }
}


void writeHeaderBlock(QXlsx::Document &xlsx, const QVariantMap &header)
{
    QXlsx::Format title = fmtTitle();
    QXlsx::Format dark = fmtDark();
    QXlsx::Format label = fmtLabel();
    QXlsx::Format val = fmtValue();
    QXlsx::Format center = fmtCentered();

    writeMerged(xlsx, QStringLiteral("A1:AF3"), QStringLiteral("INGEMA CONSULTORES"), dark);
    writeMerged(xlsx, QStringLiteral("AG1:BA2"), QStringLiteral("TESTIFICACIÓN DE CALICATA"), title);

    const QString logoLine = QStringLiteral("MTC: ") + hval(header, QStringLiteral("logo_mtc_nombre"), QStringLiteral("MTC"))
        + QStringLiteral("\nProyecto: ") + hval(header, QStringLiteral("logo_proyecto_nombre"), QStringLiteral("Proyecto"));
    writeMerged(xlsx, QStringLiteral("A4:AF6"), logoLine, center);
    writeMerged(xlsx, QStringLiteral("AG4:BA6"), hval(header, QStringLiteral("proyecto"), QStringLiteral("Proyecto")), center);

    xlsx.write(QStringLiteral("AH8"), QStringLiteral("Supervisor:"), label);
    xlsx.write(QStringLiteral("AJ8"), hval(header, QStringLiteral("supervisor"), QStringLiteral("XXX")), val);
    xlsx.write(QStringLiteral("AH9"), QStringLiteral("Máquina:"), label);
    xlsx.write(QStringLiteral("AJ9"), hval(header, QStringLiteral("maquina"), QStringLiteral("Manual")), val);
    xlsx.write(QStringLiteral("AH10"), QStringLiteral("Lado de la Vía:"), label);
    xlsx.write(QStringLiteral("AJ10"), hval(header, QStringLiteral("lado_via"), QStringLiteral("Derecho")), val);

    xlsx.write(QStringLiteral("AR8"), QStringLiteral("P.K.:"), label);
    xlsx.write(QStringLiteral("AT8"), hval(header, QStringLiteral("pk"), QStringLiteral("---")), val);
    xlsx.write(QStringLiteral("AR9"), QStringLiteral("X UTM:"), label);
    xlsx.write(QStringLiteral("AT9"), hval(header, QStringLiteral("longitud"), QStringLiteral("---")), val);
    xlsx.write(QStringLiteral("AR10"), QStringLiteral("Y UTM:"), label);
    xlsx.write(QStringLiteral("AT10"), hval(header, QStringLiteral("latitud"), QStringLiteral("---")), val);
    xlsx.write(QStringLiteral("AR11"), QStringLiteral("Z UTM:"), label);
    xlsx.write(QStringLiteral("AT11"), hval(header, QStringLiteral("altitud"), QStringLiteral("---")), val);

    xlsx.write(QStringLiteral("AV8"), QStringLiteral("Fecha inicio:"), label);
    xlsx.write(QStringLiteral("AX8"), hval(header, QStringLiteral("fecha_inicio"), hval(header, QStringLiteral("fecha"))), val);
    xlsx.write(QStringLiteral("AV9"), QStringLiteral("Fecha fin:"), label);
    xlsx.write(QStringLiteral("AX9"), hval(header, QStringLiteral("fecha_fin"), hval(header, QStringLiteral("fecha"))), val);
    xlsx.write(QStringLiteral("AV10"), QStringLiteral("Zona:"), label);
    xlsx.write(QStringLiteral("AX10"), hval(header, QStringLiteral("zona"), QStringLiteral("19K")), val);

    writeMerged(xlsx, QStringLiteral("AY8:BA8"), QStringLiteral("CALICATA"), label);
    writeMerged(xlsx, QStringLiteral("AY9:BA11"), hval(header, QStringLiteral("codigo"), QStringLiteral("CAL-001")), center);
}

void writeTableHeaders(QXlsx::Document &xlsx)
{
    QXlsx::Format h = fmtHeader();
    QXlsx::Format small = fmtSmall();

    writeMerged(xlsx, QStringLiteral("B13:D21"), QStringLiteral("PROFUNDIDAD (m)"), h);
    writeMerged(xlsx, QStringLiteral("E13:I21"), QStringLiteral("PERFIL\nESTRATIGRÁFICO"), h);
    writeMerged(xlsx, QStringLiteral("J13:R21"), QStringLiteral("DESCRIPCIÓN DEL TERRENO"), h);

    writeMerged(xlsx, QStringLiteral("S13:V13"), QStringLiteral("HUMEDAD"), h);
    const QStringList hum = { QStringLiteral("N.F."), QStringLiteral("Seco"), QStringLiteral("Bajo"), QStringLiteral("Medio") };
    for (int i = 0; i < hum.size(); ++i) xlsx.write(21, 19 + i, hum.at(i), small);

    writeMerged(xlsx, QStringLiteral("W13:Z13"), QStringLiteral("EXCAVABILIDAD"), h);
    const QStringList exc = { QStringLiteral("Manual"), QStringLiteral("R. bajo"), QStringLiteral("R. medio"), QStringLiteral("R. alto") };
    for (int i = 0; i < exc.size(); ++i) xlsx.write(21, 23 + i, exc.at(i), small);

    writeMerged(xlsx, QStringLiteral("AA13:AD13"), QStringLiteral("ESTABILIDAD"), h);
    const QStringList est = { QStringLiteral("R. muy alto"), QStringLiteral("Baja"), QStringLiteral("Media"), QStringLiteral("Alta") };
    for (int i = 0; i < est.size(); ++i) xlsx.write(21, 27 + i, est.at(i), small);

    writeMerged(xlsx, QStringLiteral("AE13:AI13"), QStringLiteral("MUESTRAS / ENSAYOS"), h);
    xlsx.write(QStringLiteral("AE21"), QStringLiteral("TIPO"), small);
    writeMerged(xlsx, QStringLiteral("AF21:AG21"), QStringLiteral("INTERVALO (m)"), small);
    writeMerged(xlsx, QStringLiteral("AH21:AI21"), QStringLiteral("RESULTADOS"), small);

    writeMerged(xlsx, QStringLiteral("AJ13:AK21"), QStringLiteral("CLASIFICACIÓN\nAASHTO"), h);
    writeMerged(xlsx, QStringLiteral("AL13:AM21"), QStringLiteral("CLASIFICACIÓN\nSUCS"), h);

    writeMerged(xlsx, QStringLiteral("AN13:AU13"), QStringLiteral("ENSAYOS DE LABORATORIO"), h);
    writeMerged(xlsx, QStringLiteral("AN14:AP16"), QStringLiteral("Granulometría (%)"), small);
    writeMerged(xlsx, QStringLiteral("AQ14:AR16"), QStringLiteral("Plasticidad"), small);
    writeMerged(xlsx, QStringLiteral("AS14:AU16"), QStringLiteral("Estado natural"), small);

    const QStringList labs = { QStringLiteral("G. Máx"), QStringLiteral("2 mm"), QStringLiteral("0.4 mm"), QStringLiteral("0.08 mm"), QStringLiteral("WL"), QStringLiteral("LP"), QStringLiteral("Humedad") };
    for (int i = 0; i < labs.size(); ++i)
        xlsx.write(21, 40 + i, labs.at(i), small);

    writeMerged(xlsx, QStringLiteral("AV13:BA21"), QStringLiteral("FOTOGRAFÍAS DE LA CALICATA"), h);
}

int rowStartForCorte(int idx)
{
    if (idx == 0) return 22;
    if (idx == 1) return 42;
    if (idx == 2) return 64;
    return 22 + idx * 14;
}

int rowEndForCorte(int idx)
{
    if (idx == 0) return 41;
    if (idx == 1) return 63;
    if (idx == 2) return 72;
    return rowStartForCorte(idx) + 13;
}

void writeIndicator(QXlsx::Document &xlsx, int row1, int row2, int col)
{
    QXlsx::Format g = fmtGray();
    for (int r = row1; r <= row2; ++r)
        xlsx.write(r, col, QString(), g);
}

int columnForHumedad(const QString &h)
{
    const QString s = h.toLower();
    if (s.contains(QStringLiteral("seca")) || s.contains(QStringLiteral("seco"))) return 20;
    if (s.contains(QStringLiteral("baja"))) return 21;
    if (s.contains(QStringLiteral("media"))) return 22;
    if (s.contains(QStringLiteral("agua"))) return 19;
    return 21;
}

int columnForExcavabilidad(const QString &e)
{
    const QString s = e.toLower();
    if (s.contains(QStringLiteral("manual"))) return 23;
    if (s.contains(QStringLiteral("baj"))) return 24;
    if (s.contains(QStringLiteral("moder")) || s.contains(QStringLiteral("medio"))) return 25;
    if (s.contains(QStringLiteral("dif")) || s.contains(QStringLiteral("alt"))) return 26;
    return 24;
}

int columnForEstabilidad(const QString &e)
{
    const QString s = e.toLower();
    if (s.contains(QStringLiteral("estable")) || s.contains(QStringLiteral("alta"))) return 30;
    if (s.contains(QStringLiteral("media"))) return 29;
    if (s.contains(QStringLiteral("baja"))) return 28;
    return 30;
}

QStringList sucsCodes(QString text)
{
    text = text.toUpper().trimmed();
    text.replace(QRegularExpression(QStringLiteral("[^A-Z]+")), QStringLiteral(" "));
    const QStringList parts = text.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QStringList out;
    for (const QString &part : parts) {
        if (QRegularExpression(QStringLiteral("^[A-Z]{1,2}$")).match(part).hasMatch()) {
            out << (part == QStringLiteral("PT") ? QStringLiteral("Pt") : part);
            if (out.size() >= 2)
                break;
        }
    }
    return out;
}

// Clasificación de reporte = Web exportModel (Rules.exportClassification):
// el laboratorio (primary_sucs / is_composite / secondary_sucs / aashto) es la
// de registro; el valor anterior del estrato solo si el laboratorio está vacío.
struct ExportClassification {
    QString primary;    // código que dibuja la trama (catálogo Web)
    QString secondary;  // segunda trama si la clasificación es compuesta
    QString label;      // "SP-SM" (compuesta) o "SP"
    QString aashto;
};

QString webSucsCatalog(const QString &value)
{
    static const QStringList catalog = {
        QStringLiteral("GW"), QStringLiteral("GP"), QStringLiteral("GM"), QStringLiteral("GC"),
        QStringLiteral("SW"), QStringLiteral("SP"), QStringLiteral("SM"), QStringLiteral("SC"),
        QStringLiteral("ML"), QStringLiteral("CL"), QStringLiteral("OL"), QStringLiteral("MH"),
        QStringLiteral("CH"), QStringLiteral("OH"), QStringLiteral("PT")};
    const QString code = value.trimmed().toUpper();
    return catalog.contains(code) ? code : QString();
}

QString webAashtoCatalog(const QString &value)
{
    static const QStringList catalog = {
        QStringLiteral("A-1-a"), QStringLiteral("A-1-b"), QStringLiteral("A-2-4"), QStringLiteral("A-2-5"),
        QStringLiteral("A-2-6"), QStringLiteral("A-2-7"), QStringLiteral("A-3"), QStringLiteral("A-4"),
        QStringLiteral("A-5"), QStringLiteral("A-6"), QStringLiteral("A-7-5"), QStringLiteral("A-7-6")};
    const QString code = value.trimmed();
    for (const QString &item : catalog)
        if (item.compare(code, Qt::CaseInsensitive) == 0) return item;
    return {};
}

ExportClassification exportClassificationFor(const QVariantMap &corte)
{
    ExportClassification out;
    const QString labPrimary = webSucsCatalog(corte.value(QStringLiteral("primary_sucs")).toString());
    const bool composite = corte.value(QStringLiteral("is_composite")).toBool();
    const QString labSecondary = composite ? webSucsCatalog(corte.value(QStringLiteral("secondary_sucs")).toString()) : QString();
    const QString labAashto = webAashtoCatalog(corte.value(QStringLiteral("lab_confirmed_aashto")).toString());
    const QStringList legacy = sucsCodes(corte.value(QStringLiteral("sucs")).toString());
    if (!labPrimary.isEmpty()) {
        out.primary = labPrimary;
        out.secondary = labSecondary == labPrimary ? QString() : labSecondary;
        out.label = out.secondary.isEmpty() ? labPrimary : labPrimary + QStringLiteral("-") + out.secondary;
    } else {
        out.primary = legacy.isEmpty() ? QString() : webSucsCatalog(legacy.at(0));
        out.secondary = legacy.size() > 1 ? webSucsCatalog(legacy.at(1)) : QString();
        out.label = corte.value(QStringLiteral("sucs")).toString().trimmed();
    }
    out.aashto = !labAashto.isEmpty() ? labAashto : corte.value(QStringLiteral("aashto")).toString().trimmed();
    return out;
}

// Tesela SUCS de exportación = Web sucsExportSymbolUrl (SUCS/web/export, mismo
// SVG), rasterizada a CALICATA_SUCS_TILE_PX (17 px) con supermuestreo x2.
constexpr int kWebSucsTilePx = 17;
QImage webSucsExportTile(const QString &code)
{
    QImageReader reader(QStringLiteral(":/SUCS/web/export/") + code + QStringLiteral(".svg"));
    reader.setScaledSize(QSize(kWebSucsTilePx * 2, kWebSucsTilePx * 2));
    return reader.read();
}

void writeCorteBlock(QXlsx::Document &xlsx, int idx, const QVariantMap &c)
{
    const int r1 = rowStartForCorte(idx);
    const int r2 = rowEndForCorte(idx);
    QXlsx::Format centered = fmtCentered();
    QXlsx::Format value = fmtValue();
    QXlsx::Format small = fmtSmall();

    writeMerged(xlsx, QStringLiteral("B%1:D%2").arg(r1).arg(r2),
                QStringLiteral("%1 - %2").arg(vstr(c.value(QStringLiteral("de"))), vstr(c.value(QStringLiteral("a")))), centered);
    writeMerged(xlsx, QStringLiteral("E%1:I%2").arg(r1).arg(r2), QStringLiteral("|||"), centered);
    writeMerged(xlsx, QStringLiteral("J%1:R%2").arg(r1).arg(r2), vstr(c.value(QStringLiteral("descripcion"))), value);

    writeIndicator(xlsx, r1, r2, columnForHumedad(vstr(c.value(QStringLiteral("humedad")))));
    writeIndicator(xlsx, r1, r2, columnForExcavabilidad(vstr(c.value(QStringLiteral("excavabilidad")))));
    writeIndicator(xlsx, r1, r2, columnForEstabilidad(vstr(c.value(QStringLiteral("estabilidad")))));

    writeMerged(xlsx, QStringLiteral("AE%1:AE%2").arg(r1).arg(r2), vstr(c.value(QStringLiteral("muestra"), QStringLiteral("MS"))), centered);
    writeMerged(xlsx, QStringLiteral("AF%1:AG%2").arg(r1).arg(r2), vstr(c.value(QStringLiteral("intervalo"))), centered);
    const ExportClassification classification = exportClassificationFor(c);
    writeMerged(xlsx, QStringLiteral("AJ%1:AK%2").arg(r1).arg(r2), classification.aashto, centered);
    writeMerged(xlsx, QStringLiteral("AL%1:AM%2").arg(r1).arg(r2), classification.label, centered);

    writeAny(xlsx, r1 + 4, 40, c.value(QStringLiteral("gmax")), centered);
    writeAny(xlsx, r1 + 4, 41, c.value(QStringLiteral("g2")), centered);
    writeAny(xlsx, r1 + 4, 42, c.value(QStringLiteral("g04")), centered);
    writeAny(xlsx, r1 + 4, 43, c.value(QStringLiteral("g008")), centered);
    writeAny(xlsx, r1 + 4, 44, c.value(QStringLiteral("wl")), centered);
    writeAny(xlsx, r1 + 4, 45, c.value(QStringLiteral("lp")), centered);
    writeAny(xlsx, r1 + 4, 46, c.value(QStringLiteral("hum2")), centered);

    xlsx.write(r1, 1, vstr(c.value(QStringLiteral("de"))), small);
    xlsx.write(r2, 1, vstr(c.value(QStringLiteral("a"))), small);
}

void writeLegend(QXlsx::Document &xlsx)
{
    QXlsx::Format small = fmtSmall();
    xlsx.write(QStringLiteral("F84"), QStringLiteral("MA: MUESTRA ALTERADA"), small);
    xlsx.write(QStringLiteral("K84"), QStringLiteral("MS: MUESTRA EN SACO"), small);
    xlsx.write(QStringLiteral("F86"), QStringLiteral("MI: MUESTRA INALTERADA"), small);
    xlsx.write(QStringLiteral("K86"), QStringLiteral("MW: MUESTRA AGUA"), small);
}

void writeLegacyCalicataTemplate(QXlsx::Document &xlsx, const QVariantMap &state)
{
    const QVariantMap header = headerFromState(state);
    const QVariantList cortes = cortesFromState(state);

    xlsx.renameSheet(QStringLiteral("Sheet1"), QStringLiteral("Calicata"));
    xlsx.selectSheet(QStringLiteral("Calicata"));

    setupColumns(xlsx);
    writeHeaderBlock(xlsx, header);
    writeTableHeaders(xlsx);

    const int maxCortes = qMin(cortes.size(), 5);
    for (int i = 0; i < maxCortes; ++i)
        writeCorteBlock(xlsx, i, cortes.at(i).toMap());

    QXlsx::Format center = fmtCentered();
    center.setFontBold(true);
    const int endRow = maxCortes > 0 ? rowEndForCorte(qMin(maxCortes - 1, 2)) + 1 : 73;
    writeMerged(xlsx, QStringLiteral("AJ%1:AU%1").arg(endRow), QStringLiteral("FIN DE LA CALICATA"), center);

    writePhotoBox(xlsx, QStringLiteral("AV22:BA39"), 23, 48,
                  QStringLiteral("Zona ejecución"),
                  hval(header, QStringLiteral("foto_zona"), QStringLiteral("")));
    writePhotoBox(xlsx, QStringLiteral("AV41:BA58"), 42, 48,
                  QStringLiteral("Interior"),
                  hval(header, QStringLiteral("foto_interior"), QStringLiteral("")));
    writePhotoBox(xlsx, QStringLiteral("AV60:BA77"), 61, 48,
                  QStringLiteral("Acopios"),
                  hval(header, QStringLiteral("foto_acopios"), QStringLiteral("")));

    const QString obs = state.value(QStringLiteral("observaciones")).toString();
    if (!obs.isEmpty())
        writeMerged(xlsx, QStringLiteral("AH84:BA86"), QStringLiteral("OBSERVACIONES\n") + obs, fmtValue());

    writeLegend(xlsx);
}

void writeDatosSheet(QXlsx::Document &xlsx, const QVariantMap &state)
{
    xlsx.addSheet(QStringLiteral("Datos"));
    xlsx.selectSheet(QStringLiteral("Datos"));

    QXlsx::Format title = fmtTitle();
    writeMerged(xlsx, QStringLiteral("A1:H1"), QStringLiteral("Datos de la ficha exportada desde InGe+ Mobile"), title);

    QXlsx::Format h = fmtHeader();
    xlsx.write(QStringLiteral("A3"), QStringLiteral("Campo"), h);
    xlsx.write(QStringLiteral("B3"), QStringLiteral("Valor"), h);

    int row = 4;
    const QVariantMap header = headerFromState(state);
    for (auto it = header.constBegin(); it != header.constEnd(); ++it) {
        xlsx.write(row, 1, it.key(), fmtLabel());
        xlsx.write(row, 2, vstr(it.value()), fmtValue());
        ++row;
    }

    xlsx.write(row + 1, 1, QStringLiteral("Observaciones"), fmtLabel());
    xlsx.write(row + 1, 2, state.value(QStringLiteral("observaciones")).toString(), fmtValue());
    xlsx.setColumnWidth(1, 28);
    xlsx.setColumnWidth(2, 70);
}

// ============================================================================
// V5 - Exportacion Android basada en la plantilla oficial Calicata_Formato.xlsx
//      La plantilla se conserva y solo se escriben los datos del JSON/estado.
// ============================================================================

constexpr int kTplBaseRow = 22;
constexpr int kTplMaxDataRow = 81;
// La geometría física original se conserva. La profundidad solo cambia la escala.

QString scalarText(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return QString();

    const QVariantMap map = value.toMap();
    if (!map.isEmpty()) {
        const QStringList keys = {
            QStringLiteral("text"), QStringLiteral("value"), QStringLiteral("currentText")
        };
        for (const QString &key : keys) {
            const QString text = vstr(map.value(key)).trimmed();
            if (!text.isEmpty())
                return text;
        }
    }
    return vstr(value).trimmed();
}

QVariant firstValue(const QVariantMap &map, const QStringList &keys)
{
    for (const QString &key : keys) {
        if (!map.contains(key))
            continue;
        const QVariant value = map.value(key);
        if (value.isValid() && !value.isNull() && !scalarText(value).isEmpty())
            return value;
    }
    return QVariant();
}

QString firstText(const QVariantMap &map, const QStringList &keys)
{
    return scalarText(firstValue(map, keys));
}

// Nombre del proyecto = projects.name (contrato Web exportModel.projectName:
// el mismo dato en ficha, fotos, Excel y PDF). Solo una ficha sin proyecto
// asignado usa el nombre antiguo guardado en su encabezado.
QString exportProjectName(const QVariantMap &header, const QVariantMap &timestamp = {})
{
    if (!header.value(QStringLiteral("projectId")).toString().trimmed().isEmpty()) {
        const QString name = firstText(header, {QStringLiteral("projectName"), QStringLiteral("project_name")});
        if (!name.isEmpty()) return name;
    }
    QString legacy = firstText(header, {QStringLiteral("project_full_name"), QStringLiteral("nombre_proyecto_completo")});
    if (legacy.isEmpty()) legacy = firstText(timestamp, {QStringLiteral("proyecto")});
    if (legacy.isEmpty()) legacy = firstText(header, {QStringLiteral("excel_title")});
    return legacy;
}

QString canonicalCalicataCode(const QVariantMap &header, const QVariantMap &timestamp = {})
{
    QString code = firstText(header, {
        QStringLiteral("codigo"),
        QStringLiteral("code"),
        QStringLiteral("calicata"),
        QStringLiteral("pk"),
        QStringLiteral("progresiva")
    });
    if (code.isEmpty())
        code = firstText(timestamp, { QStringLiteral("calicata") });
    return code.trimmed();
}

QString canonicalPk(const QVariantMap &header)
{
    const QString canonicalCode = firstText(header, { QStringLiteral("codigo") });
    if (!canonicalCode.isEmpty())
        return firstText(header, { QStringLiteral("pk"), QStringLiteral("progresiva") });

    const QString legacyCalicata = firstText(header, { QStringLiteral("calicata") });
    if (!legacyCalicata.isEmpty()) {
        QString value = firstText(header, { QStringLiteral("progresiva") });
        if (value.isEmpty()) {
            value = firstText(header, { QStringLiteral("pk") });
            if (value == legacyCalicata)
                value.clear();
        }
        return value;
    }
    return firstText(header, { QStringLiteral("progresiva"), QStringLiteral("pk") });
}

bool variantBool(const QVariantMap &map, const QString &key, bool fallback = false)
{
    if (!map.contains(key))
        return fallback;
    const QVariant value = map.value(key);
    if (value.typeId() == QMetaType::Bool)
        return value.toBool();
    const QString text = scalarText(value).trimmed().toLower();
    if (text == QStringLiteral("true") || text == QStringLiteral("1")
        || text == QStringLiteral("si") || text == QStringLiteral("sí")
        || text == QStringLiteral("encontrado")) {
        return true;
    }
    if (text == QStringLiteral("false") || text == QStringLiteral("0")
        || text == QStringLiteral("no") || text == QStringLiteral("np")
        || text == QStringLiteral("no encontrado")) {
        return false;
    }
    return fallback;
}

QString formatDateForTemplate(const QString &raw)
{
    QString s = raw.trimmed();
    if (s.isEmpty())
        return QString();

    if (s.size() >= 10) {
        const QDate iso = QDate::fromString(s.left(10), Qt::ISODate);
        if (iso.isValid())
            return iso.toString(QStringLiteral("dd/MM/yyyy"));
    }

    const QDate dmy = QDate::fromString(s, QStringLiteral("dd/MM/yyyy"));
    if (dmy.isValid())
        return dmy.toString(QStringLiteral("dd/MM/yyyy"));

    return s;
}

QString localPathFromVariant(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return QString();

    if (value.canConvert<QUrl>()) {
        const QUrl url = value.toUrl();
        if (url.isValid() && url.isLocalFile())
            return QDir::cleanPath(url.toLocalFile());
    }

    const QString s = value.toString().trimmed();
    if (s.isEmpty())
        return QString();

    const QUrl url(s);
    if (url.isValid() && url.isLocalFile())
        return QDir::cleanPath(url.toLocalFile());

    return QDir::cleanPath(QDir::fromNativeSeparators(s));
}

QString sourceJsonPathFromState(const QVariantMap &state)
{
    const QStringList keys = {
        QStringLiteral("_source_json_path"),
        QStringLiteral("_source_json_url"),
        QStringLiteral("source_json_path"),
        QStringLiteral("source_json_url")
    };
    for (const QString &key : keys) {
        const QString path = localPathFromVariant(state.value(key));
        if (!path.isEmpty())
            return path;
    }
    return QString();
}

QString resourcesBasePathFromState(const QVariantMap &state)
{
    const QStringList keys = {
        QStringLiteral("_resources_base_path"),
        QStringLiteral("resources_base_path")
    };
    for (const QString &key : keys) {
        const QString path = localPathFromVariant(state.value(key));
        if (!path.isEmpty())
            return path;
    }
    return QString();
}

QString resolveImageSource(QString source,
                           const QString &sourceJsonPath,
                           const QString &resourcesBasePath = QString())
{
    source = source.trimmed();
    if (source.isEmpty())
        return QString();

    if (source.startsWith(QStringLiteral("content://"), Qt::CaseInsensitive) ||
        source.startsWith(QStringLiteral("qrc:/"), Qt::CaseInsensitive) ||
        source.startsWith(QStringLiteral(":/"))) {
        return source;
    }

    const QUrl url(source);
    if (url.isValid() && url.isLocalFile()) {
        const QString local = QDir::cleanPath(url.toLocalFile());
        return QFileInfo::exists(local) ? local : QString();
    }

    QString normalized = QDir::cleanPath(QDir::fromNativeSeparators(source));
    if (QDir::isAbsolutePath(normalized))
        return QFileInfo::exists(normalized) ? normalized : QString();

    if (!sourceJsonPath.isEmpty()) {
        QString base = QFileInfo(sourceJsonPath).absolutePath();
        for (int i = 0; i < 10 && !base.isEmpty(); ++i) {
            const QString candidate = QDir::cleanPath(QDir(base).absoluteFilePath(normalized));
            if (QFileInfo::exists(candidate))
                return candidate;

            QDir dir(base);
            if (!dir.cdUp())
                break;
            const QString parent = QDir::cleanPath(dir.absolutePath());
            if (parent == base)
                break;
            base = parent;
        }
    }

    if (!resourcesBasePath.isEmpty()) {
        const QString candidate = QDir::cleanPath(
            QDir(resourcesBasePath).absoluteFilePath(normalized));
        if (QFileInfo::exists(candidate))
            return candidate;
    }

    return QString();
}

QXlsx::Format formatAt(QXlsx::Document &xlsx, int row, int col)
{
    const auto cell = xlsx.cellAt(row, col);
    return cell ? cell->format() : QXlsx::Format();
}

void writeTemplateValue(QXlsx::Document &xlsx, const QString &address, const QVariant &value)
{
    double number = 0.0;
    if (isSimpleNumber(value, &number))
        xlsx.write(address, number);
    else
        xlsx.write(address, scalarText(value));
}

bool percentageNumber(const QVariant &value, double *out)
{
    const QString raw = scalarText(value);
    if (raw.isEmpty())
        return false;

    double number = 0.0;
    if (!isSimpleNumber(raw, &number))
        return false;

    if (raw.contains(QLatin1Char('%')) || (number > 1.0 && number <= 100.0))
        number /= 100.0;

    if (out)
        *out = number;
    return true;
}

void writePercentageTemplateValue(QXlsx::Document &xlsx,
                                  const QString &address,
                                  const QVariant &value)
{
    double number = 0.0;
    if (percentageNumber(value, &number))
        xlsx.write(address, number);
    else
        xlsx.write(address, scalarText(value));
}

void applyNumberFormatPreservingStyle(QXlsx::Document &xlsx,
                                      int firstRow,
                                      int firstCol,
                                      int lastRow,
                                      int lastCol,
                                      const QString &numberFormat)
{
    for (int row = firstRow; row <= lastRow; ++row) {
        for (int col = firstCol; col <= lastCol; ++col) {
            QXlsx::Format fmt = formatAt(xlsx, row, col);
            fmt.setNumberFormat(numberFormat);
            xlsx.write(row, col, xlsx.read(row, col), fmt);
        }
    }
}

void applyGranulometriaFormats(QXlsx::Document &xlsx)
{
    applyNumberFormatPreservingStyle(xlsx, 22, 35, 81, 35, QStringLiteral("0%"));     // AI
    applyNumberFormatPreservingStyle(xlsx, 22, 36, 81, 39, QStringLiteral("0.0%"));   // AJ:AM
    applyNumberFormatPreservingStyle(xlsx, 22, 42, 81, 42, QStringLiteral("0.00%"));  // AP
}

void mergeTemplateRange(QXlsx::Document &xlsx, const QString &range)
{
    const QXlsx::CellRange r(range);
    if (r.rowCount() < 2 && r.columnCount() < 2)
        return;
    xlsx.mergeCells(r);
}

bool depthValue(const QVariantMap &corte, const QStringList &keys, double *out)
{
    const QVariant value = firstValue(corte, keys);
    if (!value.isValid())
        return false;
    return isSimpleNumber(value, out);
}

bool validateOfficialState(const QVariantMap &state, QString *error, double *finalDepthOut = nullptr)
{
    const QString blocker = CalicataValidation::firstBlocker(state);
    if (!blocker.isEmpty()) {
        if (error) *error = blocker;
        return false;
    }
    if (finalDepthOut) {
        double finalDepth = 0;
        for (const auto &value : cortesFromState(state)) {
            double to = 0;
            depthValue(value.toMap(), {QStringLiteral("a"), QStringLiteral("hasta")}, &to);
            finalDepth = qMax(finalDepth, to);
        }
        *finalDepthOut = finalDepth;
    }
    return true;
}

QVariant nestedComboValue(const QVariantMap &corte, const QString &key)
{
    const QVariantMap combos = corte.value(QStringLiteral("combo_boxes")).toMap();
    return combos.value(key);
}

QVariant nestedLineValue(const QVariantMap &corte, const QString &key)
{
    const QVariantMap lines = corte.value(QStringLiteral("line_edits")).toMap();
    return lines.value(key);
}

QVariant nestedTextValue(const QVariantMap &corte, const QString &key)
{
    const QVariantMap texts = corte.value(QStringLiteral("text_edits")).toMap();
    return texts.value(key);
}

int optionIndex(const QVariant &value, const QStringList &labels, bool oneBasedObjectIndex = false)
{
    if (!value.isValid() || value.isNull())
        return -1;

    const QVariantMap map = value.toMap();
    if (!map.isEmpty() && map.contains(QStringLiteral("index"))) {
        bool ok = false;
        int idx = map.value(QStringLiteral("index")).toInt(&ok);
        if (ok) {
            if (oneBasedObjectIndex && idx >= 1 && idx <= labels.size())
                idx -= 1;
            if (idx >= 0 && idx < labels.size())
                return idx;
        }
    }

    if (value.typeId() == QMetaType::Int || value.typeId() == QMetaType::UInt ||
        value.typeId() == QMetaType::LongLong || value.typeId() == QMetaType::ULongLong ||
        value.typeId() == QMetaType::Double || value.typeId() == QMetaType::Float) {
        const int idx = value.toInt();
        return (idx >= 0 && idx < labels.size()) ? idx : -1;
    }

    bool ok = false;
    const int numericText = value.toString().trimmed().toInt(&ok);
    if (ok && numericText >= 0 && numericText < labels.size())
        return numericText;

    const QString text = scalarText(value).toLower();
    for (int i = 0; i < labels.size(); ++i) {
        if (text == labels.at(i).toLower())
            return i;
    }

    return -1;
}

int humedadIndex(const QVariantMap &corte)
{
    QVariant value = corte.value(QStringLiteral("humedad"));
    if (!value.isValid()) {
        value = nestedComboValue(corte, QStringLiteral("cbHumedad"));
        const int idx = optionIndex(value,
                                    { QStringLiteral("Seco"), QStringLiteral("Bajo"), QStringLiteral("Medio"), QStringLiteral("Agua") },
                                    true);
        if (idx >= 0) return idx;
    }

    int idx = optionIndex(value,
                          { QStringLiteral("Seco"), QStringLiteral("Bajo"), QStringLiteral("Medio"), QStringLiteral("Agua") });
    if (idx >= 0) return idx;

    const QString s = scalarText(value).toLower();
    if (s.contains(QStringLiteral("seco")) || s.contains(QStringLiteral("seca"))) return 0;
    if (s.contains(QStringLiteral("baj"))) return 1;
    if (s.contains(QStringLiteral("med"))) return 2;
    if (s.contains(QStringLiteral("agua"))) return 3;
    return -1;
}

int excavabilidadIndex(const QVariantMap &corte)
{
    QVariant value = corte.value(QStringLiteral("excavabilidad"));
    if (!value.isValid()) {
        value = nestedComboValue(corte, QStringLiteral("cbExcavabilidad"));
        const int idx = optionIndex(value,
                                    { QStringLiteral("Rend. bajo"), QStringLiteral("Rend. medio"), QStringLiteral("Rend. alto"), QStringLiteral("Rend. muy alto") },
                                    true);
        if (idx >= 0) return idx;
    }

    int idx = optionIndex(value,
                          { QStringLiteral("Rend. bajo"), QStringLiteral("Rend. medio"), QStringLiteral("Rend. alto"), QStringLiteral("Rend. muy alto") });
    if (idx >= 0) return idx;

    const QString s = scalarText(value).toLower();
    if (s.contains(QStringLiteral("muy")) && s.contains(QStringLiteral("alto"))) return 3;
    if (s.contains(QStringLiteral("alto")) || s.contains(QStringLiteral("dif"))) return 2;
    if (s.contains(QStringLiteral("medio")) || s.contains(QStringLiteral("moder"))) return 1;
    if (s.contains(QStringLiteral("baj")) || s.contains(QStringLiteral("manual"))) return 0;
    return -1;
}

int estabilidadIndex(const QVariantMap &corte)
{
    QVariant value = corte.value(QStringLiteral("estabilidad"));
    if (!value.isValid()) {
        value = nestedComboValue(corte, QStringLiteral("cbEstabilidad"));
        const int idx = optionIndex(value,
                                    { QStringLiteral("Baja"), QStringLiteral("Media"), QStringLiteral("Alta"), QStringLiteral("Muy Alta") },
                                    true);
        if (idx >= 0) return idx;
    }

    int idx = optionIndex(value,
                          { QStringLiteral("Baja"), QStringLiteral("Media"), QStringLiteral("Alta"), QStringLiteral("Muy Alta") });
    if (idx >= 0) return idx;

    const QString s = scalarText(value).toLower();
    if (s.contains(QStringLiteral("muy")) && s.contains(QStringLiteral("alta"))) return 3;
    if (s.contains(QStringLiteral("alta")) || s.contains(QStringLiteral("estable"))) return 2;
    if (s.contains(QStringLiteral("media"))) return 1;
    if (s.contains(QStringLiteral("baja"))) return 0;
    return -1;
}

void shadeCellPreservingFormat(QXlsx::Document &xlsx, int row, int col)
{
    QXlsx::Format fmt = formatAt(xlsx, row, col);
    if (!fmt.isValid())
        fmt = fmtCentered();
    fmt.setFillPattern(QXlsx::Format::PatternSolid);
    fmt.setPatternForegroundColor(QColor(QStringLiteral("#808080")));
    fmt.setPatternBackgroundColor(QColor(QStringLiteral("#808080")));
    xlsx.write(row, col, QVariant(), fmt);
}

void mergeVerticalColumns(QXlsx::Document &xlsx, int firstCol, int lastCol, int r1, int r2)
{
    if (r2 <= r1)
        return;
    for (int col = firstCol; col <= lastCol; ++col)
        xlsx.mergeCells(QXlsx::CellRange(r1, col, r2, col));
}

int columnWidthPixels(QXlsx::Document &xlsx, int column)
{
    if (xlsx.isColumnHidden(column))
        return 0;

    double width = xlsx.columnWidth(column);
    if (width <= 0.0)
        width = 8.43;
    return width < 1.0 ? qRound(width * 12.0)
                       : qRound(width * 7.0) + 5;
}

double rowHeightPixels(QXlsx::Document &xlsx, int row)
{
    if (xlsx.isRowHidden(row))
        return 0;

    double points = xlsx.rowHeight(row);
    if (points <= 0.0)
        points = 15.0;
    return points * 4.0 / 3.0;
}

int rangeWidthPixels(QXlsx::Document &xlsx, int c1, int c2)
{
    int pixels = 0;
    for (int c = c1; c <= c2; ++c)
        pixels += columnWidthPixels(xlsx, c);
    return qMax(1, pixels);
}

int rangeHeightPixels(QXlsx::Document &xlsx, int r1, int r2)
{
    double pixels = 0;
    for (int r = r1; r <= r2; ++r)
        pixels += rowHeightPixels(xlsx, r);
    return qMax(1, qRound(pixels));
}

struct ExcelImageMarker
{
    int row = 1;
    int column = 1;
    QPoint offset;
};

ExcelImageMarker markerAtRangeOffset(QXlsx::Document &xlsx,
                                     int firstRow,
                                     int firstColumn,
                                     int lastRow,
                                     int lastColumn,
                                     int x,
                                     int y)
{
    ExcelImageMarker marker;
    marker.column = firstColumn;
    int remainingX = qMax(0, x);
    while (marker.column <= lastColumn) {
        const int cellWidth = columnWidthPixels(xlsx, marker.column);
        if (remainingX < cellWidth)
            break;
        remainingX -= cellWidth;
        ++marker.column;
    }
    if (marker.column > lastColumn) {
        marker.column = lastColumn + 1;
        remainingX = 0;
    }

    marker.row = firstRow;
    double remainingY = qMax(0, y);
    while (marker.row <= lastRow) {
        const double cellHeight = rowHeightPixels(xlsx, marker.row);
        if (remainingY < cellHeight)
            break;
        remainingY -= cellHeight;
        ++marker.row;
    }
    if (marker.row > lastRow) {
        marker.row = lastRow + 1;
        remainingY = 0;
    }

    marker.offset = QPoint(remainingX, qRound(remainingY));
    return marker;
}

bool insertImageFitted(QXlsx::Document &xlsx,
                       int row, int col,
                       int lastRow, int lastCol,
                       QImage img,
                       bool stretch,
                       bool keepResolution = false)
{
    if (row < 1 || col < 1 || lastRow < row || lastCol < col || img.isNull())
        return false;

    const int slotWidth = rangeWidthPixels(xlsx, col, lastCol);
    const int slotHeight = rangeHeightPixels(xlsx, row, lastRow);

    int renderWidth = slotWidth;
    int renderHeight = slotHeight;
    if (!stretch) {
        const QSize fitted = img.size().scaled(slotWidth, slotHeight, Qt::KeepAspectRatio);
        renderWidth = qBound(1, fitted.width(), slotWidth);
        renderHeight = qBound(1, fitted.height(), slotHeight);
    }

    if (!keepResolution && img.size() != QSize(renderWidth, renderHeight))
        img = img.scaled(renderWidth,
                         renderHeight,
                         Qt::IgnoreAspectRatio, // aspect already applied to the integer render size
                         Qt::SmoothTransformation);
    if (img.isNull())
        return false;

    if (!keepResolution) {
        renderWidth = img.width();
        renderHeight = img.height();
    }
    const int left = (slotWidth - renderWidth) / 2;
    const int top = (slotHeight - renderHeight) / 2;
    const ExcelImageMarker from = markerAtRangeOffset(
        xlsx, row, col, lastRow, lastCol, left, top);
    const ExcelImageMarker to = markerAtRangeOffset(
        xlsx, row, col, lastRow, lastCol, left + renderWidth, top + renderHeight);

    if (img.dotsPerMeterX() != kExcelDpm96) img.setDotsPerMeterX(kExcelDpm96);
    if (img.dotsPerMeterY() != kExcelDpm96) img.setDotsPerMeterY(kExcelDpm96);
    return xlsx.insertImageTwoCell(from.row - 1,
                                   from.column - 1,
                                   from.offset,
                                   to.row - 1,
                                   to.column - 1,
                                   to.offset,
                                   img) > 0;
}

bool insertImageFitted(QXlsx::Document &xlsx,
                       int row, int col,
                       int lastRow, int lastCol,
                       const QString &source,
                       bool stretch)
{
    QImage img;
    if (!loadImageFromSource(source, &img) || img.isNull())
        return false;
    return insertImageFitted(xlsx, row, col, lastRow, lastCol, img, stretch);
}

// Trama de un estrato sin deformación: el patrón se dibuja a UNA escala
// uniforme (igual en X e Y, fija por recurso para toda la ficha) y se repite
// desde la esquina superior izquierda hasta llenar el rectángulo, recortando
// el sobrante. Un estrato más alto muestra más repeticiones; uno más bajo,
// menos. El resultado tiene la proporción exacta del rectángulo, así que el
// ancla de dos celdas lo muestra 1:1 (nunca un stretch libre del símbolo).
QImage tiledProfilePattern(const QImage &tile, const QSize &box, double tileScale)
{
    if (tile.isNull() || box.width() <= 0 || box.height() <= 0 || !(tileScale > 0))
        return {};
    constexpr int kSupersample = 2; // nitidez al imprimir o hacer zoom
    const int tileWidth = qMax(1, qRound(tile.width() * tileScale * kSupersample));
    const QImage unit = tile.scaledToWidth(tileWidth, Qt::SmoothTransformation);
    if (unit.isNull())
        return {};
    QImage out(box * kSupersample, QImage::Format_ARGB32_Premultiplied);
    if (out.isNull())
        return {};
    out.fill(Qt::transparent);
    QPainter painter(&out);
    for (int y = 0; y < out.height(); y += unit.height())
        for (int x = 0; x < out.width(); x += unit.width())
            painter.drawImage(QPoint(x, y), unit);
    painter.end();
    out.setDotsPerMeterX(kExcelDpm96 * kSupersample);
    out.setDotsPerMeterY(kExcelDpm96 * kSupersample);
    return out;
}

QString corteText(const QVariantMap &corte,
                   const QStringList &flatKeys,
                   const QString &nestedLineKey = QString(),
                   const QString &nestedTextKey = QString())
{
    QString value = firstText(corte, flatKeys);
    if (value.isEmpty() && !nestedLineKey.isEmpty())
        value = scalarText(nestedLineValue(corte, nestedLineKey));
    if (value.isEmpty() && !nestedTextKey.isEmpty())
        value = scalarText(nestedTextValue(corte, nestedTextKey));
    return value;
}

QString structuredObservations(const QVariantMap &header,
                               double finalDepth,
                               const QString &freeObservations)
{
    // Bloque AH84:BC89 como la ficha oficial C-AA-01: título y líneas
    // estructuradas seguidas de las observaciones libres (sin línea en blanco).
    QStringList lines{QStringLiteral("OBSERVACIONES")};
    const QString location = firstText(header, {
        QStringLiteral("ubicacion"), QStringLiteral("tramo")
    });
    if (!location.isEmpty())
        lines << QStringLiteral("Ubicación: ") + location;

    const bool waterPresent = header.contains(QStringLiteral("water_table_present"))
        ? variantBool(header, QStringLiteral("water_table_present"))
        : variantBool(header, QStringLiteral("waterTablePresent"));
    QString waterText = QStringLiteral("NP");
    if (waterPresent) {
        double waterDepth = 0.0;
        const QVariant depth = firstValue(header, {
            QStringLiteral("water_table_depth"), QStringLiteral("waterTableDepth")
        });
        if (isSimpleNumber(depth, &waterDepth))
            waterText = QStringLiteral("%1 m").arg(waterDepth, 0, 'f', 2);
    }
    lines << QStringLiteral("Nivel freático: ") + waterText;
    lines << QStringLiteral("Profundidad final: %1 m").arg(finalDepth, 0, 'f', 2);

    QStringList freeLines;
    const QRegularExpression structuredLine(
        QStringLiteral("^\\s*(ubicaci[oó]n|nivel\\s+fre[aá]tico|profundidad\\s+final)\\s*:|^\\s*observaciones\\s*$"),
        QRegularExpression::CaseInsensitiveOption);
    for (const QString &line : freeObservations.split(QLatin1Char('\n'))) {
        if (!structuredLine.match(line).hasMatch())
            freeLines << line;
    }
    const QString cleanedFree = freeLines.join(QLatin1Char('\n')).trimmed();
    if (!cleanedFree.isEmpty())
        lines << cleanedFree;
    return lines.join(QLatin1Char('\n'));
}

QString imagePathFromState(const QVariantMap &state,
                           const QString &key,
                           const QString &sourceJsonPath,
                           int photoIndex = 0)
{
    const QVariantMap images = state.value(QStringLiteral("images")).toMap();
    QString source = firstText(images, { key });
    const QString resourcesBasePath = resourcesBasePathFromState(state);
    QString resolved = resolveImageSource(source, sourceJsonPath, resourcesBasePath);
    if (!resolved.isEmpty())
        return resolved;

    if (photoIndex > 0) {
        const QVariantMap cache = state.value(QStringLiteral("photos_cache")).toMap();
        source = firstText(cache, { QStringLiteral("foto%1").arg(photoIndex) });
        resolved = resolveImageSource(source, sourceJsonPath, resourcesBasePath);
        if (!resolved.isEmpty())
            return resolved;
    }

    return QString();
}

// Fuente ÚNICA de imágenes del informe, compartida por Excel y PDF: la misma
// resolución que usa la ficha (embebida, ruta absoluta, relativa a la carpeta
// de la ficha o a la base de recursos, content://, qrc). Un hueco de foto
// vacío no es error (celda en blanco, la Revisión ya lo avisa); una imagen
// registrada que no se puede leer SÍ lo es y se nombra. Logos: vacío = el
// predeterminado empaquetado; quitado = el informe no está completo.
struct ReportImage {
    QImage image;
    QString problem;
};

ReportImage reportImage(const QVariantMap &state, const QString &key, const QString &label,
                        QHash<QString, QImage> &cache,
                        const QString &resourcesBase = QString(), int photoIndex = 0)
{
    ReportImage result;
    const QVariantMap images = state.value(QStringLiteral("images")).toMap();
    const bool mtcLogo = key == QLatin1String("logo_mtc_path");
    const bool logo = mtcLogo || key == QLatin1String("logo_proyecto_path");
    if (logo && images.value(mtcLogo ? QStringLiteral("logo_mtc_removed")
                                     : QStringLiteral("logo_proyecto_removed")).toBool()) {
        result.problem = QStringLiteral("Completa los logos del informe o selecciona los predeterminados.");
        return result;
    }
    const QString encoded = state.value(QStringLiteral("embedded_resources")).toMap().value(key).toString();
    if (!encoded.isEmpty()) {
        if (encoded.size() > (kReportImageMaxBytes + 2) / 3 * 4) {
            result.problem = QStringLiteral("El recurso embebido de %1 excede 32 MiB. Reduce la imagen antes de exportar.").arg(label);
            return result;
        }
        const QByteArray ascii = encoded.toLatin1();
        const QString embeddedKey = QStringLiteral("embedded:") + QString::fromLatin1(
            QCryptographicHash::hash(ascii, QCryptographicHash::Sha256).toHex());
        const auto cached = cache.constFind(embeddedKey);
        if (cached != cache.cend()) {
            result.image = cached.value();
            return result;
        }
        const auto decoded = QByteArray::fromBase64Encoding(ascii, QByteArray::AbortOnBase64DecodingErrors);
        QBuffer buffer;
        buffer.setData(decoded.decoded);
        if (decoded && buffer.open(QIODevice::ReadOnly)) {
            QImageReader reader(&buffer);
            result.image = readReportImage(reader);
        }
        if (result.image.isNull()) {
            result.problem = QStringLiteral("No se puede leer el recurso embebido de %1. Vuelve a elegir una imagen válida o de menor tamaño.").arg(label);
            return result; // No substitute path can hide a corrupt portable resource.
        }
        cache.insert(embeddedKey, result.image);
        return result;
    }
    QString stored = firstText(images, { key });
    if (stored.isEmpty() && photoIndex > 0)
        stored = firstText(state.value(QStringLiteral("photos_cache")).toMap(),
                           { QStringLiteral("foto%1").arg(photoIndex) });
    if (stored.isEmpty() && logo)
        stored = mtcLogo ? QStringLiteral(":/images/ICONO_LOGO_MTC.jpeg")
                         : QStringLiteral(":/images/INGEMA_LOGO_COMPLETO.png");
    if (stored.isEmpty())
        return result;   // hueco vacío
    QString source = imagePathFromState(state, key, sourceJsonPathFromState(state), photoIndex);
    if (source.isEmpty())
        source = resolveImageSource(stored, QString(), resourcesBase);
    const auto cached = cache.constFind(source);
    if (cached != cache.cend()) {
        result.image = cached.value();
        return result;
    }
    if (source.isEmpty() || !loadImageFromSource(source, &result.image) || result.image.isNull()) {
        result.image = QImage();
        result.problem = QStringLiteral("No se encuentra el archivo de %1 (%2), no es legible o supera el límite de memoria. Vuelve a elegir una imagen válida o de menor tamaño antes de exportar.")
                             .arg(label, QFileInfo(stored).fileName());
    } else {
        cache.insert(source, result.image);
    }
    return result;
}

struct ReportImageSlot {
    const char *key;
    const char *label;
    int photoIndex;
};

const ReportImageSlot kReportImageSlots[] = {
    { "logo_mtc_path", "el logo de la entidad", 0 },
    { "logo_proyecto_path", "el logo del proyecto", 0 },
    { "foto1_path", "la foto «Zona de ejecución»", 1 },
    { "foto2_path", "la foto «Interior de calicata»", 2 },
    { "foto3_path", "la foto «Acopios»", 3 },
};

using ReportImages = std::array<QImage, 5>;

ReportImage reportImageAt(const QVariantMap &state, int slot, QHash<QString, QImage> &cache,
                          const QString &resourcesBase = QString())
{
    const ReportImageSlot &entry = kReportImageSlots[slot];
    return reportImage(state, QString::fromLatin1(entry.key), QString::fromUtf8(entry.label),
                       cache, resourcesBase, entry.photoIndex);
}

bool prepareReportImages(const QVariantMap &state, const QString &resourcesBase,
                         ReportImages *images, QString *error)
{
    QHash<QString, QImage> cache; // Scoped to this export/account; QImage shares pixel storage.
    for (int slot = 0; slot < int(images->size()); ++slot) {
        const ReportImage image = reportImageAt(state, slot, cache, resourcesBase);
        if (!image.problem.isEmpty()) {
            if (error) *error = image.problem;
            return false;
        }
        (*images)[slot] = image.image;
    }
    return true;
}

// Add native row boundaries at the actual layer contacts. Subdividing a row
// redistributes its height; it never enlarges the printed form.
struct NativeProfileLayout
{
    std::vector<double> boundaries;
    std::vector<int> firstRows;
    std::vector<int> lastRows;
    int delta = 0;
    int endRow = kTplMaxDataRow;
    double height = 0;
    double axisDepth = 3;

    int fractionRow(double fraction) const
    {
        return kTplBaseRow + int(std::lower_bound(boundaries.begin(), boundaries.end(), fraction)
                                 - boundaries.begin());
    }
    int boundaryRow(double depth) const { return fractionRow(qBound(0.0, depth / axisDepth, 1.0)); }
    int first(int row) const { return row < kTplBaseRow ? row : firstRows.at(row); }
    int last(int row) const { return row < kTplBaseRow ? row : lastRows.at(row); }
};

bool prepareNativeProfileRows(QXlsx::Document &xlsx, const QVariantList &cortes,
                              const QVariantMap &header, double axisDepth,
                              NativeProfileLayout *layout, QString *error)
{
    layout->axisDepth = axisDepth;
    const int originalLast = qMax(89, xlsx.dimension().lastRow());
    const int originalColumns = qMax(55, xlsx.dimension().lastColumn());
    std::vector<double> originalBoundaries{0.0};
    for (int row = kTplBaseRow; row <= kTplMaxDataRow; ++row) {
        layout->height += xlsx.rowHeight(row);
        originalBoundaries.push_back(layout->height);
    }
    if (layout->height <= 0) {
        if (error) *error = QStringLiteral("La plantilla no tiene una altura válida para el perfil.");
        return false;
    }
    for (double &value : originalBoundaries) value /= layout->height;
    originalBoundaries.back() = 1.0;
    layout->boundaries = originalBoundaries;
    for (int i = 1; i < 6; ++i) layout->boundaries.push_back(double(i) / 6.0);
    double previousEnd = 0;
    for (int index = 0; index < cortes.size(); ++index) {
        double de = 0, a = 0;
        const auto corte = cortes.at(index).toMap();
        if (!depthValue(corte, {QStringLiteral("de"), QStringLiteral("desde")}, &de)
            || !depthValue(corte, {QStringLiteral("a"), QStringLiteral("hasta")}, &a)
            || !std::isfinite(de) || !std::isfinite(a) || de < previousEnd
            || de < 0 || a <= de || a > axisDepth) {
            if (error) *error = QStringLiteral("Estrato %1: intervalo inválido, superpuesto o superior a la profundidad total.").arg(index + 1);
            return false;
        }
        previousEnd = a;
        layout->boundaries.push_back(de / axisDepth);
        layout->boundaries.push_back(a / axisDepth);
    }
    double waterDepth = 0;
    const bool waterPresent = header.contains(QStringLiteral("water_table_present"))
        ? variantBool(header, QStringLiteral("water_table_present"))
        : variantBool(header, QStringLiteral("waterTablePresent"));
    if (waterPresent && depthValue(header, {QStringLiteral("water_table_depth"), QStringLiteral("waterTableDepth")}, &waterDepth)
        && waterDepth >= 0 && waterDepth <= axisDepth)
        layout->boundaries.push_back(waterDepth / axisDepth);
    std::sort(layout->boundaries.begin(), layout->boundaries.end());
    layout->boundaries.erase(std::unique(layout->boundaries.begin(), layout->boundaries.end()), layout->boundaries.end());
    layout->endRow = kTplBaseRow + int(layout->boundaries.size()) - 2;
    layout->delta = layout->endRow - kTplMaxDataRow;
    if (originalLast + layout->delta > 1048576) {
        if (error) *error = QStringLiteral("Los estratos superan la capacidad de filas de Excel.");
        return false;
    }
    layout->firstRows.resize(originalLast + 2);
    layout->lastRows.resize(originalLast + 2);
    for (int row = kTplBaseRow; row <= originalLast + 1; ++row) {
        if (row <= kTplMaxDataRow) {
            const auto offset = std::lower_bound(layout->boundaries.begin(), layout->boundaries.end(),
                                                originalBoundaries.at(row - kTplBaseRow));
            layout->firstRows[row] = kTplBaseRow + int(offset - layout->boundaries.begin());
        } else {
            layout->firstRows[row] = row + layout->delta;
        }
        if (row > kTplBaseRow) layout->lastRows[row - 1] = layout->firstRows[row] - 1;
    }
    struct SavedCell { int row, column; QVariant value; QXlsx::Format format; QXlsx::CellFormula formula; };
    std::vector<SavedCell> cells;
    std::vector<double> heights(originalLast + 1);
    for (int row = kTplBaseRow; row <= originalLast; ++row) {
        heights[row] = xlsx.rowHeight(row);
        for (int col = 1; col <= originalColumns; ++col) {
            const auto cell = xlsx.cellAt(row, col);
            if (cell) cells.push_back({row, col, cell->value(), cell->format(), cell->formula()});
        }
    }
    const auto merges = xlsx.currentWorksheet()->mergedCells();
    for (const auto &range : merges)
        if (range.lastRow() >= kTplBaseRow) xlsx.unmergeCells(range);
    for (const auto &cell : cells) xlsx.currentWorksheet()->writeBlank(cell.row, cell.column);
    for (int row = kTplBaseRow; row <= originalLast; ++row) {
        for (int target = layout->first(row); target <= layout->last(row); ++target) {
            const double points = row <= kTplMaxDataRow
                ? (layout->boundaries.at(target - kTplBaseRow + 1) - layout->boundaries.at(target - kTplBaseRow)) * layout->height
                : heights[row];
            if (!xlsx.setRowHeight(target, points)) {
                if (error) *error = QStringLiteral("No se pudo distribuir la altura de las celdas del perfil.");
                return false;
            }
        }
    }
    for (const auto &cell : cells) {
        for (int target = layout->first(cell.row); target <= layout->last(cell.row); ++target) {
            const bool body = cell.row <= kTplMaxDataRow && cell.column <= 46;
            const QVariant value = !body && target == layout->first(cell.row) ? cell.value : QVariant();
            if (!body && target == layout->first(cell.row) && cell.formula.isValid())
                xlsx.currentWorksheet()->writeFormula(target, cell.column, cell.formula, cell.format, cell.value.toDouble());
            else
                xlsx.write(target, cell.column, value, cell.format);
        }
    }
    for (const auto &range : merges) {
        if (range.lastRow() < kTplBaseRow) continue;
        // Depth labels are rebuilt at scale marks; body data merges are rebuilt per layer.
        if (range.firstRow() <= kTplMaxDataRow && range.lastColumn() <= 46) continue;
        xlsx.mergeCells(QXlsx::CellRange(layout->first(range.firstRow()), range.firstColumn(),
                                       layout->last(range.lastRow()), range.lastColumn()));
    }
    // The last row number changes, but the total printed height stays identical.
    if (!xlsx.defineName(QStringLiteral("_xlnm.Print_Area"),
                         QStringLiteral("'Calicata'!$B$1:$BC$%1").arg(layout->first(89)),
                         QString(), QStringLiteral("Calicata"))) {
        if (error) *error = QStringLiteral("No se pudo ajustar el área de impresión de la ficha.");
        return false;
    }
    return true;
}

bool writeScaledProfile(QXlsx::Document &xlsx, const QVariantList &cortes,
                        const QVariantMap &header, double totalDepth,
                        NativeProfileLayout *layout, QString *error)
{
    const double axisDepth = totalDepth > 0 ? totalDepth : 3.0;
    if (!prepareNativeProfileRows(xlsx, cortes, header, axisDepth, layout, error)) return false;
    QHash<QString, QImage> patterns;
    for (int i = 0; i <= 6; ++i) {
        const int row = layout->fractionRow(double(i) / 6.0) - 1;
        QXlsx::Format fmt = formatAt(xlsx, row, 3);
        fmt.setNumberFormat(QStringLiteral("0.00"));
        fmt.setShrinkToFit(true);
        fmt.setVerticalAlignment(QXlsx::Format::AlignBottom);
        xlsx.mergeCells(QXlsx::CellRange(row, 3, row, 4), fmt);
        xlsx.write(row, 3, i == 6 ? axisDepth : axisDepth * i / 6.0, fmt);
    }
    for (int index = 0; index < cortes.size(); ++index) {
        const QVariantMap corte = cortes.at(index).toMap();
        double de = 0, a = 0;
        depthValue(corte, {QStringLiteral("de"), QStringLiteral("desde")}, &de);
        depthValue(corte, {QStringLiteral("a"), QStringLiteral("hasta")}, &a);
        const int r1 = layout->boundaryRow(de), r2 = layout->boundaryRow(a) - 1;
        // Every contact has its own row boundary, including very thin strata.
        // Text and laboratory values belong to native cells in the printed form.
        for (int col = 5; col <= 46; ++col) {
            QXlsx::Format fmt = formatAt(xlsx, r1, col);
            fmt.setTopBorderStyle(QXlsx::Format::BorderThin);
            xlsx.write(r1, col, QVariant(), fmt);
            fmt = formatAt(xlsx, r2, col);
            fmt.setBottomBorderStyle(QXlsx::Format::BorderThin);
            xlsx.write(r2, col, QVariant(), fmt);
        }
        xlsx.mergeCells(QXlsx::CellRange(r1, 10, r2, 16));
        mergeVerticalColumns(xlsx, 17, 46, r1, r2);
        const auto sucsPattern = [&](int first, int last, const QString &code) {
            if (!patterns.contains(code)) {
                const QImage tile = webSucsExportTile(code);
                if (tile.isNull()) return false;
                patterns.insert(code, tile);
            }
            // Only the graphic pattern E:I is an image. Direct cell anchors
            // preserve sub-pixel row heights without rasterizing any data text.
            // The anchored image already has the stratum's exact proportions
            // (repeated + cropped pattern), so the anchor never stretches it.
            const QImage tile = patterns.value(code);
            const QSize box(rangeWidthPixels(xlsx, first, last), rangeHeightPixels(xlsx, r1, r2));
            const QImage fill = tiledProfilePattern(tile, box, 0.5);   // la tesela ya viene a 2x (34 px)
            return !fill.isNull() && xlsx.insertImageTwoCell(r1 - 1, first - 1, QPoint(),
                                                            r2, last, QPoint(), fill) > 0;
        };
        // Trama = laboratorio (Web profileSucsCodes): compuesta divide E:G | H:I.
        const ExportClassification classification = exportClassificationFor(corte);
        const QString sucs = classification.label;
        bool patternOk = true;
        if (!classification.primary.isEmpty())
            patternOk = classification.secondary.isEmpty()
                ? sucsPattern(5, 9, classification.primary)
                : sucsPattern(5, 7, classification.primary) && sucsPattern(8, 9, classification.secondary);
        if (!patternOk) {
            if (error) *error = QStringLiteral("Estrato %1: no se pudo cargar su trama registrada.").arg(index + 1);
            return false;
        }
        QString desc = corteText(corte, {QStringLiteral("descripcion")}, {}, QStringLiteral("txtDescripcion"));
        const QString origin = corte.value(QStringLiteral("material_origin")).toString().trimmed();
        if (!origin.isEmpty()) desc = origin + (desc.isEmpty() ? QString() : QStringLiteral("\n") + desc);
        // Layer boundaries are distinct from sample boundaries (AE).
        desc = QStringLiteral("%1–%2 m\n").arg(de, 0, 'f', 2).arg(a, 0, 'f', 2) + desc;
        // Preserve the original template font, alignment and wrapping.
        xlsx.write(r1, 10, desc, formatAt(xlsx, r1, 10));
        const int conditions[] = {humedadIndex(corte), excavabilidadIndex(corte), estabilidadIndex(corte)};
        for (int group = 0; group < 3; ++group) {
            if (conditions[group] >= 0)
                for (int row = r1; row <= r2; ++row)
                    shadeCellPreservingFormat(xlsx, row, 18 + group * 4 + conditions[group]);
        }
        const auto writeNativeText = [&](int col, const QString &text) {
            QXlsx::Format fmt = formatAt(xlsx, r1, col);
            fmt.setRotation(90);
            fmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
            fmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
            fmt.setShrinkToFit(true);
            xlsx.write(r1, col, text, fmt);
        };
        QString tipo = corteText(corte, {QStringLiteral("tipo_muestra"), QStringLiteral("muestra"), QStringLiteral("tipoText")}, QStringLiteral("txtTipo"));
        if (tipo.compare(QStringLiteral("Otro"), Qt::CaseInsensitive) == 0)
            tipo = firstText(corte, {QStringLiteral("tipo_otro"), QStringLiteral("tipoText")});
        double sf = de, st = a;
        depthValue(corte, {QStringLiteral("muestra_desde"), QStringLiteral("sample_from")}, &sf);
        depthValue(corte, {QStringLiteral("muestra_hasta"), QStringLiteral("sample_to")}, &st);
        writeNativeText(30, tipo);
        writeNativeText(31, QStringLiteral("%1-%2").arg(sf, 0, 'f', 2).arg(st, 0, 'f', 2));
        writeNativeText(32, corteText(corte, {QStringLiteral("resultado"), QStringLiteral("resultados")}));
        writeNativeText(33, classification.aashto);
        writeNativeText(34, sucs);
        const char *flat[] = {"gmax", "g2", "g04", "g008", "g002", "wl", "lp", "hum2"};
        const char *nested[] = {"txtGranuloMax", "txtGranulo2mm", "txtGranulo0_4mm", "txtGranulo0_08mm", "txtGranulo2Micra", "txtWL", "txtLP", "txtHumedad"};
        for (int col = 0; col < 8; ++col) {
            const QString key = QString::fromLatin1(flat[col]);
            QString text = corteText(corte, {key}, QString::fromLatin1(nested[col]));
            QXlsx::Format fmt = formatAt(xlsx, r1, 35 + col);
            fmt.setRotation(90);
            fmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
            fmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
            fmt.setShrinkToFit(true);
            xlsx.write(r1, 35 + col, QVariant(), fmt);
            if (col < 5 || col == 7) {
                if (corte.value(QStringLiteral("percentage_fields")).toStringList().contains(key)
                    && !text.contains(QLatin1Char('%')) && !text.isEmpty()) text += QLatin1Char('%');
                fmt.setNumberFormat(col == 0 ? QStringLiteral("0%") : col == 7 ? QStringLiteral("0.00%") : QStringLiteral("0.0%"));
                xlsx.write(r1, 35 + col, QVariant(), fmt);
                writePercentageTemplateValue(xlsx, QXlsx::CellReference(r1, 35 + col).toString(), text);
            } else {
                writeTemplateValue(xlsx, QXlsx::CellReference(r1, 35 + col).toString(), text);
            }
        }
    }
    const bool waterPresent = header.contains(QStringLiteral("water_table_present"))
        ? variantBool(header, QStringLiteral("water_table_present"))
        : variantBool(header, QStringLiteral("waterTablePresent"));
    double waterDepth = 0;
    // Perfil > "Mostrar nivel freático" (header.profile_setup.show_water_table,
    // activo por defecto) gobierna la representación gráfica; el texto de
    // Observaciones ("Nivel freático: x m") se mantiene siempre.
    const QVariantMap profileSetup = header.value(QStringLiteral("profile_setup")).toMap();
    const bool showWater = !profileSetup.contains(QStringLiteral("show_water_table"))
        || profileSetup.value(QStringLiteral("show_water_table")).toBool();
    if (showWater && waterPresent
        && depthValue(header, {QStringLiteral("water_table_depth"), QStringLiteral("waterTableDepth")}, &waterDepth)
        && waterDepth >= 0 && waterDepth < axisDepth) {
        // Misma transformación profundidad → fila que los estratos (la cota del
        // NF ya es un límite del layout). Como la ficha oficial C-AA-01: columna
        // N.F. (Q) combinada desde el NF hasta el fondo, relleno azul claro e
        // indicador rojo con la cota en el borde superior.
        const int top = qMin(layout->endRow, layout->boundaryRow(waterDepth));
        const int bottom = layout->endRow;
        for (const auto &range : xlsx.currentWorksheet()->mergedCells())
            if (range.firstColumn() == 17 && range.lastColumn() == 17
                && range.firstRow() <= bottom && range.lastRow() >= top) xlsx.unmergeCells(range);
        QXlsx::Format water = formatAt(xlsx, top, 17);
        // C-AA-01: relleno sólido tema 3 (1F497D) con tinte 0.8 = #C6D9F1, sin
        // borde adicional (los bordes dobles laterales vienen de la plantilla).
        // La cota roja de la referencia es un cuadro flotante (QXlsx no crea
        // shapes): aquí va en la primera celda del relleno, horizontal y sin
        // reducción (la columna N.F. de 5.3 caracteres admite "0.75"/"1.4").
        water.setFillPattern(QXlsx::Format::PatternSolid);
        water.setPatternBackgroundColor(QColor(QStringLiteral("#C6D9F1")));
        water.setFontColor(QColor(QStringLiteral("#FF0000")));
        water.setFontBold(true);
        water.setRotation(0);
        water.setShrinkToFit(false);
        water.setTextWrap(false);
        water.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
        water.setVerticalAlignment(QXlsx::Format::AlignTop);
        if (bottom > top)
            xlsx.mergeCells(QXlsx::CellRange(top, 17, bottom, 17), water);
        // "1.4", "0.75", "2.35": misma notación corta que la ficha oficial.
        xlsx.write(top, 17, QString::number(waterDepth, 'g', 4), water);
    }
    return true;
}

// Cuerpo del nombre contractual en AG4:BC6. La ficha oficial C-AA-02 usa 22 pt
// con un nombre de ~230 caracteres en wrap; se reduce de forma moderada solo
// para nombres más largos (nunca se trunca).
int projectTitleFontSize(const QString &title)
{
    const int n = title.trimmed().size();
    if (n <= 240) return 22;
    if (n <= 320) return 18;
    if (n <= 420) return 16;
    return 14;
}

bool fillOfficialCalicataTemplate(QXlsx::Document &xlsx,
                                  const QVariantMap &state,
                                  ReportImages &reportImages,
                                  QString *error)
{
    if (!xlsx.selectSheet(QStringLiteral("Calicata"))) {
        if (error) *error = QStringLiteral("La plantilla no contiene la hoja Calicata.");
        return false;
    }

    const QVariantMap header = headerFromState(state);
    const QVariantMap timestamp = state.value(QStringLiteral("timestamp")).toMap();

    QString title = exportProjectName(header, timestamp);
    if (title.isEmpty())
        title = QStringLiteral("Proyecto / servicio");

    // Bloque combinado AG4:BC6 de la plantilla, como la ficha oficial: Arial
    // Narrow negrita blanca, centrado y con AJUSTE DE TEXTO (wrap). Nunca se
    // trunca ni se usa shrinkToFit (en Excel anula el wrap y vuelve ilegible
    // un nombre contractual largo); solo una reducción moderada del cuerpo.
    QXlsx::Format titleFmt = formatAt(xlsx, 4, 33); // AG4
    if (!titleFmt.isValid()) titleFmt = fmtCentered();
    titleFmt.setFontName(QStringLiteral("Arial Narrow"));
    titleFmt.setFontBold(true);
    titleFmt.setFontColor(QColor(Qt::white));
    titleFmt.setShrinkToFit(false);
    titleFmt.setTextWrap(true);
    titleFmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    titleFmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    titleFmt.setFontSize(projectTitleFontSize(title));
    xlsx.write(QStringLiteral("AG4"), title, titleFmt);

    // "Título de la ficha / testificación" (calicatas.description): banda
    // TESTIFICACIÓN DE CALICATA (AG1:BC3) de la plantilla. Nunca reemplaza al
    // proyecto (AG4:BC6), que es otra semántica.
    const QString testification = firstText(header, { QStringLiteral("description") });
    if (!testification.isEmpty()) {
        QXlsx::Format bandFmt = formatAt(xlsx, 1, 33); // AG1
        if (!bandFmt.isValid()) bandFmt = fmtTitle();
        bandFmt.setTextWrap(true);
        bandFmt.setShrinkToFit(true);
        bandFmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
        bandFmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
        xlsx.write(QStringLiteral("AG1"), QStringLiteral("TESTIFICACIÓN DE CALICATA\n") + testification, bandFmt);
    }

    const QString supervisor = firstText(header, { QStringLiteral("supervisor") });
    const QString maquina = firstText(header, { QStringLiteral("maquina") });
    const QString lado = firstText(header, { QStringLiteral("lado_via") });
    const QString pk = canonicalPk(header);
    const QString utmX = firstText(header, { QStringLiteral("utm_x"), QStringLiteral("longitud") });
    const QString utmY = firstText(header, { QStringLiteral("utm_y"), QStringLiteral("latitud") });
    QString altitud = firstText(header, { QStringLiteral("utm_z"), QStringLiteral("altitud") });
    if (altitud.isEmpty()) altitud = firstText(timestamp, { QStringLiteral("altitud") });
    const QString zona = firstText(header, { QStringLiteral("zona") });
    const QString calicata = canonicalCalicataCode(header, timestamp);

    if (!supervisor.isEmpty()) xlsx.write(QStringLiteral("AJ9"), supervisor);
    if (!maquina.isEmpty()) xlsx.write(QStringLiteral("AJ10"), maquina);
    if (!lado.isEmpty()) xlsx.write(QStringLiteral("AJ11"), lado);
    if (!pk.isEmpty()) writeTemplateValue(xlsx, QStringLiteral("AT8"), pk);
    if (!utmX.isEmpty()) writeTemplateValue(xlsx, QStringLiteral("AT9"), utmX);
    if (!utmY.isEmpty()) writeTemplateValue(xlsx, QStringLiteral("AT10"), utmY);
    if (!altitud.isEmpty()) writeTemplateValue(xlsx, QStringLiteral("AT11"), altitud);
    if (!zona.isEmpty()) xlsx.write(QStringLiteral("AW10"), zona);
    // Código visible de la calicata dentro del documento (AY9:AZ11), con el
    // formato propio de la plantilla; no depende del nombre del archivo.
    if (!calicata.isEmpty()) {
        QXlsx::Format codeFmt = formatAt(xlsx, 9, 51); // AY9
        if (!codeFmt.isValid()) codeFmt = fmtCentered();
        codeFmt.setShrinkToFit(false);
        codeFmt.setTextWrap(true);
        codeFmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
        codeFmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
        xlsx.write(QStringLiteral("AY9"), calicata, codeFmt);
    }

    const QString fechaInicio = formatDateForTemplate(firstText(header, { QStringLiteral("fecha_inicio"), QStringLiteral("fecha") }));
    const QString fechaFin = formatDateForTemplate(firstText(header, { QStringLiteral("fecha_fin"), QStringLiteral("fecha") }));
    if (!fechaInicio.isEmpty()) xlsx.write(QStringLiteral("AU8"), QStringLiteral("Fecha inicio: ") + fechaInicio);
    if (!fechaFin.isEmpty()) xlsx.write(QStringLiteral("AU9"), QStringLiteral("Fecha fin: ") + fechaFin);

    const QVariantList cortes = cortesFromState(state);
    double recordedDepth = 0.0;
    for (const auto &value : cortes) {
        double to = 0.0;
        if (depthValue(value.toMap(), {QStringLiteral("a"), QStringLiteral("hasta")}, &to))
            recordedDepth = qMax(recordedDepth, to);
    }
    const QVariant requested = header.value(QStringLiteral("requested_depth_m"), header.value(QStringLiteral("depth_m")));
    double parsedRequested = 0.0;
    if (!scalarText(requested).isEmpty()
        && (!isSimpleNumber(requested, &parsedRequested) || !std::isfinite(parsedRequested) || parsedRequested < 0)) {
        if (error) *error = QStringLiteral("La profundidad total debe ser un número finito mayor o igual que cero.");
        return false;
    }
    const double totalDepth = parsedRequested > 0 ? parsedRequested : recordedDepth;
    if (!std::isfinite(totalDepth)) {
        if (error) *error = QStringLiteral("No se pudo resolver la profundidad total de la ficha.");
        return false;
    }
    writeTemplateValue(xlsx, QStringLiteral("BA9"), 1);
    xlsx.write(QStringLiteral("BA10"), QStringLiteral("DE 1"));
    NativeProfileLayout layout;
    if (!writeScaledProfile(xlsx, cortes, header, totalDepth, &layout, error)) return false;
    // Fin en el borde inferior de la plantilla, aunque falte describir un tramo.
    const int finRow = layout.first(82);
    QXlsx::Format fin = formatAt(xlsx, finRow, 17);
    fin.setFontBold(true);
    fin.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    xlsx.mergeCells(QXlsx::CellRange(finRow, 17, finRow, 46), fin);
    xlsx.write(finRow, 17, QStringLiteral("FIN DE LA CALICATA — %1 m").arg(totalDepth, 0, 'f', 2), fin);

    const QString observations = structuredObservations(
        header, totalDepth,
        state.value(QStringLiteral("observaciones")).toString());
    xlsx.write(layout.first(84), 34, observations);

    // Logos (B6:O9, P6:AF9) y fotos (AU22:BC41, AU43:BC61, AU63:BC82) en cada hoja.
    static const int kImageRanges[5][4] = {
        { 6, 2, 9, 15 }, { 6, 16, 9, 32 }, { 21, 47, 41, 55 }, { 43, 47, 61, 55 }, { 63, 47, 82, 55 }
    };
    for (int slot = 0; slot < 5; ++slot) {
        QImage &image = reportImages[slot];
        if (image.isNull())
            continue;   // foto aún no tomada: la celda queda en blanco
        const int *range = kImageRanges[slot];
        const int firstRow = layout.first(range[0]);
        const int lastRow = layout.last(range[2]);
        const QSize slotSize(rangeWidthPixels(xlsx, range[1], range[3]),
                             rangeHeightPixels(xlsx, firstRow, lastRow));
        const QSize fitted = image.size().scaled(slotSize, Qt::KeepAspectRatio);
        // Identical template geometry on subsequent sheets reuses these pixels.
        if (image.size() != fitted)
            image = image.scaled(fitted, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        if (image.dotsPerMeterX() != kExcelDpm96) image.setDotsPerMeterX(kExcelDpm96);
        if (image.dotsPerMeterY() != kExcelDpm96) image.setDotsPerMeterY(kExcelDpm96);
        if (!insertImageFitted(xlsx, firstRow, range[1], lastRow, range[3], image, false)) {
            if (error) *error = QStringLiteral("No se pudo insertar %1 en el Excel.")
                                    .arg(QString::fromUtf8(kReportImageSlots[slot].label));
            return false;
        }
    }

    return true;
}

bool copyOfficialTemplate(const QString &outPath, QString *error)
{
    const QString resource = QStringLiteral(":/templates/Calicata_Formato.xlsx");
    if (!QFileInfo::exists(resource)) {
        if (error) *error = QStringLiteral("No se encontro la plantilla embebida: ") + resource;
        return false;
    }

    QFile::remove(outPath);
    if (!QFile::copy(resource, outPath)) {
        if (error) *error = QStringLiteral("No se pudo copiar la plantilla oficial a: ") + outPath;
        return false;
    }
    return true;
}

#endif

#ifdef Q_OS_ANDROID
bool copyFileToMediaStoreDownloads(const QString &sourcePath, const QString &displayName,
                                   const QString &mimeType, QString *publicHint,
                                   QString *error)
{
    QFile input(sourcePath);
    if (!input.open(QIODevice::ReadOnly)) {
        if (error) *error = QStringLiteral("No se pudo abrir temporal: ") + input.errorString();
        return false;
    }

    // Qt Android: se evita incluir <QNativeInterface>, porque en este kit no existe
    // como cabecera publica. Obtenemos el Context usando JNI directo.
    QJniObject context;
    QJniObject activityThread = QJniObject::callStaticObjectMethod(
        "android/app/ActivityThread",
        "currentActivityThread",
        "()Landroid/app/ActivityThread;");

    if (activityThread.isValid()) {
        context = activityThread.callObjectMethod(
            "getApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid()) {
        context = QJniObject::callStaticObjectMethod(
            "android/app/ActivityThread",
            "currentApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid()) {
        if (error) *error = QStringLiteral("Contexto Android no disponible.");
        return false;
    }

    QJniObject resolver = context.callObjectMethod("getContentResolver", "()Landroid/content/ContentResolver;");
    if (!resolver.isValid()) {
        if (error) *error = QStringLiteral("ContentResolver no disponible.");
        return false;
    }

    QJniObject values("android/content/ContentValues", "()V");
    auto putString = [&](const char *key, const QString &value) {
        QJniObject jkey = QJniObject::fromString(QString::fromLatin1(key));
        QJniObject jvalue = QJniObject::fromString(value);
        values.callMethod<void>("put", "(Ljava/lang/String;Ljava/lang/String;)V", jkey.object<jstring>(), jvalue.object<jstring>());
    };
    auto putInt = [&](const char *key, int value) {
        QJniObject jkey = QJniObject::fromString(QString::fromLatin1(key));
        QJniObject jint("java/lang/Integer", "(I)V", value);
        values.callMethod<void>("put", "(Ljava/lang/String;Ljava/lang/Integer;)V", jkey.object<jstring>(), jint.object<jobject>());
    };

    putString("_display_name", displayName);
    putString("mime_type", mimeType);
    putString("relative_path", QStringLiteral("Download/InGePlus"));
    putInt("is_pending", 1);

    QJniObject collection = QJniObject::getStaticObjectField("android/provider/MediaStore$Downloads", "EXTERNAL_CONTENT_URI", "Landroid/net/Uri;");
    if (!collection.isValid()) {
        if (error) *error = QStringLiteral("MediaStore Downloads no disponible.");
        return false;
    }

    QJniObject uri = resolver.callObjectMethod("insert", "(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;", collection.object<jobject>(), values.object<jobject>());
    if (!uri.isValid()) {
        if (error) *error = QStringLiteral("No se pudo crear archivo en Descargas/InGePlus.");
        return false;
    }

    QJniObject out = resolver.callObjectMethod("openOutputStream", "(Landroid/net/Uri;)Ljava/io/OutputStream;", uri.object<jobject>());
    if (!out.isValid()) {
        if (error) *error = QStringLiteral("No se pudo abrir stream de escritura Android.");
        return false;
    }

    QJniEnvironment env;
    bool ok = true;
    while (!input.atEnd()) {
        const QByteArray chunk = input.read(64 * 1024);
        jbyteArray arr = env->NewByteArray(chunk.size());
        env->SetByteArrayRegion(arr, 0, chunk.size(), reinterpret_cast<const jbyte *>(chunk.constData()));
        out.callMethod<void>("write", "([BII)V", arr, 0, chunk.size());
        env->DeleteLocalRef(arr);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            ok = false;
            break;
        }
    }

    out.callMethod<void>("flush", "()V");
    out.callMethod<void>("close", "()V");
    input.close();

    values.callMethod<void>("clear", "()V");
    putInt("is_pending", 0);
    resolver.callMethod<jint>("update", "(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I", uri.object<jobject>(), values.object<jobject>(), nullptr, nullptr);

    if (!ok) {
        if (error) *error = QStringLiteral("Error copiando bytes al archivo publico.");
        return false;
    }

    if (publicHint) *publicHint = QStringLiteral("Descargas/InGePlus/") + displayName;
    return true;
}
#endif

} // namespace

AndroidCalicataExporter::AndroidCalicataExporter(QObject *parent)
    : QObject(parent)
{
#ifdef Q_OS_ANDROID
    if (appContext() && appContext()->auth()) {
        const auto clearAccount = [this] {
            m_exportResult.clear(); m_exportProject.clear(); m_exportLogicalPath.clear();
            m_publishedFiles.clear(); m_publishedUser.clear(); emit exportResultChanged();
        };
        connect(appContext()->auth(), &AuthSession::loggedOut, this, clearAccount);
        connect(appContext()->auth(), &AuthSession::accountSwitchStarted, this,
            [clearAccount](const QString &) { clearAccount(); });
    }
#endif
}

QString AndroidCalicataExporter::lastError() const
{
    return m_lastError;
}

QVariantMap AndroidCalicataExporter::lastExportResult() const
{
    auto result = m_exportResult;
#ifdef Q_OS_ANDROID
    const QString localExportPath = result.value("localPhysicalPath").toString();
    if (m_exports && !m_exportLogicalPath.isEmpty()) {
        const auto current = m_exports->resultFor(m_exportProject, m_exportLogicalPath,
            result.value("provider","SUPABASE").toString());
        for (auto it = current.cbegin(); it != current.cend(); ++it) result[it.key()] = it.value();
    }
    // Keep the readable export name when opening/sharing the workbook. The
    // outbox mirror has a hash-based name used for synchronization identity.
    if (!localExportPath.isEmpty() && QFileInfo(localExportPath).isFile()) {
        result["localPhysicalPath"] = localExportPath;
        result["localPath"] = localExportPath;
        result["fileName"] = QFileInfo(localExportPath).fileName();
    }
#endif
    return result;
}

void AndroidCalicataExporter::retryPendingExports()
{
#ifdef Q_OS_ANDROID
    if (m_exports && !m_exportLogicalPath.isEmpty()) {
        if (!m_exports->retryDocument(m_exportProject, m_exportLogicalPath,
                                     m_exportResult.value("provider", "SUPABASE").toString())) {
            setLastError(QStringLiteral("No se pudo reintentar esta exportación. El archivo local se conserva."));
            m_exportResult["syncState"]="ERROR";m_exportResult["error"]=lastError();
        }
        emit exportResultChanged();
    } else if (m_exports) m_exports->retry();
#endif
}

bool AndroidCalicataExporter::openLastExport(bool share)
{
    const auto path = lastExportResult().value("localPhysicalPath").toString();
    if (path.isEmpty() || !QFileInfo(path).isFile()) {
        setLastError(QStringLiteral("El mirror del Excel no está disponible.")); return false;
    }
#ifdef Q_OS_ANDROID
    const auto context = QNativeInterface::QAndroidApplication::context();
    const auto file = QJniObject::fromString(path);
    const auto result = QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge", "open",
        "(Landroid/content/Context;Ljava/lang/String;ZZ)Ljava/lang/String;",
        context.object(), file.object<jstring>(), jboolean(share), jboolean(share));
    QJniEnvironment env;
    if (env->ExceptionCheck()) { env->ExceptionClear(); setLastError(QStringLiteral("No se pudo abrir el Excel.")); return false; }
    if (!result.isValid()) { setLastError(QStringLiteral("Android no respondió al abrir el Excel.")); return false; }
    setLastError(result.toString()); return result.toString().isEmpty();
#else
    Q_UNUSED(share);
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
#endif
}

bool AndroidCalicataExporter::publishCalicata(const QVariantMap &state, const QString &xlsxPath)
{
#ifdef Q_OS_ANDROID
    // This workbook already belongs to the Google outbox. Only the editable
    // JSON follows the existing Supabase publication path.
    if (!xlsxPath.isEmpty() && m_exportResult.value("provider")=="GOOGLE_DRIVE"
        && xlsxPath==m_exportResult.value("localPhysicalPath").toString())
        return publishCalicata(state, {});
    // Validation never gates publication (advisory only).
    const auto header = state.value("header").toMap();
    const auto project = header.value("projectId").toString();
    const auto document = state.value("instance_id").toString();
    auto *ctx = appContext();
    if (!ctx || !ctx->auth()->logged() || QUuid(project).isNull() || QUuid(document).isNull()
        || (!xlsxPath.isEmpty() && !QFileInfo(xlsxPath).isFile())) {
        setLastError(QStringLiteral("Selecciona un proyecto e inicia sesión antes de publicar."));
        return false;
    }
    m_exports = RenditionExportService::shared(ctx->supabase(), ctx->auth());
    const auto user = ctx->auth()->userId();
    if (m_publishedUser != user) { m_publishedFiles.clear(); m_publishedUser = user; }
    const auto bytes = QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact);
    const auto hash = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
    const auto stem = safeFileName(header.value("codigo").toString()) + '_' + document
        + '_' + QString::fromLatin1(hash.left(20));
    const auto snapshotPath = QDir(defaultExportDir()).filePath(stem + ".calicata.json");
    QSaveFile snapshot(snapshotPath);
    if (!snapshot.open(QIODevice::WriteOnly) || snapshot.write(bytes) != bytes.size() || !snapshot.commit()) {
        setLastError(QStringLiteral("No se pudo conservar la ficha portable.")); return false;
    }
    const auto remoteEdit = "Calicatas/Edit/" + stem + ".calicata.json";
    const QString calicataId = header.value("remoteCalicataId", header.value("remote_calicata_id")).toString();
    QString remoteExcel;
    if (!xlsxPath.isEmpty()) {
        if (m_exportProject == project && (xlsxPath == m_exportResult.value("localPhysicalPath").toString()
            || xlsxPath == lastExportResult().value("localPhysicalPath").toString())) {
            remoteExcel = m_exportLogicalPath; // Same operation staged during generation.
        } else {
            QFile file(xlsxPath);
            if (!file.open(QIODevice::ReadOnly)) { setLastError(QStringLiteral("No se pudo leer el XLSX.")); return false; }
            const auto xlsxHash = QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex();
            remoteExcel = "Calicatas/exports/" + safeFileName(header.value("codigo").toString())
                + '_' + QString::fromLatin1(xlsxHash.left(20)) + ".xlsx";
        }
        m_publishedFiles[document] = xlsxPath; // Open/share does not wait for connectivity.
    }
    const QPointer<AndroidCalicataExporter> guard(this);
    const auto notified = std::make_shared<bool>(false);
    const auto completion = [guard, user, document, project, remoteEdit, remoteExcel, notified](bool ok, const QString &error) {
        if (!guard || !appContext() || !appContext()->auth()->logged() || appContext()->auth()->userId() != user) return;
        emit guard->exportResultChanged();
        if (!ok) { emit guard->calicataPublishFailed(document, error); return; }
        if (*notified || !guard->m_exports->resultFor(project, remoteEdit).value("success").toBool()) return;
        if (remoteExcel.isEmpty()) {
            *notified = true; emit guard->calicataSavedOnline(document); return;
        }
        const auto exported = guard->m_exports->resultFor(project, remoteExcel);
        if (!exported.value("success").toBool()) return;
        *notified = true;
        guard->m_publishedFiles[document] = exported.value("localPhysicalPath").toString();
        emit guard->calicataPublished(document);
    };
    if (!m_exports->enqueueDocument(snapshotPath, project, remoteEdit, completion)
        || (!xlsxPath.isEmpty() && !m_exports->enqueueDocument(xlsxPath, project, remoteExcel, completion,
            remoteEdit, calicataId, "SUPABASE", true,
            safeFileName(QString(canonicalCalicataCode(header)).remove('*')) + ".xlsx"))) {
        setLastError(QStringLiteral("No se pudo registrar la publicación; los archivos locales se conservan."));
        return false;
    }
    setLastError({});
    return true;
#else
    Q_UNUSED(state); Q_UNUSED(xlsxPath);
    setLastError(QStringLiteral("La publicación online de Calicatas requiere la sesión Android."));
    return false;
#endif
}


bool AndroidCalicataExporter::sharePublishedCalicata(const QString &documentId)
{
#ifdef Q_OS_ANDROID
    if (!appContext() || !appContext()->auth()->logged()
        || m_publishedUser != appContext()->auth()->userId()) return false;
    const auto path = m_publishedFiles.value(documentId);
    if (path.isEmpty() || !QFileInfo::exists(path)) {
        setLastError(QStringLiteral("La copia temporal ya no está disponible; vuelve a exportar."));
        return false;
    }
    const auto context = QNativeInterface::QAndroidApplication::context();
    const auto file = QJniObject::fromString(path);
    const auto result = QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge", "open",
        "(Landroid/content/Context;Ljava/lang/String;ZZ)Ljava/lang/String;",
        context.object(), file.object<jstring>(), jboolean(true), jboolean(true));
    QJniEnvironment env;
    if (env->ExceptionCheck()) { env->ExceptionClear(); setLastError(QStringLiteral("No se pudo abrir Compartir.")); return false; }
    if (!result.isValid()) { setLastError(QStringLiteral("Android no respondió al abrir Compartir.")); return false; }
    setLastError(result.toString());
    return result.toString().isEmpty();
#else
    Q_UNUSED(documentId); return false;
#endif
}

void AndroidCalicataExporter::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

QString AndroidCalicataExporter::safeFileName(QString name) const
{
    name = name.trimmed();
    if (name.isEmpty())
        name = QStringLiteral("calicata");
    if (name.endsWith(QStringLiteral(".xlsx"), Qt::CaseInsensitive))
        name.chop(5);
    name.replace(QRegularExpression(QStringLiteral("[<>:\"/\\\\|?*\\x00-\\x1F]")),
                 QStringLiteral("_"));
    while (name.contains(QStringLiteral("__")))
        name.replace(QStringLiteral("__"), QStringLiteral("_"));
    name = name.trimmed();
    while (name.endsWith(QLatin1Char('.')) || name.endsWith(QLatin1Char(' ')))
        name.chop(1);
    return (name.isEmpty() ? QStringLiteral("calicata") : name).left(120);
}

QString AndroidCalicataExporter::defaultExportDir() const
{
#ifdef Q_OS_ANDROID
    // Pending exports must not live in an OS-evictable cache.
    const QString staging = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (!staging.isEmpty()) {
        const auto user = appContext() && appContext()->auth() ? appContext()->auth()->userId() : QString();
        QDir d(staging + "/inge-drive/" + (QUuid(user).isNull() ? QStringLiteral("unassigned") : user));
        d.mkpath(QStringLiteral("Exportaciones"));
        return d.filePath(QStringLiteral("Exportaciones"));
    }
#endif

    QStringList candidates;
    const QString download = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!download.isEmpty()) candidates << QDir(download).filePath(QStringLiteral("InGePlus/Exportaciones"));
    const QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (!docs.isEmpty()) candidates << QDir(docs).filePath(QStringLiteral("InGePlus/Exportaciones"));
    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (!appData.isEmpty()) candidates << QDir(appData).filePath(QStringLiteral("Exportaciones"));
    candidates << QDir(QDir::homePath()).filePath(QStringLiteral("InGePlus/Exportaciones"));

    for (const QString &candidate : candidates) {
        QDir d(candidate);
        if (!d.exists() && !d.mkpath(QStringLiteral(".")))
            continue;
        const QString probe = d.filePath(QStringLiteral(".inge_write_test"));
        QFile f(probe);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write("ok");
            f.close();
            QFile::remove(probe);
            return d.absolutePath();
        }
    }

    return QDir::homePath();
}

QString AndroidCalicataExporter::makeOutputPath(const QString &fileBaseName) const
{
    return makeOutputPathWithExtension(fileBaseName, QStringLiteral("xlsx"));
}

QString AndroidCalicataExporter::makeOutputPathWithExtension(
    const QString &fileBaseName, const QString &extension) const
{
    const QString name = safeFileName(fileBaseName.isEmpty()
                                          ? QStringLiteral("calicata")
                                          : fileBaseName);
    const QString extensionSuffix = QStringLiteral(".") + extension;
    const QDir dir(defaultExportDir());
    const QString professionalPath = dir.filePath(name + extensionSuffix);
    if (!QFileInfo::exists(professionalPath))
        return professionalPath;

    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    QString fallback = dir.filePath(name + QStringLiteral("_") + stamp + extensionSuffix);
    for (int collisionIndex = 2; QFileInfo::exists(fallback); ++collisionIndex) {
        fallback = dir.filePath(name + QStringLiteral("_") + stamp
                                + QStringLiteral("_") + QString::number(collisionIndex)
                                + extensionSuffix);
    }
    return fallback;
}

QVariantMap AndroidCalicataExporter::readJsonObject(const QString &jsonPath)
{
    QFile f(jsonPath);
    if (!f.open(QIODevice::ReadOnly)) {
        setLastError(QStringLiteral("No se pudo abrir JSON: ") + f.errorString());
        return {};
    }

    const QByteArray raw = f.readAll();
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        setLastError(QStringLiteral("JSON inválido: ") + pe.errorString());
        return {};
    }

    return doc.object().toVariantMap();
}

QVariantMap AndroidCalicataExporter::readWorkbookCells(const QString &path) const
{
    // Excel como entrada NO confiable: solo valores de celda y rangos combinados.
    // No se evalúan fórmulas, enlaces, macros (VBA) ni objetos incrustados.
    static constexpr qint64 kMaxBytes = 40 * 1024 * 1024;
    static constexpr int kMaxSheets = 12;
    static constexpr int kMaxRows = 2000;
    static constexpr int kMaxColumns = 200;
    static constexpr int kMaxCells = 60000;
    static constexpr int kMaxCellText = 8000;

    QVariantMap result;
    result[QStringLiteral("ok")] = false;
    const QString local = path.startsWith(QStringLiteral("file:"))
            ? QUrl(path).toLocalFile() : path;
    const QFileInfo info(local);
    if (local.isEmpty() || !info.exists() || !info.isFile()) {
        result[QStringLiteral("error")] = QStringLiteral("No se encontró el archivo Excel.");
        return result;
    }
    if (info.suffix().compare(QStringLiteral("xlsx"), Qt::CaseInsensitive) != 0) {
        result[QStringLiteral("error")] = QStringLiteral("Solo se pueden abrir archivos .xlsx.");
        return result;
    }
    if (info.size() <= 0 || info.size() > kMaxBytes) {
        result[QStringLiteral("error")] = QStringLiteral("El archivo Excel es demasiado grande o está vacío.");
        return result;
    }
    QFile file(local);
    if (!file.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("error")] = QStringLiteral("No se pudo leer el archivo Excel.");
        return result;
    }
    // Firma ZIP (OOXML). Un .xlsx renombrado desde otro formato se rechaza.
    if (file.peek(2) != QByteArrayLiteral("PK")) {
        result[QStringLiteral("error")] = QStringLiteral("El archivo no es un libro .xlsx válido.");
        return result;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    file.close();
    result[QStringLiteral("sha256")] = QString::fromLatin1(hash.result().toHex());
    result[QStringLiteral("path")] = local;
    result[QStringLiteral("fileName")] = info.fileName();
    result[QStringLiteral("size")] = info.size();

#ifdef INGE_HAS_QXLSX
    QXlsx::Document xlsx(local);
    if (!xlsx.load()) {
        result[QStringLiteral("error")] = QStringLiteral("No se pudo abrir el libro Excel.");
        return result;
    }
    const QStringList names = xlsx.sheetNames();
    if (names.isEmpty() || names.size() > kMaxSheets) {
        result[QStringLiteral("error")] = QStringLiteral("El libro no tiene hojas legibles o tiene demasiadas.");
        return result;
    }
    int totalCells = 0;
    QVariantList sheets;
    for (const QString &name : names) {
        if (!xlsx.selectSheet(name)) continue;
        QXlsx::Worksheet *sheet = xlsx.currentWorksheet();
        if (!sheet) continue;
        QVariantMap cells;
        const QXlsx::CellRange dim = sheet->dimension();
        const bool truncated = dim.isValid() && (dim.lastRow() > kMaxRows || dim.lastColumn() > kMaxColumns);
        if (dim.isValid()) {
            const int lastRow = qMin(dim.lastRow(), kMaxRows);
            const int lastCol = qMin(dim.lastColumn(), kMaxColumns);
            for (int row = qMax(1, dim.firstRow()); row <= lastRow; ++row) {
                for (int col = qMax(1, dim.firstColumn()); col <= lastCol; ++col) {
                    const std::shared_ptr<QXlsx::Cell> cell = sheet->cellAt(row, col);
                    if (!cell) continue;
                    // Valor almacenado (resultado en caché si es fórmula; nunca se evalúa).
                    const QVariant value = cell->value();
                    QString text;
                    if (value.typeId() == QMetaType::Double || value.typeId() == QMetaType::Int
                        || value.typeId() == QMetaType::LongLong) {
                        const double number = value.toDouble();
                        text = std::isfinite(number) && std::floor(number) == number && std::fabs(number) < 1e15
                                ? QString::number(qint64(number)) : QString::number(number, 'g', 15);
                    } else {
                        text = value.toString();
                    }
                    if (text.trimmed().isEmpty()) continue;
                    if (++totalCells > kMaxCells) {
                        result[QStringLiteral("error")] = QStringLiteral("El libro contiene demasiadas celdas para importarlo.");
                        return result;
                    }
                    cells.insert(QXlsx::CellReference(row, col).toString(), text.left(kMaxCellText));
                }
            }
        }
        QVariantList merges;
        for (const QXlsx::CellRange &range : sheet->mergedCells())
            merges << range.toString();
        sheets << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("cells"), cells},
                              {QStringLiteral("merges"), merges}, {QStringLiteral("truncated"), truncated}};
    }
    result[QStringLiteral("sheets")] = sheets;
    result[QStringLiteral("ok")] = true;
#else
    result[QStringLiteral("error")] = QStringLiteral("QXlsx no está disponible en esta compilación.");
#endif
    return result;
}

QString AndroidCalicataExporter::exportJsonFileToXlsx(const QString &jsonPath, const QString &fileBaseName)
{
    QVariantMap state = readJsonObject(jsonPath);
    if (state.isEmpty())
        return QString();

    const QFileInfo fi(jsonPath);
    state.insert(QStringLiteral("_source_json_path"), fi.absoluteFilePath());
    return exportStateToXlsx(state, fileBaseName);
}

QString AndroidCalicataExporter::exportStateToXlsx(const QVariantMap &state, const QString &fileBaseName,
                                                 const QString &provider)
{
#ifdef INGE_HAS_QXLSX
    setLastError(QString());
    m_exportProject.clear(); m_exportLogicalPath.clear();
    m_exportResult = {{"success",false},{"syncState","ERROR"}};
    emit exportResultChanged();

    if (state.isEmpty()) {
        setLastError(QStringLiteral("No hay datos de calicata para exportar."));
        return QString();
    }
    if (provider != "GOOGLE_DRIVE" && provider != "SUPABASE") {
        setLastError(QStringLiteral("Selecciona Google Drive o InGeDrive para exportar."));
        return {};
    }

    // Review BLOCKERS are advisory: an incomplete ficha is still exported with
    // blank cells. Only technical failures below may stop the export.
    QString validationError;
    if (!validateOfficialState(state, &validationError))
        qInfo().noquote() << "INGE_CALICATA_EXPORT_ADVISORY" << validationError;

    const QVariantMap header = headerFromState(state);
    const QVariantMap timestamp = state.value(QStringLiteral("timestamp")).toMap();
    const QString reportCode = canonicalCalicataCode(header, timestamp);
    const QString visibleFileName = safeFileName(QString(reportCode).remove('*')) + ".xlsx";
#ifdef Q_OS_ANDROID
    // An operation directory isolates repeated codes without exposing IDs in filenames.
    const QString outPath = QDir(defaultExportDir()).filePath("workbooks/"
        + QUuid::createUuid().toString(QUuid::WithoutBraces) + '/' + visibleFileName);
#else
    const QString outPath = makeOutputPath(fileBaseName.trimmed().isEmpty() ? reportCode : fileBaseName);
#endif
#ifdef Q_OS_ANDROID
    const auto projectId = header.value("projectId", header.value("project_id")).toString();
    const auto logicalStem = "Calicatas/exports/" + safeFileName(reportCode)
        + '_' + safeFileName(state.value("instance_id").toString());
    const QString calicataId = header.value("remoteCalicataId", header.value("remote_calicata_id")).toString();
    auto *exportContext = appContext();
    if (exportContext && exportContext->auth() && exportContext->supabase())
        m_exports = RenditionExportService::shared(exportContext->supabase(), exportContext->auth());
    if (!m_exports || !m_exports->prepareGeneration(outPath, projectId, logicalStem, calicataId, provider, visibleFileName)) {
        setLastError(QStringLiteral("No se pudo registrar la exportación: selecciona proyecto y cuenta, y verifica espacio local."));
        return {};
    }
#endif
    const QFileInfo outputInfo(outPath);
    const QString outputDir = outputInfo.absolutePath();
    if (!QDir().mkpath(outputDir)) {
        setLastError(QStringLiteral("No se pudo crear la carpeta de exportacion: ") + outputDir);
        return QString();
    }

    const QString workingTemplatePath = QDir(outputDir).filePath(
        outputInfo.completeBaseName() + QStringLiteral("_template_work.xlsx"));
    auto removeWorkingTemplate = [&workingTemplatePath]() {
        if (QFileInfo::exists(workingTemplatePath) && !QFile::remove(workingTemplatePath)) {
            qWarning().noquote()
                << "No se pudo eliminar la plantilla temporal de exportacion:"
                << workingTemplatePath;
        }
    };
    auto logExportDiagnostics = [&outputDir, &workingTemplatePath, &outPath](
                                    const QString &reason,
                                    const QString &probeError = QString()) {
        const QFileInfo outputDirInfo(outputDir);
        const QFileInfo workingTemplateInfo(workingTemplatePath);
        qWarning().noquote()
            << "Diagnostico de exportacion Excel:" << reason
            << "\n  input template:" << workingTemplatePath
            << "\n  output:" << outPath
            << "\n  output directory exists:" << outputDirInfo.exists()
            << "\n  output directory writable:" << outputDirInfo.isWritable()
            << "\n  template exists:" << workingTemplateInfo.exists()
            << "\n  template readable:" << workingTemplateInfo.isReadable()
            << "\n  template writable:" << workingTemplateInfo.isWritable()
            << "\n  template permissions:" << workingTemplateInfo.permissions()
            << "\n  probe error:" << (probeError.isEmpty() ? QStringLiteral("<none>") : probeError);
    };

    QString templateError;
    if (!copyOfficialTemplate(workingTemplatePath, &templateError)) {
        setLastError(templateError);
        return QString();
    }

    QXlsx::Document xlsx(workingTemplatePath);
    if (!xlsx.load()) {
        removeWorkingTemplate();
        setLastError(QStringLiteral("QXlsx no pudo abrir la plantilla oficial copiada: ") + workingTemplatePath);
        return QString();
    }

    QString fillError;
    ReportImages reportImages;
    if (!prepareReportImages(state, resourcesBasePathFromState(state), &reportImages, &fillError)) {
        removeWorkingTemplate();
        setLastError(fillError);
        return {};
    }
    if (!fillOfficialCalicataTemplate(xlsx, state, reportImages, &fillError)) {
        removeWorkingTemplate();
        setLastError(fillError);
        return QString();
    }

    QFile staleOutput(outPath);
    if (staleOutput.exists() && !staleOutput.remove()) {
        logExportDiagnostics(QStringLiteral("No se pudo eliminar el archivo de salida preexistente."),
                             staleOutput.errorString());
        removeWorkingTemplate();
        setLastError(QStringLiteral("No se pudo preparar el archivo Excel de salida: ")
                     + staleOutput.errorString());
        return QString();
    }

    const QString probePath = outPath + QStringLiteral(".probe");
    QFile probe(probePath);
    QString probeError;
    if (!probe.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        probeError = probe.errorString();
    } else {
        if (probe.write("ok") != 2)
            probeError = probe.errorString();
        probe.close();
    }
    QFile::remove(probePath);

    if (!probeError.isEmpty()) {
        logExportDiagnostics(QStringLiteral("La prueba de escritura del archivo de salida fallo."),
                             probeError);
        removeWorkingTemplate();
        setLastError(QStringLiteral("No se puede escribir el Excel en la carpeta de exportacion: ")
                     + probeError);
        return QString();
    }

    const QString generatingPath = outPath + QStringLiteral(".generating.xlsx");
    if (!xlsx.saveAs(generatingPath) || !QFile::rename(generatingPath, outPath)) {
        logExportDiagnostics(QStringLiteral("QXlsx saveAs fallo despues de una prueba de escritura exitosa."));
        QFile::remove(outPath);
        removeWorkingTemplate();
        setLastError(QStringLiteral("No se pudo guardar el Excel basado en la plantilla: ") + outPath);
        return QString();
    }

    removeWorkingTemplate();

    m_exportResult = {{"success",false},{"fileName",QFileInfo(outPath).fileName()},
        {"localPhysicalPath",outPath},{"displayPath",outPath},{"syncState","PENDING_SYNC"},{"error",QString()}};
#ifdef Q_OS_ANDROID
    m_exportResult["provider"] = provider;
    m_exportProject = header.value("projectId", header.value("project_id")).toString();
    QFile generated(outPath);
    if (!generated.open(QIODevice::ReadOnly) || generated.size() <= 0) {
        setLastError(QStringLiteral("El XLSX generado no se puede abrir para sincronizar."));
        m_exportResult["error"] = lastError(); m_exportResult["syncState"] = "ERROR";
        emit exportResultChanged(); return {};
    }
    const auto hash = QCryptographicHash::hash(generated.readAll(), QCryptographicHash::Sha256).toHex();
    generated.close();
    m_exportLogicalPath = logicalStem + '_' + QString::fromLatin1(hash.left(20)) + ".xlsx";
    m_exportResult["remoteLogicalPath"] = m_exportLogicalPath;
    auto *context = appContext();
    if (context && context->auth() && context->supabase())
        m_exports = RenditionExportService::shared(context->supabase(), context->auth());
    const QPointer<AndroidCalicataExporter> guard(this);
    const auto user = context && context->auth() ? context->auth()->userId() : QString();
    const auto logicalPath = m_exportLogicalPath;
    if (!m_exports || !m_exports->enqueueDocument(outPath, m_exportProject, logicalPath,
        [guard, user, logicalPath](bool, const QString &) {
            if (guard && appContext() && appContext()->auth()->userId() == user
                && guard->m_exportLogicalPath == logicalPath) emit guard->exportResultChanged();
        }, {}, calicataId, provider, true, visibleFileName)) {
        setLastError(QStringLiteral("Excel generado y conservado; no se pudo guardar la cola del destino elegido. Selecciona un proyecto y una cuenta válidos y reintenta."));
        m_exportResult["syncState"] = "ERROR"; m_exportResult["error"] = lastError();
        emit exportResultChanged();
        return {}; // A generated file alone is not a successfully queued export.
    }
    m_exports->generationQueued(outPath);
    // The durable private file belongs to the upload queue. Viewing/downloading
    // the published version is an explicit action in Google Drive.
#else
    // Desktop golden/export tools remain a pure generation entry point. Android
    // always requires the durable InGeDrive operation above.
    m_exportResult["syncState"] = "GENERATED";
#endif
    emit exportResultChanged();
    // Compatibility return is ALWAYS a QFile-readable physical path.
    return lastExportResult().value("localPhysicalPath", outPath).toString();

#else
    Q_UNUSED(state)
    Q_UNUSED(fileBaseName)
    Q_UNUSED(provider)
    setLastError(QStringLiteral("QXlsx no está enlazado en este build. Revisa CMakeLists.txt y thirdparty/QXlsx."));
    return QString();
#endif
}


QString AndroidCalicataExporter::exportGenericWorkbookToXlsx(const QVariantMap &state, const QString &fileBaseName)
{
#ifdef INGE_HAS_QXLSX
    setLastError(QString());

    if (state.isEmpty()) {
        setLastError(QStringLiteral("No hay datos para exportar."));
        return QString();
    }

    const QString outPath = makeOutputPath(fileBaseName.isEmpty() ? QStringLiteral("inventario") : fileBaseName);
    QDir().mkpath(QFileInfo(outPath).absolutePath());

    QXlsx::Document xlsx;
    QXlsx::Format title = fmtTitle();
    QXlsx::Format headerFmt = fmtHeader();
    QXlsx::Format labelFmt = fmtLabel();
    QXlsx::Format valueFmt = fmtValue();

    xlsx.renameSheet(QStringLiteral("Sheet1"), QStringLiteral("Inventario"));
    xlsx.selectSheet(QStringLiteral("Inventario"));

    xlsx.setColumnWidth(1, 24);
    xlsx.setColumnWidth(2, 44);
    xlsx.setColumnWidth(3, 22);

    const QString titleText = vstr(state.value(QStringLiteral("title"))).isEmpty()
        ? QStringLiteral("Inventario InGe+")
        : vstr(state.value(QStringLiteral("title")));

    xlsx.mergeCells(QStringLiteral("A1:C2"), title);
    xlsx.write(QStringLiteral("A1"), titleText, title);

    int row = 4;
    xlsx.write(row, 1, QStringLiteral("Campo"), headerFmt);
    xlsx.write(row, 2, QStringLiteral("Valor"), headerFmt);
    row++;

    const QVariantMap header = state.value(QStringLiteral("header")).toMap();
    for (auto it = header.constBegin(); it != header.constEnd(); ++it) {
        xlsx.write(row, 1, it.key(), labelFmt);
        writeAny(xlsx, row, 2, it.value(), valueFmt);
        row++;
    }

    row += 2;
    xlsx.write(row, 1, QStringLiteral("Detalle"), headerFmt);
    xlsx.write(row, 2, QStringLiteral("Valor"), headerFmt);
    row++;

    const QVariantList rows = state.value(QStringLiteral("rows")).toList();
    for (const QVariant &rv : rows) {
        const QVariantMap m = rv.toMap();
        if (!m.isEmpty()) {
            writeAny(xlsx, row, 1, m.value(QStringLiteral("campo")), valueFmt);
            writeAny(xlsx, row, 2, m.value(QStringLiteral("valor")), valueFmt);
        } else {
            writeAny(xlsx, row, 1, rv, valueFmt);
        }
        row++;
    }

    if (!xlsx.saveAs(outPath)) {
        setLastError(QStringLiteral("No se pudo guardar el Excel en: ") + outPath);
        return QString();
    }

#ifdef Q_OS_ANDROID
    const QString displayName = QFileInfo(outPath).fileName();
    QString publicHint;
    QString mediaError;
    if (copyFileToMediaStoreDownloads(
            outPath, displayName,
            QStringLiteral("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            &publicHint, &mediaError))
        return publicHint;

    setLastError(QStringLiteral("Excel creado internamente, pero no se pudo publicar: ") + mediaError + QStringLiteral(". Ruta: ") + outPath);
    return outPath;
#else
    return outPath;
#endif

#else
    Q_UNUSED(state)
    Q_UNUSED(fileBaseName)
    setLastError(QStringLiteral("QXlsx no está enlazado en este build."));
    return QString();
#endif
}

QString AndroidCalicataExporter::exportReceivedSnapshot(const QVariantMap &received, const QString &format)
{
    setLastError({});
    SnapshotExportModel model;
    QString error;
    if (!SnapshotExportModel::fromReceived(received, &model, &error)
        || (format != QLatin1String("pdf") && format != QLatin1String("xlsx"))) {
        setLastError(error.isEmpty() ? QStringLiteral("Formato no soportado.") : error);
        return {};
    }
    const QString path = makeOutputPathWithExtension(model.fileBaseName(), format);
    QDir().mkpath(QFileInfo(path).absolutePath());
    if (!RenditionSnapshotExporter::write(model, format, path, &error)) {
        setLastError(error);
        return {};
    }
    const auto snapshot = received.value("snapshot_payload").toMap();
    const auto header = snapshot.value("rendition").toMap();
    const auto projects = snapshot.value("projects").toList();
    const auto project = header.value("primary_project_id",
        projects.isEmpty() ? QVariant{} : projects.first().toMap().value("id")).toString();
    if (appContext() && appContext()->auth() && appContext()->supabase()) {
        auto *exports = RenditionExportService::shared(appContext()->supabase(), appContext()->auth());
        if (!exports->enqueue(path, project, received.value("rendition_id", header.value("id")).toString(), model.versionId, format))
            setLastError(QStringLiteral("Archivo creado localmente; no se pudo registrar su subida. Conserva el archivo y reintenta."));
    }
    return path;
}

QString AndroidCalicataExporter::exportRenditionToXlsx(
    const QVariantMap &state, const QString &fileBaseName)
{
#ifdef INGE_HAS_QXLSX
    setLastError(QString());
    const QVariantMap rendition = state.value(QStringLiteral("rendition")).toMap();
    const QVariantMap summary = state.value(QStringLiteral("summary")).toMap();
    const QVariantList expenses = state.value(QStringLiteral("expenses")).toList();
    if (rendition.isEmpty()) {
        setLastError(QStringLiteral("No hay una rendición seleccionada para exportar."));
        return QString();
    }

    const auto textFor = [](const QVariantMap &map, const QStringList &keys) {
        for (const QString &key : keys) {
            const QString text = vstr(map.value(key)).trimmed();
            if (!text.isEmpty())
                return text;
        }
        return QString();
    };
    const QString code = textFor(
        rendition, {QStringLiteral("visibleCode"), QStringLiteral("visible_code"),
                    QStringLiteral("reference"), QStringLiteral("localId")});
    const QString outPath = makeOutputPathWithExtension(
        fileBaseName.isEmpty() ? QStringLiteral("Rendicion_") + code : fileBaseName,
        QStringLiteral("xlsx"));
    QDir().mkpath(QFileInfo(outPath).absolutePath());

    QXlsx::Document xlsx;
    xlsx.renameSheet(QStringLiteral("Sheet1"), QStringLiteral("Rendición"));
    xlsx.selectSheet(QStringLiteral("Rendición"));
    const QXlsx::Format title = fmtTitle();
    const QXlsx::Format header = fmtHeader();
    const QXlsx::Format label = fmtLabel();
    QXlsx::Format valueFmt = fmtValue();
    valueFmt.setTextWrap(true);

    xlsx.setColumnWidth(1, 13);
    xlsx.setColumnWidth(2, 18);
    xlsx.setColumnWidth(3, 18);
    xlsx.setColumnWidth(4, 25);
    xlsx.setColumnWidth(5, 38);
    xlsx.setColumnWidth(6, 25);
    xlsx.setColumnWidth(7, 22);
    xlsx.setColumnWidth(8, 24);
    xlsx.setColumnWidth(9, 22);
    xlsx.setColumnWidth(10, 17);
    xlsx.setColumnWidth(11, 17);
    xlsx.setColumnWidth(12, 18);

    xlsx.mergeCells(QStringLiteral("A1:L2"), title);
    xlsx.write(QStringLiteral("A1"), QStringLiteral("InGe+ · Rendición ") + code, title);

    const QList<QPair<QString, QString>> metadata = {
        {QStringLiteral("Estado"), textFor(rendition, {QStringLiteral("status")})},
        {QStringLiteral("Periodo"), textFor(rendition, {QStringLiteral("periodStart"), QStringLiteral("period_start")})
             + QStringLiteral(" — ")
             + textFor(rendition, {QStringLiteral("periodEnd"), QStringLiteral("period_end")})},
        {QStringLiteral("Moneda base"), textFor(rendition, {QStringLiteral("baseCurrency"), QStringLiteral("base_currency")})},
        {QStringLiteral("Proyecto principal"), textFor(rendition, {QStringLiteral("primaryProjectName"), QStringLiteral("primary_project_name")})},
        {QStringLiteral("Ubicación documental"), textFor(rendition, {QStringLiteral("documentParentNodeName"), QStringLiteral("document_parent_node_name")})},
        {QStringLiteral("Versión"), textFor(rendition, {QStringLiteral("versionNumber"), QStringLiteral("version_number")})},
    };
    int row = 4;
    for (const auto &item : metadata) {
        xlsx.write(row, 1, item.first, label);
        xlsx.mergeCells(QXlsx::CellRange(row, 2, row, 4), valueFmt);
        xlsx.write(row, 2, item.second, valueFmt);
        ++row;
    }

    row += 1;
    xlsx.write(row, 1, QStringLiteral("Resumen"), header);
    xlsx.write(row, 2, QStringLiteral("Cantidad"), header);
    xlsx.write(row, 3, QStringLiteral("Total PEN"), header);
    xlsx.write(row, 4, QStringLiteral("Total USD"), header);
    ++row;
    xlsx.write(row, 1, QStringLiteral("Gastos"), valueFmt);
    xlsx.write(row, 2, expenses.size(), valueFmt);
    writeAny(xlsx, row, 3, summary.value(QStringLiteral("totalPen"), summary.value(QStringLiteral("total_pen"))), valueFmt);
    writeAny(xlsx, row, 4, summary.value(QStringLiteral("totalUsd"), summary.value(QStringLiteral("total_usd"))), valueFmt);

    row += 2;
    const QStringList expenseHeaders = {
        QStringLiteral("Fecha"), QStringLiteral("Proyecto"), QStringLiteral("Categoría"),
        QStringLiteral("Concepto"), QStringLiteral("Proveedor / beneficiario"),
        QStringLiteral("Medio de pago"), QStringLiteral("Detalle de pago"),
        QStringLiteral("Tipo de sustento"), QStringLiteral("N.º sustento"),
        QStringLiteral("Moneda"), QStringLiteral("Monto"), QStringLiteral("Revisión")};
    for (int column = 0; column < expenseHeaders.size(); ++column)
        xlsx.write(row, column + 1, expenseHeaders.at(column), header);
    ++row;
    for (const QVariant &entry : expenses) {
        const QVariantMap expense = entry.toMap();
        const QVariantList values = {
            textFor(expense, {QStringLiteral("expenseDate"), QStringLiteral("expense_date")}),
            textFor(expense, {QStringLiteral("projectName"), QStringLiteral("project_name"), QStringLiteral("projectId")}),
            textFor(expense, {QStringLiteral("categoryName"), QStringLiteral("category_name"), QStringLiteral("categoryCode")}),
            textFor(expense, {QStringLiteral("concept")}),
            textFor(expense, {QStringLiteral("beneficiary")}),
            textFor(expense, {QStringLiteral("paymentMethodName"), QStringLiteral("payment_method_name"), QStringLiteral("paymentMethodCode")}),
            textFor(expense, {QStringLiteral("paymentMethodDetail"), QStringLiteral("payment_method_detail")}),
            textFor(expense, {QStringLiteral("supportTypeName"), QStringLiteral("support_type_name"), QStringLiteral("supportTypeCode")}),
            textFor(expense, {QStringLiteral("supportNumber"), QStringLiteral("support_number")}),
            textFor(expense, {QStringLiteral("currencyCode"), QStringLiteral("currency_code")}),
            expense.value(QStringLiteral("amount")),
            textFor(expense, {QStringLiteral("reviewStatus"), QStringLiteral("review_status")}),
        };
        for (int column = 0; column < values.size(); ++column)
            writeAny(xlsx, row, column + 1, values.at(column), valueFmt);
        xlsx.setRowHeight(row, 30);
        ++row;
    }

    row += 2;
    xlsx.write(row, 1, QStringLiteral("Sustentos"), header);
    xlsx.write(row, 2, state.value(QStringLiteral("attachments")).toList().size(), valueFmt);
    xlsx.write(row + 1, 1, QStringLiteral("Versiones"), header);
    xlsx.write(row + 1, 2, state.value(QStringLiteral("versions")).toList().size(), valueFmt);

    if (!xlsx.saveAs(outPath)) {
        setLastError(QStringLiteral("No se pudo guardar el Excel de la rendición."));
        return QString();
    }
#ifdef Q_OS_ANDROID
    QString publicHint;
    QString mediaError;
    if (copyFileToMediaStoreDownloads(
            outPath, QFileInfo(outPath).fileName(),
            QStringLiteral("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            &publicHint, &mediaError))
        return publicHint;
    setLastError(QStringLiteral("Excel creado, pero Android no pudo publicarlo en Descargas: ")
                 + mediaError);
#endif
    return outPath;
#else
    Q_UNUSED(state)
    Q_UNUSED(fileBaseName)
    setLastError(QStringLiteral("QXlsx no está enlazado en este build."));
    return QString();
#endif
}

QString AndroidCalicataExporter::exportRenditionToPdf(
    const QVariantMap &state, const QString &fileBaseName)
{
    setLastError(QString());
    const QVariantMap rendition = state.value(QStringLiteral("rendition")).toMap();
    const QVariantMap summary = state.value(QStringLiteral("summary")).toMap();
    const QVariantList expenses = state.value(QStringLiteral("expenses")).toList();
    if (rendition.isEmpty()) {
        setLastError(QStringLiteral("No hay una rendición seleccionada para exportar."));
        return QString();
    }
    const auto textFor = [](const QVariantMap &map, const QStringList &keys) {
        for (const QString &key : keys) {
            const QString text = vstr(map.value(key)).trimmed();
            if (!text.isEmpty())
                return text;
        }
        return QString();
    };
    const QString code = textFor(
        rendition, {QStringLiteral("visibleCode"), QStringLiteral("visible_code"),
                    QStringLiteral("reference"), QStringLiteral("localId")});
    const QString outPath = makeOutputPathWithExtension(
        fileBaseName.isEmpty() ? QStringLiteral("Rendicion_") + code : fileBaseName,
        QStringLiteral("pdf"));
    QDir().mkpath(QFileInfo(outPath).absolutePath());

    QPdfWriter pdf(outPath);
    pdf.setCreator(QStringLiteral("InGe+ Android"));
    pdf.setTitle(QStringLiteral("Rendición ") + code);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setPageMargins(QMarginsF(12, 12, 12, 12), QPageLayout::Millimeter);
    pdf.setResolution(96);
    QPainter painter(&pdf);
    if (!painter.isActive()) {
        setLastError(QStringLiteral("No se pudo iniciar el generador PDF."));
        return QString();
    }

    const int left = 18;
    const int width = pdf.width() - left * 2;
    const int bottom = pdf.height() - 24;
    int y = 18;
    const QFont normal(QStringLiteral("Sans Serif"), 9);
    QFont bold = normal;
    bold.setBold(true);
    QFont heading = bold;
    heading.setPointSize(16);
    auto line = [&](const QString &text, const QFont &font, const QColor &color,
                    int gap = 5) {
        painter.setFont(font);
        painter.setPen(color);
        QFontMetrics metrics(font);
        const QRect measured = metrics.boundingRect(
            QRect(0, 0, width, 10000), Qt::TextWordWrap, text);
        if (y + measured.height() + gap > bottom) {
            pdf.newPage();
            y = 18;
        }
        painter.drawText(QRect(left, y, width, measured.height() + 2),
                         Qt::TextWordWrap, text);
        y += measured.height() + gap;
    };

    line(QStringLiteral("InGe+ · Rendición ") + code, heading, QColor(QStringLiteral("#176B5B")), 10);
    line(QStringLiteral("Estado: ") + textFor(rendition, {QStringLiteral("status")}), bold, Qt::black);
    line(QStringLiteral("Periodo: ")
             + textFor(rendition, {QStringLiteral("periodStart"), QStringLiteral("period_start")})
             + QStringLiteral(" — ")
             + textFor(rendition, {QStringLiteral("periodEnd"), QStringLiteral("period_end")}),
         normal, Qt::black);
    line(QStringLiteral("Proyecto principal: ")
             + textFor(rendition, {QStringLiteral("primaryProjectName"), QStringLiteral("primary_project_name")}),
         normal, Qt::black);
    line(QStringLiteral("Ubicación documental: ")
             + textFor(rendition, {QStringLiteral("documentParentNodeName"), QStringLiteral("document_parent_node_name")}),
         normal, Qt::black, 10);
    line(QStringLiteral("Resumen"), bold, QColor(QStringLiteral("#176B5B")));
    line(QStringLiteral("%1 gastos · PEN %2 · USD %3")
             .arg(expenses.size())
             .arg(vstr(summary.value(QStringLiteral("totalPen"), summary.value(QStringLiteral("total_pen")))))
             .arg(vstr(summary.value(QStringLiteral("totalUsd"), summary.value(QStringLiteral("total_usd"))))),
         normal, Qt::black, 10);
    line(QStringLiteral("Detalle de gastos"), bold, QColor(QStringLiteral("#176B5B")));
    int index = 0;
    for (const QVariant &entry : expenses) {
        const QVariantMap expense = entry.toMap();
        const QString detail = QStringLiteral("%1. %2 · %3 %4\n%5 · %6\n%7 · %8 · %9")
                                   .arg(++index)
                                   .arg(textFor(expense, {QStringLiteral("expenseDate"), QStringLiteral("expense_date")}))
                                   .arg(textFor(expense, {QStringLiteral("currencyCode"), QStringLiteral("currency_code")}))
                                   .arg(vstr(expense.value(QStringLiteral("amount"))))
                                   .arg(textFor(expense, {QStringLiteral("concept")}))
                                   .arg(textFor(expense, {QStringLiteral("beneficiary")}))
                                   .arg(textFor(expense, {QStringLiteral("categoryName"), QStringLiteral("category_name"), QStringLiteral("categoryCode")}))
                                   .arg(textFor(expense, {QStringLiteral("paymentMethodName"), QStringLiteral("payment_method_name"), QStringLiteral("paymentMethodCode")}))
                                   .arg(textFor(expense, {QStringLiteral("supportTypeName"), QStringLiteral("support_type_name"), QStringLiteral("supportNumber")}));
        line(detail, normal, Qt::black, 9);
    }
    line(QStringLiteral("Sustentos: %1 · Versiones: %2")
             .arg(state.value(QStringLiteral("attachments")).toList().size())
             .arg(state.value(QStringLiteral("versions")).toList().size()),
         normal, Qt::black);
    painter.end();

#ifdef Q_OS_ANDROID
    QString publicHint;
    QString mediaError;
    if (copyFileToMediaStoreDownloads(
            outPath, QFileInfo(outPath).fileName(), QStringLiteral("application/pdf"),
            &publicHint, &mediaError))
        return publicHint;
    setLastError(QStringLiteral("PDF creado, pero Android no pudo publicarlo en Descargas: ")
                 + mediaError);
#endif
    return outPath;
}

// ===================== P6: ficha de Calicata en PDF =====================
// Same portable state that feeds the Excel/InGeDrive publication; the file is
// named by the state hash, so the same ficha is the same logical export (a
// repeated tap or a retry never becomes a second job).
namespace {
// Imagen de la ficha para el PDF: primero los bytes que portableState() ya resolvió
// (junto a la ficha o bajo Documentos) en embedded_resources; si no, la ruta.
QString pdfText(const QVariantMap &map, std::initializer_list<const char *> keys)
{
    for (const char *key : keys) {
        const QString value = map.value(QLatin1String(key)).toString().trimmed();
        if (!value.isEmpty()) return value;
    }
    return QStringLiteral("—");
}

// Largo/ancho son opcionales (vacío o 0 = no informado): nunca " × " incompleto.
QString pdfExcavationSize(const QVariantMap &header)
{
    const auto dimension = [&header](const char *key) {
        const QString text = header.value(QLatin1String(key)).toString().trimmed().replace(QLatin1Char(','), QLatin1Char('.'));
        bool ok = false;
        const double value = text.toDouble(&ok);
        return ok && value > 0 ? text : QString();
    };
    const QString length = dimension("length_m"), width = dimension("width_m");
    if (!length.isEmpty() && !width.isEmpty()) return length + QStringLiteral(" × ") + width;
    if (!length.isEmpty()) return QStringLiteral("Largo ") + length;
    if (!width.isEmpty()) return QStringLiteral("Ancho ") + width;
    return QString();
}
} // namespace

QString AndroidCalicataExporter::exportCalicataToPdf(const QVariantMap &state, const QString &resourcesBase)
{
    setLastError({});
    const QVariantMap header = state.value(QStringLiteral("header")).toMap();
    const QVariantList cortes = state.value(QStringLiteral("cortes")).toList();
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(
        QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex().left(20));
    const QString code = safeFileName(pdfText(header, {"code", "codigo", "calicata"}));
    const QString outPath = QDir(defaultExportDir()).filePath(code + QLatin1Char('_') + hash + QStringLiteral(".pdf"));
    // Imágenes antes de crear el archivo: una imagen activada que no se puede leer
    // detiene la exportación con su nombre (nunca un PDF incompleto en silencio).
    ReportImages reportImages;
    QString imageError;
    if (!prepareReportImages(state, resourcesBase, &reportImages, &imageError)) {
        setLastError(imageError);
        return {};
    }
    if (QFileInfo(outPath).size() > 0) return outPath;   // identical ficha already rendered
    if (!QDir().mkpath(QFileInfo(outPath).absolutePath())) {
        setLastError(QStringLiteral("No se pudo crear la carpeta del PDF."));
        return {};
    }

    QSaveFile output(outPath);
    if (!output.open(QIODevice::WriteOnly)) {
        setLastError(QStringLiteral("No se pudo crear el PDF: ") + output.errorString());
        return {};
    }
    QPdfWriter pdf(&output);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setResolution(150);
    pdf.setTitle(QStringLiteral("Calicata ") + code);
    pdf.setCreator(QStringLiteral("InGe+ Android"));
    QPainter p;
    if (!p.begin(&pdf)) { setLastError(QStringLiteral("No se pudo crear el PDF.")); return {}; }
    const int W = pdf.width(), H = pdf.height(), M = 60;
    int y = M;
    QFont title(QStringLiteral("sans-serif")); title.setPixelSize(34); title.setBold(true);
    QFont label(QStringLiteral("sans-serif")); label.setPixelSize(18); label.setBold(true);
    QFont body(QStringLiteral("sans-serif")); body.setPixelSize(18);
    QFont small(QStringLiteral("sans-serif")); small.setPixelSize(14);
    // Encabezado corrido y número de página en cada hoja del PDF.
    const QString runningTitle = QStringLiteral("Calicata ") + pdfText(header, {"code", "codigo"})
        + QStringLiteral(" · ") + exportProjectName(header);
    int pageNumber = 1;
    bool pageFailed = false;
    const auto drawFooter = [&]() {
        p.save();
        p.setFont(small);
        p.setPen(QColor(96, 104, 112));
        const QRect footer(M, H - M + 10, W - 2 * M, 30);
        p.drawText(footer, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, runningTitle);
        p.drawText(footer, Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("Página %1").arg(pageNumber));
        p.restore();
    };
    const auto newPageIfNeeded = [&](int needed) {
        if (y + needed <= H - M) return;
        drawFooter();
        if (!pdf.newPage()) {
            pageFailed = true;
            return;
        }
        ++pageNumber;
        y = M;
        p.save();
        p.setFont(small);
        p.setPen(QColor(96, 104, 112));
        p.drawText(QRect(M, y, W - 2 * M, 26), Qt::AlignLeft | Qt::TextSingleLine, runningTitle);
        p.restore();
        y += 40;
    };
    const auto drawImage = [&](const QImage &image, const QRect &box) {
        if (image.isNull()) return;
        const QSize fitted = image.size().scaled(box.size(), Qt::KeepAspectRatio);
        p.drawImage(QRect(box.topLeft() + QPoint((box.width() - fitted.width()) / 2, (box.height() - fitted.height()) / 2), fitted), image);
    };

    // Encabezado: logos del proyecto y de la entidad + título.
    drawImage(reportImages[1], QRect(M, y, 220, 90));          // logo del proyecto
    drawImage(reportImages[0], QRect(W - M - 220, y, 220, 90)); // logo de la entidad
    p.setFont(title);
    p.drawText(QRect(M, y, W - 2 * M, 90), Qt::AlignCenter, QStringLiteral("REGISTRO DE CALICATA ") + pdfText(header, {"code", "codigo"}));
    y += 110;
    p.setFont(body);
    p.drawText(QRect(M, y, W - 2 * M, 60), Qt::TextWordWrap, exportProjectName(header));
    y += 64;

    // Nivel freático: profundidad registrada o el estado declarado (nunca inventado).
    QString waterTable = pdfText(header, {"groundwater_depth_m", "water_table_depth"});
    if (waterTable == QStringLiteral("—")) {
        const QString status = header.value(QStringLiteral("water_table_status")).toString().trimmed().toUpper();
        if (status == QLatin1String("ENCONTRADO")) waterTable = QStringLiteral("Encontrado (sin profundidad)");
        else if (status == QLatin1String("NO_ENCONTRADO")) waterTable = QStringLiteral("No encontrado");
        else if (status == QLatin1String("NO_EVALUADO")) waterTable = QStringLiteral("No evaluado");
    }
    const QList<QPair<QString, QString>> fields = {
        {QStringLiteral("Título / testificación"), pdfText(header, {"description"})},
        {QStringLiteral("Estado"), pdfText(header, {"status"})},
        {QStringLiteral("Progresiva"), pdfText(header, {"progresiva", "pk"})},
        {QStringLiteral("Lado de la vía"), pdfText(header, {"location", "lado_via"})},
        {QStringLiteral("Ubicación / tramo"), pdfText(header, {"ubicacion", "tramo"})},
        {QStringLiteral("UTM · zona / datum"), pdfText(header, {"zona", "utm_zone"}) + QStringLiteral(" / ") + pdfText(header, {"datum"})},
        {QStringLiteral("Este / Norte (m)"), pdfText(header, {"utm_x", "easting"}) + QStringLiteral(" / ") + pdfText(header, {"utm_y", "northing"})},
        {QStringLiteral("Altitud (m.s.n.m.)"), pdfText(header, {"utm_z", "altitude_m", "altitud"})
            + (header.value(QStringLiteral("altitude_source")).toString() == QLatin1String("GPS_ELIPSOIDAL")
               ? QStringLiteral(" (GPS elipsoidal, no m.s.n.m.)") : QString())},
        {QStringLiteral("Fecha inicio / fin"), pdfText(header, {"start_date", "fecha_inicio"}) + QStringLiteral(" / ") + pdfText(header, {"end_date", "fecha_fin"})},
        {QStringLiteral("Supervisor"), pdfText(header, {"supervisor"})},
        {QStringLiteral("Maquinaria"), pdfText(header, {"machine", "maquina"})},
        {QStringLiteral("Profundidad (m)"), pdfText(header, {"depth_m", "final_depth_m"})},
        {QStringLiteral("Largo × ancho (m)"), pdfExcavationSize(header)},
        {QStringLiteral("Nivel freático (m)"), waterTable},
    };
    const int half = (W - 2 * M) / 2;
    for (int i = 0; i < fields.size(); ++i) {
        const int col = i % 2, x = M + col * half;
        if (col == 0 && i > 0) { y += 50; newPageIfNeeded(50); }
        p.setFont(label); p.drawText(QRect(x, y, half - 10, 24), Qt::AlignLeft, fields.at(i).first);
        p.setFont(body);  p.drawText(QRect(x, y + 22, half - 10, 26), Qt::AlignLeft | Qt::TextSingleLine, fields.at(i).second);
    }
    y += 70;

    // Perfil estratigráfico + laboratorio por estrato (misma fuente: el estrato).
    static const QStringList humidity = {QStringLiteral("Seco"), QStringLiteral("Bajo"), QStringLiteral("Medio"), QStringLiteral("Agua")};
    QList<QPair<QString, int>> columns = {
        {QStringLiteral("De–A (m)"), 150}, {QStringLiteral("Descripción"), 520}, {QStringLiteral("Humedad"), 110},
        {QStringLiteral("Muestra"), 110}, {QStringLiteral("SUCS"), 100}, {QStringLiteral("AASHTO"), 110},
        {QStringLiteral("Nº4/10/40/200"), 220}, {QStringLiteral("LL/LP/IP"), 140}};
    const int tableWidth = W - 2 * M;
    int baseWidth = 0, usedWidth = 0;
    for (const auto &column : columns) baseWidth += column.second;
    for (int i = 0; i < columns.size(); ++i) {
        columns[i].second = i == columns.size() - 1 ? tableWidth - usedWidth
            : qMax(1, qRound(double(columns[i].second) * tableWidth / baseWidth));
        usedWidth += columns[i].second;
    }
    const auto drawRow = [&](const QStringList &cells, bool bold) {
        p.setFont(bold ? label : body);
        std::vector<std::unique_ptr<QTextLayout>> layouts;
        int maxLines = 1;
        qreal lineHeight = 24;
        for (int c = 0; c < cells.size(); ++c) {
            auto layout = std::make_unique<QTextLayout>(cells.at(c), p.font());
            QTextOption option;
            option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
            layout->setTextOption(option);
            layout->beginLayout();
            for (;;) {
                QTextLine line = layout->createLine();
                if (!line.isValid()) break;
                line.setLineWidth(columns.at(c).second - 8);
                lineHeight = qMax(lineHeight, line.height());
            }
            layout->endLayout();
            maxLines = qMax(maxLines, layout->lineCount());
            layouts.push_back(std::move(layout));
        }
        // Continue an oversized stratum by whole text lines; no clipped content.
        const int totalHeight = int(std::ceil(maxLines * lineHeight)) + 12;
        if (totalHeight <= H - 2 * M - 40)
            newPageIfNeeded(totalHeight); // Preserve whole rows when they fit a page.
        for (int firstLine = 0; firstLine < maxLines;) {
            newPageIfNeeded(int(std::ceil(lineHeight)) + 12);
            if (pageFailed) return;
            const int count = qMin(maxLines - firstLine, qMax(1, int((H - M - y - 12) / lineHeight)));
            const int height = int(std::ceil(count * lineHeight)) + 12;
            int x = M;
            for (int c = 0; c < cells.size(); ++c) {
                p.drawRect(QRect(x, y, columns.at(c).second, height));
                const QTextLayout &layout = *layouts.at(c);
                for (int l = firstLine; l < qMin(firstLine + count, layout.lineCount()); ++l) {
                    const QTextLine line = layout.lineAt(l);
                    line.draw(&p, QPointF(x + 4, y + 6 + (l - firstLine) * lineHeight) - line.position());
                }
                x += columns.at(c).second;
            }
            y += height;
            firstLine += count;
        }
    };
    newPageIfNeeded(80);
    p.setFont(label); p.drawText(M, y, QStringLiteral("PERFIL ESTRATIGRÁFICO Y LABORATORIO")); y += 16;
    QStringList head; for (const auto &c : columns) head << c.first;
    drawRow(head, true);
    for (const QVariant &value : cortes) {
        const QVariantMap row = value.toMap();
        bool ok = false; const int hum = row.value(QStringLiteral("humedad")).toInt(&ok);
        const QString ll = row.value(QStringLiteral("wl")).toString(), lp = row.value(QStringLiteral("lp")).toString();
        bool okLl = false, okLp = false; const double ip = ll.toDouble(&okLl) - lp.toDouble(&okLp);
        drawRow({row.value(QStringLiteral("de")).toString() + QStringLiteral("–") + row.value(QStringLiteral("a")).toString(),
                 row.value(QStringLiteral("descripcion")).toString(),
                 ok && hum >= 0 && hum < humidity.size() ? humidity.at(hum) : QStringLiteral("—"),
                 pdfText(row, {"tipoText", "tipo_muestra"}),
                 exportClassificationFor(row).label, exportClassificationFor(row).aashto,
                 QStringList{pdfText(row, {"passing_no4"}), pdfText(row, {"g2"}), pdfText(row, {"g04"}), pdfText(row, {"g008"})}.join(QStringLiteral(" / ")),
                 QStringList{pdfText(row, {"wl"}), pdfText(row, {"lp"}), okLl && okLp ? QString::number(ip, 'f', 2) : QStringLiteral("—")}.join(QStringLiteral(" / "))},
                false);
    }
    y += 20;

    // Observaciones generales (no la testificación).
    const QString observations = state.value(QStringLiteral("observaciones")).toString().trimmed();
    p.setFont(label); newPageIfNeeded(80); p.drawText(M, y + 20, QStringLiteral("OBSERVACIONES")); y += 30;
    p.setFont(body);
    const QStringList paragraphs = (observations.isEmpty() ? QStringLiteral("—") : observations).split(QLatin1Char('\n'));
    for (const QString &paragraph : paragraphs) {
        QTextLayout layout(paragraph.isEmpty() ? QStringLiteral(" ") : paragraph, body);
        QTextOption option;
        option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
        layout.setTextOption(option);
        layout.beginLayout();
        for (;;) {
            QTextLine line = layout.createLine();
            if (!line.isValid()) break;
            line.setLineWidth(W - 2 * M);
        }
        layout.endLayout();
        for (int l = 0; l < layout.lineCount(); ++l) {
            const QTextLine line = layout.lineAt(l);
            const int height = int(std::ceil(line.height()));
            newPageIfNeeded(height);
            if (pageFailed) break;
            line.draw(&p, QPointF(M, y) - line.position());
            y += height;
        }
        y += 6;
    }
    y += 14;

    // Fotografías publicadas (derivadas en uso).
    static const QStringList photoTitles = {QStringLiteral("Zona de ejecución"), QStringLiteral("Interior de calicata"), QStringLiteral("Acopios")};
    for (int i = 1; i <= 3; ++i) {
        const QImage &photo = reportImages[i + 1];
        if (photo.isNull()) continue;   // categoría sin foto
        const int photoHeight = qMin(580, H - 2 * M - 120);
        newPageIfNeeded(photoHeight + 40);
        p.setFont(label); p.drawText(M, y + 20, photoTitles.at(i - 1)); y += 30;
        drawImage(photo, QRect(M, y, W - 2 * M, photoHeight));
        y += photoHeight + 10;
    }
    drawFooter();
    const bool painted = p.end();
    if (pageFailed || !painted) {
        output.cancelWriting();
        setLastError(QStringLiteral("No se pudo completar la paginación o escritura del PDF."));
        return {};
    }
    if (!output.commit()) {
        setLastError(QStringLiteral("No se pudo guardar el PDF: ") + output.errorString());
        return {};
    }
    setLastError({});
    return outPath;
}

bool AndroidCalicataExporter::publishCalicataPdf(const QVariantMap &state, const QString &pdfPath)
{
#ifdef Q_OS_ANDROID
    const auto header = state.value("header").toMap();
    const auto project = header.value("projectId").toString();
    auto *ctx = appContext();
    if (!ctx || !ctx->auth()->logged() || QUuid(project).isNull() || !QFileInfo(pdfPath).isFile()) {
        setLastError(QStringLiteral("Selecciona un proyecto e inicia sesión antes de publicar el PDF."));
        return false;
    }
    m_exports = RenditionExportService::shared(ctx->supabase(), ctx->auth());
    // REMOTE_LOGICAL_PATH inside the project's InGeDrive; the local file is the
    // physical copy / mirror. Same name for the same ficha -> same job.
    const QString remotePdf = QStringLiteral("Calicatas/PDF/") + QFileInfo(pdfPath).fileName();
    const QPointer<AndroidCalicataExporter> guard(this);
    const auto document = state.value("instance_id").toString();
    if (!m_exports->enqueueDocument(pdfPath, project, remotePdf, [guard, document](bool ok, const QString &error) {
            if (!guard) return;
            emit guard->exportResultChanged();
            if (!ok) emit guard->calicataPublishFailed(document, error);
        })) {
        setLastError(QStringLiteral("No se pudo registrar la publicación del PDF; el archivo local se conserva."));
        return false;
    }
    m_publishedFiles[document] = pdfPath;
    setLastError({});
    return true;
#else
    Q_UNUSED(state); Q_UNUSED(pdfPath);
    setLastError(QStringLiteral("La publicación online del PDF requiere la sesión Android."));
    return false;
#endif
}

// Open or share any exported file (PDF/XLSX) through the same safe Android
// bridge as the Excel export (content URI + temporary read permission).
bool AndroidCalicataExporter::openExportedFile(const QString &path, bool share)
{
    if (path.isEmpty() || !QFileInfo(path).isFile()) {
        setLastError(QStringLiteral("El archivo exportado no está disponible.")); return false;
    }
#ifdef Q_OS_ANDROID
    const auto context = QNativeInterface::QAndroidApplication::context();
    const auto file = QJniObject::fromString(path);
    const auto result = QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge", "open",
        "(Landroid/content/Context;Ljava/lang/String;ZZ)Ljava/lang/String;",
        context.object(), file.object<jstring>(), jboolean(share), jboolean(share));
    QJniEnvironment env;
    if (env->ExceptionCheck()) { env->ExceptionClear(); setLastError(QStringLiteral("No se pudo abrir el archivo.")); return false; }
    if (!result.isValid()) { setLastError(QStringLiteral("Android no respondió al abrir el archivo.")); return false; }
    setLastError(result.toString()); return result.toString().isEmpty();
#else
    Q_UNUSED(share);
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
#endif
}
