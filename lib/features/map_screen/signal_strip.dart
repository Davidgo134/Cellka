import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';
import 'cell_details_screen.dart';

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
/// Тап открывает [CellDetailsScreen].
class SignalStrip extends StatelessWidget {
  final CellInfo? cell;
  final List<CellInfo> allCells;
  final bool permissionsGranted;
  final VoidCallback? onRequestPermissions;
  final bool hasFix; // есть ли GPS-фикс
  final bool isRecording; // идёт ли запись трека

  const SignalStrip({
    super.key,
    this.cell,
    this.allCells = const [],
    this.permissionsGranted = true,
    this.onRequestPermissions,
    this.hasFix = false,
    this.isRecording = false,
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

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CellDetailsScreen(
            servingCell: cell,
            allCells: allCells,
          ),
        ),
      ),
      child: _StripContainer(
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
                _StatusIcons(hasFix: hasFix, isRecording: isRecording),
                const SizedBox(width: 8),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatCellSubtitle(cell)} · сот: ${allCells.length}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.white38,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Иконки статуса: GPS и запись.
class _StatusIcons extends StatelessWidget {
  final bool hasFix;
  final bool isRecording;

  const _StatusIcons({required this.hasFix, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.satellite_alt,
          size: 14,
          color: hasFix ? Colors.greenAccent : Colors.white24,
        ),
        if (isRecording) ...[
          const SizedBox(width: 6),
          const _RecordingDot(),
        ],
      ],
    );
  }
}

/// Мигающая красная точка записи.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
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
