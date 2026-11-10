#pragma once

// Port of ingeplus-main/src/lib/calicatas/exportPagination.ts (04-11-2026).
// Shared, integer-centimetre pagination for Android XLSX and PDF.
// No background uploads, no reliance on a browser or Excel/COM.
#include <QVariantMap>
#include <QVariantList>
#include <QVector>
#include <QString>
#include <QtMath>
#include <algorithm>
#include <cmath>

namespace CalicataExportPages {
constexpr int kBaseRow = 22;
constexpr int kRows = 60;
constexpr int kStepCm = 5;
constexpr int kPageCm = 300;
constexpr int kNativeMaxPages = 10; // Preformatted, byte-faithful QXlsx sheets.

inline bool centimetres(const QVariant &value, int *result)
{
    if (!value.isValid() || value.isNull() || value.toString().trimmed().isEmpty()) return false;
    QString text = value.toString().trimmed();
    text.replace(QLatin1Char(','), QLatin1Char('.'));
    bool ok = false;
    const double metres = text.toDouble(&ok);
    if (!ok || !std::isfinite(metres) || metres < 0 || metres > 10000) return false;
    *result = qRound(metres * 100.0);
    return true;
}

struct Fragment {
    QVariantMap row;
    int sequence = 0;
    int fullFromCm = 0;
    int fullToCm = 0;
    int fromCm = 0;
    int toCm = 0;
    int firstRow = kBaseRow;
    int lastRow = kBaseRow;
    int partNumber = 1;
    int partCount = 1;
    bool firstPart() const { return partNumber == 1; }
    bool continuesAbove() const { return partNumber > 1; }
    bool continuesBelow() const { return partNumber < partCount; }
};

struct Page {
    int number = 1;
    int count = 1;
    int originCm = 0;
    int endCm = kPageCm;
    int totalCm = kPageCm;
    QVector<Fragment> fragments;
    int lastDataRow() const { return std::min(81, 21 + (endCm - originCm) / kStepCm); }
    int closingRow() const { return number == count ? kBaseRow + (endCm - originCm) / kStepCm : -1; }
};

inline QVector<Page> paginate(const QVariantMap &header, const QVariantList &cuts, QString *error = nullptr)
{
    struct Whole { QVariantMap data; int sequence; int from; int to; };
    QVector<Whole> valid;
    int deepestCm = 0;
    int sequence = 0;
    for (const QVariant &value : cuts) {
        const QVariantMap row = value.toMap();
        ++sequence;
        int from = 0, to = 0;
        const QVariant fromV = row.contains(QStringLiteral("de")) ? row.value(QStringLiteral("de")) : row.value(QStringLiteral("desde"));
        const QVariant toV = row.contains(QStringLiteral("a")) ? row.value(QStringLiteral("a")) : row.value(QStringLiteral("hasta"));
        // The web skips incomplete/invalid strata while retaining declared depth.
        if (!centimetres(fromV, &from) || !centimetres(toV, &to)
            || to <= from || from % kStepCm || to % kStepCm) continue;
        valid.push_back({row, sequence, from, to});
        deepestCm = std::max(deepestCm, to);
    }
    int requestedCm = 0;
    const QVariant requested = header.contains(QStringLiteral("requested_depth_m"))
        ? header.value(QStringLiteral("requested_depth_m")) : header.value(QStringLiteral("depth_m"));
    centimetres(requested, &requestedCm);
    const int measuredCm = std::max(requestedCm, deepestCm);
    const int totalCm = measuredCm > 0 ? measuredCm : kPageCm;
    const int count = std::max(1, (totalCm + kPageCm - 1) / kPageCm);
    if (count > kNativeMaxPages) {
        if (error) *error = QStringLiteral("La profundidad requiere %1 hojas; la plantilla Android admite %2. No se generó un archivo incompleto.")
            .arg(count).arg(kNativeMaxPages);
        return {};
    }
    QVector<Page> pages;
    pages.reserve(count);
    for (int index = 0; index < count; ++index) {
        Page page;
        page.number = index + 1;
        page.count = count;
        page.originCm = index * kPageCm;
        page.endCm = std::min((index + 1) * kPageCm, totalCm);
        page.totalCm = measuredCm;
        for (const Whole &stratum : valid) {
            const int from = std::max(page.originCm, stratum.from);
            const int to = std::min(page.originCm + kPageCm, stratum.to);
            if (to <= from) continue;
            Fragment part;
            part.row = stratum.data;
            part.sequence = stratum.sequence;
            part.fullFromCm = stratum.from;
            part.fullToCm = stratum.to;
            part.fromCm = from;
            part.toCm = to;
            part.firstRow = kBaseRow + (from - page.originCm) / kStepCm;
            part.lastRow = kBaseRow + (to - page.originCm) / kStepCm - 1;
            part.partCount = ((stratum.to - kStepCm) / kPageCm) - (stratum.from / kPageCm) + 1;
            part.partNumber = index - stratum.from / kPageCm + 1;
            page.fragments.push_back(part);
        }
        pages.push_back(page);
    }
    return pages;
}
} // namespace CalicataExportPages
