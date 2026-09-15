import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/widgets/editor_servicio.dart';

/// Abre el editor y devuelve lo que entregó al guardar.
Future<EdicionServicio?> _abrir(
  WidgetTester tester, {
  required List<PuntoServicio> puntos,
  String observaciones = '',
  String responsable = '',
  String cargo = '',
  int? odt,
}) async {
  EdicionServicio? resultado;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await editarServicio(
              context,
              icono: Icons.vibration_rounded,
              titulo: 'Vibración LOC-2',
              subtitulo: 'NOX-LIQUIDO · 2026-08-25 09:00',
              unidad: 'mm/s',
              puntos: puntos,
              observaciones: observaciones,
              responsable: responsable,
              cargo: cargo,
              odt: odt,
              fecha: '2026-08-25',
              hora: '09:00:00',
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

List<PuntoServicio> get _unPunto => const [
      PuntoServicio(
        nombre: 'Motor - lado libre',
        campos: [
          CampoServicio(clave: 'H1', etiqueta: 'Horizontal', valor: 4.33),
          CampoServicio(clave: 'V1', etiqueta: 'Vertical', valor: 3.13),
          CampoServicio(clave: 'A1', etiqueta: 'Axial', valor: null),
        ],
      ),
    ];

void main() {
  testWidgets('muestra el nombre real del punto, no "Punto 1"',
      (tester) async {
    // El tecnico que entra a corregir un numero tiene que saber cual de los
    // cuatro puntos del equipo esta tocando.
    await _abrir(tester, puntos: _unPunto);
    expect(find.text('Motor - lado libre'), findsOneWidget);
    expect(find.text('Horizontal'), findsOneWidget);
    expect(find.text('Vertical'), findsOneWidget);
    expect(find.text('Axial'), findsOneWidget);
  });

  testWidgets('trae los valores actuales cargados', (tester) async {
    await _abrir(tester, puntos: _unPunto);
    expect(find.text('4.33'), findsOneWidget);
    expect(find.text('3.13'), findsOneWidget);
  });

  testWidgets('deja corregir responsable, cargo y ODT', (tester) async {
    // Ninguno de los editores viejos permitia tocarlos: para arreglar un
    // nombre mal escrito habia que borrar el registro y volver a medir.
    await _abrir(
      tester,
      puntos: _unPunto,
      responsable: 'ALEXI AVILA',
      cargo: 'SUP.MECANICO',
      odt: 4521,
    );
    expect(find.text('ALEXI AVILA'), findsOneWidget);
    expect(find.text('SUP.MECANICO'), findsOneWidget);
    expect(find.text('4521'), findsOneWidget);
  });

  testWidgets('devuelve lo editado al guardar', (tester) async {
    EdicionServicio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await editarServicio(
                context,
                icono: Icons.vibration_rounded,
                titulo: 'Vibración LOC-2',
                subtitulo: '',
                unidad: 'mm/s',
                puntos: _unPunto,
                observaciones: '',
                responsable: '',
                cargo: '',
                odt: null,
                fecha: '2026-08-25',
                hora: '09:00:00',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '7.25');
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(resultado, isNotNull);
    expect(resultado!.valores['H1'], 7.25);
    // El que estaba vacio sigue vacio y no se convierte en cero: un cero es
    // una lectura, y "no medido" no lo es.
    expect(resultado!.valores['A1'], isNull);
  });

  testWidgets('acepta la coma como separador decimal', (tester) async {
    // El teclado numerico de la tablet ofrece coma. Antes `double.tryParse`
    // la rechazaba y la lectura se guardaba vacia, sin avisar de nada.
    EdicionServicio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await editarServicio(
                context,
                icono: Icons.thermostat_rounded,
                titulo: 'Temperatura LOC-2',
                subtitulo: '',
                unidad: '°C',
                puntos: const [
                  PuntoServicio(
                    nombre: 'Motor - lado libre',
                    campos: [
                      CampoServicio(
                          clave: 'T1', etiqueta: 'Temperatura', valor: null),
                    ],
                  ),
                ],
                observaciones: '',
                responsable: '',
                cargo: '',
                odt: null,
                fecha: '2026-08-25',
                hora: '09:00:00',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '62,5');
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(resultado!.valores['T1'], 62.5);
  });

  testWidgets('cancelar no devuelve nada', (tester) async {
    EdicionServicio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await editarServicio(
                context,
                icono: Icons.vibration_rounded,
                titulo: 'x',
                subtitulo: '',
                unidad: 'mm/s',
                puntos: _unPunto,
                observaciones: '',
                responsable: '',
                cargo: '',
                odt: null,
                fecha: '2026-08-25',
                hora: '09:00:00',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '99');
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNull);
  });

  testWidgets('un entero no se convierte en decimal al abrir', (tester) async {
    // Formatear siempre a dos decimales convertia un 5 en 5.00 con solo
    // abrir y guardar, y el historial mostraba una edicion que no hubo.
    await _abrir(tester, puntos: const [
      PuntoServicio(
        nombre: 'Motor - lado libre',
        campos: [
          CampoServicio(clave: 'T1', etiqueta: 'Temperatura', valor: 62),
        ],
      ),
    ]);
    expect(find.text('62'), findsOneWidget);
    expect(find.text('62.00'), findsNothing);
  });
}
