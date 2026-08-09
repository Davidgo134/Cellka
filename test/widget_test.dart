import 'package:flutter_test/flutter_test.dart';
import 'package:cellka/main.dart';

void main() {
  testWidgets('CellkaApp builds and shows title', (tester) async {
    await tester.pumpWidget(const CellkaApp());
    expect(find.text('Cellka'), findsOneWidget);
  });
}
