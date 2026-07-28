import 'package:flutter_test/flutter_test.dart';

import 'package:rds_phorestal/main.dart';

void main() {
  testWidgets('App inicia sem erros', (WidgetTester tester) async {
    await tester.pumpWidget(const RdsPhorestalApp());
    await tester.pump();
  });
}
