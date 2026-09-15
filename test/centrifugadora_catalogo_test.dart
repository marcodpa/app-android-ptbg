import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/models/equipo_visual_config.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/theme.dart';
import 'package:scv_ptbg/widgets/industrial_equipment_card.dart';

Equipo separador(int localizacion, {int tipo = 10}) => Equipo(
      id: localizacion + 4,
      codeSys: 6,
      equipo: 'CENTRIFUGE SEPARATOR',
      localizacion: localizacion,
      puntos: tipo,
      ptEq: tipo,
      sistema: 'TRATAMIENTO DE COMBUSTIBLE',
    );

void main() {
  test('los tres separadores cambian solo su foto de catálogo', () {
    for (final localizacion in [43, 44, 45]) {
      final equipo = separador(localizacion);
      final foto = EquipoVisualResolver.catalogFromEquipo(equipo);
      expect(foto.cleanAsset, 'assets/images/visual_centrifugadora.jpg');
      expect(foto.fit, BoxFit.cover);
      expect(foto.backgroundColor, isNotNull);
      expect(EquipoVisualResolver.fromEquipo(equipo).asset,
          'assets/images/visual_separador_motor.jpg');
      expect(EquipoVisualResolver.previewFromEquipo(equipo).asset,
          'assets/images/visual_separador_motor.jpg');
      expect(EquipoVisualResolver.fromEquipo(equipo).puntos.map((p) => p.punto),
          [1, 2]);
    }
  });

  test('otros tipos conservan su vista previa existente', () {
    for (var tipo = 1; tipo <= 9; tipo++) {
      final equipo = separador(43, tipo: tipo);
      expect(EquipoVisualResolver.catalogFromEquipo(equipo),
          same(EquipoVisualResolver.previewFromEquipo(equipo)));
    }
  });

  for (final dark in [true, false]) {
    for (final size in [const Size(375, 812), const Size(1280, 800)]) {
      testWidgets('tarjeta con foto sin márgenes: dark=$dark, tamaño=$size',
          (tester) async {
        SharedPreferences.setMockInitialValues({'ester_dark_mode': dark});
        await esterThemeController.load();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                height: 340 / 1.02,
                child: IndustrialEquipmentCard(
                  equipo: separador(43),
                  ultima: null,
                  pendingCount: 0,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final foto = tester.widget<Image>(find.byType(Image));
        expect(foto.fit, BoxFit.cover);
        final imagePadding = tester.widget<Padding>(
          find
              .ancestor(of: find.byType(Image), matching: find.byType(Padding))
              .first,
        );
        expect(imagePadding.padding, EdgeInsets.zero);
        final imageArea = find
            .ancestor(of: find.byType(Image), matching: find.byType(ClipRRect))
            .first;
        expect(tester.getSize(find.byType(Image)).width,
            tester.getSize(imageArea).width);
        expect(foto.semanticLabel, 'Separador de combustible');
        final provider = foto.image as ResizeImage;
        expect((provider.imageProvider as AssetImage).assetName,
            'assets/images/visual_centrifugadora.jpg');
        expect(tester.takeException(), isNull);
        if (size.width == 1280) {
          await expectLater(
            find.byType(IndustrialEquipmentCard),
            matchesGoldenFile(
                'goldens/centrifugadora_${dark ? 'oscuro' : 'claro'}.png'),
          );
        }
        await tester.tap(find.byType(IndustrialEquipmentCard));
        expect(taps, 1);
      });
    }
  }
}
