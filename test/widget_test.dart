import 'package:cellka/core/models/cell_info.dart';
import 'package:cellka/features/map_screen/signal_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CellInfo _lte({
  bool registered = true,
  int? band = 7,
  int? pci = 142,
  int? rsrp = -87,
}) {
  return CellInfo(
    technology: 'LTE',
    registered: registered,
    mcc: 250,
    mnc: 1,
    tac: 12345,
    ci: 987654,
    pci: pci,
    earfcn: 3100,
    band: band,
    rsrp: rsrp,
    timestamp: DateTime(2026, 8, 25, 12),
  );
}

void main() {
  group('formatCellTitle', () {
    test('null → заглушка', () {
      expect(formatCellTitle(null), 'Нет данных о соте');
    });

    test('полная сота → технология, band, PCI, dBm', () {
      expect(formatCellTitle(_lte()), 'LTE B7 · PCI 142 · -87 dBm');
    });

    test('без band и PCI → только технология и dBm', () {
      expect(
        formatCellTitle(_lte(band: null, pci: null)),
        'LTE · -87 dBm',
      );
    });
  });

  group('formatCellSubtitle', () {
    test('null → ожидание', () {
      expect(formatCellSubtitle(null), 'Ожидание данных от модема…');
    });

    test('MCC-MNC с padLeft, TAC и CI', () {
      expect(formatCellSubtitle(_lte()), '250-01 · TAC 12345 · CI 987654');
    });
  });

  group('signalColor', () {
    test('пороги RSRP', () {
      expect(signalColor(null), Colors.grey);
      expect(signalColor(-70), Colors.greenAccent);
      expect(signalColor(-80), Colors.greenAccent);
      expect(signalColor(-90), Colors.amber);
      expect(signalColor(-100), Colors.amber);
      expect(signalColor(-110), Colors.redAccent);
    });
  });

  group('SignalStrip widget', () {
    testWidgets('без разрешений → предупреждение', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalStrip(permissionsGranted: false),
          ),
        ),
      );
      expect(find.textContaining('Нет разрешений'), findsOneWidget);
    });

    testWidgets('с данными → заголовок и счётчик сот', (tester) async {
      final cells = [_lte(), _lte(registered: false, pci: 143)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalStrip(cell: cells.first, allCells: cells),
          ),
        ),
      );
      expect(find.text('LTE B7 · PCI 142 · -87 dBm'), findsOneWidget);
      expect(find.textContaining('сот: 2'), findsOneWidget);
    });
  });
}
