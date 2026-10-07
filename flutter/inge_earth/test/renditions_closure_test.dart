import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/v3/state/smart_fill.dart';
import 'package:inge_earth/renditions/v3/state/rendition_editor_state.dart';

void main() {
  const receipt = 'JORGE ZANABRIA ROLY\nRUC: 10459805597\nFACTURA E001-884\nFECHA DE EMISION: 28/05/2026\nSUBTOTAL 238.14\nIGV 42.86\nTOTAL S/ 281.00\nCONTADO';
  test('E001-884 local extraction and one review preserve date and unknown payment', () {
    final result = localReceiptResult(parseReceipt({'text': receipt}, 'a'));
    final values = {for (final row in result['fields']) row['field']: row['value']};
    expect(values['beneficiary'], 'JORGE ZANABRIA ROLY');
    expect(values['ruc'], '10459805597');
    expect(values['supportNumber'], 'E001-884');
    expect(values['expenseDate'], '2026-05-28');
    expect(values['currencyCode'], 'PEN');
    expect(values['amount'], '281.00');
    expect(values['subtotal'], '238.14');
    expect(values['igv'], '42.86');
    expect(values['paymentMethodCode'], isNull);
    final review = ReceiptReview.fromResult(result, '2026-09-11', '2026-09-24');
    expect(review.unavailable, isTrue);
    expect(review.issues.map((r) => r['reason']), containsAll(['DATE_OUTSIDE_RENDITION_PERIOD','PAYMENT_METHOD_UNKNOWN']));
  });
  test('manual cleared value and modified default are never overwritten', () {
    final field = {'field':'amount','value':'281.00','valid':true,'confidence':.99};
    expect(ReceiptReview.canAutofill(field, '', true), isFalse);
    expect(ReceiptReview.canAutofill(field, '', false), isTrue);
    expect(ReceiptReview.canAutofill(field, '280.00', false), isFalse);
    expect(ReceiptReview.canAutofill({...field,'confidence':.8}, '', false), isFalse);
  });
  test('conflicting sources are retained and require review', () {
    final result = localReceiptResult([...parseReceipt({'text':receipt}, 'a'), ...parseReceipt({'text':'TOTAL S/ 282.00'}, 'b')]);
    final amount = (result['fields'] as List).firstWhere((r) => r['field']=='amount');
    expect(amount['conflict'], isTrue);
    expect(amount['valid'], isFalse);
  });
  test('duplicate robust to concept/category edits and snake case', () {
    final candidate = {'supportNumber':'E001-884','amount':'281.00','currencyCode':'PEN','expenseDate':'2026-05-28','ruc':'10459805597','concept':'editado'};
    final existing = {'support_number':'e001 - 884','amount':281,'currency_code':'PEN','expense_date':'2026-05-28','concept':'original'};
    expect(similarExpense(candidate, existing), isTrue);
    expect(similarExpense(candidate, {...existing,'currency_code':'USD'}), isFalse);
    expect(similarExpense(candidate, {...existing,'ruc':'99999999999'}), isFalse);
    expect(similarExpense(candidate, {...existing,'archived':true}), isFalse);
    expect(similarExpense({'attachments':[{'sha256':'abc'}]}, {'attachments':[{'sha256':'abc'}]}), isTrue);
  });
}
