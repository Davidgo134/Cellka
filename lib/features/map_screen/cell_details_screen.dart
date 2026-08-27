import 'package:flutter/material.dart';

import '../../core/models/cell_info.dart';
import '../../core/telephony/band_mapper.dart';
import 'signal_strip.dart';

/// Экран деталей текущей соты: сначала простым языком, потом параметры
/// с (i)-объяснениями, затем соседние соты.
class CellDetailsScreen extends StatelessWidget {
  final CellInfo? cell;
  final List<CellInfo> allCells;

  const CellDetailsScreen({
    super.key,
    required this.cell,
    this.allCells = const [],
  });

  /// Простые объяснения параметров для (i)-диалогов.
  static const _explains = {
    'plmn': 'MCC — код страны (250 — Россия), MNC — код оператора: '
        '20 — t2, 2 — МегаФон, 1 — МТС, 99 — Билайн.',
    'tac': 'Код зоны регистрации — район, в котором сеть «помнит» '
        'ваш телефон для входящих звонков.',
    'ci': 'Уникальный номер соты (сектора) в сети оператора.',
    'enb': 'Номер базовой станции и сектора её антенны. Один eNodeB — '
        'это обычно мачта с тремя секторами.',
    'pci': 'Короткий идентификатор соты (0–503), по нему телефон '
        'различает соты при переключении.',
    'band': 'Частотный диапазон. Низкие (700–900 МГц) бьют далеко и '
        'сквозь стены, высокие (2600+) — быстрее, но на меньшей дистанции.',
    'earfcn': 'Номер канала — точная частота внутри диапазона.',
    'duplex': 'TDD — приём и передача по очереди на одной частоте; '
        'FDD — одновременно на двух разных.',
    'rxtx': 'RX — частота, на которой телефон слушает вышку; '
        'TX — на которой отвечает ей.',
    'bw': 'Ширина канала в МГц: шире — выше скорость. '
        '20 МГц — максимум одного LTE-канала.',
    'rsrp': 'Уровень сигнала от вышки. До −80 dBm — отлично, '
        'около −100 — средне, ниже −110 — плохо.',
    'rsrq': 'Качество сигнала: насколько соседние вышки шумят в эфире. '
        '−10 dB и выше — хорошо.',
    'rssi': 'Общая мощность на частоте, включая шум и чужие сигналы.',
    'sinr': 'Соотношение сигнал/шум. Выше 20 dB — отлично, '
        'ниже 0 — помехи съедают скорость.',
    'ta': 'Timing Advance — примерная дальность до вышки: '
        '1 единица ≈ 78 метров.',
  };

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
                _summaryCard(context, c),
                const SizedBox(height: 16),
                ..._identityRows(context, c),
                const SizedBox(height: 8),
                ..._radioRows(context, c),
                const SizedBox(height: 8),
                ..._signalRows(context, c),
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

  // ─── Простым языком ─────────────────────────────────────────────────────

  /// Карточка-резюме: насколько всё хорошо и к чему мы подключены.
  Widget _summaryCard(BuildContext context, CellInfo c) {
    final color = signalColor(c.rsrp);
    final band = BandMapper.bandForEarfcn(c.earfcn);

    final lines = <String>[
      _signalVerdict(c.rsrp),
      'Вы на ${c.technology}-соте'
          '${band != null ? ' (Band $band, ${BandMapper.rxFreqMhz(c.earfcn)?.toStringAsFixed(0) ?? ''} МГц)' : ''}'
          '${c.operator != null ? ' оператора ${c.operator}' : ''}.',
      if (c.eNbId != null) 'Вышка: eNodeB ${c.eNbId}, сектор ${c.sectorId}.',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cell_tower, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              lines.join('\n'),
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _signalVerdict(int? rsrp) {
    if (rsrp == null) return 'Данных об уровне сигнала нет.';
    if (rsrp >= -80) return 'Сигнал отличный — всё будет летать.';
    if (rsrp >= -90) return 'Сигнал хороший — видео и звонки без проблем.';
    if (rsrp >= -100) {
      return 'Сигнал средний — мессенджеры ок, видео может подтормаживать.';
    }
    if (rsrp >= -110) {
      return 'Сигнал слабый — интернет медленный, возможны обрывы.';
    }
    return 'Сигнал очень слабый — связь на грани.';
  }

  // ─── Таблицы параметров ─────────────────────────────────────────────────

  List<Widget> _identityRows(BuildContext context, CellInfo c) {
    return [
      _section('Идентификация'),
      _row(context, 'Оператор (PLMN)', '${c.mcc ?? '—'}-${c.mnc ?? '—'}',
          explain: 'plmn'),
      _row(context, 'TAC / LAC', '${c.tac ?? c.lac ?? '—'}', explain: 'tac'),
      _row(context, 'Cell ID', '${c.ci ?? c.nci ?? '—'}', explain: 'ci'),
      if (c.eNbId != null)
        _row(context, 'eNodeB · сектор', '${c.eNbId}:${c.sectorId}',
            explain: 'enb'),
      _row(context, 'PCI', '${c.pci ?? '—'}', explain: 'pci'),
    ];
  }

  List<Widget> _radioRows(BuildContext context, CellInfo c) {
    final band = BandMapper.bandForEarfcn(c.earfcn);
    final rx = BandMapper.rxFreqMhz(c.earfcn);
    final tx = BandMapper.txFreqMhz(c.earfcn);
    final duplex = BandMapper.duplexForBand(band);
    final bw = c.bandwidth;
    return [
      _section('Радио'),
      _row(context, 'Диапазон', BandMapper.bandDisplay(band),
          explain: 'band'),
      _row(context, 'EARFCN', '${c.earfcn ?? '—'}', explain: 'earfcn'),
      if (duplex != null)
        _row(context, 'Дуплекс', duplex, explain: 'duplex'),
      if (rx != null)
        _row(context, 'RX (downlink)', '${rx.toStringAsFixed(1)} МГц',
            explain: 'rxtx'),
      if (tx != null && duplex != 'TDD')
        _row(context, 'TX (uplink)', '${tx.toStringAsFixed(1)} МГц',
            explain: 'rxtx'),
      if (bw != null && bw > 0)
        _row(context, 'Ширина канала',
            '${(bw / 1000).toStringAsFixed(0)} МГц',
            explain: 'bw'),
    ];
  }

  List<Widget> _signalRows(BuildContext context, CellInfo c) {
    return [
      _section('Сигнал'),
      _row(context, 'RSRP', '${c.rsrp ?? '—'} dBm', explain: 'rsrp'),
      _row(context, 'RSRQ', '${c.rsrq ?? '—'} dB', explain: 'rsrq'),
      if (c.rssi != null)
        _row(context, 'RSSI', '${c.rssi} dBm', explain: 'rssi'),
      if (c.sinr != null)
        _row(context, 'SINR', '${c.sinr} dB', explain: 'sinr'),
      if (c.ta != null)
        _row(context, 'Timing Advance', '${c.ta}',
            explain: 'ta'),
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

  Widget _row(BuildContext context, String label, String value,
      {String? explain}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                if (explain != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showExplain(context, label, explain),
                    child: const Icon(
                      Icons.info_outline,
                      size: 15,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showExplain(BuildContext context, String label, String key) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(_explains[key] ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}
