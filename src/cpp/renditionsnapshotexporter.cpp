#include "renditionsnapshotexporter.h"
#include "renditionmoney.h"

#include <QDateTime>
#include <QFileInfo>
#include <QFontMetricsF>
#include <QImage>
#include <QTemporaryDir>
#include <cmath>
#include <QFont>
#include <QPainter>
#include <QPageLayout>
#include <QPdfWriter>
#include <QRegularExpression>
#include <QTextDocument>
#ifdef INGE_HAS_QXLSX
#include "xlsxdocument.h"
#include "xlsxformat.h"
#endif

namespace {
QString text(const QVariantMap &m, const char *key) { return m.value(QLatin1String(key)).toString(); }
QString projectLabel(const QVariantMap &p) {
    const QString code = text(p, "code"), name = text(p, "name");
    return code.isEmpty() ? name : (name.isEmpty() ? code : code + QStringLiteral(" - ") + name);
}
QString label(const QVariantMap &m, const char *name, const char *code) {
    const QString result = text(m, name);
    return result.isEmpty() ? text(m, code) : result;
}
}

bool SnapshotExportModel::fromReceived(const QVariantMap &received, SnapshotExportModel *model, QString *error)
{
    const auto snapshot = received.value(QStringLiteral("snapshot_payload")).toMap();
    const auto rendition = snapshot.value(QStringLiteral("rendition")).toMap();
    const auto totals = snapshot.value(QStringLiteral("totals")).toMap();
    SnapshotExportModel result;
    result.code = text(rendition, "visible_code");
    result.version = received.value(QStringLiteral("version_number")).toInt();
    result.versionId = text(received, "rendition_version_id");
    result.hash = text(received, "snapshot_hash");
    if (text(snapshot, "schema_version") != QLatin1String("RENDITION_SNAPSHOT_V01")
        || text(rendition, "id") != text(received, "rendition_id")
        || result.code != text(received, "visible_code")
        || !QRegularExpression(QStringLiteral("^RDC-[0-9]{4}-[0-9]+$")).match(result.code).hasMatch()
        || result.version < 1 || result.versionId.isEmpty()
        || !QRegularExpression(QStringLiteral("^[a-fA-F0-9]{64}$")).match(result.hash).hasMatch()
        || !snapshot.value(QStringLiteral("expenses")).canConvert<QVariantList>()
        || !totals.contains(QStringLiteral("total_declared_pen"))
        || !totals.contains(QStringLiteral("total_declared_usd"))) {
        *error = QStringLiteral("Snapshot incompleto o identidad de versión inválida; no se exportó.");
        return false;
    }
    // The V01 snapshot stores owner_user_id; the authorized RPC supplies its label.
    result.owner = text(received, "owner_name");
    result.period = text(rendition, "period_start") + QStringLiteral(" / ") + text(rendition, "period_end");
    result.periodStart = text(rendition, "period_start");
    result.periodEnd = text(rendition, "period_end");
    result.displayName = text(received, "display_name").isEmpty() ? text(rendition, "display_name") : text(received, "display_name");
    result.status = text(rendition, "status");
    result.submittedAt = text(rendition, "submitted_at");
    result.totalPen = totals.value(QStringLiteral("total_declared_pen")).toDouble();
    result.totalUsd = totals.value(QStringLiteral("total_declared_usd")).toDouble();
    const auto projects = snapshot.value(QStringLiteral("projects")).toList();
    for (const auto &entry : projects) {
        if (!result.projects.isEmpty()) result.projects += QStringLiteral("; ");
        result.projects += projectLabel(entry.toMap());
        if (entry.toMap().value(QStringLiteral("is_primary")).toBool())
            result.project = projectLabel(entry.toMap());
    }
    for (const auto &entry : snapshot.value(QStringLiteral("expenses")).toList()) {
        auto expense = entry.toMap();
        for (const auto &project : projects)
            if (text(project.toMap(), "id") == text(expense, "project_id"))
                expense.insert(QStringLiteral("project_label"), projectLabel(project.toMap()));
        result.expenses.append(expense);
    }
    result.attachments = snapshot.value(QStringLiteral("attachments")).toList();
    if (received.contains("funding") || received.contains("exchangeRate")) {
        result.funding = received.value("funding").toMap(); result.exchangeRate = received.value("exchangeRate").toMap();
        if (received.value("financialVersionId").toString()!=result.versionId
            || text(result.funding,"rendition_id")!=text(received,"rendition_id")
            || text(result.exchangeRate,"rendition_id")!=text(received,"rendition_id")
            || !RenditionMoney::cents(result.funding.value("pen").toString())
            || !RenditionMoney::cents(result.funding.value("usd").toString())) {
            *error = QStringLiteral("Suplementos no corresponden a la versión inmutable."); return false;
        }
        result.financialSupplements = true;
    }
    *model = result;
    return true;
}

QString SnapshotExportModel::fileBaseName() const
{
    // Nombre legible («JENNIFER v1»); sin caracteres no válidos en archivos. Respaldo: código.
    QString base = displayName.trimmed();
    base.replace(QRegularExpression(QStringLiteral("[\\/:*?\"<>|\x00-\x1f]")), QStringLiteral(" "));
    base = base.simplified().left(80).trimmed();
    if (base.isEmpty()) base = code;
    return base + QStringLiteral(" v%1").arg(version);
}

// ---------------------------------------------------------------------------
// Mismo documento que la Web (renditionPdfLayout.ts / renditionExcelLayout.ts):
// colores del Manual Corporativo Ingema, secciones 01-04 y hojas Resumen,
// Detalle_Gastos, Evidencias y Versión. Fuente: snapshot inmutable.
namespace {
// Logos a color: Ingema Consultores siempre acompañado de HVA Group (empresa matriz).
// INGE_EXPORT_IMAGES permite generar la muestra de escritorio fuera de la app.
QImage exportImage(const char *file) {
    return QImage(qEnvironmentVariable("INGE_EXPORT_IMAGES", QStringLiteral(":/images")) + QLatin1Char('/') + QLatin1String(file));
}
const QColor cNavy(0x15, 0x1A, 0x30), cSecondary(0x1C, 0x2D, 0x50), cBlue(0x06, 0x54, 0xA2),
    cGreen(0x48, 0x64, 0x26), cPale(0xF1, 0xF5, 0xFA), cLine(0xDD, 0xE5, 0xEE), cMuted(0x53, 0x60, 0x78);

QString dateLabel(const QString &v) {
    return QRegularExpression(QStringLiteral("^\\d{4}-\\d{2}-\\d{2}$")).match(v).hasMatch()
        ? v.mid(8, 2) + QLatin1Char('/') + v.mid(5, 2) + QLatin1Char('/') + v.left(4) : v;
}
QString timestampLabel(const QString &v) {
    const QDateTime t = QDateTime::fromString(v, Qt::ISODateWithMs);
    return t.isValid() ? dateLabel(t.toUTC().toString(QStringLiteral("yyyy-MM-dd"))) + t.toUTC().toString(QStringLiteral(" HH:mm:ss")) + QStringLiteral(" UTC") : v;
}
QString money(const QVariant &amount, const QString &currency) {
    if (!amount.isValid() || amount.isNull() || amount.toString().isEmpty()) return QStringLiteral("Monto pendiente");
    return (currency == QLatin1String("PEN") ? QStringLiteral("S/") : currency) + QStringLiteral(" %1").arg(amount.toDouble(), 0, 'f', 2);
}

struct ExportRow {
    QString id, project, date, category, conceptText, beneficiary, payment, support, supportNumber, currency, justification, review;
    QVariant amount; bool withSupport = false; int line = 0;
};
struct ExportEvidence { QString id, expenseId, fileName, documentNumber, mimeType, createdAt, createdBy, status; };

QList<ExportEvidence> evidenceOf(const SnapshotExportModel &m) {
    QList<ExportEvidence> out;
    for (const auto &v : m.attachments) {
        const auto a = v.toMap();
        out.append({text(a, "id"), text(a, "expense_id"), text(a, "file_name"), text(a, "document_number"), text(a, "mime_type"),
                     text(a, "created_at"), text(a, "actor_name").isEmpty() ? text(a, "actor_user_id") : text(a, "actor_name"), text(a, "status")});
    }
    return out;
}
QList<ExportRow> rowsOf(const SnapshotExportModel &m, const QList<ExportEvidence> &evidence) {
    QList<ExportRow> out;
    int line = 0;
    for (const auto &v : m.expenses) {
        const auto e = v.toMap();
        ExportRow r;
        r.id = text(e, "id"); r.project = text(e, "project_label"); r.date = text(e, "expense_date");
        r.category = label(e, "category_name", "category_code"); r.conceptText = text(e, "concept"); r.beneficiary = text(e, "beneficiary");
        r.payment = label(e, "payment_method_name", "payment_method_code"); r.support = label(e, "support_type_name", "support_type_code");
        r.supportNumber = text(e, "support_number"); r.currency = text(e, "currency_code"); r.justification = text(e, "justification");
        r.review = text(e, "review_status"); r.amount = e.value(QStringLiteral("amount")); r.line = ++line;
        for (const auto &f : evidence) if (f.expenseId == r.id) { r.withSupport = true; break; }
        out.append(r);
    }
    return out;
}
double sumCurrency(const QList<ExportRow> &rows, const QString &currency) {
    double s = 0;
    for (const auto &r : rows) if (r.currency == currency) s += r.amount.toDouble();
    return std::round(s * 100.0) / 100.0;
}
QStringList uniqueLabels(const QList<ExportRow> &rows, bool project) {
    QStringList out;
    for (const auto &r : rows) { const QString k = project ? r.project : r.category; if (!out.contains(k)) out.append(k); }
    return out;
}
// Saldo equivalente: fondo - gastos en la moneda, más la otra moneda convertida si hay cambio.
QVariant balanceOf(const SnapshotExportModel &m, const QList<ExportRow> &rows, bool pen) {
    const double fp = m.funding.value("pen").toDouble(), fu = m.funding.value("usd").toDouble();
    const double rate = m.exchangeRate.value("rate").toDouble();
    const double sp = sumCurrency(rows, "PEN"), su = sumCurrency(rows, "USD");
    if (rate <= 0) return pen ? QVariant(fp - sp) : QVariant(fu - su);
    return pen ? QVariant(std::round(((fp - sp) + (fu - su) * rate) * 100) / 100)
               : QVariant(std::round(((fu - su) + (fp - sp) / rate) * 100) / 100);
}
QVariant fundEquivalent(const SnapshotExportModel &m, bool pen) {
    const double fp = m.funding.value("pen").toDouble(), fu = m.funding.value("usd").toDouble();
    const double rate = m.exchangeRate.value("rate").toDouble();
    if (rate <= 0) return pen ? QVariant(fp) : QVariant(fu);
    return pen ? QVariant(fp + fu * rate) : QVariant(fu + fp / rate);
}

// ------------------------------------------------------------------ PDF
class PdfLayout {
public:
    PdfLayout(QPdfWriter &w, QPainter &p, const SnapshotExportModel &m) : writer(w), painter(p), model(m) {
        logo = exportImage("INGEMA_CONSULTORES_LOGO.png");
        hva = exportImage("HVA_GROUP_LOGO.png");
    }
    static constexpr double W = 595.28, H = 841.89, M = 42, BODY = W - 2 * 42, BOTTOM = 70, LINE = 12;
    QPdfWriter &writer; QPainter &painter; const SnapshotExportModel &model;
    QImage logo, hva; double y = 0; bool first = true; int pages = 0, total = 0; QString secNum, secTitle;
    void footer() {
        if (pages == 0) return;
        painter.setPen(QPen(cLine, 0.5)); painter.drawLine(QPointF(M, H - 51), QPointF(W - M, H - 51));
        textAt(QStringLiteral("Ingema Consultores | Rendición de gastos"), M, 36, 8, false, cMuted);
        const QString n = QStringLiteral("Página %1 de %2").arg(pages).arg(qMax(total, pages));
        textAt(n, W - M - width(n, 8, false), 36, 8, false, cMuted);
        textAt(QStringLiteral("Versión %1 | %2").arg(model.version).arg(model.code), M, 23, 7, false, cMuted);
    }

    QFont font(double size, bool bold) { QFont f(QStringLiteral("Helvetica")); f.setPixelSize(qMax(1, int(std::round(size)))); f.setPointSizeF(size); f.setBold(bold); return f; }
    double width(const QString &s, double size, bool bold) { return QFontMetricsF(font(size, bold), &writer).horizontalAdvance(s); }
    // Web coordinates (origin bottom-left) -> painter (origin top-left).
    void rect(double x, double yBottom, double w, double h, const QColor &c) { painter.fillRect(QRectF(x, H - yBottom - h, w, h), c); }
    void textAt(const QString &s, double x, double baseline, double size, bool bold, const QColor &c) {
        painter.setFont(font(size, bold)); painter.setPen(c); painter.drawText(QPointF(x, H - baseline), s);
    }
    QStringList wrap(const QString &value, double w, bool bold, double size) {
        QStringList result;
        for (const QString &para : QString(value).replace(QLatin1Char('\r'), QString()).split(QLatin1Char('\n'))) {
            QString line;
            for (const QString &word : para.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts)) {
                const QString cand = line.isEmpty() ? word : line + QLatin1Char(' ') + word;
                if (width(cand, size, bold) <= w) { line = cand; continue; }
                if (!line.isEmpty()) { result << line; line.clear(); }
                for (const QChar ch : word) {
                    if (!line.isEmpty() && width(line + ch, size, bold) > w) { result << line; line.clear(); }
                    line += ch;
                }
            }
            result << line;
        }
        return result;
    }
    void newPage(bool continuation = false) {
        if (first) first = false; else { footer(); writer.newPage(); }
        ++pages;
        // Cabecera blanca: logos a color sin recuadro; sólo la franja de sección en azul #0654A2.
        rect(M, H - 148, BODY, 38, cBlue);
        // Recuadro blanco con Ingema Consultores | HVA Group (logos a color).
        const double top = 46, ph = 56, iw = 150, hh = 30;
        const double ih = logo.isNull() ? 36 : iw * logo.height() / logo.width();
        const double hw = hva.isNull() ? 74 : hh * hva.width() / hva.height();
        const double pw = 12 + iw + 12 + 1 + 12 + hw + 12;
        Q_UNUSED(pw)
        if (!logo.isNull()) painter.drawImage(QRectF(M + 22, top + (ph - ih) / 2, iw, ih), logo);
        painter.setPen(QPen(cLine, 1)); painter.drawLine(QPointF(M + 22 + iw + 12, top + 10), QPointF(M + 22 + iw + 12, top + ph - 10));
        if (!hva.isNull()) painter.drawImage(QRectF(M + 22 + iw + 25, top + (ph - hh) / 2, hw, hh), hva);
        textAt(model.code, W - M - 12 - width(model.code, 10, true), H - 57, 10, true, cNavy);
        const QString source = QStringLiteral("VERSIÓN %1").arg(model.version);
        textAt(source, W - M - 12 - width(source, 8, false), H - 72, 8, false, cMuted);
        textAt(secNum + QStringLiteral("  ") + secTitle + (continuation ? QStringLiteral(" (continuación)") : QString()), M + 12, H - 138, 18, true, Qt::white);
        y = H - 156;
    }
    void section(const QString &n, const QString &t) { secNum = n; secTitle = t; newPage(); }
    void ensure(double h) { if (y - h < BOTTOM) newPage(true); }
    void lines(const QStringList &ls, double x, double top, bool bold, double size, const QColor &c) {
        for (int i = 0; i < ls.size(); ++i) if (!ls[i].isEmpty()) textAt(ls[i], x, top - size - i * LINE, size, bold, c);
    }
    void paragraph(const QString &v, double size = 10, bool bold = false, const QColor &c = cMuted) {
        for (const auto &l : wrap(v, BODY, bold, size)) { ensure(LINE + 4); lines({l}, M, y, bold, size, c); y -= LINE; }
        y -= 8;
    }
    void caption(const QString &v) {
        ensure(90);
        rect(M, y - 20, BODY, 20, cGreen);
        textAt(v, M + 8, y - 14, 10, true, Qt::white);
        y -= 26;
    }
    void table(const QStringList &headers, const QList<double> &widths, const QList<QStringList> &values) {
        auto header = [&]() {
            QList<QStringList> hl; int maxL = 1;
            for (int i = 0; i < headers.size(); ++i) { hl << wrap(headers[i], widths[i] - 16, true, 9); maxL = qMax(maxL, int(hl.last().size())); }
            const double h = maxL * LINE + 12;
            rect(M, y - h, BODY, h, cSecondary);
            double x = M;
            for (int i = 0; i < hl.size(); ++i) { lines(hl[i], x + 8, y - 6, true, 9, Qt::white); x += widths[i]; }
            y -= h;
        };
        ensure(70); header();
        for (int r = 0; r < values.size(); ++r) {
            QList<QStringList> cells; int total = 1;
            for (int i = 0; i < widths.size(); ++i) { cells << wrap(values[r].value(i), widths[i] - 16, false, 9.5); total = qMax(total, int(cells.last().size())); }
            int offset = 0;
            while (offset < total) {
                const double remaining = (total - offset) * LINE + 14;
                if (y - qMin(remaining, 38.0) < BOTTOM) { newPage(true); header(); }
                const int count = qMax(1, qMin(total - offset, int(std::floor((y - BOTTOM - 14) / LINE))));
                const double h = count * LINE + 14;
                rect(M, y - h, BODY, h, r % 2 ? cPale : QColor(Qt::white));
                double x = M;
                for (int i = 0; i < cells.size(); ++i) { lines(cells[i].mid(offset, count), x + 8, y - 7, false, 9.5, cNavy); x += widths[i]; }
                painter.setPen(QPen(cLine, 0.5)); painter.drawLine(QPointF(M, H - (y - h)), QPointF(M + BODY, H - (y - h)));
                y -= h; offset += count;
                if (offset < total) { newPage(true); header(); }
            }
        }
        y -= 14;
    }
};
}

bool RenditionSnapshotExporter::write(const SnapshotExportModel &m, const QString &format,
                                       const QString &path, QString *error)
{
    const QList<ExportEvidence> evidence = evidenceOf(m);
    const QList<ExportRow> rows = rowsOf(m, evidence);
    const QString name = m.displayName.isEmpty() ? m.code : m.displayName;
    const QString period = dateLabel(m.periodStart) + QStringLiteral(" al ") + dateLabel(m.periodEnd);
    const QString evLabel = QStringLiteral("E%1");
    if (format == QLatin1String("xlsx")) {
#ifdef INGE_HAS_QXLSX
        using namespace QXlsx;
        Document x;
        auto fmt = [](const QColor &fill, const QColor &ink, int size, bool bold) {
            Format f; f.setFontName(QStringLiteral("Arial")); f.setFontSize(size); f.setFontBold(bold); f.setFontColor(ink);
            if (fill.isValid()) f.setPatternBackgroundColor(fill);
            f.setVerticalAlignment(Format::AlignVCenter); f.setTextWrap(true); f.setIndent(1);
            return f;
        };
        auto body = [&](int row, bool alt) {
            Format f = fmt(alt ? cPale : QColor(Qt::white), cNavy, 11, false);
            f.setBottomBorderStyle(Format::BorderThin); f.setBottomBorderColor(cLine);
            f.setRightBorderStyle(Format::BorderThin); f.setRightBorderColor(cLine);
            Q_UNUSED(row) return f;
        };
        auto band = [&](const QString &range, const QString &value, int size, const QColor &color) {
            Format f = fmt(color, Qt::white, size, true);
            const CellRange r(range);
            if (r.rowCount() > 1 || r.columnCount() > 1) x.mergeCells(r, f);
            x.currentWorksheet()->writeString(r.firstRow(), r.firstColumn(), value, f);
        };
        // Una sola imagen: Ingema | HVA Group centrados en vertical (siempre alineados).
        QImage xLogos;
        {
            const QImage ing = exportImage("INGEMA_CONSULTORES_LOGO.png").scaledToHeight(168, Qt::SmoothTransformation);
            const QImage hvaImg = exportImage("HVA_GROUP_LOGO.png").scaledToHeight(144, Qt::SmoothTransformation);
            if (!ing.isNull()) {
                const int gap = 56, h = 192, w = ing.width() + (hvaImg.isNull() ? 0 : gap * 2 + 4 + hvaImg.width());
                xLogos = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
                xLogos.fill(Qt::transparent);
                QPainter lp(&xLogos);
                lp.setRenderHint(QPainter::SmoothPixmapTransform);
                lp.drawImage(0, (h - ing.height()) / 2, ing);
                if (!hvaImg.isNull()) {
                    lp.fillRect(QRect(ing.width() + gap, 28, 4, h - 56), cLine);
                    lp.drawImage(ing.width() + gap * 2 + 4, (h - hvaImg.height()) / 2, hvaImg);
                }
                lp.end();
                // Se conserva en alta resolución; el tamaño visible lo fija el anclaje de dos celdas.
            }
        }
        auto prepare = [&](const QString &last, const QString &title, const QString &subtitle, const QList<double> &colWidths) {
            // Fila del título en blanco: logos a color (Ingema + HVA Group) y título azul marino.
            Format t = fmt(QColor(Qt::white), cNavy, 18, true); t.setHorizontalAlignment(Format::AlignRight);
            t.setBottomBorderStyle(Format::BorderMedium); t.setBottomBorderColor(cNavy);
            x.mergeCells(CellRange(QStringLiteral("A1:") + last + QStringLiteral("1")), t);
            x.currentWorksheet()->writeString(1, 1, title, t);
            x.setRowHeight(1, 54);
            if (!xLogos.isNull()) {
                // Nítido: imagen 2x mostrada a 46 px de alto, desde (18, 13) dentro de A1.
                const double shownH = 46, shownW = shownH * xLogos.width() / xLogos.height();
                double right = 18 + shownW; int col = 0;
                while (col < colWidths.size()) {
                    const double px = std::floor(colWidths[col] * 7 + 5);
                    if (right <= px) break;
                    right -= px; ++col;
                }
                x.insertImageTwoCell(0, 0, QPoint(18, 13), 0, col, QPoint(int(right), int(13 + shownH)), xLogos);
            }
            Format s = fmt(cPale, cMuted, 10, false);
            x.mergeCells(CellRange(QStringLiteral("A2:") + last + QStringLiteral("2")), s);
            x.currentWorksheet()->writeString(2, 1, subtitle, s);
            x.setRowHeight(2, 32);
            band(QStringLiteral("A3:") + last + QStringLiteral("3"), QString(), 1, cBlue);
            x.setRowHeight(3, 6);
        };
        auto header = [&](int row, const QStringList &labels) {
            Format f = fmt(cSecondary, Qt::white, 10, true); f.setHorizontalAlignment(Format::AlignHCenter); f.setIndent(0);
            for (int i = 0; i < labels.size(); ++i) x.currentWorksheet()->writeString(row, i + 1, labels[i], f);
            x.setRowHeight(row, 42);
        };
        auto put = [&](int row, int col, const QVariant &v, const Format &f) {
            if (v.metaType().id() == QMetaType::Double || v.metaType().id() == QMetaType::Int) x.write(row, col, v, f);
            else x.currentWorksheet()->writeString(row, col, v.toString(), f);   // texto: nunca fórmula
        };
        auto fit = [&](int row, const QVariantList &values, const QList<double> &widths) {
            int linesN = 1;
            for (int i = 0; i < values.size(); ++i) {
                const double w = qMax(8.0, widths.value(i, 18) - 2);
                int n = 0; for (const auto &l : values[i].toString().split(QLatin1Char('\n'))) n += qMax(1, int(std::ceil(l.size() / w)));
                linesN = qMax(linesN, n);
            }
            x.setRowHeight(row, qMin(409, qMax(30, linesN * 15 + 8)));
        };

        // --- Resumen
        if (!x.addSheet(QStringLiteral("Resumen")) || !x.selectSheet(QStringLiteral("Resumen"))) { *error = QStringLiteral("No se pudo crear la hoja Resumen."); return false; }
        x.setColumnWidth(1, 12, 11); x.setColumnWidth(7, 14);
        prepare(QStringLiteral("L"), QStringLiteral("RENDICIÓN DE GASTOS"), QStringLiteral("%1 | VERSIÓN %2 | %3").arg(name).arg(m.version).arg(m.status), {11, 11, 11, 11, 11, 11, 14, 11, 11, 11, 11, 11});
        band(QStringLiteral("A4:L4"), QStringLiteral("DATOS GENERALES"), 11, cBlue);
        const QList<QStringList> pairs = {{"Código", m.code, "Responsable", m.owner}, {"Periodo", period, "Estado", m.status},
                                          {"Proyecto", m.project, "Fuente", QStringLiteral("Snapshot · versión %1").arg(m.version)}};
        for (int i = 0; i < pairs.size(); ++i) {
            const int row = 5 + i;
            Format b = body(row, row % 2 == 0), lb = b; lb.setFontBold(true); lb.setFontColor(cSecondary); lb.setFontSize(10);
            x.currentWorksheet()->writeString(row, 1, pairs[i][0], lb);
            x.mergeCells(CellRange(row, 2, row, 6), b); x.currentWorksheet()->writeString(row, 2, pairs[i][1], b);
            x.currentWorksheet()->writeString(row, 7, pairs[i][2], lb);
            x.mergeCells(CellRange(row, 8, row, 12), b); x.currentWorksheet()->writeString(row, 8, pairs[i][3], b);
            x.setRowHeight(row, row == 7 ? 38 : 28);
        }
        const QList<QStringList> cards = {{"A", "C", "TOTAL PEN"}, {"D", "F", "TOTAL USD"}, {"G", "I", "GASTOS"}, {"J", "L", "EVIDENCIAS"}};
        const QList<QVariant> cardValues = {sumCurrency(rows, "PEN"), sumCurrency(rows, "USD"), int(rows.size()), int(evidence.size())};
        for (int i = 0; i < cards.size(); ++i) {
            Format h = fmt(cSecondary, Qt::white, 10, true); h.setHorizontalAlignment(Format::AlignHCenter);
            x.mergeCells(CellRange(cards[i][0] + "10:" + cards[i][1] + "10"), h); x.currentWorksheet()->writeString(10, 1 + i * 3, cards[i][2], h);
            Format v = fmt(cSecondary, Qt::white, 22, true); v.setHorizontalAlignment(Format::AlignHCenter); v.setIndent(0);
            if (i < 2) v.setNumberFormat(i == 0 ? QStringLiteral("\"S/ \" #,##0.00") : QStringLiteral("\"USD \" #,##0.00"));
            x.mergeCells(CellRange(cards[i][0] + "11:" + cards[i][1] + "13"), v); x.write(11, 1 + i * 3, cardValues[i], v);
        }
        band(QStringLiteral("A15:L15"), QStringLiteral("CONTROL DE LA RENDICIÓN"), 11, cGreen);
        int pendingAmounts = 0, noSupport = 0;
        for (const auto &r : rows) { if (r.amount.toString().isEmpty()) ++pendingAmounts; if (!r.withSupport) ++noSupport; }
        QList<QVariantList> control = {{QStringLiteral("Sin sustento"), noSupport, QStringLiteral("Con sustento = No; no acredita revisión del comprobante.")},
                                       {QStringLiteral("Monto pendiente"), pendingAmounts, QStringLiteral("Se conserva vacío; no se convierte en cero.")}};
        if (m.financialSupplements && m.funding.value("enabled", true).toBool()) {
            const QString rate = text(m.exchangeRate, "rate");
            const QString note = QStringLiteral("Fondo original: S/ %1 + USD %2. %3 Fondo y cambio conservados para esta versión.")
                .arg(m.funding.value("pen").toDouble(), 0, 'f', 2).arg(m.funding.value("usd").toDouble(), 0, 'f', 2)
                .arg(rate.isEmpty() ? QStringLiteral("Requiere cambio para equivalencias.") : QStringLiteral("1 USD = S/ %1. %2").arg(rate,
                     text(m.exchangeRate, "mode") == QLatin1String("AUTOMATIC") ? QStringLiteral("BCRP/SBS venta %1.").arg(text(m.exchangeRate, "quoted_on")) : QStringLiteral("Manual.")));
            control.append({QStringLiteral("Saldo equivalente PEN"), balanceOf(m, rows, true), note});
            control.append({QStringLiteral("Saldo equivalente USD"), balanceOf(m, rows, false), note});
        }
        for (int i = 0; i < control.size(); ++i) {
            const int row = 16 + i;
            Format b = body(row, row % 2 == 0); b.setFontSize(10);
            x.mergeCells(CellRange(row, 1, row, 3), b); x.currentWorksheet()->writeString(row, 1, control[i][0].toString(), b);
            Format c = b; c.setHorizontalAlignment(Format::AlignHCenter);
            if (control[i][1].metaType().id() == QMetaType::Double) c.setNumberFormat(QStringLiteral("#,##0.00"));
            put(row, 4, control[i][1], c);
            x.mergeCells(CellRange(row, 5, row, 12), b); x.currentWorksheet()->writeString(row, 5, control[i][2].toString(), b);
            x.setRowHeight(row, 30);
        }
        const int noteRow = 17 + control.size();
        Format nf = fmt(QColor(), cMuted, 10, false);
        x.mergeCells(CellRange(noteRow, 1, noteRow, 12), nf);
        x.currentWorksheet()->writeString(noteRow, 1, QStringLiteral("Archivo derivado del snapshot inmutable indicado en Versión."), nf);
        x.setRowHeight(noteRow, 30);
        const int groupRow = noteRow + 2;
        band(QStringLiteral("A%1:F%1").arg(groupRow), QStringLiteral("POR PROYECTO"), 11, cGreen);
        band(QStringLiteral("G%1:L%1").arg(groupRow), QStringLiteral("POR CATEGORÍA"), 11, cGreen);
        auto groups = [&](bool project, int start) {
            Format h = fmt(cSecondary, Qt::white, 10, true);
            x.mergeCells(CellRange(groupRow + 1, start, groupRow + 1, start + 3), h);
            x.currentWorksheet()->writeString(groupRow + 1, start, project ? QStringLiteral("Proyecto") : QStringLiteral("Categoría"), h);
            x.currentWorksheet()->writeString(groupRow + 1, start + 4, QStringLiteral("PEN"), h);
            x.currentWorksheet()->writeString(groupRow + 1, start + 5, QStringLiteral("USD"), h);
            const QStringList labels = uniqueLabels(rows, project);
            for (int i = 0; i < labels.size(); ++i) {
                const int row = groupRow + 2 + i;
                Format c = fmt(cPale, cNavy, 10, false); c.setBottomBorderStyle(Format::BorderThin); c.setBottomBorderColor(cLine);
                x.mergeCells(CellRange(row, start, row, start + 3), c);
                x.currentWorksheet()->writeString(row, start, labels[i].isEmpty() ? QStringLiteral("Sin asignar") : labels[i], c);
                QList<ExportRow> sub; for (const auto &r : rows) if ((project ? r.project : r.category) == labels[i]) sub << r;
                Format n = c; n.setNumberFormat(QStringLiteral("#,##0.00"));
                x.write(row, start + 4, sumCurrency(sub, "PEN"), n); x.write(row, start + 5, sumCurrency(sub, "USD"), n);
                x.setRowHeight(row, 38);
            }
        };
        groups(true, 1); groups(false, 7);
        x.setRowHeight(groupRow + 1, 28);

        // --- Detalle_Gastos
        if (!x.addSheet(QStringLiteral("Detalle_Gastos")) || !x.selectSheet(QStringLiteral("Detalle_Gastos"))) { *error = QStringLiteral("No se pudo crear la hoja Detalle_Gastos."); return false; }
        const QStringList cols = {"N.º", "Fecha", "Proyecto", "Categoría", "Concepto", "Proveedor / beneficiario", "Medio de pago", "Tipo de sustento",
                                  "N.º comprobante / operación", "Monto", "Con sustento", "Justificación", "Evidencia", "Estado de revisión"};
        const QList<double> widths = {7, 12, 21, 18, 34, 23, 17, 22, 22, 14, 13, 34, 25, 18};
        for (int i = 0; i < widths.size(); ++i) x.setColumnWidth(i + 1, widths[i]);
        prepare(QStringLiteral("N"), QStringLiteral("DETALLE DE GASTOS"), QStringLiteral("%1 | %2 | VERSIÓN %3").arg(m.code, name).arg(m.version), widths);
        header(4, cols);
        for (int i = 0; i < rows.size(); ++i) {
            const auto &r = rows[i]; const int row = 5 + i;
            Format b = body(row, row % 2 == 0), center = b; center.setHorizontalAlignment(Format::AlignHCenter);
            QStringList files; for (const auto &f : evidence) if (f.expenseId == r.id) files << f.fileName;
            const QVariantList values = {r.line, dateLabel(r.date), r.project, r.category, r.conceptText, r.beneficiary, r.payment, r.support,
                                         r.supportNumber, QVariant(), r.withSupport ? "Sí" : "No", r.justification, files.join("\n"), r.review.isEmpty() ? "PENDIENTE" : r.review};
            for (int c = 0; c < values.size(); ++c) if (c != 9) put(row, c + 1, values[c], c == 0 || c == 1 || c == 10 ? center : b);
            Format mny = b; mny.setHorizontalAlignment(Format::AlignRight);
            mny.setNumberFormat(r.currency == QLatin1String("USD") ? QStringLiteral("\"USD \" #,##0.00") : QStringLiteral("\"S/ \" #,##0.00"));
            if (r.amount.toString().isEmpty()) x.currentWorksheet()->writeBlank(row, 10, mny); else x.write(row, 10, r.amount.toDouble(), mny);
            Format sup = center; sup.setFontBold(true); sup.setFontColor(r.withSupport ? cGreen : cSecondary);
            x.currentWorksheet()->writeString(row, 11, r.withSupport ? QStringLiteral("Sí") : QStringLiteral("No"), sup);
            x.currentWorksheet()->writeString(row, 15, r.currency, b);
            fit(row, values, widths);
        }
        x.currentWorksheet()->writeString(4, 15, QStringLiteral("Moneda"));
        x.setColumnHidden(15, true);

        // --- Evidencias
        if (!x.addSheet(QStringLiteral("Evidencias")) || !x.selectSheet(QStringLiteral("Evidencias"))) { *error = QStringLiteral("No se pudo crear la hoja Evidencias."); return false; }
        const QList<double> ew = {32, 10, 18, 32, 23, 26, 18, 24};
        for (int i = 0; i < ew.size(); ++i) x.setColumnWidth(i + 1, ew[i]);
        prepare(QStringLiteral("H"), QStringLiteral("ÍNDICE DE EVIDENCIAS"), m.code + QStringLiteral(" | Referencias de los archivos; los adjuntos no están incrustados en este Excel."), ew);
        header(4, {"ID de evidencia", "N.º gasto", "Tipo", "Archivo", "Fecha de carga (UTC)", "Usuario / ID", "Estado", "N.º documento"});
        for (int i = 0; i < evidence.size(); ++i) {
            const auto &f = evidence[i]; const int row = 5 + i;
            int line = 0; for (const auto &r : rows) if (r.id == f.expenseId) line = r.line;
            const QVariantList values = {f.id, line ? QVariant(line) : QVariant(QString()), f.mimeType, f.fileName, timestampLabel(f.createdAt), f.createdBy,
                                         f.status.isEmpty() ? QStringLiteral("Referencia") : f.status, f.documentNumber};
            for (int c = 0; c < values.size(); ++c) put(row, c + 1, values[c], body(row, row % 2 == 0));
            fit(row, values, ew);
        }

        // --- Versión
        if (!x.addSheet(QStringLiteral("Versión")) || !x.selectSheet(QStringLiteral("Versión"))) { *error = QStringLiteral("No se pudo crear la hoja Versión."); return false; }
        x.setColumnWidth(1, 24); x.setColumnWidth(2, 90);
        prepare(QStringLiteral("B"), QStringLiteral("DATOS DE VERSIÓN"), m.code + QStringLiteral(" | Trazabilidad de la exportación"), {24, 90});
        header(4, {"Campo", "Valor"});
        const QList<QStringList> meta = {{"Nombre", name}, {"RDC", m.code}, {"Propietario", m.owner}, {"Proyecto principal", m.project}, {"Periodo", period},
                                         {"Estado", m.status}, {"Versión", QString::number(m.version)}, {"Hash", m.hash}, {"Presentada", m.submittedAt},
                                         {"Fuente", "Snapshot inmutable; archivo derivado"}, {"Diseño", "PROTOTIPO_RENDICIONES_INGEPLUS_V01 · adaptación a datos disponibles"}};
        for (int i = 0; i < meta.size(); ++i) {
            const int row = 5 + i;
            for (int c = 0; c < 2; ++c) x.currentWorksheet()->writeString(row, c + 1, meta[i][c], body(row, row % 2 == 0));
            fit(row, {meta[i][0], meta[i][1]}, {24, 90});
        }
        x.selectSheet(QStringLiteral("Resumen"));
        if (x.saveAs(path)) return true;
        *error = QStringLiteral("No se pudo guardar el Excel del snapshot.");
#else
        Q_UNUSED(m) Q_UNUSED(path)
        *error = QStringLiteral("QXlsx no está enlazado.");
#endif
        return false;
    }
    if (format != QLatin1String("pdf")) {
        *error = QStringLiteral("Formato de exportación no soportado.");
        return false;
    }

    // Dos pasadas: la primera cuenta las páginas para el pie «Página X de Y».
    auto render = [&](const QString &target, int total) -> int {
            QPdfWriter pdf(target);
        pdf.setResolution(72);                                   // 1 unidad = 1 punto (igual que pdf-lib)
        pdf.setPageSize(QPageSize(QPageSize::A4));
        pdf.setPageMargins(QMarginsF(0, 0, 0, 0), QPageLayout::Point);
        pdf.setCreator(QStringLiteral("InGe+ Android"));
        pdf.setTitle(QStringLiteral("Expediente ") + m.code);
        QPainter painter(&pdf);
        if (!painter.isActive()) return -1;
        painter.setRenderHint(QPainter::Antialiasing);
        PdfLayout L(pdf, painter, m);
        L.total = total;
        const double BODY = PdfLayout::BODY;

        L.section("01", QStringLiteral("Resumen de la rendición"));
        L.paragraph(name, 11, true, cSecondary);
        L.table({"Dato", "Información"}, {112, BODY - 112},
                {{"Código", m.code}, {"Responsable", m.owner}, {"Periodo", period}, {"Proyecto principal", m.project}, {"Estado", m.status}});
        L.ensure(94);
        const QList<QStringList> cards = {{"TOTAL PEN", money(sumCurrency(rows, "PEN"), "PEN")}, {"TOTAL USD", money(sumCurrency(rows, "USD"), "USD")},
                                          {"GASTOS", QString::number(rows.size())}, {"EVIDENCIAS", QString::number(evidence.size())}};
        const double cw = (BODY - 24) / 4;
        for (int i = 0; i < cards.size(); ++i) {
            const double cx = PdfLayout::M + i * (cw + 8);
            L.rect(cx, L.y - 65, cw, 65, cSecondary);
            L.textAt(cards[i][0], cx + 10, L.y - 18, 8, true, Qt::white);
            const double size = qMin(18.0, 18.0 * (cw - 20) / qMax(1.0, L.width(cards[i][1], 18, true)));
            L.textAt(cards[i][1], cx + 10, L.y - 45, size, true, Qt::white);
        }
        L.y -= 82;
        if (m.financialSupplements && m.funding.value("enabled", true).toBool()) {
            L.caption(QStringLiteral("Fondo y saldo equivalente"));
            const bool hasRate = m.exchangeRate.value("rate").toDouble() > 0;
            L.table({"Moneda", "Fondo equivalente", "Saldo equivalente"}, {112, 170, BODY - 282},
                    {{"PEN", money(fundEquivalent(m, true), "PEN"), money(balanceOf(m, rows, true), "PEN")},
                     {"USD", hasRate ? money(fundEquivalent(m, false), "USD") : QStringLiteral("Sin tipo de cambio"),
                             hasRate ? money(balanceOf(m, rows, false), "USD") : QStringLiteral("Sin tipo de cambio")}});
            const QString rate = text(m.exchangeRate, "rate");
            L.paragraph(QStringLiteral("Fondo original: S/ %1 + USD %2. %3").arg(m.funding.value("pen").toDouble(), 0, 'f', 2).arg(m.funding.value("usd").toDouble(), 0, 'f', 2)
                        .arg(rate.isEmpty() ? QStringLiteral("Sin tipo de cambio registrado.") : QStringLiteral("1 USD = S/ %1. %2").arg(rate,
                             text(m.exchangeRate, "mode") == QLatin1String("AUTOMATIC") ? QStringLiteral("BCRP/SBS venta %1.").arg(text(m.exchangeRate, "quoted_on")) : QStringLiteral("Manual."))), 9);
            L.paragraph(QStringLiteral("Fondo conservado para esta versión; diferencia sobre sus gastos declarados, no liquidación."), 9);
        }
        L.caption(QStringLiteral("Control de la rendición"));
        int noSupport = 0, pending = 0;
        for (const auto &r : rows) { if (!r.withSupport) ++noSupport; if (r.amount.toString().isEmpty()) ++pending; }
        L.rect(PdfLayout::M, L.y - 32, BODY, 32, cPale);
        L.textAt(QStringLiteral("Gastos sin sustento: %1").arg(noSupport), PdfLayout::M + 10, L.y - 20, 10, false, cSecondary);
        L.textAt(QStringLiteral("Montos pendientes: %1").arg(pending), PdfLayout::M + BODY / 2, L.y - 20, 10, false, cSecondary);
        L.y -= 48;
        auto groups = [&](bool project, const QString &title) {
            const QStringList labels = uniqueLabels(rows, project);
            if (labels.isEmpty()) return;
            L.caption(title);
            QList<QStringList> values;
            for (const auto &lbl : labels) {
                QList<ExportRow> sub; for (const auto &r : rows) if ((project ? r.project : r.category) == lbl) sub << r;
                values << QStringList{lbl.isEmpty() ? QStringLiteral("Sin asignar") : lbl, QString::number(sumCurrency(sub, "PEN"), 'f', 2), QString::number(sumCurrency(sub, "USD"), 'f', 2)};
            }
            L.table({project ? "Proyecto" : "Categoría", "PEN", "USD"}, {BODY - 164, 82, 82}, values);
        };
        groups(false, QStringLiteral("Distribución por categoría"));
        groups(true, QStringLiteral("Distribución por proyecto"));
        L.paragraph(QStringLiteral("Documento derivado de la versión inmutable identificada en la sección 04."), 9);

        L.section("02", QStringLiteral("Detalle de gastos"));
        if (rows.isEmpty()) L.paragraph(QStringLiteral("No hay gastos en la fuente de esta exportación."));
        QList<QStringList> detail;
        for (const auto &r : rows) {
            QStringList links; for (int i = 0; i < evidence.size(); ++i) if (evidence[i].expenseId == r.id) links << evLabel.arg(i + 1, 2, 10, QLatin1Char('0'));
            detail << QStringList{QStringLiteral("%1. %2").arg(r.line).arg(r.date.isEmpty() ? QStringLiteral("Fecha pendiente") : dateLabel(r.date)),
                QStringLiteral("%1\nProyecto: %2\nCategoría: %3\nProveedor / beneficiario: %4\nPago: %5\nSustento: %6\nN.º comprobante: %7\nJustificación: %8")
                    .arg(r.conceptText.isEmpty() ? "Concepto pendiente" : r.conceptText, r.project.isEmpty() ? "Sin asignar" : r.project, r.category.isEmpty() ? "Pendiente" : r.category,
                         r.beneficiary.isEmpty() ? "Sin registrar" : r.beneficiary, r.payment.isEmpty() ? "Pendiente" : r.payment, r.support.isEmpty() ? "Pendiente" : r.support,
                         r.supportNumber.isEmpty() ? "Sin registrar" : r.supportNumber, r.justification.isEmpty() ? "Pendiente" : r.justification),
                QStringLiteral("%1\nCon sustento: %2\n%3\nRevisión: %4").arg(money(r.amount, r.currency), r.withSupport ? "Sí" : "No",
                    links.isEmpty() ? "Sin adjuntos" : links.join(", "), r.review.isEmpty() ? "PENDIENTE" : r.review)};
        }
        L.table({"Gasto / fecha", "Concepto y datos", "Importe / evidencia"}, {88, BODY - 202, 114}, detail);

        L.section("03", QStringLiteral("Índice de evidencias"));
        L.paragraph(QStringLiteral("Los códigos E01, E02... relacionan cada archivo con sus gastos. Se conservan las referencias documentales; los originales están disponibles en la ficha y no se incrustan en el PDF."), 9);
        if (evidence.isEmpty()) L.paragraph(QStringLiteral("Sin archivos adjuntos en esta fuente."));
        QList<QStringList> evRows;
        for (int i = 0; i < evidence.size(); ++i) {
            const auto &f = evidence[i];
            QString line = QStringLiteral("sin identificar"); for (const auto &r : rows) if (r.id == f.expenseId) line = QString::number(r.line);
            evRows << QStringList{evLabel.arg(i + 1, 2, 10, QLatin1Char('0')) + QStringLiteral("\nGasto ") + line,
                QStringLiteral("%1\nTipo: %2\nN.º documento: %3").arg(f.fileName, f.mimeType.isEmpty() ? "Sin registrar" : f.mimeType, f.documentNumber.isEmpty() ? "Sin registrar" : f.documentNumber),
                QStringLiteral("%1\nID: %2\nUsuario / ID: %3\nEstado: %4").arg(f.createdAt.isEmpty() ? "Sin registrar" : timestampLabel(f.createdAt),
                    f.id.isEmpty() ? "Sin registrar" : f.id, f.createdBy.isEmpty() ? "Sin registrar" : f.createdBy, f.status.isEmpty() ? "Referencia" : f.status)};
        }
        L.table({"Referencia", "Archivo / documento", "Carga y trazabilidad"}, {80, BODY - 278, 198}, evRows);

        L.section("04", QStringLiteral("Versión y trazabilidad"));
        L.table({"Campo", "Información"}, {132, BODY - 132},
                {{"Nombre", name}, {"Código", m.code}, {"Responsable", m.owner}, {"Estado", m.status}, {"Versión", QString::number(m.version)},
                 {"Hash de versión", m.hash}, {"Presentada", m.submittedAt.isEmpty() ? "Sin presentación registrada" : m.submittedAt},
                 {"Fuente", "Snapshot inmutable autorizado. Archivo derivado."}});
        L.paragraph(QStringLiteral("Esta exportación conserva los datos de la versión indicada; el documento maestro es su snapshot inmutable."));
        L.paragraph(QStringLiteral("La presencia de un comprobante o archivo se identifica como Con sustento: Sí. No constituye por sí sola una validación fiscal o aprobación del gasto."), 9);
        L.footer();
        painter.end();
        return L.pages;
    };
    QTemporaryDir tmp;
    const int counted = tmp.isValid() ? render(tmp.filePath(QStringLiteral("count.pdf")), 0) : 0;
    if (render(path, counted) < 0) { *error = QStringLiteral("No se pudo iniciar el PDF."); return false; }

    if (QFileInfo(path).size() > 0) return true;
    *error = QStringLiteral("El PDF está vacío.");
    return false;
}
