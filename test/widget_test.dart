import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cellka/core/models/cell_info.dart';
import 'package:cellka/features/map_screen/signal_strip.dart';

void main() {
  test('CellInfo: eNodeB/сектор из LTE CI', () {
    const cell = CellInfo(
      technology: 'LTE',
      registered: true,
      ci: 199158304,
      band: 40,
    );
    expect(cell.eNbId, 777962);
    expect(cell.sectorId, 32);
    expect(cell.technology, 'LTE');
  });

  testWidgets('SignalStrip показывает текущую соту', (tester) async {
    const cell = CellInfo(
      technology: 'LTE',
      registered: true,
      mcc: 250,
      mnc: 20,
      ci: 199158304,
      pci: 444,
      band: 40,
      rsrp: -102,
      operator: 't2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignalStrip(
            cell: cell,
            allCells: const [cell],
            permissionsGranted: true,
            onRequestPermissions: () {},
            hasFix: true,
            isRecording: false,
          ),
        ),
      ),
    );

    expect(find.textContaining('LTE'), findsWidgets);
    expect(find.textContaining('B40'), findsOneWidget);
    expect(find.textContaining('-102'), findsOneWidget);
  });
}
