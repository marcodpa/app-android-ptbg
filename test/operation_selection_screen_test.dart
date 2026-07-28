import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/models/operation_flow.dart';
import 'package:scv_ptbg/screens/operation_selection_screen.dart';
import 'package:scv_ptbg/screens/replacement_screen.dart';

const _equipo = Equipo(
  id: 2,
  codeSys: 1,
  equipo: 'NOX-LIQUIDO',
  localizacion: 2,
  qrCode: '11-MOT-6242',
  puntos: 6,
  ptEq: 6,
  sistema: 'TURBINA BG-1',
);

const _equipoSinAlineacion = Equipo(
  id: 3,
  codeSys: 1,
  equipo: 'VENTILADOR',
  localizacion: 3,
  puntos: 3,
  ptEq: 3,
  sistema: 'TURBINA BG-1',
);

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OperationSelectionScreen(equipo: _equipo)),
    );
  }

  testWidgets('muestra las cuatro operaciones para PUNTOS 6', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Vibracion'), findsOneWidget);
    expect(find.text('Medición de temperatura'), findsOneWidget);
    expect(find.text('Lubricacion'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Alineación'), findsOneWidget);
    expect(find.text('Reemplazo de equipo'), findsOneWidget);
  });

  testWidgets('oculta alineación cuando PUNTOS no es 1, 2, 6 o 9', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OperationSelectionScreen(equipo: _equipoSinAlineacion),
      ),
    );

    expect(find.text('Alineación'), findsNothing);
    expect(find.byKey(const Key('operation-alignment')), findsNothing);
  });

  testWidgets('abre temperatura con el mismo equipo seleccionado',
      (tester) async {
    OperationType? launched;
    Equipo? launchedEquipment;
    await tester.pumpWidget(
      MaterialApp(
        home: OperationSelectionScreen(
          equipo: _equipo,
          launcher: (_, operation, equipo) async {
            launched = operation;
            launchedEquipment = equipo;
            return null;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('operation-temperature')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start-operations-button')));
    await tester.pump();

    expect(launched, OperationType.temperature);
    expect(launchedEquipment, same(_equipo));
  });

  testWidgets('no permite comenzar sin seleccionar una operacion',
      (tester) async {
    await pumpScreen(tester);

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('start-operations-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('al seleccionar ambas solicita cual comienza', (tester) async {
    await pumpScreen(tester);

    tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('operation-vibration')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final replacementTile = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('operation-replacement')),
        matching: find.byType(InkWell),
      ),
    );
    replacementTile.onTap!();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Elige cual comienza'), findsOneWidget);
    expect(find.text('Primero Vibracion'), findsOneWidget);
    expect(find.text('Primero Reemplazo'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('start-operations-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('abre reemplazo con el mismo equipo seleccionado',
      (tester) async {
    await pumpScreen(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('operation-replacement')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start-operations-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReplacementScreen), findsOneWidget);
    expect(find.text('NOX-LIQUIDO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('component-gearbox')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Caja'), findsOneWidget);
  });

  testWidgets('ejecuta cuatro operaciones respetando la primera elegida',
      (tester) async {
    final launched = <OperationType>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OperationSelectionScreen(
          equipo: _equipo,
          launcher: (_, operation, __) async {
            launched.add(operation);
            return true;
          },
        ),
      ),
    );

    for (final key in const [
      'operation-vibration',
      'operation-temperature',
    ]) {
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await tester.pump();
    }
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('operation-alignment')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pump();
    tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('operation-replacement')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primero Temperatura'));
    await tester.pump();
    tester
        .widget<ElevatedButton>(
          find.byKey(const Key('start-operations-button')),
        )
        .onPressed!();
    await tester.pump();

    expect(launched, [OperationType.temperature]);
    await tester.tap(find.text('Continuar con Vibracion'));
    await tester.pump();
    expect(launched, [OperationType.temperature, OperationType.vibration]);
    await tester.tap(find.text('Continuar con Alineación'));
    await tester.pump();
    await tester.tap(find.text('Continuar con Reemplazo de equipo'));
    await tester.pumpAndSettle();
    expect(launched, [
      OperationType.temperature,
      OperationType.vibration,
      OperationType.alignment,
      OperationType.replacement,
    ]);
  });
}
