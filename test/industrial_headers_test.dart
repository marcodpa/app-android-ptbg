import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/widgets/industrial_navigation.dart';

void main() {
  for (final width in [320.0, 736.0, 1024.0]) {
    for (final dark in [false, true]) {
      testWidgets('headers fit width $width, dark $dark, enlarged text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final panel in [false, true]) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: DefaultTabController(
                length: 2,
                child: Scaffold(
                  appBar: IndustrialAppBar(
                    titulo: 'Órdenes de reparación de componentes industriales',
                    subtitulo:
                        'Equipo de ejemplo con identificación larga · LOC-048',
                    panel: panel,
                    leading: IconButton(
                        onPressed: () {}, icon: const Icon(Icons.arrow_back)),
                    actions: [
                      IconButton(
                          onPressed: () {}, icon: const Icon(Icons.refresh))
                    ],
                    bottom: const TabBar(tabs: [
                      Tab(text: 'Abiertas'),
                      Tab(text: 'Finalizadas')
                    ]),
                  ),
                  body: Column(children: [
                    IndustrialContentHeader(
                      title: 'Mapa de la planta y sistemas industriales',
                      subtitle: 'Todos los equipos ubicados en la planta',
                      actions: [
                        IconButton(
                            onPressed: () {}, icon: const Icon(Icons.search)),
                        IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.fit_screen)),
                      ],
                    )
                  ]),
                )),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Finalizadas'));
          await tester.pumpAndSettle();
          expect(
              DefaultTabController.of(tester.element(find.byType(TabBar)))
                  .index,
              1);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('content header preserves custom back, actions and home fallback',
      (tester) async {
    var backs = 0;
    var actions = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IndustrialContentHeader(
      title: 'Sincronización',
      onBack: () => backs++,
      actions: [
        IconButton(
            tooltip: 'Actualizar',
            onPressed: () => actions++,
            icon: const Icon(Icons.refresh))
      ],
    ))));
    await tester.tap(find.byTooltip('Volver'));
    await tester.tap(find.byTooltip('Actualizar'));
    expect(backs, 1);
    expect(actions, 1);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      routes: {'/home': (_) => const Scaffold(body: Text('Inicio confirmado'))},
      home: const Scaffold(body: IndustrialContentHeader(title: 'Equipos')),
    ));
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio confirmado'), findsOneWidget);
  });

  testWidgets('service back respects unsaved-work PopScope', (tester) async {
    var blocked = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => PopScope(
                              canPop: false,
                              onPopInvokedWithResult: (popped, _) {
                                if (!popped) blocked++;
                              },
                              child: const Scaffold(
                                  appBar: IndustrialAppBar(
                                      titulo: 'Captura pendiente')),
                            ),
                          )),
                      child: const Text('Abrir')),
                ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(blocked, 1);
    expect(find.text('Captura pendiente'), findsOneWidget);
  });

  testWidgets('render approved family from real Flutter widgets',
      (tester) async {
    const fontPath = String.fromEnvironment('HEADER_FONT');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('HeaderPreview');
        loader.addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
            File('${File(fontPath).parent.path}/materialicons-regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView));
        await icons.load();
      });
    }
    await tester.binding.setSurfaceSize(const Size(736, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: fontPath.isEmpty ? null : 'HeaderPreview'),
        home: Scaffold(
            body: RepaintBoundary(
          key: boundaryKey,
          child: const ColoredBox(
              color: Color(0xFFEFF3F7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IndustrialContentHeader(
                      title: 'Panel industrial',
                      subtitle: 'Equipos, servicios y seguimiento de planta',
                      showBack: false,
                      icon: Icons.dashboard_rounded),
                  SizedBox(height: 20),
                  SizedBox(
                      height: 100,
                      child: IndustrialAppBar(
                          titulo: 'Todos los equipos',
                          leading: BackButton(),
                          subtitulo:
                              'Conjuntos de planta e inventario de piezas',
                          panel: true)),
                  SizedBox(height: 20),
                  SizedBox(
                      height: 76,
                      child: IndustrialAppBar(
                          titulo: 'Captura de vibración',
                          leading: BackButton(),
                          subtitulo: 'Motor de bomba · LOC-048')),
                ],
              )),
        ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('HEADER_PREVIEW');
    if (output.isNotEmpty) {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
