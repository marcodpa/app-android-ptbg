import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/db/filter_seed.dart';
import 'package:scv_ptbg/db/filter_store.dart';
import 'package:scv_ptbg/models/filter_catalog.dart';
import 'package:scv_ptbg/screens/filters_screen.dart';
import 'package:scv_ptbg/theme.dart';
import 'package:scv_ptbg/widgets/filter_flux.dart';

final catalog =
    FilterSeed.decode(File(FilterSeed.assetPath).readAsStringSync());

class FluxTestStore extends FilterStore {
  int saves = 0;
  @override
  Future<FilterCatalog> catalog() async =>
      FilterSeed.decode(File(FilterSeed.assetPath).readAsStringSync());
  @override
  Future<int> saveChange(FilterRow element, FilterRow details) async {
    saves++;
    return 42;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'rol': 'operador'}));

  test('all 46 catalog entries resolve a bundled illustration without mutation',
      () {
    expect(catalog.elements.length, 46);
    for (final element in catalog.elements) {
      final before = Map<String, dynamic>.from(element);
      expect(File(FilterFluxAssets.element(element)).existsSync(), isTrue);
      expect(element, before);
    }
    for (final path in FilterFluxAssets.all) {
      expect(File(path).lengthSync(), greaterThan(1000));
    }
  });

  test('system illustrations follow names, not the previous reversed codes',
      () {
    final diesel = catalog.systems.singleWhere((s) => s['CODE_SYS'] == 3);
    final water = catalog.systems.singleWhere((s) => s['CODE_SYS'] == 4);
    expect(FilterFluxAssets.system(diesel), FilterFluxAssets.fuel);
    expect(FilterFluxAssets.system(water), FilterFluxAssets.water);
    expect(FilterFluxAssets.element({'ELEMENTO': 'MANTAS DE AIRE'}),
        FilterFluxAssets.airBlanket);
    expect(FilterFluxAssets.element({'elemento': 'PREFILTROS DE AIRE'}),
        FilterFluxAssets.airPrefilter);
    expect(FilterFluxAssets.element({'ELEMENTO': 'Filtro nuevo desconocido'}),
        FilterFluxAssets.metalCartridge);
  });

  for (final width in [375.0, 600.0]) {
    testWidgets('Flux grid adapts to portrait width $width', (tester) async {
      tester.view.physicalSize = Size(width, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(), home: FiltersScreen(store: FluxTestStore())));
      await tester.pumpAndSettle();
      final a = tester.getTopLeft(find.text('Turbogenerador 1'));
      final b = tester.getTopLeft(find.text('Turbogenerador 2'));
      if (width == 600) {
        expect(a.dy, b.dy);
        expect(b.dx, greaterThan(a.dx));
      } else {
        expect(b.dy, greaterThan(a.dy));
        expect(a.dx, b.dx);
      }
      expect(find.text('Administrar filtros'), findsNothing);
      await tester.enterText(find.byType(TextField), 'no-existe-este-sistema');
      await tester.pumpAndSettle();
      expect(find.byType(FilterFluxNavigationCard), findsNothing);
      expect(
          find.textContaining('No hay elementos habilitados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel confirmation never records a change', (tester) async {
    final store = FluxTestStore();
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home:
            FilterChangeScreen(store: store, element: catalog.elements.first)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Revisar y guardar'), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Revisar y guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar cambio completo'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Volver'));
    await tester.pumpAndSettle();
    expect(store.saves, 0);
    expect(find.text('Confirmar cambio completo'), findsNothing);
  });
}
