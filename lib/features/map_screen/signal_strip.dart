import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';

/// Формат заголовка: «LTE B7 · PCI 142 · -87 dBm».
String formatCellTitle(CellInfo? cell) {
  if (cell == null) return 'Нет данных о соте';
  final head =
      cell.band != null ? '${cell.technology} B${cell.band}' : cell.technology;
  final parts = <String>[head];
  if (cell.pci != null) parts.add('PCI ${cell.pci}');
  final dbm = cell.rsrp ?? cell.dbm;
  if (dbm != null) parts.add('$dbm dBm');
  return parts.join(' · ');
}

/// Формат подзаголовка: «250-01 · TAC 12345 · CI 987654».
String formatCellSubtitle(CellInfo? cell) {
  if (cell == null) return 'Ожидание данных от модема…';
  final parts = <String>[];
  if (cell.mcc != null && cell.mnc != null) {
    parts.add('${cell.mcc}-${cell.mnc.toString().padLeft(2, '0')}');
  }
  if (cell.tac != null) parts.add('TAC ${cell.tac}');
  if (cell.lac != null) parts.add('LAC ${cell.lac}');
  if (cell.ci != null) parts.add('CI ${cell.ci}');
  if (cell.nci != null) parts.add('NCI ${cell.nci}');
  return parts.isEmpty ? cell.technology : parts.join(' · ');
}

/// Цвет уровня сигнала по RSRP (пороги из DESIGN.md).
Color signalColor(int? rsrp) {
  if (rsrp == null) return Colors.grey;
  if (rsrp >= -80) return Colors.greenAccent;
  if (rsrp >= -100) return Colors.amber;
  return Colors.redAccent;
}

/// Нижняя панель с параметрами текущей обслуживающей соты.
class SignalStrip extends StatelessWidget {
  final CellInfo? cell;
  final int cellCount;
  final bool permissionsGranted;
  final VoidCallback? onRequestPermissions;

  const SignalStrip({
    super.key,
    this.cell,
    this.cellCount = 0,
    this.permissionsGranted = true,
    this.onRequestPermissions,
  });

  @override
  Widget build(BuildContext context) {
    if (!permissionsGranted) {
      return _StripContainer(
        child: InkWell(
          onTap: onRequestPermissions,
          child: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Нет разрешений на геолокацию/телефон. Нажмите, чтобы выдать.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dbm = cell?.rsrp ?? cell?.dbm;

    return _StripContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatCellTitle(cell),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                dbm != null ? '$dbm' : '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: signalColor(cell?.rsrp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${formatCellSubtitle(cell)} · сот: $cellCount',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _StripContainer extends StatelessWidget {
  final Widget child;

  const _StripContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }
}
