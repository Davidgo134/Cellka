import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';
import 'signal_strip.dart' show signalColor;

/// Экран подробной информации о текущей соте и списке соседних сот.
class CellDetailsScreen extends StatelessWidget {
  final CellInfo? servingCell;
  final List<CellInfo> allCells;

  const CellDetailsScreen({
    super.key,
    required this.servingCell,
    required this.allCells,
  });

  @override
  Widget build(BuildContext context) {
    final neighbors = allCells.where((c) => !c.registered).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D24),
        foregroundColor: Colors.white,
        title: const Text('Детали соты', style: TextStyle(fontSize: 16)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _SectionHeader('Обслуживающая сота'),
          if (servingCell == null)
            const _EmptyCard('Нет данных от модема')
          else ...[
            _VerdictCard(servingCell!),
            const SizedBox(height: 8),
            _CellParamsCard(servingCell!),
          ],
          const SizedBox(height: 16),
          _SectionHeader('Соседние соты (${neighbors.length})'),
          if (neighbors.isEmpty)
            const _EmptyCard('Данные о соседних сотах недоступны')
          else
            ...neighbors.map((c) => _NeighborCard(c)),
        ],
      ),
    );
  }
}

// ─── Verdict ────────────────────────────────────────────────────────────────

class _VerdictCard extends StatelessWidget {
  final CellInfo cell;
  const _VerdictCard(this.cell);

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict(cell);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: verdict.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: verdict.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(verdict.icon, color: verdict.color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.title,
                  style: TextStyle(
                    color: verdict.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  verdict.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictData {
  final String title;
  final String description;
  final Color color;
  final IconData icon;
  const _VerdictData(this.title, this.description, this.color, this.icon);
}

_VerdictData _verdict(CellInfo c) {
  final rsrp = c.rsrp;
  final rsrq = c.rsrq;
  final sinr = c.sinr;

  if (rsrp == null && c.dbm == null) {
    return const _VerdictData(
      'Нет данных',
      'Устройство не предоставило метрики сигнала.',
      Colors.grey,
      Icons.help_outline,
    );
  }

  final dbm = rsrp ?? c.dbm!;

  if (dbm >= -80) {
    final qualityIssue =
        (rsrq != null && rsrq < -12) || (sinr != null && sinr < 5);
    if (qualityIssue) {
      return const _VerdictData(
        'Сигнал сильный, качество низкое',
        'Уровень сигнала хороший, но помехи или высокая нагрузка на сектор снижают качество. Интернет может быть нестабильным.',
        Colors.amber,
        Icons.warning_amber,
      );
    }
    return const _VerdictData(
      'Отличный сигнал',
      'Уровень и качество сигнала в норме. Проблем с соединением не ожидается.',
      Colors.greenAccent,
      Icons.signal_cellular_alt,
    );
  } else if (dbm >= -95) {
    final qualityIssue =
        (rsrq != null && rsrq < -15) || (sinr != null && sinr < 0);
    if (qualityIssue) {
      return const _VerdictData(
        'Слабый сигнал и помехи',
        'Сигнал слабый и качество низкое. Возможны обрывы соединения.',
        Colors.deepOrange,
        Icons.signal_cellular_connected_no_internet_4_bar,
      );
    }
    return const _VerdictData(
      'Приемлемый сигнал',
      'Сигнал достаточен для звонков и передачи данных, но скорость может быть ниже максимальной.',
      Colors.amber,
      Icons.signal_cellular_alt_2_bar,
    );
  } else {
    return const _VerdictData(
      'Слабый сигнал',
      'Сигнал слабый. Попробуйте другую точку, ближе к окну или на улице. Возможны обрывы.',
      Colors.redAccent,
      Icons.signal_cellular_0_bar,
    );
  }
}

// ─── Params table ────────────────────────────────────────────────────────────

class _CellParamsCard extends StatelessWidget {
  final CellInfo cell;
  const _CellParamsCard(this.cell);

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows(cell);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _ParamRow(rows[i], alternate: i.isEven),
            if (i < rows.length - 1)
              const Divider(height: 1, color: Colors.white12),
          ],
        ],
      ),
    );
  }
}

List<_Param> _buildRows(CellInfo c) {
  String bw(int? hz) {
    if (hz == null) return '—';
    if (hz >= 1000000) return '${(hz / 1000000).toStringAsFixed(0)} МГц';
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(0)} кГц';
    return '$hz Гц';
  }

  String ts(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  return [
    _Param('Технология', c.technology),
    _Param(
      'Оператор',
      c.mcc != null && c.mnc != null
          ? '${c.mcc}-${c.mnc.toString().padLeft(2, '0')}'
          : null,
    ),
    _Param('Диапазон', c.band != null ? 'B${c.band}' : null),
    _Param('RSRP', c.rsrp != null ? '${c.rsrp} дБм' : null,
        valueColor: signalColor(c.rsrp)),
    _Param('RSRQ', c.rsrq != null ? '${c.rsrq} дБ' : null,
        valueColor: _rsrqColor(c.rsrq)),
    _Param('SINR', c.sinr != null ? '${c.sinr} дБ' : null,
        valueColor: _sinrColor(c.sinr)),
    _Param('RSSI', c.rssi != null ? '${c.rssi} дБм' : null),
    _Param('dBm (общий)', c.dbm != null ? '${c.dbm} дБм' : null),
    _Param('ASU', c.asu?.toString()),
    _Param('PCI', c.pci?.toString()),
    _Param('PSC (UMTS)', c.psc?.toString()),
    _Param('BSIC (GSM)', c.bsic?.toString()),
    _Param('Cell ID', c.ci?.toString()),
    _Param('NR Cell ID', c.nci?.toString()),
    _Param('TAC', c.tac?.toString()),
    _Param('LAC', c.lac?.toString()),
    _Param('EARFCN', c.earfcn?.toString()),
    _Param('NR-ARFCN', c.nrarfcn?.toString()),
    _Param('UARFCN', c.uarfcn?.toString()),
    _Param('ARFCN (GSM)', c.arfcn?.toString()),
    _Param('Ширина канала', bw(c.bandwidth)),
    _Param('Timing Advance', c.ta?.toString()),
    _Param('Обновлено', ts(c.timestamp)),
  ].where((p) => p.value != null && p.value != '—').toList();
}

Color _rsrqColor(int? v) {
  if (v == null) return Colors.grey;
  if (v >= -10) return Colors.greenAccent;
  if (v >= -15) return Colors.amber;
  return Colors.redAccent;
}

Color _sinrColor(int? v) {
  if (v == null) return Colors.grey;
  if (v >= 10) return Colors.greenAccent;
  if (v >= 0) return Colors.amber;
  return Colors.redAccent;
}

class _Param {
  final String label;
  final String? value;
  final Color? valueColor;
  const _Param(this.label, this.value, {this.valueColor});
}

class _ParamRow extends StatelessWidget {
  final _Param param;
  final bool alternate;
  const _ParamRow(this.param, {this.alternate = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color:
          alternate ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              param.label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              param.value ?? '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: param.valueColor ?? Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Neighbor cell card ───────────────────────────────────────────────────────

class _NeighborCard extends StatelessWidget {
  final CellInfo cell;
  const _NeighborCard(this.cell);

  @override
  Widget build(BuildContext context) {
    final dbm = cell.rsrp ?? cell.dbm;
    final color = signalColor(cell.rsrp);
    final subtitle = _neighborSubtitle(cell);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: EdgeInsets.zero,
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white38,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${cell.technology}'
                '${cell.band != null ? ' B${cell.band}' : ''}'
                '${cell.pci != null ? ' · PCI ${cell.pci}' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (dbm != null)
              Text(
                '$dbm dBm',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
          ],
        ),
        subtitle: subtitle.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 2, left: 18),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            : null,
        children: [
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _CellParamsCard(cell),
          ),
        ],
      ),
    );
  }
}

String _neighborSubtitle(CellInfo c) {
  final parts = <String>[];
  if (c.mcc != null && c.mnc != null) {
    parts.add('${c.mcc}-${c.mnc.toString().padLeft(2, '0')}');
  }
  if (c.tac != null) parts.add('TAC ${c.tac}');
  if (c.lac != null) parts.add('LAC ${c.lac}');
  if (c.ci != null) parts.add('CI ${c.ci}');
  return parts.join(' · ');
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}
