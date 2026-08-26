/// Маппинг EARFCN → LTE band, дуплекс и частоты (3GPP TS 36.101).
/// Покрывает бэнды, актуальные для РФ/Европы; неизвестные → null.
class BandMapper {
  const BandMapper._();

  static const _tddBands = {33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 48};

  /// band → [band, earfcnFrom, earfcnTo, dlLowMhz, ulLowMhz (0 для TDD)].
  static const List<List<num>> _bands = [
    [1, 0, 599, 2110, 1920],
    [2, 600, 1199, 1930, 1850],
    [3, 1200, 1949, 1805, 1710],
    [4, 1950, 2399, 2110, 1710],
    [5, 2400, 2649, 869, 824],
    [7, 2750, 3449, 2620, 2500],
    [8, 3450, 3799, 925, 880],
    [12, 5010, 5179, 729, 699],
    [17, 5730, 5849, 734, 704],
    [20, 6150, 6449, 791, 832],
    [25, 8040, 8689, 1930, 1850],
    [26, 8690, 9039, 859, 814],
    [28, 9210, 9659, 758, 703],
    [38, 37750, 38249, 2570, 0],
    [40, 38650, 39649, 2300, 0],
    [41, 39650, 41589, 2496, 0],
    [66, 66436, 67335, 2110, 1710],
  ];

  /// Частотные подписи диапазонов для UI.
  static const Map<int, String> _bandNames = {
    1: '2100',
    2: '1900',
    3: '1800',
    4: '1700/2100',
    5: '850',
    7: '2600',
    8: '900',
    12: '700',
    17: '700',
    20: '800',
    25: '1900',
    26: '850',
    28: '700',
    38: '2600 TDD',
    40: '2300 TDD',
    41: '2500 TDD',
    66: '1700/2100',
  };

  static List<num>? _row(int? earfcn) {
    if (earfcn == null) return null;
    for (final r in _bands) {
      if (earfcn >= r[1] && earfcn <= r[2]) return r;
    }
    return null;
  }

  static int? bandForEarfcn(int? earfcn) => _row(earfcn)?[0].toInt();

  /// TDD или FDD по номеру band.
  static String? duplexForBand(int? band) {
    if (band == null) return null;
    return _tddBands.contains(band) ? 'TDD' : 'FDD';
  }

  /// Частота downlink, МГц: FDL = FDL_low + 0.1·(EARFCN − NOffsDL).
  static double? rxFreqMhz(int? earfcn) {
    final r = _row(earfcn);
    if (r == null) return null;
    return r[3] + 0.1 * (earfcn! - r[1]);
  }

  /// Частота uplink, МГц. Для TDD совпадает с downlink.
  static double? txFreqMhz(int? earfcn) {
    final r = _row(earfcn);
    if (r == null) return null;
    if (r[4] == 0) return rxFreqMhz(earfcn); // TDD
    return r[4] + 0.1 * (earfcn! - r[1]);
  }

  /// «B40» для компактных мест.
  static String bandLabel(int? band) => band == null ? '—' : 'B$band';

  /// «Band 40 · 2300 TDD МГц» для экрана деталей.
  static String bandDisplay(int? band) {
    if (band == null) return '—';
    final name = _bandNames[band];
    return name == null ? 'Band $band' : 'Band $band · $name МГц';
  }
}
