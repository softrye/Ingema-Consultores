import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/home_final.dart';

// Test data only. Production Home always uses the authenticated host projection.
const _state = <String, dynamic>{
  'homeProjection': {
    'header': {
      'name': 'Ana Torres',
      'role': 'Ingeniera de Terreno',
      'avatar': '',
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map;
    final sdk = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
    final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('$fonts/roboto-$weight.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  Future<void> pumpHome(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    Map<String, dynamic> state = _state,
    ValueChanged<String>? onAction,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('home-preview'),
          child: InGeFinalHome(state: state, onAction: onAction ?? (_) {}),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(InGeFinalHome));
      await precacheImage(
        const AssetImage('assets/home_final/approved_reference.png'),
        context,
      );
    });
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(412, 915),
    const Size(480, 960),
  ]) {
    for (final textScale in [1.0, 1.6]) {
      testWidgets('Home fits ${size.width}x${size.height}, text $textScale', (
        tester,
      ) async {
        await pumpHome(tester, size, textScale: textScale);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Pendientes'),
          160,
          scrollable: find.byType(Scrollable),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final element in find.byType(Text).evaluate()) {
          final box = element.renderObject;
          if (box is RenderBox && box.hasSize) {
            final rect = box.localToGlobal(Offset.zero) & box.size;
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
        }
      });
    }
  }

  testWidgets(
    'Existing routes dispatch once and optional actions stay disabled',
    (tester) async {
      final actions = <String>[];
      await pumpHome(tester, const Size(360, 800), onAction: actions.add);
      for (final entry in {
        'Calicatas': 'calicatas',
        'Documentos': 'documents',
        'InGe Earth': 'earth',
        'Rendición de cuentas': 'renditions',
        'Nuevo\nregistro': 'newProject',
        'Abrir\nmapa': 'earth',
        'Inicio': 'home',
        'Perfil': 'profile',
        'Ajustes': 'settings',
      }.entries) {
        final target = find.text(entry.key);
        await tester.ensureVisible(target);
        // Portal text sits below the single full-surface hit target.
        await tester.tapAt(tester.getCenter(target));
        await tester.pumpAndSettle();
        expect(actions.removeLast(), entry.value);
        expect(actions, isEmpty);
      }
      for (final label in ['Último\ndocumento', 'Pendientes']) {
        final target = find.text(label);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(actions, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Header refreshes when the account projection changes', (
    tester,
  ) async {
    await pumpHome(tester, const Size(360, 800));
    expect(find.text('Ana Torres'), findsOneWidget);
    await pumpHome(
      tester,
      const Size(360, 800),
      state: const {
        'homeProjection': {
          'header': {'name': 'Luis Vega', 'role': 'Supervisor', 'avatar': ''},
        },
      },
    );
    expect(find.text('Ana Torres'), findsNothing);
    expect(find.text('Luis Vega'), findsOneWidget);
    expect(find.text('Supervisor'), findsOneWidget);
    expect(find.text('LV'), findsOneWidget);
  });

  testWidgets('Render 720x1600 source preview', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await pumpHome(tester, const Size(360, 800));
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('home-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          '../../docs/validation/responsive_neutral/home-720x1600.png',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}
