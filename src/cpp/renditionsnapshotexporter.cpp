#include "renditionsnapshotexporter.h"

#include <QFileInfo>
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
QString escaped(const QString &s) { return s.toHtmlEscaped(); }
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
    *model = result;
    return true;
}

QString SnapshotExportModel::fileBaseName() const { return code + QStringLiteral("-v%1").arg(version); }

bool RenditionSnapshotExporter::write(const SnapshotExportModel &m, const QString &format,
                                       const QString &path, QString *error)
{
    if (format == QLatin1String("xlsx")) {
#ifdef INGE_HAS_QXLSX
        QXlsx::Document xlsx;
        // This vendored QXlsx creates its default sheet lazily: name it explicitly.
        if (!xlsx.addSheet(QStringLiteral("Gastos")) || !xlsx.selectSheet(QStringLiteral("Gastos"))) {
            *error = QStringLiteral("No se pudo crear la hoja Gastos.");
            return false;
        }
        QXlsx::Format header, cell, money;
        header.setFontBold(true);
        header.setFontColor(QColor(Qt::white));
        header.setPatternBackgroundColor(QColor(QStringLiteral("#161616")));
        cell.setTextWrap(true);
        money.setNumberFormat(QStringLiteral("0.00"));
        const QStringList columns = {QStringLiteral("RDC"), QStringLiteral("Usuario"), QStringLiteral("Project"),
            QStringLiteral("Periodo"), QStringLiteral("Fecha gasto"), QStringLiteral("Categoría"),
            QStringLiteral("Concepto"), QStringLiteral("Beneficiario"), QStringLiteral("Medio"),
            QStringLiteral("Sustento"), QStringLiteral("Número comprobante"), QStringLiteral("Moneda"),
            QStringLiteral("Monto"), QStringLiteral("Estado"), QStringLiteral("Versión"),
            QStringLiteral("Detalle pago"), QStringLiteral("Detalle sustento"), QStringLiteral("Justificación")};
        for (int i = 0; i < columns.size(); ++i) xlsx.write(1, i + 1, columns[i], header);
        xlsx.setColumnWidth(1, 15, 22);
        xlsx.setColumnWidth(3, 3, 38);
        xlsx.setColumnWidth(7, 7, 38);
        int row = 2;
        for (const auto &entry : m.expenses) {
            const auto e = entry.toMap();
            const QStringList values = {m.code, m.owner, text(e, "project_label"), m.period,
                text(e, "expense_date"), label(e, "category_name", "category_code"), text(e, "concept"),
                text(e, "beneficiary"), label(e, "payment_method_name", "payment_method_code"),
                label(e, "support_type_name", "support_type_code"), text(e, "support_number"), text(e, "currency_code")};
            // writeString prevents user-supplied text from becoming spreadsheet formulas.
            for (int i = 0; i < values.size(); ++i) xlsx.currentWorksheet()->writeString(row, i + 1, values[i], cell);
            xlsx.write(row, 13, e.value(QStringLiteral("amount")).toDouble(), money);
            xlsx.currentWorksheet()->writeString(row, 14, m.status, cell);
            xlsx.write(row, 15, m.version, cell);
            xlsx.currentWorksheet()->writeString(row, 16, text(e, "payment_method_detail"), cell);
            xlsx.currentWorksheet()->writeString(row, 17, text(e, "support_detail"), cell);
            xlsx.currentWorksheet()->writeString(row, 18, text(e, "justification"), cell);
            xlsx.setRowHeight(row++, 42);
        }
        if (!xlsx.addSheet(QStringLiteral("Versión")) || !xlsx.selectSheet(QStringLiteral("Versión"))) {
            *error = QStringLiteral("No se pudo crear la hoja Versión.");
            return false;
        }
        xlsx.write(1, 1, QStringLiteral("Campo"), header);
        xlsx.write(1, 2, QStringLiteral("Valor"), header);
        const QList<QPair<QString, QVariant>> metadata = {
            {QStringLiteral("RDC"), m.code}, {QStringLiteral("Versión"), m.version},
            {QStringLiteral("Hash"), m.hash}, {QStringLiteral("Presentada"), m.submittedAt},
            {QStringLiteral("Propietario"), m.owner}, {QStringLiteral("Periodo"), m.period},
            {QStringLiteral("Proyecto principal"), m.project},
            {QStringLiteral("Proyectos asociados"), m.projects},
            {QStringLiteral("Total PEN"), m.totalPen}, {QStringLiteral("Total USD"), m.totalUsd},
            {QStringLiteral("Fuente"), QStringLiteral("Snapshot inmutable; archivo derivado")}};
        row = 2;
        for (const auto &item : metadata) {
            xlsx.currentWorksheet()->writeString(row, 1, item.first, cell);
            if (item.second.metaType().id() == QMetaType::Int || item.second.metaType().id() == QMetaType::Double) xlsx.write(row, 2, item.second, cell);
            else xlsx.currentWorksheet()->writeString(row, 2, item.second.toString(), cell);
            ++row;
        }
        xlsx.setColumnWidth(1, 22);
        xlsx.setColumnWidth(2, 75);
        if (xlsx.saveAs(path)) return true;
        *error = QStringLiteral("No se pudo guardar el Excel del snapshot.");
#else
        Q_UNUSED(m)
        Q_UNUSED(path)
        *error = QStringLiteral("QXlsx no está enlazado.");
#endif
        return false;
    }
    if (format != QLatin1String("pdf")) {
        *error = QStringLiteral("Formato de exportación no soportado.");
        return false;
    }
    QPdfWriter pdf(path);
    pdf.setResolution(96);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setPageMargins(QMarginsF(14, 14, 14, 14), QPageLayout::Millimeter);
    pdf.setCreator(QStringLiteral("InGe+ Android"));
    pdf.setTitle(m.fileBaseName());
    QString html = QStringLiteral("<h1>INGEMA</h1><h2>EXPEDIENTE ADMINISTRATIVO DE RENDICION</h2>");
    const auto field = [&html](const QString &name, const QString &v) {
        html += QStringLiteral("<p><b>%1:</b> %2</p>").arg(escaped(name), escaped(v));
    };
    field(QStringLiteral("RDC"), m.code);
    field(QStringLiteral("Propietario"), m.owner);
    field(QStringLiteral("Periodo"), m.period);
    field(QStringLiteral("Project principal"), m.project);
    field(QStringLiteral("Estado"), m.status);
    field(QStringLiteral("Presentada"), m.submittedAt);
    field(QStringLiteral("Versión"), QString::number(m.version));
    field(QStringLiteral("Hash de versión"), m.hash);
    field(QStringLiteral("Totales"), QStringLiteral("PEN %1 | USD %2").arg(m.totalPen, 0, 'f', 2).arg(m.totalUsd, 0, 'f', 2));
    html += QStringLiteral("<h2>GASTOS</h2>");
    int index = 0;
    for (const auto &entry : m.expenses) {
        const auto e = entry.toMap();
        field(QString::number(++index), QStringLiteral("%1 | %2 | %3\n%4 | %5 | %6 %7 | %8 %9 | %10")
            .arg(text(e, "expense_date"), label(e, "category_name", "category_code"), text(e, "concept"),
                 text(e, "project_label"), label(e, "payment_method_name", "payment_method_code"),
                 label(e, "support_type_name", "support_type_code"), text(e, "support_number"),
                 text(e, "currency_code"), QString::number(e.value(QStringLiteral("amount")).toDouble(), 'f', 2), text(e, "beneficiary")));
    }
    html += QStringLiteral("<h2>REFERENCIAS DE SUSTENTOS</h2>");
    if (m.attachments.isEmpty()) html += QStringLiteral("<p>Sin archivos adjuntos en esta version.</p>");
    for (const auto &entry : m.attachments) {
        const auto a = entry.toMap();
        field(text(a, "file_name"), text(a, "support_type_code") + QStringLiteral(" | ")
              + text(a, "document_number") + QStringLiteral(" | ") + text(a, "id"));
    }
    QTextDocument doc;
    doc.setDefaultFont(QFont(QStringLiteral("Sans Serif"), 9));
    doc.setDefaultStyleSheet(QStringLiteral("h1 {color:#161616;font-size:20pt} h2 {font-size:11pt} p {margin:4px 0;white-space:pre-wrap}"));
    doc.setHtml(html);
    const int bodyHeight = pdf.height() - 44;
    doc.setPageSize(QSizeF(pdf.width(), bodyHeight));
    QPainter painter(&pdf);
    if (!painter.isActive()) { *error = QStringLiteral("No se pudo iniciar el PDF."); return false; }
    const int pages = doc.pageCount();
    for (int page = 0; page < pages; ++page) {
        if (page && !pdf.newPage()) { *error = QStringLiteral("No se pudo crear una página PDF."); return false; }
        painter.save();
        painter.setClipRect(0, 0, pdf.width(), bodyHeight);
        painter.translate(0, -page * bodyHeight);
        doc.drawContents(&painter, QRectF(0, page * bodyHeight, pdf.width(), bodyHeight));
        painter.restore();
        painter.setFont(QFont(QStringLiteral("Sans Serif"), 8));
        painter.drawText(QRect(0, bodyHeight + 8, pdf.width(), 32), Qt::TextWordWrap,
            QStringLiteral("Página %1 de %2 | Derivado - fuente maestra: snapshot %3 | %4 v%5")
                .arg(page + 1).arg(pages).arg(m.hash.left(16), m.code).arg(m.version));
    }
    painter.end();
    if (QFileInfo(path).size() > 0) return true;
    *error = QStringLiteral("El PDF está vacío.");
    return false;
}
