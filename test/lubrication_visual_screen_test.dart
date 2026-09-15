import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/screens/lubrication_capture_screen.dart';

const _equipo = Equipo(
  id: 1,
  codeSys: 1,
  equipo: 'BOMBA DE PRUEBA',
  localizacion: 10,
  puntos: 6,
  ptEq: 6,
  sistema: 'SERVICIOS',
  info: EquipoInfo(
    localizacion: 10,
    marca: 'PTBG',
    lubricacion: 'Grasa EP2',
    motoresLub: 'Motor principal',
    cantMotLub: 10,
    elecMotLub: 5,
    manMotLub: 4,
    elementoLub: 'Bomba y caja',
    cantElemLub: 8,
    elecElemLub: 4,
    manElemLub: 3,
  ),
);

void main() {
  testWidgets('muestra todos los puntos, foto y ficha plegable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LubricationCaptureScreen(equipo: _equipo)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Rodamiento acople:'), findsNothing);
    await tester.tap(find.byKey(const Key('lubrication-info-expansion')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rodamiento acople:'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('lubrication-visual-map')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Guía visual de lubricación'), findsOneWidget);
    expect(find.text('Motor'), findsNothing);
    expect(find.text('Caja multiplicadora'), findsNothing);
    expect(find.text('Bomba / compresor'), findsNothing);
    expect(find.text('Pistola eléctrica'), findsWidgets);
    expect(find.text('Pistola manual'), findsWidgets);
    expect(
      find.byKey(const Key('lubrication-location-L1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('lubrication-L1')), findsOneWidget);
    expect(find.byKey(const Key('lubrication-L6')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save-lubrication-button')), findsOneWidget);
  });

  testWidgets('deja vacíos los gramos no configurados', (tester) async {
    const equipoSinCantidades = Equipo(
      id: 2,
      codeSys: 1,
      equipo: 'BOMBA SIN CANTIDAD',
      localizacion: 11,
      puntos: 1,
      ptEq: 1,
      sistema: 'SERVICIOS',
      info: EquipoInfo(
        localizacion: 11,
        lubricacion: 'Grasa EP2',
        cantMotLub: 0,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LubricationCaptureScreen(equipo: equipoSinCantidades),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('lubrication-L1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final motorField = tester.widget<TextFormField>(
      find.byKey(const Key('lubrication-L1')),
    );
    final pumpField = tester.widget<TextFormField>(
      find.byKey(const Key('lubrication-L5')),
    );
    expect(motorField.controller!.text, isEmpty);
    expect(pumpField.controller!.text, isEmpty);
  });

  testWidgets('NOX aplica elemento solo al acoplamiento L3 y L4', (
    tester,
  ) async {
    const equipoNox = Equipo(
      id: 3,
      codeSys: 1,
      equipo: 'BOMBA NOX',
      localizacion: 12,
      puntos: 6,
      ptEq: 6,
      sistema: 'NOX SERVICIOS',
      info: EquipoInfo(
        localizacion: 12,
        motoresLub: 'MOTOR NOX',
        cantMotLub: 55,
        elecMotLub: 28,
        manMotLub: 23,
        elementoLub: 'ACOPLAMIENTO DE NOX',
        cantElemLub: 110,
        elecElemLub: 55,
        manElemLub: 46,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: LubricationCaptureScreen(equipo: equipoNox)),
    );
    await tester.pumpAndSettle();

    TextFormField field(String point) => tester.widget<TextFormField>(
          find.byKey(Key('lubrication-$point')),
        );

    expect(field('L1').controller!.text, '55');
    expect(field('L2').controller!.text, '55');
    expect(field('L3').controller!.text, '110');
    expect(field('L4').controller!.text, '110');
    expect(field('L5').controller!.text, isEmpty);
    expect(field('L6').controller!.text, isEmpty);
  });

  testWidgets('ventiladores interpreta cantidad como emboladas, no gramos', (
    tester,
  ) async {
    const ventiladores = Equipo(
      id: 4,
      codeSys: 1,
      equipo: 'VENTILADORES NOX',
      localizacion: 13,
      puntos: 5,
      ptEq: 5,
      sistema: 'NOX SERVICIOS',
      info: EquipoInfo(
        localizacion: 13,
        elementoLub: 'VENTILADORES',
        cantElemLub: 3,
        elecElemLub: 4,
        manElemLub: 3,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LubricationCaptureScreen(equipo: ventiladores),
      ),
    );
    await tester.pumpAndSettle();

    final l7 = tester.widget<TextFormField>(
      find.byKey(const Key('lubrication-L7')),
    );
    final l8 = tester.widget<TextFormField>(
      find.byKey(const Key('lubrication-L8')),
    );
    expect(l7.controller!.text, isEmpty);
    expect(l8.controller!.text, isEmpty);
    expect(find.text('3 emboladas'), findsNWidgets(2));
    expect(find.text('3 g'), findsNothing);
  });
}
