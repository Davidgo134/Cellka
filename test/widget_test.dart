import 'package:cellka/core/models/cell_info.dart';
import 'package:cellka/features/map_screen/signal_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CellInfo _fakeCell() => CellInfo(
      technology: 'LTE',
      registered: true,
      mcc: 250,
      mnc: 1,
      tac: 12345,
      ci: 987654,
      pci: 142,
      band: 7,
      rsrp: -87,
      timestamp: DateTime(2026, 8, 9),
    );

void main() {
  group('Форматирование SignalStrip', () {
    test('formatCellTitle с полными данными', () {
      expect(formatCellTitle(_fakeCell()), 'LTE B7 · PCI 142 · -87 dBm');
    });

    test('formatCellTitle без соты', () {
      expect(formatCellTitle(null), 'Нет данных о соте');
    });

    test('formatCellSubtitle с полными данными', () {
      expect(formatCellSubtitle(_fakeCell()), '250-01 · TAC 12345 · CI 987654');
    });

    test('formatCellSubtitle без соты', () {
      expect(formatCellSubtitle(null), 'Ожидание данных от модема…');
    });

    test('signalColor по порогам RSRP', () {
      expect(signalColor(-70), Colors.greenAccent);
      expect(signalColor(-90), Colors.amber);
      expect(signalColor(-110), Colors.redAccent);
      expect(signalColor(null), Colors.grey);
    });
  });

  testWidgets('SignalStrip показывает обслуживающую соту', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SignalStrip(cell: _fakeCell(), cellCount: 5)),
      ),
    );
    expect(find.text('LTE B7 · PCI 142 · -87 dBm'), findsOneWidget);
    expect(find.text('250-01 · TAC 12345 · CI 987654 · сот: 5'), findsOneWidget);
  });

  testWidgets('SignalStrip предупреждает об отсутствии разрешений',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SignalStrip(permissionsGranted: false)),
      ),
    );
    expect(find.textContaining('Нет разрешений'), findsOneWidget);
  });
}
