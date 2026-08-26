import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';
import '../../core/telephony/band_mapper.dart';
import 'signal_strip.dart';

/// Экран деталей текущей соты + список соседних.
class CellDetailsScreen extends StatelessWidget {
  final CellInfo? cell;
  final List<CellInfo> allCells;

  const CellDetailsScreen({
    super.key,
    required this.cell,
    this.allCells = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = cell;
    final neighbors = allCells.where((e) => !e.registered).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Текущая сота')),
      body: c == null
          ? const Center(child: Text('Нет данных о соте'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(c),
                const SizedBox(height: 16),
                ..._identityRows(c),
                const SizedBox(height: 8),
                ..._radioRows(c),
                const SizedBox(height: 8),
                ..._signalRows(c),
                if (neighbors.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Соседние соты (${neighbors.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...neighbors.map(_neighborTile),
                ],
              ],
            ),
    );
  }

  Widget _header(CellInfo c) {
    final color = signalColor(c.rsrp);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.cell_tower, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.technology}'
                  '${c.operator != null ? ' · ${c.operator}' : ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${c.rsrp ?? '—'} dBm'
                  '${c.rsrq != null ? ' · RSRQ ${c.rsrq} dB' : ''}',
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _identityRows(CellInfo c) {
    final rows = <Widget>[
      _row('Оператор (PLMN)', '${c.mcc ?? '—'}-${c.mnc ?? '—'}'),
      _row('TAC / LAC', '${c.tac ?? c.lac ?? '—'}'),
      _row('Cell ID', '${c.ci ?? c.nci ?? '—'}'),
      if (c.eNbId != null) _row('eNodeB · сектор', '${c.eNbId}:${c.sectorId}'),
      _row('PCI', '${c.pci ?? '—'}'),
    ];
    return [_section('Идентификация'), ...rows];
  }

  List<Widget> _radioRows(CellInfo c) {
    final band = BandMapper.bandForEarfcn(c.earfcn);
    final rx = BandMapper.rxFreqMhz(c.earfcn);
    final tx = BandMapper.txFreqMhz(c.earfcn);
    final duplex = BandMapper.duplexForBand(band);
    final bw = c.bandwidth;
    return [
      _section('Радио'),
      _row('Диапазон', BandMapper.bandDisplay(band)),
      _row('EARFCN', '${c.earfcn ?? '—'}'),
      if (duplex != null) _row('Дуплекс', duplex),
      if (rx != null) _row('RX (downlink)', '${rx.toStringAsFixed(1)} МГц'),
      if (tx != null && duplex != 'TDD')
        _row('TX (uplink)', '${tx.toStringAsFixed(1)} МГц'),
      if (bw != null && bw > 0)
        _row('Ширина канала', '${(bw / 1000).toStringAsFixed(0)} МГц'),
    ];
  }

  List<Widget> _signalRows(CellInfo c) {
    return [
      _section('Сигнал'),
      _row('RSRP', '${c.rsrp ?? '—'} dBm'),
      _row('RSRQ', '${c.rsrq ?? '—'} dB'),
      if (c.rssi != null) _row('RSSI', '${c.rssi} dBm'),
      if (c.sinr != null) _row('SINR', '${c.sinr} dB'),
      if (c.ta != null) _row('Timing Advance', '${c.ta}'),
    ];
  }

  Widget _neighborTile(CellInfo n) {
    final color = signalColor(n.rsrp);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: color, radius: 6),
      title: Text(
        '${n.technology} · PCI ${n.pci ?? '—'}',
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        'Cell ID ${n.ci ?? n.nci ?? '—'}'
        '${n.earfcn != null ? ' · EARFCN ${n.earfcn}' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '${n.rsrp ?? '—'} dBm',
        style: TextStyle(fontSize: 13, color: color),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
