import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';
import '../../core/telephony/band_mapper.dart';
import 'cell_details_screen.dart';

/// Цвет уровня сигнала RSRP: зелёный хорошо, красный плохо.
Color signalColor(int? rsrp) {
  if (rsrp == null) return Colors.grey;
  if (rsrp >= -80) return Colors.greenAccent;
  if (rsrp >= -90) return Colors.lightGreen;
  if (rsrp >= -100) return Colors.amber;
  if (rsrp >= -110) return Colors.orange;
  return Colors.redAccent;
}

/// Нижняя панель главного экрана: текущая сота + статусы GPS/записи.
class SignalStrip extends StatelessWidget {
  final CellInfo? cell;
  final List<CellInfo> allCells;
  final bool permissionsGranted;
  final VoidCallback onRequestPermissions;
  final bool hasFix;
  final bool isRecording;

  const SignalStrip({
    super.key,
    required this.cell,
    required this.allCells,
    required this.permissionsGranted,
    required this.onRequestPermissions,
    required this.hasFix,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    if (!permissionsGranted) {
      return _shell(
        onTap: onRequestPermissions,
        child: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Нужны разрешения: геолокация и телефон',
                style: TextStyle(fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      );
    }

    final c = cell;
    final color = signalColor(c?.rsrp);

    return _shell(
      onTap: c == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CellDetailsScreen(cell: c, allCells: allCells),
                ),
              ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color, radius: 7),
          const SizedBox(width: 10),
          Expanded(
            child: c == null
                ? const Text('Нет данных о соте',
                    style: TextStyle(fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${c.technology}'
                        '${c.band != null ? ' ${BandMapper.bandLabel(c.band)}' : ''}'
                        '${c.operator != null ? ' · ${c.operator}' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'PCI ${c.pci ?? c.psc ?? '—'} · '
                        '${c.rsrp ?? '—'} dBm',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
          ),
          Icon(
            Icons.gps_fixed,
            size: 16,
            color: hasFix ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          Icon(
            isRecording
                ? Icons.fiber_manual_record
                : Icons.fiber_manual_record_outlined,
            size: 16,
            color: isRecording ? Colors.redAccent : Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _shell({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: child,
        ),
      ),
    );
  }
}
