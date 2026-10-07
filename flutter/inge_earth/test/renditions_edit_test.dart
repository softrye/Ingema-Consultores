import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/renditions_bridge.dart';
import 'package:inge_earth/renditions/renditions_models.dart';
import 'package:inge_earth/renditions/v2/rendition_detail.dart';
import 'package:inge_earth/renditions/v2/widgets/dashboard_widgets.dart';

class EditBridge extends RenditionsBridge {
  JsonMap? savedArguments;
  @override
  Future<JsonMap> command(
    String operation, [
    JsonMap arguments = const {},
  ]) async {
    expect(operation, 'update');
    savedArguments = arguments;
    current = RenditionData({
      ...current!.raw,
      'periodStart': arguments['periodStart'],
      'periodEnd': arguments['periodEnd'],
    });
    return {'current': current!.raw};
  }
}

void main() {
  for (final status in ['BORRADOR', 'PRESENTADA', 'FINAL']) {
    testWidgets('Existing $status preserves identity and editing rules', (
      tester,
    ) async {
      final bridge = EditBridge()
        ..current = RenditionData({
          'localId': 'local-1',
          'remoteId': 'remote-1',
          'primaryProjectId': 'project-1',
          'projectIds': ['project-1'],
          'rowVersion': 7,
          'status': status,
          'syncState': 'SYNCED',
          'periodStart': '2026-09-01',
          'periodEnd': '2026-09-08',
        });
      Widget screen() => MaterialApp(
        home: Scaffold(
          body: RenditionDetailV2(
            bridge: bridge,
            selected: bridge.current!,
            palette: const RenditionsPalette(false),
            onBack: () {},
          ),
        ),
      );
      await tester.pumpWidget(screen());
      expect(find.text('2026-09-01'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      if (status != 'BORRADOR') {
        expect(button.onPressed, isNull);
      } else {
        await tester.enterText(find.byType(TextFormField).first, '2026-09-02');
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(bridge.savedArguments!['localId'], 'local-1');
        expect(bridge.savedArguments!['expectedRowVersion'], 7);
        expect(bridge.savedArguments!['primaryProjectId'], 'project-1');
        expect(bridge.current!.remoteId, 'remote-1');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(screen());
        expect(find.text('2026-09-02'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      bridge.dispose();
    });
  }
}
