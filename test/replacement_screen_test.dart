import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/replacement_request.dart';
import 'package:scv_ptbg/screens/replacement_screen.dart';
import 'package:scv_ptbg/widgets/replacement_focus_image.dart';

const _motorCajaBomba = Equipo(
  id: 2,
  codeSys: 1,
  equipo: 'NOX-LIQUIDO',
  localizacion: 2,
  qrCode: '11-MOT-6242',
  puntos: 6,
  ptEq: 6,
  sistema: 'TURBINA BG-1',
);

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReplacementScreen(equipo: _motorCajaBomba)),
    );
  }

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  Future<void> selectMotor(
    WidgetTester tester, {
    required bool technicalSpecs,
  }) async {
    await scrollTo(tester, const Key('component-motor'));
    await tester.tap(find.byKey(const Key('component-motor')));
    await tester.pumpAndSettle();
    expect(find.text('Especificaciones del motor'), findsOneWidget);
    await tester.tap(find.text(
      technicalSpecs ? 'Si, cambiarlas' : 'No, conservarlas',
    ));
    await tester.pumpAndSettle();
  }

  Future<void> prepareMotorReplacement(WidgetTester tester) async {
    await selectMotor(tester, technicalSpecs: false);
    await tester.ensureVisible(find.byKey(const Key('brand-motor')));
    await tester.enterText(find.byKey(const Key('brand-motor')), 'WEG');
    await tester.ensureVisible(find.byKey(const Key('model-motor')));
    await tester.enterText(find.byKey(const Key('model-motor')), 'W22');
    await tester.ensureVisible(find.byKey(const Key('serial-motor')));
    await tester.enterText(find.byKey(const Key('serial-motor')), 'M-001');
    await tester.ensureVisible(
      find.byKey(const Key('review-replacement-button')),
    );
    await tester.tap(find.byKey(const Key('review-replacement-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra solo los componentes que posee el equipo',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(ReplacementFocusImage), findsOneWidget);
    await scrollTo(tester, const Key('component-motor'));
    expect(find.text('Motor'), findsOneWidget);
    await scrollTo(tester, const Key('component-gearbox'));
    expect(find.text('Caja'), findsOneWidget);
    await scrollTo(tester, const Key('component-pump'));
    expect(find.text('Bomba'), findsOneWidget);
    expect(find.text('Ventilador'), findsNothing);
  });

  testWidgets('exige marca modelo y serial por componente', (tester) async {
    await pumpScreen(tester);

    await selectMotor(tester, technicalSpecs: false);
    expect(find.byKey(const Key('replacement-image-focused')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('review-replacement-button')));
    await tester.tap(find.byKey(const Key('review-replacement-button')));
    await tester.pump();

    expect(find.text('Ingresa la marca'), findsOneWidget);
    expect(find.text('Ingresa el modelo'), findsOneWidget);
    expect(find.text('Ingresa el serial'), findsOneWidget);
  });

  testWidgets('muestra la placa tecnica completa al reemplazar un motor',
      (tester) async {
    await pumpScreen(tester);

    await selectMotor(tester, technicalSpecs: true);

    for (final key in const [
      'voltage-motor',
      'current-motor',
      'rpm-motor',
      'service-factor-motor',
      'horsepower-motor',
      'frame-motor',
      'drive-bearing-motor',
      'opposite-bearing-motor',
      'cycle-motor',
      'start-motor',
      'phases-motor',
      'tension-motor',
      'lubrication-motor',
    ]) {
      await scrollTo(tester, Key(key));
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });

  testWidgets('conserva la placa tecnica cuando el usuario responde no',
      (tester) async {
    await pumpScreen(tester);

    await selectMotor(tester, technicalSpecs: false);

    expect(find.byKey(const Key('brand-motor')), findsOneWidget);
    expect(find.byKey(const Key('voltage-motor')), findsNothing);
    expect(find.text('Se conservaran las especificaciones actuales'),
        findsOneWidget);
  });

  testWidgets('permite revisar varios componentes por separado',
      (tester) async {
    await pumpScreen(tester);

    await selectMotor(tester, technicalSpecs: false);
    await scrollTo(tester, const Key('component-gearbox'));
    await tester.tap(find.byKey(const Key('component-gearbox')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('brand-motor')));
    await tester.enterText(find.byKey(const Key('brand-motor')), 'WEG');
    await tester.ensureVisible(find.byKey(const Key('model-motor')));
    await tester.enterText(find.byKey(const Key('model-motor')), 'W22');
    await tester.ensureVisible(find.byKey(const Key('serial-motor')));
    await tester.enterText(find.byKey(const Key('serial-motor')), 'M-001');
    await tester.scrollUntilVisible(
      find.byKey(const Key('brand-gearbox')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('brand-gearbox')), 'SEW');
    await tester.ensureVisible(find.byKey(const Key('model-gearbox')));
    await tester.enterText(find.byKey(const Key('model-gearbox')), 'R97');
    await tester.ensureVisible(find.byKey(const Key('serial-gearbox')));
    await tester.enterText(find.byKey(const Key('serial-gearbox')), 'C-002');

    await tester
        .ensureVisible(find.byKey(const Key('review-replacement-button')));
    await tester.tap(find.byKey(const Key('review-replacement-button')));
    await tester.pumpAndSettle();

    expect(find.text('Revisar reemplazo'), findsOneWidget);
    expect(find.byType(ReplacementFocusImage), findsOneWidget);
    expect(find.byKey(const Key('replacement-image-focused')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('WEG'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WEG'), findsOneWidget);
    expect(find.text('M-001'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('SEW'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SEW'), findsOneWidget);
    expect(find.text('C-002'), findsOneWidget);
  });

  testWidgets('confirma cuando la tablet guarda el reemplazo localmente',
      (tester) async {
    ReplacementRequest? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: ReplacementScreen(
          equipo: _motorCajaBomba,
          saveReplacement: (request) async {
            sent = request;
            return const ReplacementSaveResult.success(
              created: 1,
              updated: 0,
              unchanged: 0,
            );
          },
        ),
      ),
    );
    await prepareMotorReplacement(tester);

    await tester
        .ensureVisible(find.byKey(const Key('complete-replacement-button')));
    await tester.tap(find.byKey(const Key('complete-replacement-button')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(sent, isNotNull);
    expect(sent!.components[ReplacementComponent.motor]!.serial, 'M-001');
    expect(find.text('Reemplazo guardado'), findsOneWidget);
    expect(find.textContaining('guardado en la tablet'), findsOneWidget);
  });

  testWidgets('mantiene los datos cuando SQLite rechaza el reemplazo',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReplacementScreen(
          equipo: _motorCajaBomba,
          saveReplacement: (_) async =>
              const ReplacementSaveResult.failure('Falta la bomba actual'),
        ),
      ),
    );
    await prepareMotorReplacement(tester);

    await tester
        .ensureVisible(find.byKey(const Key('complete-replacement-button')));
    await tester.tap(find.byKey(const Key('complete-replacement-button')));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo guardar localmente'), findsOneWidget);
    expect(find.text('Falta la bomba actual'), findsOneWidget);
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('WEG'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WEG'), findsOneWidget);
    expect(find.text('M-001'), findsOneWidget);
  });
}
