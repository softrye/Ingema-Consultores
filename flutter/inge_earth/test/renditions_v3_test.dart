import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/v3/state/rendition_editor_state.dart';

// Pruebas de lógica de Rendiciones V3 (las pruebas de widgets se retiraron
// con la interfaz Flutter, Visual Zero 2026-10-10).
void main() {
  test('Semantic duplicate warning allows legitimate distinct expenses', () {
    final expense = <String, dynamic>{'projectId':'p', 'expenseDate':'2026-09-10',
      'categoryCode':'FOOD', 'currencyCode':'PEN', 'concept':'  Almuerzo   equipo ',
      'beneficiary':'Proveedor', 'supportTypeCode':'RECEIPT', 'supportNumber':'R001', 'amount':'25.50'};
    expect(similarExpense(expense, {...expense, 'concept':'almuerzo equipo', 'amount':25.5}), true);
    expect(similarExpense(expense, {...expense, 'supportNumber':'R002'}), false);
    expect(similarExpense(expense, {...expense, 'archived':true}), false);
  });
  test('period, explicit primary and folder invalidation', () {
    final state = RenditionEditorState()
      ..start = '2026-09-10'
      ..end = '2026-09-01';
    expect(state.periodValid, false);
    state.end = '2026-09-30';
    expect(state.periodValid, true);
    expect(RenditionEditorState.validDate('2026-02-30'), false);
    state.toggleProject('p1');
    state.toggleProject('p2');
    expect(state.primary, 'p1');
    state.folder = 'folder';
    state.space = 'space';
    state.setPrimary('p2');
    expect(state.folder, isEmpty);
    state.toggleProject('p2');
    expect(state.primary, 'p1');
    expect(state.includesExpenseDate('2026-10-01'), false);
    expect(state.valid, false); // root is not a destination
  });
}
