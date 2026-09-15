import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/mapa_marcadores.dart';
import 'package:scv_ptbg/models/mapa_planta.dart';
import 'package:scv_ptbg/screens/mapa_planta_screen.dart';

MarcadorMapa _marcador(int loc, double x, double y,
        {String sistema = 'S.C.I'}) =>
    MarcadorMapa(
      localizacion: loc,
      punto: PuntoMapa(x, y),
      nombre: 'EQ-$loc',
      tag: 'TAG-$loc',
      sistema: sistema,
      color: colorDeSistema(sistema),
    );

void main() {
  group('coordenadas del mapa', () {
    test('todas caen dentro del plano', () {
      for (final entrada in mapaEquipos.entries) {
        expect(entrada.value.x, inInclusiveRange(0.0, 1.0),
            reason: 'LOC-${entrada.key} se salio del plano en X');
        expect(entrada.value.y, inInclusiveRange(0.0, 1.0),
            reason: 'LOC-${entrada.key} se salio del plano en Y');
      }
      expect(mapaBlackStart.x, inInclusiveRange(0.0, 1.0));
      expect(mapaBlackStart.y, inInclusiveRange(0.0, 1.0));
    });

    test('no hay dos equipos en el mismo punto exacto', () {
      // Dos coordenadas identicas hasta el ultimo decimal no salen de dos
      // clics: salen de copiar una linea y olvidar cambiarla. Uno de los dos
      // marcadores quedaria tapado para siempre.
      final vistos = <String, int>{};
      for (final entrada in mapaEquipos.entries) {
        final clave = '${entrada.value.x},${entrada.value.y}';
        expect(vistos.containsKey(clave), isFalse,
            reason: 'LOC-${entrada.key} esta encima de LOC-${vistos[clave]}');
        vistos[clave] = entrada.key;
      }
    });

    test('las zonas son rectangulos con esquinas en orden', () {
      expect(mapaZonas, isNotEmpty);
      for (final z in mapaZonas) {
        expect(z.x0, lessThan(z.x1),
            reason: '${z.nombre} tiene el ancho al reves');
        expect(z.y0, lessThan(z.y1),
            reason: '${z.nombre} tiene el alto al reves');
        expect(z.x1, inInclusiveRange(0.0, 1.0), reason: z.nombre);
        expect(z.y1, inInclusiveRange(0.0, 1.0), reason: z.nombre);
      }
    });

    test('los compresores caen dentro de su zona', () {
      // Comprobacion de cordura de la traduccion de Python a Dart: si el
      // generador mezclara las columnas X e Y, esto lo caza. Los compresores
      // son buen testigo porque estan juntos y bien rotulados en el plano.
      final zona =
          mapaZonas.firstWhere((z) => z.nombre == 'COMPRESORES DE AIRE');
      for (final loc in [53, 54, 55]) {
        final p = mapaEquipos[loc]!;
        expect(p.x, inInclusiveRange(zona.x0, zona.x1), reason: 'LOC-$loc');
        expect(p.y, inInclusiveRange(zona.y0, zona.y1), reason: 'LOC-$loc');
      }
    });

    test('el plano se declara apaisado', () {
      // Si esto cambia es que se reexporto el plano, y la pantalla se abre de
      // lado justamente porque es mas ancho que alto.
      expect(planoRelacion, greaterThan(1.0));
    });
  });

  group('colores por sistema', () {
    test('cada sistema del mapa tiene color propio', () {
      final usados = <Color>{};
      for (final color in coloresSistema.values) {
        expect(usados.add(color), isTrue,
            reason: 'dos sistemas comparten el mismo color');
      }
    });

    test('tolera como venga escrito el sistema en la base', () {
      // "S.C.I", "SCI" y "s.c.i." son el mismo sistema. Pintar uno de gris
      // por una diferencia de puntuacion se lee como sistema desconocido.
      final esperado = coloresSistema['S.C.I'];
      expect(colorDeSistema('S.C.I'), esperado);
      expect(colorDeSistema('SCI'), esperado);
      expect(colorDeSistema('  s.c.i.  '), esperado);
    });

    test('un sistema que no conoce no revienta', () {
      expect(colorDeSistema('SISTEMA NUEVO'), colorSistemaDesconocido);
      expect(colorDeSistema(''), colorSistemaDesconocido);
    });
  });

  group('toque sobre el mapa', () {
    const plano = Size(1000, 500);

    test('devuelve el mas cercano, no el primero que entre', () {
      // Donde hay seis centrifugadoras en un palmo, varias caen dentro de la
      // tolerancia; el que el mecanico quiere es al que apunto mas de cerca.
      final marcadores = [
        _marcador(1, 0.500, 0.5),
        _marcador(2, 0.510, 0.5),
        _marcador(3, 0.520, 0.5),
      ];
      final tocado = marcadorMasCercano(
        marcadores,
        const Offset(512, 250),
        plano,
        30,
      );
      expect(tocado?.localizacion, 2);
    });

    test('el plano vacio no selecciona nada', () {
      final marcadores = [_marcador(1, 0.1, 0.1)];
      expect(
        marcadorMasCercano(marcadores, const Offset(900, 400), plano, 20),
        isNull,
      );
    });

    test('sin marcadores tampoco', () {
      expect(
        marcadorMasCercano(const [], const Offset(10, 10), plano, 20),
        isNull,
      );
    });
  });

  group('leyenda', () {
    test('cuenta los equipos de cada sistema', () {
      final resumen = resumenSistemas([
        _marcador(1, 0.1, 0.1, sistema: 'S.C.I'),
        _marcador(2, 0.2, 0.2, sistema: 'S.C.I'),
        _marcador(3, 0.3, 0.3, sistema: 'AGUA POTABLE'),
      ]);
      expect(resumen.length, 2);
      expect(Map.fromEntries(resumen)['S.C.I'], 2);
      expect(Map.fromEntries(resumen)['AGUA POTABLE'], 1);
    });

    test('el orden es fijo, no por cantidad', () {
      // Una leyenda que se reordena sola obliga a releerla entera para
      // encontrar el mismo sistema de ayer.
      final resumen = resumenSistemas([
        _marcador(1, 0.1, 0.1, sistema: 'AGUA POTABLE'),
        _marcador(2, 0.2, 0.2, sistema: 'TURBINA BG-1'),
        _marcador(3, 0.3, 0.3, sistema: 'TURBINA BG-1'),
      ]);
      // TURBINA BG-1 va antes que AGUA POTABLE en la tabla de colores,
      // aunque aqui AGUA POTABLE se hubiera contado primero.
      expect(resumen.first.key, 'TURBINA BG-1');
    });

    test('un sistema desconocido aparece igual, al final', () {
      final resumen = resumenSistemas([
        _marcador(1, 0.1, 0.1, sistema: 'SISTEMA RARO'),
        _marcador(2, 0.2, 0.2, sistema: 'S.C.I'),
      ]);
      expect(resumen.length, 2);
      expect(resumen.last.key, 'SISTEMA RARO');
    });
  });

  group('pantalla del mapa', () {
    testWidgets(
        'conserva leyenda buscador centrar y volver con la barra compacta',
        (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        routes: {
          '/home': (_) => const Scaffold(body: Text('Inicio confirmado'))
        },
        home: const MapaPlantaScreen(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sistemas'));
      await tester.pumpAndSettle();
      expect(find.text('Orden abierta'), findsOneWidget);
      await tester.tap(find.text('Sistemas'));
      await tester.pumpAndSettle();
      expect(find.text('Orden abierta'), findsNothing);
      await tester.tap(find.byTooltip('Buscar un equipo'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver toda la planta'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio confirmado'), findsOneWidget);
    });
    for (final size in [
      const Size(960, 600),
      const Size(800, 480),
      const Size(640, 360),
      const Size(450, 800)
    ]) {
      testWidgets('barra compacta deja visible el plano en $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const MapaPlantaScreen(),
        ));
        await tester.pumpAndSettle();
        final plano = tester.getRect(find.byType(InteractiveViewer));
        expect(plano.top, lessThanOrEqualTo(64));
        expect(plano.height, greaterThanOrEqualTo(size.height - 64));
        expect(find.text('Orden abierta'), findsNothing);
        expect(find.byTooltip('Volver'), findsOneWidget);
        expect(find.byTooltip('Buscar un equipo'), findsOneWidget);
        expect(find.byTooltip('Ver toda la planta'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('dibuja el plano sin base de datos', (tester) async {
      // Sin sqflite la carga falla; la pantalla tiene que aguantarlo y
      // mostrar el plano igual, porque el plano por si solo ya sirve para
      // ubicarse.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: MapaPlantaScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Mapa de la planta'), findsOneWidget);
      expect(find.text('Sistemas'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Image) return false;
          // El plano lleva cacheWidth, asi que su AssetImage viene envuelto
          // en un ResizeImage; hay que mirar adentro.
          final proveedor = w.image;
          final base =
              proveedor is ResizeImage ? proveedor.imageProvider : proveedor;
          return base is AssetImage && base.assetName == planoPlanta;
        }),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no muestra la ficha hasta que se toca un marcador',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: MapaPlantaScreen()));
      await tester.pumpAndSettle();

      // El marcador es chico a proposito; tocar el plano vacio no debe abrir
      // nada ni dejar una ficha colgada.
      expect(find.text('Abrir'), findsNothing);
      await tester.tapAt(const Offset(200, 700));
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
