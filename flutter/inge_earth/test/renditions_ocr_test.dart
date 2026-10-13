import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/v3/state/smart_fill.dart';

void main() {
  test('Receipt total, currency, date and document are suggestions only', () {
    final result = parseReceipt({
      'text':
          'Proveedor\n08/09/2026\nF001-123\nSUBTOTAL 100.00\nTOTAL S/ 118.00',
    }, 'attachment-1');
    final values = {for (final p in result) p.field: p.proposedValue};
    expect(values['amount'], '118.00');
    expect(values['currencyCode'], 'PEN');
    expect(values['expenseDate'], '2026-09-08');
    expect(values['supportNumber'], 'F001-123');
    expect(result.every((p) => p.sourceAttachment == 'attachment-1'), true);
  });
  test('Low confidence and invalid dates cannot suggest values', () {
    final result = parseReceipt({
      'lines': [
        {'text': 'TOTAL USD 900.00', 'confidence': .2},
        {'text': '31/02/2026', 'confidence': .99},
      ],
    }, 'a');
    expect(
      result.where(
        (p) => ['amount', 'currencyCode', 'expenseDate'].contains(p.field),
      ),
      isEmpty,
    );
  });
}
