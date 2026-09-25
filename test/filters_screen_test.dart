import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/db/filter_store.dart';
import 'package:scv_ptbg/db/filter_seed.dart';
import 'package:scv_ptbg/models/filter_catalog.dart';
import 'package:scv_ptbg/screens/filters_screen.dart';
import 'package:scv_ptbg/theme.dart';
import 'package:scv_ptbg/widgets/filter_visuals.dart';
import 'package:scv_ptbg/widgets/filter_flux.dart';
import 'package:scv_ptbg/widgets/industrial_navigation.dart';

final element = <String, dynamic>{
  'ID': 20,
  'CODE_SYS': 1,
  'CODE_SUB_SYS': 9,
  'ELEMENTO': 'Filtro de aire casa de filtros',
  'LOCALIZACION': 1,
  'CANTIDAD': 152,
  'TAGNAME': 'N/A',
  'MODELO': 'SIN DATOS',
  'MARCA': 'SIN DATOS',
  'ESPECIFICACIONES': 'SIN DATOS'
};
final data = FilterCatalog(systems: [
  {
    'ID': 99,
    'CODE_SYS': 1,
    'SISTEMA': 'TURBOGENERADOR_CT_GTG_001',
    'PTBG_FLT': 1
  },
  {'ID': 1, 'CODE_SYS': 5, 'SISTEMA': 'No habilitado', 'PTBG_FLT': 0}
], subsystems: [
  {
    'ID': 88,
    'CODE_SYS': 1,
    'CODE_SUB_SYS': 9,
    'NAME_SUB_SYS': 'Aire para ventilación y combustión',
    'PTBG_FLT': 1
  }
], elements: [
  element
]);

class FakeStore extends FilterStore {
  int saves = 0;
  @override
  Future<FilterCatalog> catalog() async => data;
  @override
  Future<List<FilterRow>> history(
          {int? location, bool pendingOnly = false}) async =>
      [];
  @override
  Future<List<FilterRow>> catalogRequests() async => [];
  @override
  Future<int> saveChange(FilterRow element, FilterRow details) async {
    saves++;
    return 123;
  }
}

class CatalogPreviewStore extends FakeStore {
  final preview =
      FilterSeed.decode(File(FilterSeed.assetPath).readAsStringSync());
  @override
  Future<FilterCatalog> catalog() async => preview;
}

Future<void> loadFluxImages(WidgetTester tester) async {
  final errors = <Object>[];
  await tester.runAsync(() async {
    final context = tester.element(find.byType(FilterPage));
    for (final asset in FilterFluxAssets.all) {
      await precacheImage(ResizeImage(AssetImage(asset), width: 960), context,
          onError: (error, _) => errors.add(error));
    }
  });
  expect(errors, isEmpty,
      reason: 'All bundled Flux images must decode offline');
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'rol': 'admin'}));
  test('catalog matches CODE_SYS and CODE_SUB_SYS, never ID', () {
    expect(data.enabledSystems.length, 1);
    expect(data.forSystem(1).single['ID'], 88);
    expect(data.forSubsystem(1, 9).single['CANTIDAD'], 152);
    expect(data.forSubsystem(2, 9), isEmpty);
    expect(
        FilterCatalog.validateElement({...element, 'CANTIDAD': 0}), isNotNull);
    expect(FilterCatalog.validateElement(element), isNull);
  });
  for (final size in [
    const Size(375, 812),
    const Size(600, 960),
    const Size(960, 600)
  ]) {
    testWidgets('all sections fit $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FakeStore();
      for (final theme in [buildTheme(), buildDayTheme()]) {
        for (final page in <Widget>[
          FiltersScreen(store: store),
          FilterChangeScreen(store: store, element: element),
          FilterHistoryScreen(store: store),
          FilterAdminScreen(store: store),
          FilterAddScreen(store: store, catalog: data),
          FilterAvailabilityScreen(store: store, catalog: data)
        ]) {
          await tester.pumpWidget(MaterialApp(
              theme: theme,
              home: MediaQuery(
                  data: MediaQueryData(
                      size: size,
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true),
                  child: page)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${page.runtimeType} at $size');
          await tester.pumpWidget(const SizedBox());
        }
      }
    });
  }
  testWidgets('navigate systems to filter and save only after confirmation',
      (tester) async {
    final store = FakeStore();
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: FiltersScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('No habilitado'), findsNothing);
    expect(find.byType(IndustrialSideRail), findsOneWidget);
    expect(find.byType(FilterFluxImage), findsOneWidget);
    await tester.tap(find.text('Turbogenerador 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aire para ventilación y combustión'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Registrar cambio'));
    await tester.tap(find.text('Registrar cambio'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Revisar y guardar'), 300,
        scrollable: find
            .descendant(
                of: find.descendant(
                    of: find.byType(FilterChangeScreen),
                    matching: find.byType(ListView)),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Revisar y guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pumpAndSettle();
    expect(store.saves, 0);
    expect(find.text('Confirmar cambio completo'), findsOneWidget);
    await tester.tap(find.text('Guardar cambio'));
    await tester.pumpAndSettle();
    expect(store.saves, 1);
  });
  testWidgets('portrait reference screenshot', (tester) async {
    // Optional readable QA image. Normal CI golden keeps deterministic Ahem.
    final qaFont = Platform.environment['FILTER_QA_FONT'];
    if (qaFont != null) {
      await tester.runAsync(() async {
        final fonts = FontLoader('Roboto')
          ..addFont(
              File(qaFont).readAsBytes().then((b) => ByteData.sublistView(b)));
        await fonts.load();
        await (FontLoader('Ahem')
              ..addFont(File(qaFont)
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b))))
            .load();
        final iconBytes =
            await rootBundle.load('fonts/MaterialIcons-Regular.otf');
        await (FontLoader('MaterialIcons')..addFont(Future.value(iconBytes)))
            .load();
      });
    }
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final qaTheme = buildTheme();
    await tester.pumpWidget(MaterialApp(
        theme: qaFont == null
            ? qaTheme
            : qaTheme.copyWith(
                appBarTheme: qaTheme.appBarTheme.copyWith(
                    titleTextStyle: const TextStyle(fontFamily: 'Roboto'))),
        home: FiltersScreen(store: FakeStore())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turbogenerador 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aire para ventilación y combustión'));
    await tester.pumpAndSettle();
    await loadFluxImages(tester);
    await expectLater(
        find.byType(FiltersScreen),
        matchesGoldenFile(qaFont == null
            ? 'goldens/filtros_vertical.png'
            : 'goldens/filtros_vertical_readable.png'));
  });

  testWidgets('approved illustrations cover the four real systems',
      (tester) async {
    final store = CatalogPreviewStore();
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: FiltersScreen(store: store)));
    await tester.pumpAndSettle();
    expect(store.preview.enabledSystems.map(filterSystemArt), [
      FilterArt.turbine,
      FilterArt.turbine,
      FilterArt.fuel,
      FilterArt.water
    ]);
    await tester.scrollUntilVisible(find.text('Agua'), 240,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('Agua'), findsOneWidget);
    expect(
        tester
            .widgetList<FilterFluxImage>(find.byType(FilterFluxImage))
            .any((i) => i.asset == FilterFluxAssets.water),
        isTrue);
  });

  if (Platform.environment['FILTER_QA_FONT'] != null) {
    testWidgets('readable QA screenshots of all eight portrait sections',
        (tester) async {
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Ahem']) {
          await (FontLoader(family)
                ..addFont(File(Platform.environment['FILTER_QA_FONT']!)
                    .readAsBytes()
                    .then((b) => ByteData.sublistView(b))))
              .load();
        }
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      tester.view.physicalSize = const Size(600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CatalogPreviewStore();
      final theme = buildTheme();
      Future<void> mount(Widget page) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(
            theme: theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                    titleTextStyle: const TextStyle(fontFamily: 'Roboto'))),
            home: page));
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await loadFluxImages(tester);
        expect(tester.takeException(), isNull);
        await expectLater(find.byType(FilterPage),
            matchesGoldenFile('goldens/filtros_$name.png'));
      }

      await mount(FiltersScreen(store: store));
      await capture('01_sistemas');
      await tester.tap(find.text('Turbogenerador 1'));
      await tester.pumpAndSettle();
      await capture('02_subsistemas');
      await tester.tap(find.text('Aire para ventilacion y combustion'));
      await tester.pumpAndSettle();
      await capture('03_elementos');
      final e = store.preview.elements.first;
      await mount(FilterChangeScreen(store: store, element: e));
      await capture('04_registro');
      await mount(FilterHistoryScreen(store: store, element: e));
      expect(
          tester
              .widget<FilterHistoryScreen>(find.byType(FilterHistoryScreen))
              .element,
          isNotNull);
      expect(find.text('Filtro de aire casa de filtros'), findsOneWidget);
      await tester.ensureVisible(find.text('Filtro de aire casa de filtros'));
      await tester.pumpAndSettle();
      await capture('05_historial');
      await mount(FilterAdminScreen(store: store));
      await capture('06_administracion');
      await mount(FilterAddScreen(store: store, catalog: store.preview));
      await capture('07_alta');
      await mount(
          FilterAvailabilityScreen(store: store, catalog: store.preview));
      await capture('08_disponibilidad');
    });
  }
}
