import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:scv_ptbg/widgets/fecha_medicion.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(FechaHoraMedicion valor) => MaterialApp(
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SelectorFechaMedicion(valor: valor)),
    );

void main() {
  test('elegida hoy a las 00:00 en punto: fecha de hoy y hora de medianoche',
      () {
    // El limite inferior del dia: una medicion retro-fechada a la medianoche
    // exacta de hoy sigue siendo "hoy" y la hora sale con los tres ceros.
    final ahora = DateTime.now();
    final medianoche = DateTime(ahora.year, ahora.month, ahora.day);
    final valor = FechaHoraMedicion()..elegida = medianoche;
    expect(valor.manual, isTrue);
    expect(valor.fecha, DateFormat('yyyy-MM-dd').format(ahora));
    expect(valor.hora, '00:00:00');
  });

  test('registrarSiManual sin base de datos disponible NO lanza', () async {
    // En las pruebas no hay SQLite: DbHelper truena por dentro al abrir la
    // base. La promesa del metodo es que un tropiezo anotando la bitacora
    // jamas rompe la pantalla despues de un guardado exitoso.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'rol': 'admin'});
    final valor = FechaHoraMedicion()..elegida = DateTime(2026, 8, 30, 14, 30);
    await expectLater(
      valor.registrarSiManual(
        servicio: 'VIBRACIONES',
        localizacion: 57,
        uuid: 'uuid-prueba',
      ),
      completes,
    );
  });

  test('registrarSiManual con fecha automatica no toca la base y completa',
      () async {
    // Sin fecha manual no hay nada que anotar: debe salir de inmediato aun
    // si la base no existe (ni siquiera debe intentar abrirla).
    final valor = FechaHoraMedicion();
    await expectLater(
      valor.registrarSiManual(
        servicio: 'VIBRACIONES',
        localizacion: 57,
        uuid: 'uuid-prueba',
      ),
      completes,
    );
  });

  test('por defecto estampa el momento del guardado', () {
    final valor = FechaHoraMedicion();
    expect(valor.manual, isFalse);
    expect(valor.fecha, DateFormat('yyyy-MM-dd').format(DateTime.now()));
  });

  test('con fecha elegida estampa exactamente esa fecha y hora', () {
    final valor = FechaHoraMedicion()
      ..elegida = DateTime(2026, 8, 30, 14, 30);
    expect(valor.manual, isTrue);
    expect(valor.fecha, '2026-08-30');
    expect(valor.hora, '14:30:00');
  });

  testWidgets('el mecánico no ve el selector: retro-fechar es del admin',
      (tester) async {
    SharedPreferences.setMockInitialValues({'rol': 'mecanico'});
    await tester.pumpWidget(_app(FechaHoraMedicion()));
    await tester.pumpAndSettle();
    expect(find.text('Se guardará con la fecha y hora actual'), findsNothing);
    expect(find.byKey(const Key('fecha-medicion-cambiar')), findsNothing);
  });

  testWidgets('admin: elegir fecha y hora desde los pickers y volver a "ahora"',
      (tester) async {
    SharedPreferences.setMockInitialValues({'rol': 'admin'});
    final valor = FechaHoraMedicion();
    await tester.pumpWidget(_app(valor));
    await tester.pumpAndSettle();
    expect(find.text('Se guardará con la fecha y hora actual'), findsOneWidget);

    // Abre el picker de fecha (queda en hoy) y luego el de hora.
    await tester.tap(find.byKey(const Key('fecha-medicion-cambiar')));
    await tester.pumpAndSettle();
    expect(find.text('Fecha en que se hizo la medición'), findsOneWidget);
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    expect(find.text('Hora en que se hizo la medición'), findsOneWidget);
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();

    expect(valor.manual, isTrue);
    expect(find.textContaining('Hecha el'), findsOneWidget);

    // La equis regresa al comportamiento normal: la hora del guardado.
    await tester.tap(find.byKey(const Key('fecha-medicion-reset')));
    await tester.pumpAndSettle();
    expect(valor.manual, isFalse);
    expect(find.text('Se guardará con la fecha y hora actual'), findsOneWidget);
  });
}
