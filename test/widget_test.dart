import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_claw/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterClawApp());
    await tester.pump();
  });
}
