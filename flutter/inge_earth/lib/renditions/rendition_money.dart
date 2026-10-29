// Existing server policy: decimal nearest rounding, ties away from zero.
BigInt decimalScaled(Object value, int places) {
  final text = value.toString().trim();
  final m = RegExp(r'^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$').firstMatch(text);
  if (m == null || text.length > 96 || places < 0 || places > 6) throw const FormatException('INVALID_DECIMAL');
  final exponent = int.tryParse(m[4] ?? '0');
  if (exponent == null || exponent.abs() > 32) throw const FormatException('INVALID_DECIMAL');
  final fraction = m[3] ?? '';
  final digits = BigInt.parse('${m[2]}$fraction');
  final shift = places + exponent - fraction.length;
  final magnitude = shift >= 0 ? digits * BigInt.from(10).pow(shift)
      : (digits + BigInt.from(10).pow(-shift) ~/ BigInt.two) ~/ BigInt.from(10).pow(-shift);
  return m[1] == '-' ? -magnitude : magnitude;
}
int moneyCents(Object value) {
  final result = decimalScaled(value, 2);
  if (result.abs() > BigInt.from(9007199254740991)) throw const FormatException('MONEY_OVERFLOW');
  return result.toInt();
}
int? _rounded(BigInt numerator, BigInt denominator) {
  final sign = numerator.isNegative ? -BigInt.one : BigInt.one;
  final value = ((numerator.abs() + denominator ~/ BigInt.two) ~/ denominator) * sign;
  return value.abs() > BigInt.from(9007199254740991) ? null : value.toInt();
}
({int? pen, int? usd}) commonFundBalance(Object fundPen, Object fundUsd, Object spentPen, Object spentUsd, Object? rate) {
  final pen = BigInt.from(moneyCents(fundPen) - moneyCents(spentPen));
  final usd = BigInt.from(moneyCents(fundUsd) - moneyCents(spentUsd));
  if (rate == null) return (pen: usd == BigInt.zero ? pen.toInt() : null, usd: pen == BigInt.zero ? usd.toInt() : null);
  final r = decimalScaled(rate, 6), scale = BigInt.from(1000000);
  if (r <= BigInt.zero) throw const FormatException('INVALID_EXCHANGE_RATE');
  return (pen: _rounded(pen * scale + usd * r, scale), usd: _rounded(usd * r + pen * scale, r));
}
