import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/checklist_compresor.dart';
import 'package:scv_ptbg/models/models.dart';
import 'package:scv_ptbg/screens/checklist_compresor_screen.dart';

/// La pantalla del check list de compresores (SF-OP-FOR-040).
///
/// En las pruebas no hay SQLite, asi que el historial de mantenimiento cae en
/// "Sin registro previo": justo el caso de una tablet nueva.
const _compresor = Equipo(
  id: 57,
  codeSys: 9,
  equipo: 'COMPRESOR A',
  localizacion: 57,
  puntos: 0,
  sistema: 'COMPRESORES DE AIRE',
  subsistema: 'AIRE COMPRIMIDO',
);

Future<void> _abrir(
  WidgetTester tester, {
  List<ChecklistCompresor> historial = const [],
}) async {
  // Alto como la tablet real: con los 600 px por defecto las secciones de
  // abajo quedan fuera de pantalla y los taps no llegan.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Con la misma localizacion que la app real: el calendario del
  // mantenimiento sale en espanol y sus botones dicen ACEPTAR y Cancelar.
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ChecklistCompresorScreen(
        compresor: _compresor,
        cargarHistorial: (_) async => historial,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _hoyDdMmAaaa() {
  final hoy = DateTime.now();
  return '${hoy.day.toString().padLeft(2, '0')}/'
      '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
}

/// El texto del primer campo con esa etiqueta: hay uno por cada una de las
/// cuatro tareas de mantenimiento, y las pruebas trabajan sobre la primera.
String _textoDe(WidgetTester tester, String etiqueta) =>
    tester
        .widget<TextField>(find.widgetWithText(TextField, etiqueta).first)
        .controller
        ?.text ??
    '';

void main() {
  testWidgets(
      'NO muestra fecha horas y observacion anteriores sin campos nuevos',
      (tester) async {
    await _abrir(tester, historial: [
      ChecklistCompresor.fromMap({
        'uuid': 'anterior',
        'localizacion': 57,
        'fecha': '2026-07-01',
        'hora': '08:00',
        'mtto_lub_uf': '01/07/2026',
        'mtto_lub_uh': '3000',
        'mtto_lub_obs': 'Grasa aplicada',
      }),
      ChecklistCompresor.fromMap({
        'uuid': 'sin-mantenimiento',
        'localizacion': 57,
        'fecha': '2026-08-01',
        'hora': '08:00',
      }),
    ]);
    await tester.tap(find.text('Control de mantenimiento'));
    await tester.pumpAndSettle();
    expect(find.text('Última vez: 01/07/2026 · 3000 horas · Grasa aplicada'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Fecha'), findsNothing);
    expect(find.text('Sin registro previo'), findsNWidgets(3));
    await tester.tap(find.text('SÍ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO').first);
    await tester.pumpAndSettle();
    expect(find.text('Última vez: 01/07/2026 · 3000 horas · Grasa aplicada'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Fecha'), findsNothing);
  });
  // Lo que el formulario pide al abrir: 4 datos de cabecera mas una
  // respuesta por pregunta de inspeccion. Se calcula y no se pone el numero
  // a mano para que agregar una pregunta al formato no rompa estas pruebas.
  final base = 4 + ChecklistCompresor.preguntas.length;

  testWidgets('el SI tambien deja escribir una observacion, pero opcional',
      (tester) async {
    await _abrir(tester);

    await tester.tap(find.text('Inspeccion y control mecanico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SI').first);
    await tester.pumpAndSettle();

    // Aparece la caja de observacion en modo opcional, sin regano.
    expect(find.text('Observación (opcional)'), findsOneWidget);
    expect(find.text('Obligatoria porque la respuesta es NO'), findsNothing);

    // Con NO la caja pasa a obligatoria.
    await tester.tap(find.text('NO').first);
    await tester.pumpAndSettle();
    expect(find.text('Obligatoria porque la respuesta es NO'), findsOneWidget);
  });

  testWidgets('responder NO y escribir la observacion salda ese faltante',
      (tester) async {
    await _abrir(tester);
    expect(find.text('Faltan $base datos por llenar'), findsOneWidget);

    await tester.tap(find.text('Inspeccion y control mecanico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO').first);
    await tester.pumpAndSettle();

    // Un NO sin explicacion sigue contando como faltante.
    expect(find.text('Faltan $base datos por llenar'), findsOneWidget);
    expect(find.text('Obligatoria porque la respuesta es NO'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'FUGA EN LA VALVULA');
    await tester.pumpAndSettle();
    expect(find.text('Faltan ${base - 1} datos por llenar'), findsOneWidget);

    // Y si la borra, vuelve a contar: el NO no queda saldado con espacios.
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pumpAndSettle();
    expect(find.text('Faltan $base datos por llenar'), findsOneWidget);
  });

  testWidgets('al escribir la observacion del NO el regano rojo desaparece',
      (tester) async {
    // El aviso tiene que apagarse en cuanto se escribe, sin esperar a que
    // otra cosa repinte la tarjeta.
    await _abrir(tester);

    await tester.tap(find.text('Inspeccion y control mecanico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO').first);
    await tester.pumpAndSettle();
    expect(find.text('Obligatoria porque la respuesta es NO'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'FUGA EN LA VALVULA');
    await tester.pumpAndSettle();
    expect(find.text('Obligatoria porque la respuesta es NO'), findsNothing);
  });

  testWidgets('el control de mantenimiento arranca en NO y sin campos',
      (tester) async {
    await _abrir(tester);

    await tester.tap(find.text('Control de mantenimiento'));
    await tester.pumpAndSettle();

    // Sin historial cada tarea lo dice, y no hay nada que llenar hasta que
    // se marque que SI se hizo.
    expect(find.text('Sin registro previo'), findsNWidgets(4));
    expect(find.widgetWithText(TextField, 'Fecha'), findsNothing);
    expect(find.widgetWithText(TextField, 'Horas del equipo'), findsNothing);
    // Y no reclama nada: las tareas en NO son opcionales, como en el papel.
    expect(find.text('Faltan $base datos por llenar'), findsOneWidget);
  });

  testWidgets('marcar SI abre fecha y horas, ya propuestas', (tester) async {
    await _abrir(tester);

    // El horometro de la jornada, que es el que se propone.
    await tester.enterText(
        find.widgetWithText(TextField, 'Numero de horas'), '1200');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control de mantenimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SÍ').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Fecha'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Horas del equipo'), findsOneWidget);
    expect(_textoDe(tester, 'Fecha'), _hoyDdMmAaaa());
    expect(_textoDe(tester, 'Horas del equipo'), '1200');

    // Volver a NO cierra los campos sin borrar lo escrito.
    await tester.tap(find.text('NO').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Fecha'), findsNothing);
  });

  testWidgets('la fecha se elige en el calendario, no se teclea',
      (tester) async {
    await _abrir(tester);

    await tester.tap(find.text('Control de mantenimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SÍ').first);
    await tester.pumpAndSettle();

    // El campo es de solo lectura: al tocarlo abre el calendario.
    final campo =
        tester.widget<TextField>(find.byKey(const Key('mtto-fecha-0')));
    expect(campo.readOnly, isTrue,
        reason: 'escrita a mano entraba hasta una hora como "11PM"');

    await tester.tap(find.byKey(const Key('mtto-fecha-0')));
    await tester.pumpAndSettle();
    expect(find.text('Fecha del mantenimiento'), findsOneWidget);

    // Cancelar deja la fecha propuesta intacta.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(_textoDe(tester, 'Fecha'), _hoyDdMmAaaa());
  });

  testWidgets('marcar SI sin horas: el pie lo reclama', (tester) async {
    await _abrir(tester);

    await tester.tap(find.text('Control de mantenimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SÍ').first);
    await tester.pumpAndSettle();

    // Sin horometro en la cabecera las horas quedan vacias y falta ese dato:
    // decir que se hizo y no anotar con que horometro no sirve de nada.
    expect(_textoDe(tester, 'Horas del equipo'), isEmpty);
    expect(find.text('Faltan ${base + 1} datos por llenar'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Horas del equipo'), '3450');
    await tester.pumpAndSettle();
    expect(find.text('Faltan $base datos por llenar'), findsOneWidget);
  });
}
