import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/equipo_visual_config.dart';
import 'package:scv_ptbg/models/temperature_plan.dart';
import 'package:scv_ptbg/models/lubrication_plan.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/models/replacement_visual_layout.dart';
import 'package:scv_ptbg/models/work_order.dart';
import 'package:scv_ptbg/models/limpieza_plato.dart';
import 'package:scv_ptbg/screens/limpieza_plato_screen.dart';
import 'package:scv_ptbg/screens/operation_selection_screen.dart';

const equipo = Equipo(
    id: 47,
    codeSys: 6,
    equipo: 'SEPARADOR',
    localizacion: 43,
    puntos: 10,
    ptEq: 10,
    sistema: 'CENTRIFUGADORAS');

void main() {
  test('tipo 10 solo mide los dos apoyos del motor', () {
    expect(Equipo.resolverTipoVisual(rawPtEq: 10), 10);
    expect(PlanMedicionResolver.fromPuntos(10).map((p) => p.puntoDb), [1, 2]);
    expect(TemperaturePlanResolver.fromPuntos(10).map((p) => p.dbColumn),
        ['T1', 'T2']);
    expect(LubricationPlanResolver.fromPuntos(10).map((p) => p.dbColumn),
        ['L1', 'L2']);
    expect(EquipoVisualResolver.fromEquipo(equipo).puntos.length, 2);
    expect(EquipoVisualResolver.fromEquipo(equipo).asset,
        'assets/images/visual_separador_motor.jpg');
    expect(ReplacementComponentResolver.fromPuntos(10),
        [ReplacementComponent.motor]);
    expect(ReplacementVisualResolver.fromPuntos(10)!.components,
        {ReplacementComponent.motor});
    expect(CouplingChangeResolver.isEligible(10), isTrue);
    expect(BeltAdjustmentResolver.isEligible(10), isFalse);
    expect(
        AlignmentPlanResolver.fromPuntos(10).single.fields.map((f) => f.column),
        [
          'AMB_ANGULO_V',
          'AMB_ANGULO_H',
          'AMB_COMPENSACION_V',
          'AMB_COMPENSACION_H'
        ]);
    expect(
        PlanMedicionResolver.fromPuntos(1).map((p) => p.puntoDb), [1, 2, 5, 6]);
  });

  test(
      'horometro entero incluye cero sin aceptar negativos, decimales ni overflow',
      () {
    for (final value in ['', '-1', '0.1', '1,5', '2147483648']) {
      expect(LimpiezaPlato.leerHorometro(value), isNull);
    }
    expect(LimpiezaPlato.leerHorometro('0'), 0);
    expect(LimpiezaPlato.leerHorometro(' 1234 '), 1234);
  });

  test('seleccionar limpieza no la marca como realizada antes de guardar', () {
    final odt = WorkOrder.forSelection(
        tabletOrigen: 'TABLET-TEST',
        odt: 12,
        createdAt: DateTime(2026, 9, 8),
        equipo: 'SEPARADOR',
        ubicacion: 43,
        codeConjunto: 6,
        services: {OperationType.plateCleaning});
    expect(odt.toDbMap()['limpieza_plato'], 0);
  });

  testWidgets('limpieza aparece exclusivamente en el menu tipo 10',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: OperationSelectionScreen(equipo: equipo)));
    await tester.scrollUntilVisible(
        find.byKey(const Key('operation-plate-cleaning')), 300);
    expect(find.byKey(const Key('operation-plate-cleaning')), findsOneWidget);
    expect(find.byKey(const Key('operation-belt-adjustment')), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: OperationSelectionScreen(
            equipo: Equipo(
                id: 1,
                codeSys: 1,
                equipo: 'BOMBA',
                localizacion: 1,
                puntos: 1,
                ptEq: 1,
                sistema: 'PLANTA'))));
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('operation-plate-cleaning')), findsNothing);
  });

  testWidgets('guarda fecha y hora automaticas, horometro y observacion',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'responsable': 'MARCO', 'cargo': 'MECANICO'});
    LimpiezaPlato? guardada;
    await tester.pumpWidget(MaterialApp(
        home: LimpiezaPlatoScreen(
            equipo: equipo,
            odt: 123,
            reloj: () => DateTime(2026, 9, 8, 10, 22, 23),
            onSave: (m) async {
              guardada = m;
            })));
    await tester.enterText(find.byKey(const Key('plato-horometro')), '1234');
    await tester.enterText(
        find.byKey(const Key('plato-observaciones')), 'Limpieza realizada');
    await tester.ensureVisible(find.byKey(const Key('plato-guardar')));
    await tester.tap(find.byKey(const Key('plato-guardar')));
    await tester.pumpAndSettle();
    expect(guardada, isNotNull);
    expect(guardada!.fecha, '2026-09-08');
    expect(guardada!.hora, '10:22:23');
    expect(guardada!.horasFuncionamiento, 1234);
    expect(guardada!.responsable, 'MARCO');
    expect(guardada!.odt, 123);
    expect(guardada!.observaciones, 'Limpieza realizada');
    expect(guardada!.sincronizado, isFalse);
    expect(LimpiezaPlato.fromMap(guardada!.toDbMap()).toDbMap(),
        guardada!.toDbMap());
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin horometro no guarda, otros equipos no permiten limpieza',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: LimpiezaPlatoScreen(
            equipo: equipo,
            odt: 123,
            onSave: (_) async {
              saves++;
            })));
    await tester.ensureVisible(find.byKey(const Key('plato-guardar')));
    await tester.tap(find.byKey(const Key('plato-guardar')));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Ingrese horas enteras entre 0 y 2147483647.'),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('plato-horometro')), '0.1');
    await tester.ensureVisible(find.byKey(const Key('plato-guardar')));
    await tester.tap(find.byKey(const Key('plato-guardar')));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Ingrese horas enteras entre 0 y 2147483647.'),
        findsOneWidget);
  });
}
