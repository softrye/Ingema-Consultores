#pragma once
#include <QDate>
#include <QVariantMap>
#include <QVariantList>
#include <QRegularExpression>
#include <cmath>
#include "renditionmoney.h"

namespace RenditionValidation {
// These RPC exceptions abort CREATE's transaction. Transport failures and
// idempotency conflicts are deliberately excluded: their payload stays frozen.
inline bool rejectedExpenseCreate(const QVariantMap &entry) {
    if (entry.value("operation").toString() != QLatin1String("expense_create")
        || entry.value("state").toString() != QLatin1String("ERROR")) return false;
    const auto error = entry.value("lastSafeError").toString().trimmed();
    return error == QLatin1String("RENDITION_EXPENSE_JUSTIFICATION_REQUIRED")
        || error == QLatin1String("RENDITION_EXPENSE_SUPPORT_DETAIL_REQUIRED")
        || error == QLatin1String("RENDITION_EXPENSE_PAYMENT_DETAIL_REQUIRED");
}
inline bool meaningfulText(const QString &value) {
    static const QRegularExpression words(QStringLiteral("[\\p{L}]{2,}"));
    auto matches = words.globalMatch(value);
    int count = 0; QString letters;
    while (matches.hasNext()) { letters += matches.next().captured().toCaseFolded(); ++count; }
    QString unique;
    for (const auto c : letters) if (!unique.contains(c)) unique += c;
    return count >= 2 && unique.size() >= 4;
}
inline bool date(const QString &value) {
    const auto parsed = QDate::fromString(value, Qt::ISODate);
    return parsed.isValid() && parsed.toString(Qt::ISODate) == value;
}
inline QString header(const QString &start, const QString &end,
                      const QVariantList &projects, const QString &primary,
                      const QString &folder, const QString &space) {
    if (!date(start) || !date(end) || end < start)
        return QStringLiteral("El período no es válido: la fecha final debe ser mayor o igual a la inicial.");
    if (primary.isEmpty() || !projects.contains(primary))
        return QStringLiteral("Selecciona proyectos asociados y un proyecto principal.");
    if (folder.isEmpty() || space.isEmpty())
        return QStringLiteral("Selecciona una carpeta documental dentro del proyecto.");
    return {};
}
inline QString expense(const QVariantMap &draft, const QVariantMap &row) {
    const auto day = row.value(QStringLiteral("expenseDate")).toString();
    if (!date(day) || day < draft.value(QStringLiteral("periodStart")).toString()
        || day > draft.value(QStringLiteral("periodEnd")).toString())
        return QStringLiteral("La fecha del gasto debe estar dentro del período de la rendición.");
    if (!draft.value(QStringLiteral("projectIds")).toList().contains(row.value(QStringLiteral("projectId"))))
        return QStringLiteral("El proyecto del gasto debe estar asociado a la rendición.");
    const auto amount = row.value(QStringLiteral("amount")).toString();
    const auto rounded = RenditionMoney::cents(amount);
    if (!rounded || *rounded <= 0 || *rounded > 99999999999999LL)
        return QStringLiteral("El monto redondeado debe ser positivo y estar dentro del límite admitido.");
    const auto currency = row.value(QStringLiteral("currencyCode")).toString();
    if (currency != QLatin1String("PEN") && currency != QLatin1String("USD"))
        return QStringLiteral("Moneda no admitida.");
    if (!meaningfulText(row.value(QStringLiteral("concept")).toString()))
        return QStringLiteral("Concepto: describe qué se compró o qué servicio se realizó.");
    for (const auto &key : {"concept", "categoryCode", "paymentMethodCode", "supportTypeCode"})
        if (row.value(QLatin1String(key)).toString().trimmed().isEmpty())
            return QStringLiteral("Falta completar: %1.").arg(QLatin1String(key));
    if (row.value(QStringLiteral("paymentMethodCode")).toString() == QLatin1String("UNKNOWN"))
        return QStringLiteral("Indica el medio real de pago; CONTADO no identifica cómo pagaste.");
    const auto support = row.value(QStringLiteral("supportTypeCode")).toString();
    if ((row.value(QStringLiteral("categoryCode")).toString() == QLatin1String("OTHER")
         || support == QLatin1String("DECLARATION_WITHOUT_SUPPORT"))
        && row.value(QStringLiteral("justification")).toString().trimmed().isEmpty())
        return QStringLiteral("Justificación: explica el gasto para la categoría Otros o la declaración sin sustento.");
    if (support == QLatin1String("OTHER")
        && row.value(QStringLiteral("supportDetail")).toString().trimmed().isEmpty())
        return QStringLiteral("Detalle del comprobante: describe el otro sustento.");
    if (row.value(QStringLiteral("paymentMethodCode")).toString() == QLatin1String("OTHER")
        && row.value(QStringLiteral("paymentMethodDetail")).toString().trimmed().isEmpty())
        return QStringLiteral("Detalle de pago: describe el otro medio de pago.");
    return {};
}
inline void totals(QVariantMap &draft) {
    qint64 pen = 0, usd = 0; int count = 0, pending = 0;
    for (const auto &value : draft.value(QStringLiteral("expenses")).toList()) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("archived")).toBool()) continue;
        ++count;
        const auto parsed = RenditionMoney::cents(row.value(QStringLiteral("amount")).toString());
        if (!parsed) { draft.insert(QStringLiteral("accountingError"), QStringLiteral("INVALID_AMOUNT")); return; }
        const auto cents = *parsed;
        if ((row.value(QStringLiteral("currencyCode")).toString() == QLatin1String("PEN") && cents > std::numeric_limits<qint64>::max() - pen)
            || (row.value(QStringLiteral("currencyCode")).toString() == QLatin1String("USD") && cents > std::numeric_limits<qint64>::max() - usd)) {
            draft.insert(QStringLiteral("accountingError"), QStringLiteral("MONEY_OVERFLOW")); return;
        }
        if (row.value(QStringLiteral("currencyCode")).toString() == QLatin1String("PEN")) pen += cents;
        if (row.value(QStringLiteral("currencyCode")).toString() == QLatin1String("USD")) usd += cents;
        const auto review = row.value(QStringLiteral("reviewStatus"), QStringLiteral("PENDIENTE")).toString();
        if (review == QLatin1String("PENDIENTE") || review == QLatin1String("PENDING")) ++pending;
    }
    draft.insert(QStringLiteral("totalPen"), pen / 100.0);
    draft.insert(QStringLiteral("totalUsd"), usd / 100.0);
    draft.insert(QStringLiteral("expenseCount"), count);
    draft.insert(QStringLiteral("pendingCount"), pending);
}
}
