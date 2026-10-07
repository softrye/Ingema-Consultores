import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/renditions_bridge.dart';
import 'package:inge_earth/renditions/renditions_models.dart';
import 'package:inge_earth/renditions/v3/renditions_root.dart';
import 'package:inge_earth/renditions/v3/renditions_shell.dart';
import 'package:inge_earth/renditions/v3/screens/rendition_editor.dart';
import 'package:inge_earth/renditions/v3/screens/expense_editor.dart';
import 'package:inge_earth/renditions/v3/state/rendition_editor_state.dart';
import 'package:inge_earth/renditions/v3/theme/rendition_theme.dart';

class TestStoreBridge extends RenditionsBridge {
  final records = <String, JsonMap>{};
  final operations = <String>[];
  @override
  Future<void> initialize() async {
    projects = [
      {'id': 'p1', 'name': 'Proyecto real simulado', 'code': 'P1'},
    ];
    catalogs = [
      for (final kind in ['CATEGORY', 'PAYMENT_METHOD', 'SUPPORT_TYPE'])
        {'catalog_type': kind, 'code': kind, 'name': kind},
    ];
  }

  @override
  Future<JsonMap> command(String operation, [JsonMap args = const {}]) async {
    operations.add(operation);
    switch (operation) {
      case 'saveEditorDraft':
        final key = args['key'].toString();
        final draft = jsonMap(args['draft']);
        if (draft.isEmpty) { editorDrafts.remove(key); } else { editorDrafts[key] = draft; }
        return {};
      case 'projectWorkspace':
        return {'space_id': 's1', 'project_id': 'p1'};
      case 'listFolders':
        return {
          'folders': [
            {
              'id': 'f1',
              'name': '02_ADMINISTRACION',
              'item_kind': 'FOLDER',
              'node_type': 'FOLDER',
            },
          ],
        };
      case 'folderCapabilities':
        return {
          'space_id': 's1',
          'node_id': 'f1',
          'node_kind': 'FOLDER',
          'lifecycle': 'ACTIVE',
          'can_accept_child': true,
        };
      case 'create':
        records['local-1'] = {
          ...args,
          'localId': 'local-1',
          'remoteId': '',
          'status': 'BORRADOR',
          'syncState': 'PENDING_CREATE',
          'expenses': <JsonMap>[],
        };
        current = RenditionData(records['local-1']!);
        renditions = [current!];
        notifyListeners();
        return {'localId': 'local-1', 'current': current!.raw};
      case 'select':
        current = RenditionData(records[args['localId']]!);
        notifyListeners();
        return {'current': current!.raw};
      case 'saveExpense':
        final draft = records[args['localId']]!;
        final rows = jsonRows(draft['expenses']).toList();
        final id = (args['expenseLocalId'] as String).isEmpty
            ? 'expense-1'
            : args['expenseLocalId'];
        rows.removeWhere((e) => e['localId'] == id);
        rows.add({
          ...jsonMap(args['expense']),
          'localId': id,
          'reviewStatus': 'PENDIENTE',
        });
        draft['expenses'] = rows;
        draft['expenseCount'] = rows.length;
        for (final currency in ['PEN', 'USD']) {
          draft[currency == 'PEN' ? 'totalPen' : 'totalUsd'] = rows
              .where((e) => e['currencyCode'] == currency)
              .fold<double>(
                0,
                (s, e) => s + double.parse(e['amount'].toString()),
              );
        }
        current = RenditionData(draft);
        notifyListeners();
        return {'localId': id};
      case 'closeDetail':
        current = null;
        return {};
      default:
        return {};
    }
  }
}

void main() {
  test('Semantic duplicate warning allows legitimate distinct expenses', () {
    final expense = <String, dynamic>{'projectId':'p', 'expenseDate':'2026-09-10',
      'categoryCode':'FOOD', 'currencyCode':'PEN', 'concept':'  Almuerzo   equipo ',
      'beneficiary':'Proveedor', 'supportTypeCode':'RECEIPT', 'supportNumber':'R001', 'amount':'25.50'};
    expect(similarExpense(expense, {...expense, 'concept':'almuerzo equipo', 'amount':25.5}), true);
    expect(similarExpense(expense, {...expense, 'supportNumber':'R002'}), false);
    expect(similarExpense(expense, {...expense, 'archived':true}), false);
  });
  testWidgets('Expense autosave restores unfinished text and double save creates once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge=TestStoreBridge(); await bridge.initialize();
    await bridge.command('create', {'periodStart':'2026-09-01', 'periodEnd':'2026-09-30',
      'projectIds':['p1'], 'primaryProjectId':'p1'});
    final rendition=bridge.current!;
    var saved=0;
    Widget editor() => MaterialApp(home: Scaffold(body: ExpenseEditor(bridge:bridge,
      rendition:rendition, onBack:(){}, onSaved:(){saved++;}, onChanged:(){})));
    await tester.pumpWidget(editor());
    var state=tester.state<ExpenseEditorViewState>(find.byType(ExpenseEditor));
    state.fields['concept']!.text='Borrador incompleto'; state.fields['amount']!.text='1,';
    await tester.pump(const Duration(milliseconds:700)); await tester.pump();
    expect(bridge.operations.where((o)=>o=='saveExpense'), isEmpty);
    expect(jsonMap(bridge.editorDrafts['expense:local-1:new'])['amount'], '1,');
    final intention=jsonMap(bridge.editorDrafts['expense:local-1:new'])['clientIntentId'];
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    await tester.pumpWidget(editor());
    state=tester.state<ExpenseEditorViewState>(find.byType(ExpenseEditor));
    expect(state.fields['concept']!.text, 'Borrador incompleto');
    state.category='CATEGORY'; state.payment='PAYMENT_METHOD'; state.support='SUPPORT_TYPE';
    state.fields['beneficiary']!.text='Proveedor'; state.fields['amount']!.text='25.50';
    state.changed(); await tester.pump();
    await Future.wait([state.save(), state.save()]); await tester.pump();
    expect(saved,1);
    expect(bridge.operations.where((o)=>o=='saveExpense').length,1);
    expect(jsonRows(bridge.current!.raw['expenses']).single['clientIntentId'], intention);
    expect(bridge.editorDrafts.containsKey('expense:local-1:new'),false);
    await tester.pumpWidget(const SizedBox()); bridge.dispose();
  });
  testWidgets(
    'Documents UUID opens V3 draft and presented detail without duplication',
    (tester) async {
      final bridge = TestStoreBridge();
      await tester.pumpWidget(
        MaterialApp(
          home: RenditionsRootV3(
            dark: false,
            onGlobalAction: (_) async {},
            bridge: bridge,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final status in ['BORRADOR', 'PRESENTADA']) {
        bridge.current = RenditionData({
          'localId': 'same-local',
          'remoteId': 'same-uuid',
          'visibleCode': 'RDC-2026-000007',
          'status': status,
          'syncState': 'SYNCED',
          'expenses': <JsonMap>[],
          'periodStart': '2026-09-01',
          'periodEnd': '2026-09-30',
        });
        bridge.documentTargetId = 'same-uuid';
        bridge.documentOpenRevision++;
        bridge.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('RDC-2026-000007'), findsOneWidget);
        expect(
          find.text('Agregar gasto'),
          status == 'BORRADOR' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Editar período y proyectos'),
          status == 'BORRADOR' ? findsOneWidget : findsNothing,
        );
        expect(bridge.operations.where((op) => op == 'create'), isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Rendiciones'), findsOneWidget);
      }
    },
  );
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
