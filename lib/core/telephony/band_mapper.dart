/// Преобразование ARFCN → номер диапазона (band) для LTE / NR / UMTS.
///
/// Внимание: в NR-ARFCN диапазоны n38/n40/n41/n7 частично пересекаются,
/// точный band без данных от модема определить нельзя — для таких случаев
/// используется приближение (первый совпавший диапазон таблицы).
class BandMapper {
  static int? bandFor({
    required String technology,
    int? earfcn,
    int? nrarfcn,
    int? uarfcn,
    int? arfcn,
  }) {
    switch (technology) {
      case 'LTE':
        final v = earfcn;
        return v == null ? null : _lookup(_lteBands, v);
      case 'NR':
        final v = nrarfcn;
        return v == null ? null : _lookup(_nrBands, v);
      case 'UMTS':
        final v = uarfcn;
        return v == null ? null : _lookup(_umtsBands, v);
      default:
        // GSM: однозначного маппинга ARFCN→band нет (зависит от региона)
        return null;
    }
  }

  static int? _lookup(List<(int, int, int)> table, int value) {
    for (final (band, from, to) in table) {
      if (value >= from && value <= to) return band;
    }
    return null;
  }

  // (band, earfcnFrom, earfcnTo) — DL EARFCN диапазоны
  static const _lteBands = <(int, int, int)>[
    (1, 0, 599),
    (2, 600, 1199),
    (3, 1200, 1949),
    (4, 1950, 2399),
    (5, 2400, 2649),
    (7, 2750, 3449),
    (8, 3450, 3799),
    (12, 5010, 5179),
    (13, 5180, 5279),
    (17, 5730, 5849),
    (20, 6150, 6449),
    (25, 8040, 8689),
    (26, 8690, 9039),
    (28, 9210, 9659),
    (38, 37750, 38249),
    (39, 38250, 38649),
    (40, 38650, 39649),
    (41, 39650, 41589),
    (66, 66436, 67335),
  ];

  // (band, nrarfcnFrom, nrarfcnTo) — глобальный растр NR-ARFCN
  static const _nrBands = <(int, int, int)>[
    (78, 620000, 653333),
    (1, 422000, 434000),
    (3, 361000, 376000),
    (8, 185000, 192000),
    (28, 151600, 160600),
    (20, 158200, 164200),
    (38, 514000, 524000),
    (7, 524000, 538000),
    (41, 499200, 537999),
    (40, 496000, 598000),
  ];

  // (band, uarfcnFrom, uarfcnTo) — DL UARFCN
  static const _umtsBands = <(int, int, int)>[
    (1, 10562, 10838),
    (2, 9262, 9538),
    (5, 4132, 4233),
    (8, 2937, 3088),
  ];
}
