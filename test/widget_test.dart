import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/main.dart';

void main() {
  testWidgets('SCV-PTBG smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScvApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
  });
}
