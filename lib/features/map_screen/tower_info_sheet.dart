import 'package:flutter/material.dart';

import '../../core/towers/towers_repository.dart';

/// Карточка вышки по тапу — аналог Tower Info у CellMapper,
/// с полями, которые реально есть в дампе OpenCelliD.
class TowerInfoSheet extends StatelessWidget {
  final Tower tower;
  final VoidCallback onGoTo;

  const TowerInfoSheet({super.key, required this.tower, required this.onGoTo});

  @override
  Widget build(BuildContext context) {
    final color = colorForMnc(tower.mnc);
    final opName = operatorNameForMnc(tower.mnc);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$opName · ${tower.radio}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('MCC / MNC / TAC', '250 / ${tower.mnc} / ${tower.area}'),
            _row('Cell ID', '${tower.cell}'),
            if (tower.range != null)
              _row('Радиус соты (оценка)', '${tower.range} м'),
            if (tower.samples != null)
              _row('Замеров в OpenCelliD', '${tower.samples}'),
            if (tower.updated != null) _row('Обновлена', _fmtDate(tower.updated!)),
            if (tower.changeable == 1)
              _row('Позиция', 'вычислена из замеров'),
            _row(
              'Координаты',
              '${tower.lat.toStringAsFixed(5)}, ${tower.lon.toStringAsFixed(5)}',
            ),
            const SizedBox(height: 10),
            const Text(
              'Band и частоты появятся из собственных замеров — '
              'в дампе OpenCelliD их нет.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onGoTo,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('К вышке'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(int unixSeconds) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
