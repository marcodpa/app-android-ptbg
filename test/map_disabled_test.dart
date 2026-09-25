import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/main.dart';
import 'package:scv_ptbg/screens/home_screen.dart';
import 'package:scv_ptbg/screens/mapa_planta_screen.dart';
import 'package:scv_ptbg/theme.dart';

void main() {
  for (final size in [const Size(600, 960), const Size(960, 600)]) {
    testWidgets('Inicio y menu sin mapa en $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Mapa de la planta'), findsNothing);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(find.text('Subir pendientes'), findsOneWidget);
      expect(find.byTooltip('Cambio de filtros'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ruta antigua del mapa abre Inicio, nunca el plano',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ScvApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final route = app.onGenerateRoute!(const RouteSettings(name: '/mapa'))!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      onGenerateRoute: (_) => route,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(MapaPlantaScreen), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
