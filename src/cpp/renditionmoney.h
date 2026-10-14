#pragma once
#include <QRegularExpression>
#include <QString>
#include <limits>
#include <optional>

namespace RenditionMoney {
// Parse decimal text directly; PostgreSQL numeric rounds ties away from zero.
inline std::optional<qint64> scaled(QString text, int places) {
    static const QRegularExpression pattern(QStringLiteral("^([+-]?)([0-9]+)(?:\\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$"));
    auto m = pattern.match(text.trimmed());
    if (!m.hasMatch() || text.size() > 96 || places < 0 || places > 6) return {};
    bool ok = true; int exponent = m.captured(4).isEmpty() ? 0 : m.captured(4).toInt(&ok);
    if (!ok || qAbs(exponent) > 32) return {};
    QString digits = m.captured(2) + m.captured(3);
    int shift = places + exponent - m.captured(3).size();
    bool increment = false;
    if (shift >= 0) digits += QString(shift, QLatin1Char('0'));
    else {
        const int keep = digits.size() + shift;
        increment = keep >= 0 && keep < digits.size() && digits[keep] >= QLatin1Char('5');
        digits = keep > 0 ? digits.left(keep) : QStringLiteral("0");
    }
    while (digits.size() > 1 && digits.startsWith(QLatin1Char('0'))) digits.remove(0, 1);
    qint64 result = digits.toLongLong(&ok);
    if (!ok || (increment && result == std::numeric_limits<qint64>::max())) return {};
    if (increment) ++result;
    return m.captured(1) == QLatin1String("-") ? -result : result;
}
inline std::optional<qint64> cents(const QString &text) {
    const auto value = scaled(text, 2);
    if (!value || *value > 9007199254740991LL || *value < -9007199254740991LL) return {};
    return value;
}
#if defined(__SIZEOF_INT128__)
struct Balance { std::optional<qint64> pen, usd; };
// Android arm64 Clang and portable GCC/MinGW runners support this exact wide integer.
inline Balance commonFund(qint64 fundPen, qint64 fundUsd, qint64 spentPen, qint64 spentUsd, std::optional<qint64> rateMicro) {
    using Wide = __int128;
    const Wide pen = Wide(fundPen) - spentPen, usd = Wide(fundUsd) - spentUsd;
    auto round = [](Wide n, Wide d) -> std::optional<qint64> {
        const int sign = n < 0 ? -1 : 1;
        const Wide rounded = ((n * sign + d / 2) / d) * sign;
        if (rounded > 9007199254740991LL || rounded < -9007199254740991LL) return {};
        return qint64(rounded);
    };
    if (!rateMicro) return {usd == 0 ? round(pen, 1) : std::nullopt, pen == 0 ? round(usd, 1) : std::nullopt};
    if (*rateMicro <= 0) return {};
    const Wide r = *rateMicro, scale = 1000000;
    return {round(pen * scale + usd * r, scale), round(usd * r + pen * scale, r)};
}
#endif
}
