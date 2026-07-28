import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/widgets/alignment_reference_card.dart';

void main() {
  testWidgets('PUNTOS 1 muestra referencia MOTOR–BOMBA', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlignmentReferenceCard(puntos: 1),
        ),
      ),
    );

    expect(
      find.byKey(const Key('alignment-reference-motor-pump')),
      findsOneWidget,
    );
    expect(find.text('Referencia de alineación correcta'), findsOneWidget);
    expect(find.text('MOTOR'), findsOneWidget);
    expect(find.text('BOMBA'), findsOneWidget);
    expect(find.text('CAJA'), findsNothing);
  });

  testWidgets('PUNTOS 6 distingue los dos acoples', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlignmentReferenceCard(puntos: 6),
        ),
      ),
    );

    expect(
      find.byKey(const Key('alignment-reference-motor-gearbox-pump')),
      findsOneWidget,
    );
    expect(find.text('MOTOR'), findsOneWidget);
    expect(find.text('CAJA'), findsOneWidget);
    expect(find.text('BOMBA'), findsOneWidget);
    expect(find.text('Motor–Caja'), findsOneWidget);
    expect(find.text('Caja–Bomba'), findsOneWidget);
  });

  testWidgets('la referencia aclara que no calcula un diagnóstico', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlignmentReferenceCard(puntos: 9),
        ),
      ),
    );

    expect(
      find.text('Guía visual · no representa un diagnóstico calculado'),
      findsOneWidget,
    );
  });
}
