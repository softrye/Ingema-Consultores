import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/renditions_bridge.dart';
import 'package:inge_earth/renditions/renditions_flow.dart';
import 'package:inge_earth/renditions/renditions_models.dart';
import 'package:inge_earth/renditions/v2/received/received_models.dart';

// Reglas extraídas de la interfaz Flutter eliminada (Visual Zero 2026-10-10).
RenditionData draft({
  String status = 'BORRADOR',
  String sync = 'SYNCED',
  List<JsonMap> expenses = const [],
}) => RenditionData({
  'localId': 'local-1',
  'status': status,
  'syncState': sync,
  'periodStart': '2026-09-01',
  'periodEnd': '2026-09-30',
  'projectIds': ['p1'],
  'primaryProjectId': 'p1',
  'documentParentNodeId': 'folder',
  'spaceId': 'space',
  'rowVersion': 3,
  'expenses': expenses,
});

ExpenseData expense(String date, {String project = 'p1', bool archived = false}) =>
    ExpenseData({'localId': 'e-$date', 'expenseDate': date, 'projectId': project,
      if (archived) 'archived': true});

void main() {
  test('received search matches any non-null column, ignoring case', () {
    final row = <String, dynamic>{'code': 'RDC-1', 'owner': 'Ana', 'x': null};
    expect(receivedRowMatches(row, '  '), true);
    expect(receivedRowMatches(row, 'ana'), true);
    expect(receivedRowMatches(row, ' rdc-1 '), true);
    expect(receivedRowMatches(row, 'null'), false);
  });

  test('received pagination follows the cursor and rejects repeated pages', () async {
    JsonMap row(int i) => {'rendition_id': 'r$i', 'submitted_at': 's$i'};
    final cursors = <JsonMap>[];
    final rows = await loadAllReceived((cursor) async {
      cursors.add(cursor);
      final from = cursors.length == 1 ? 0 : 200;
      final count = cursors.length == 1 ? 200 : 3;
      return {'rows': [for (var i = from; i < from + count; i++) row(i)]};
    });
    expect(rows!.length, 203);
    expect(cursors, [{}, {'afterSubmittedAt': 's199', 'afterId': 'r199'}]);
    await expectLater(
      loadAllReceived((cursor) async => {'rows': [for (var i = 0; i < 200; i++) row(i % 199)]}),
      throwsA(isA<RenditionCommandException>().having((e) => e.code, 'code', 'REPEATED_PAGE')));
    var live = true;
    final cancelled = await loadAllReceived((cursor) async { live = false; return {'rows': []}; },
        alive: () => live);
    expect(cancelled, isNull);
  });

  test('snapshot, selection and saved identity are confirmed', () {
    final row = ReceivedRendition({'rendition_id': 'a'});
    expect(confirmReceivedSnapshot({'rows': [{'rendition_id': 'a', 'x': 1}]}, row).raw['x'], 1);
    expect(() => confirmReceivedSnapshot({'rows': [{'rendition_id': 'b'}]}, row),
        throwsA(isA<RenditionCommandException>()));
    expect(() => confirmReceivedSnapshot({'rows': []}, row), throwsA(isA<RenditionCommandException>()));
    expect(confirmSelected({'current': {'localId': 'l'}}, 'l').localId, 'l');
    expect(() => confirmSelected({'current': {'localId': 'x'}}, 'l'), throwsA(isA<RenditionCommandException>()));
    expect(confirmSaved({'current': {'localId': 'n'}}, null).localId, 'n');
    expect(() => confirmSaved({'current': {}}, null), throwsA(isA<RenditionCommandException>()));
    expect(() => confirmSaved({'current': {'localId': 'other'}}, draft()),
        throwsA(isA<RenditionCommandException>()));
    expect(headerSaveCommand(null), 'create');
    expect(headerSaveCommand(draft()), 'update');
    expect(headerDraftKey(null), 'header:new');
  });

  test('note request ids are reused only for the same body', () {
    var n = 0;
    String uuid() => 'id${++n}';
    expect(noteRequestId('hola', '', '', uuid: uuid), 'id1');
    expect(noteRequestId('hola', 'hola', 'id1', uuid: uuid), 'id1');
    expect(noteRequestId('otra', 'hola', 'id1', uuid: uuid), 'id2');
    final id = newRequestUuid(Random(7));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), true);
    expect(receivedAddNoteArgs({'renditionId': 'r'}, 'b', 'q'),
        {'renditionId': 'r', 'body': 'b', 'noteRequestId': 'q'});
    final owner = exportCommand(null, 'pdf');
    expect(owner.command, 'ownerExport');
    expect(owner.args, {'format': 'pdf'});
    final received = exportCommand({'hash': 'h'}, 'xlsx');
    expect(received.command, 'receivedExport');
    expect(received.args, {'hash': 'h', 'format': 'xlsx'});
  });

  test('present preflight blocks in the original order', () {
    expect(presentPreflight(null, []), 'Sólo se puede presentar un borrador.');
    expect(presentPreflight(draft(status: 'PRESENTADA'), []), 'Sólo se puede presentar un borrador.');
    expect(presentPreflight(draft(), []), 'Agrega al menos un gasto.');
    expect(presentPreflight(draft(sync: 'CONFLICT'), [expense('2026-09-10')]),
        'Resuelve el conflicto antes de presentar.');
    expect(presentPreflight(draft(), [expense('2026-10-01')]), 'Revisa las fechas y proyectos de los gastos.');
    expect(presentPreflight(draft(), [expense('2026-09-10', project: 'p2')]),
        'Revisa las fechas y proyectos de los gastos.');
    expect(presentPreflight(draft(), [expense('2026-09-10')]), isNull);
    final incomplete = RenditionData({...draft().raw, 'spaceId': ''});
    expect(presentPreflight(incomplete, [expense('2026-09-10')]),
        'Completa el período, proyectos y ubicación documental.');
    final withArchived = draft(expenses: [
      {'localId': 'a', 'archived': true}, {'localId': 'b'},
    ]);
    expect(activeExpenses(withArchived).map((e) => e.localId), ['b']);
    expect(activeExpenses(null), isEmpty);
    expect(renditionEditable(draft(), busy: false), true);
    expect(renditionEditable(draft(), busy: true), false);
    expect(renditionEditable(draft(sync: 'SYNCING'), busy: false), false);
    expect(renditionEditable(draft(sync: 'NEEDS_RECONCILIATION'), busy: false), false);
  });

  test('folders: workspace, capabilities, path and parent', () {
    expect(workspaceSpaceId({'space_id': 's'}), 's');
    expect(() => workspaceSpaceId({}), throwsA(isA<RenditionCommandException>()));
    final ok = {'node_kind': 'FOLDER', 'lifecycle': 'ACTIVE', 'can_accept_child': true,
      'space_id': 's', 'node_id': 'n'};
    validateFolderCapabilities(ok, 's', 'n');
    for (final broken in [
      {...ok, 'node_kind': 'FILE'}, {...ok, 'lifecycle': 'ARCHIVED'},
      {...ok, 'can_accept_child': false}, {...ok, 'space_id': 'x'}, {...ok, 'node_id': 'x'},
    ]) {
      expect(() => validateFolderCapabilities(broken, 's', 'n'), throwsA(isA<RenditionCommandException>()));
    }
    expect(folderPath([{'name': 'A'}, {'name': 'B'}], 'C'), 'A/B/C');
    expect(parentFolderId([{'id': 'a'}]), '');
    expect(parentFolderId([{'id': 'a'}, {'id': 'b'}]), 'a');
    final del = deleteCommand('l', null);
    expect(del.command, 'deleteDraft');
    expect(del.args, {'localId': 'l'});
    final delExpense = deleteCommand('l', 'e');
    expect(delExpense.command, 'deleteExpense');
    expect(delExpense.args, {'localId': 'l', 'expenseLocalId': 'e'});
  });

  test('network failures are deferred, data errors are not', () {
    expect(isNetworkFailure('OFFLINE', 'x'), true);
    expect(isNetworkFailure('ONLINE', Exception('SocketException: Host not found')), true);
    expect(isNetworkFailure('ONLINE', 'Sin conexión'), true);
    expect(isNetworkFailure('ONLINE', 'error de conexión'), true);
    expect(isNetworkFailure('ONLINE', 'ROW_VERSION_CONFLICT'), false);
  });

  test('expense validation, values and command contracts', () {
    expect(expenseFieldError('amount', '', required: true, numeric: true), 'Campo obligatorio');
    expect(expenseFieldError('amount', '0', required: true, numeric: true), 'Monto válido con hasta 2 decimales');
    expect(expenseFieldError('amount', '12,345', required: true, numeric: true), 'Monto válido con hasta 2 decimales');
    expect(expenseFieldError('amount', '12,34', required: true, numeric: true), isNull);
    expect(expenseFieldError('igv', '', required: false, numeric: true), isNull);
    expect(expenseFieldError('igv', '0', required: false, numeric: true), isNull);
    expect(expenseFieldError('concept', 'Almuerzo de equipo', required: true), isNull);
    expect(expenseDateError(draft(), '2026-09-15'), isNull);
    expect(expenseDateError(draft(), '2026-10-15'), isNotNull);
    expect(expenseDraftKey('r', null), 'expense:r:new');
    expect(expenseDraftKey('r', 'e'), 'expense:r:e');
    expect(newExpenseIntentId(DateTime.fromMicrosecondsSinceEpoch(42)), 'expense-42');
    final values = expenseValues(intentId: 'i', projectId: 'p1', expenseDate: '2026-09-10',
        categoryCode: 'FOOD', currencyCode: 'PEN', paymentMethodCode: 'CASH',
        supportTypeCode: 'RECEIPT', fields: {'amount': '25,50', 'concept': 'Almuerzo'});
    expect(values['amount'], '25.50');
    expect(values['concept'], 'Almuerzo');
    final save = saveExpenseArgs(renditionLocalId: 'r', savedId: '', expectedRowVersion: 4,
        values: values, receiptEvidence: {});
    expect(save.containsKey('expectedExpenseRowVersion'), false);
    expect(save['synchronize'], true);
    expect((save['expense'] as JsonMap)['clientIntentId'], 'i');
    expect(saveExpenseArgs(renditionLocalId: 'r', savedId: 'e', expectedRowVersion: 4,
        values: values, receiptEvidence: {})['expectedExpenseRowVersion'], 4);
    expect(confirmSavedExpenseId({'localId': 'e'}), 'e');
    expect(() => confirmSavedExpenseId({}), throwsA(isA<RenditionCommandException>()));
    final attach = attachSupportArgs(renditionLocalId: 'r', expenseLocalId: 'e', intentId: 'i',
        attachment: {'localUri': 'file:///a.pdf', 'fileName': 'a.pdf'},
        supportTypeCode: 'RECEIPT', documentNumber: 'B001');
    expect((attach['attachment'] as JsonMap)['clientIntentId'], 'i:file:///a.pdf');
    expect((attach['attachment'] as JsonMap)['fileName'], 'a.pdf');
    final existing = ExpenseData({'localId': 'x', ...values});
    expect(duplicateExpenses([existing], '', values, []).length, 1);
    expect(duplicateExpenses([existing], 'x', values, []), isEmpty);
  });

  test('receipt analysis: accepted patches, defaults and core context', () {
    final patches = acceptedReceiptPatches({'fields': [
      {'field': 'amount', 'value': '10', 'valid': true, 'confidence': .7, 'sources': ['a', 'b']},
      {'field': 'ruc', 'value': '1', 'valid': true, 'confidence': .69},
      {'field': 'concept', 'value': 'x', 'valid': false, 'confidence': .99},
      {'field': 'igv', 'value': '2', 'valid': true, 'confidence': .9, 'conflict': true},
    ]});
    expect(patches.map((p) => p.field), ['amount']);
    expect(patches.single.sourceAttachment, 'a, b');
    expect(untouchedDefaultField('expenseDate', isNew: true, date: 'd', periodStart: 'd', currency: 'USD'), true);
    expect(untouchedDefaultField('currencyCode', isNew: true, date: 'x', periodStart: 'd', currency: 'PEN'), true);
    expect(untouchedDefaultField('currencyCode', isNew: false, date: 'x', periodStart: 'd', currency: 'PEN'), false);
    final history = [for (var i = 0; i < 25; i++) ExpenseData({'localId': 'h$i'})];
    final args = coreAnalyzeArgs(attachments: [], projectId: 'p', entityId: 'i',
        renditionLocalId: 'r', currentFields: {}, periodStart: 's', periodEnd: 'e',
        categories: [], supportTypes: [], paymentMethods: [], history: history, savedId: 'h0');
    final context = args['context'] as JsonMap;
    expect((context['related_history'] as List).length, 20);
    expect((context['related_history'] as List).first, {'localId': 'h1'});
    expect((context['entity'] as JsonMap)['rendition_id'], 'r');
  });
}
