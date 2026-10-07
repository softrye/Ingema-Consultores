import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/v2/received/received_models.dart';
import 'package:inge_earth/renditions/v2/received/received_metro_board.dart';
import 'package:inge_earth/renditions/v2/received/received_filter_sheet.dart';
import 'package:inge_earth/renditions/v3/renditions_root.dart';
import 'package:inge_earth/renditions/v2/widgets/dashboard_widgets.dart';
import 'package:inge_earth/renditions/v2/received/received_query.dart';

void main() {
  test(
    'Metro remains within two columns, disjoint and capped after resizing and reordering',
    () {
      final layout = ReceivedMetroLayout({
        'a': MetroSize.small,
        'b': MetroSize.wide,
        'c': MetroSize.large,
        'd': MetroSize.small,
      });
      for (var i = 0; i < 96; i++) {
        layout.resize(layout.order[i % 4]);
        layout.move(layout.order.first, layout.order.last);
        final cells = <String>{};
        expect(layout.placements.length, 4);
        for (final p in layout.placements) {
          expect(p.column, greaterThanOrEqualTo(0));
          expect(p.column + p.width, lessThanOrEqualTo(2));
          for (var y = 0; y < p.height; y++) {
            for (var x = 0; x < p.width; x++) {
              expect(cells.add('${p.column + x},${p.row + y}'), isTrue);
            }
          }
        }
      }
      expect(
        () => ReceivedMetroLayout({
          for (var i = 0; i < 5; i++) '$i': MetroSize.small,
        }),
        throwsArgumentError,
      );
      layout.dispose();
    },
  );

  test(
    'Search covers code, owner and project; periods overlap and orders are deterministic',
    () {
      final rows = [
        ReceivedRendition({
          'rendition_id': 'a',
          'visible_code': 'RDC-2026-000002',
          'owner_name': 'Ana',
          'primary_project_name': 'Norte',
          'period_start': '2026-07-01',
          'period_end': '2026-09-02',
          'submitted_at': '2026-08-30T12:00:00Z',
        }),
        ReceivedRendition({
          'rendition_id': 'b',
          'visible_code': 'RDC-2026-000001',
          'owner_name': 'Luis',
          'primary_project_name': 'Sur',
          'period_start': '2026-09-03',
          'period_end': '2026-09-30',
          'submitted_at': '2026-09-01T12:00:00Z',
          'received_at': '2026-09-02T12:00:00Z',
        }),
      ];
      final f = ReceivedFilter();
      expect(f.apply(rows, 'ANA').single.id, 'a');
      expect(f.apply(rows, 'sur').single.id, 'b');
      expect(f.apply(rows, '000002').single.id, 'a');
      expect(f.apply(rows, '').first.id, 'b');
      f.order = ReceivedOrder.oldest;
      expect(f.apply(rows, '').first.id, 'a');
      f.periodFrom = '2026-08-01';
      f.periodTo = '2026-08-31';
      expect(f.apply(rows, '').single.id, 'a');
      f.periodFrom = '2026-10-01';
      expect(f.valid, false);
      f.clear();
      f.order = ReceivedOrder.code;
      expect(f.apply(rows, '').first.id, 'b');
      expect(rows.first.reception, 'PENDIENTE DE RECEPCIÓN');
      expect(rows.last.reception, 'RECIBIDA');
      expect(receivedDate('2026-09-03'), '03/09/2026');
    },
  );

  testWidgets(
    'Calendar is the only filter layer using blur; Back removes it first',
    (tester) async {
      final filter = ReceivedFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showReceivedFilters(
                  context,
                  filter,
                  const RenditionsPalette(false),
                ),
                child: const Text('Filtros'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.textContaining('Periodo desde'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceivedDatePicker), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ReceivedFilterSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReceivedFilterSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Received target opens pinned query, export has identity only, Back preserves tray',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('inge.renditions/host');
      const codec = StandardMethodCodec();
      final calls = <Map<String, dynamic>>[];
      const row = <String, dynamic>{
        'rendition_id': 'received-id',
        'visible_code': 'RDC-2026-000007',
        'owner_name': 'Test Owner',
        'primary_project_name': 'Test Project',
        'period_start': '2026-08-01',
        'period_end': '2026-09-03',
        'submitted_at': '2026-09-03T12:00:00Z',
        'status': 'PRESENTADA',
        'expense_count': 0,
        'total_declared_pen': 0,
        'total_declared_usd': 0,
        'version_number': 1,
        'rendition_version_id': 'immutable-version',
      };
      final snapshot = {
        ...row,
        'snapshot_hash': 'hash-from-server',
        'snapshot_payload': {'expenses': [], 'attachments': []},
      };
      Future<void> event(Map<String, dynamic> value) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            MethodCall('renditionEvent', jsonEncode(value)),
          ),
          (_) {},
        );
      }

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'submit') return null;
        final request =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        calls.add(request);
        final op = request['operation'];
        Map<String, dynamic> result = {};
        if (op == 'receivedList') {
          result = {
            'rows': [row],
          };
        }
        if (op == 'receivedQuery') {
          result = {
            'rows': [snapshot],
          };
        }
        if (op == 'receivedNotes' || op == 'receivedActivity') {
          result = {'rows': []};
        }
        if (op == 'receivedExport') {
          result = {'output': 'Downloads/RDC-2026-000007-v1.xlsx'};
        }
        await event({
          'type': 'commandResult',
          'requestId': request['requestId'],
          'ok': true,
          'result': result,
        });
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RenditionsRootV3(
            dark: false,
            onGlobalAction: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Recibidas'));
      await tester.pumpAndSettle();
      expect(find.text('Rendiciones recibidas'), findsOneWidget);
      await tester.tap(find.text('RDC-2026-000007'));
      await tester.pumpAndSettle();
      expect(find.text('Consulta de snapshot · V1'), findsOneWidget);
      expect(
        calls
            .where((c) => c['operation'] == 'receivedQuery')
            .single['arguments']['versionId'],
        'immutable-version',
      );
      tester
          .state<ReceivedQueryState>(find.byType(ReceivedQuery))
          .focusTile('admin');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nueva observación'),
        'Nota administrativa de prueba',
      );
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrar observación'));
      await tester.tap(find.text('Registrar observación'));
      await tester.pumpAndSettle();
      final note =
          calls
                  .where((c) => c['operation'] == 'receivedAddNote')
                  .single['arguments']
              as Map;
      expect(note['versionId'], 'immutable-version');
      expect(
        note['noteRequestId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Rendiciones recibidas'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Rendiciones'), findsOneWidget);
      expect(find.byType(ReceivedQuery), findsNothing);
      expect(calls.where((c) => c['operation'] == 'globalAction'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
