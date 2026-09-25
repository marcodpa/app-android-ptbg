import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/screens/home_screen.dart';
import 'package:scv_ptbg/theme.dart';
import 'package:scv_ptbg/widgets/filter_visuals.dart';
import 'package:scv_ptbg/widgets/filter_cartridge_icon.dart';

void main() {
  testWidgets('inicio muestra filtros ilustrado y abre su ruta',
      (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'Técnico'});
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
      routes: {
        '/filtros': (_) => const Scaffold(body: Text('Catálogo de filtros'))
      },
    ));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('home-filter-module'));
    expect(tester.getTopLeft(card).dy,
        greaterThan(tester.getBottomLeft(find.text('Subir pendientes')).dy));
    expect(find.byType(FilterCartridgeIcon), findsNWidgets(2));
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    await tester.ensureVisible(card);
    expect(card.hitTestable(), findsOneWidget);
    expect(find.text('Cambio de filtros'), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(FilterIllustration)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Catálogo de filtros'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el cartucho lateral abre filtros', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
      routes: {
        '/filtros': (_) => const Scaffold(body: Text('Catálogo de filtros'))
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cambio de filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Catálogo de filtros'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
