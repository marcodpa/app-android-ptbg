import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/widgets/selector_hora_rueda.dart';

/// El selector de hora con ruedas del check list de compresores.
///
/// Antes la hora se escribia a mano y entraba de todo ('8', '8:5', '08.30').
/// Con las ruedas siempre sale HH:mm.
Future<String?> _abrir(WidgetTester tester, {String? inicial}) async {
  String? elegida;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            elegida = await elegirHoraConRuedas(
              context,
              inicial: inicial,
              titulo: 'Hora de inicio',
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return elegida;
}

void main() {
  testWidgets('arranca en la hora que ya tenia el campo', (tester) async {
    await _abrir(tester, inicial: '07:30');
    expect(find.byKey(const Key('hora-rueda-valor')), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
  });

  testWidgets('acepta tambien la hora con segundos, como la guarda la base',
      (tester) async {
    await _abrir(tester, inicial: '14:05:22');
    expect(find.text('14:05'), findsOneWidget);
  });

  testWidgets('una hora imposible o basura no rompe: arranca en la actual',
      (tester) async {
    // '99:99' y 'ocho y media' vienen de la epoca en que se escribia a mano.
    for (final basura in ['99:99', 'ocho y media', '']) {
      await _abrir(tester, inicial: basura);
      final ahora = TimeOfDay.now();
      final esperado = '${ahora.hour.toString().padLeft(2, '0')}:'
          '${ahora.minute.toString().padLeft(2, '0')}';
      expect(find.text(esperado), findsOneWidget,
          reason: 'con "$basura" debe caer en la hora actual');
      // Cerrar antes de la siguiente vuelta: la hoja abierta tapa el boton.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('deslizar la rueda de minutos cambia la hora que se devuelve',
      (tester) async {
    String? elegida;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              elegida = await elegirHoraConRuedas(
                context,
                inicial: '06:00',
                titulo: 'Hora de inicio',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Sube la rueda de minutos: en una rueda, arrastrar hacia arriba avanza.
    await tester.drag(
      find.byKey(const Key('hora-rueda-minutos')),
      const Offset(0, -42 * 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('06:05'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hora-rueda-aceptar')));
    await tester.pumpAndSettle();
    expect(elegida, '06:05');
  });

  testWidgets('cancelar no devuelve nada: el campo se queda como estaba',
      (tester) async {
    String? elegida = 'sin tocar';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              elegida = await elegirHoraConRuedas(
                context,
                inicial: '06:00',
                titulo: 'Hora de fin',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(elegida, isNull);
  });
}
