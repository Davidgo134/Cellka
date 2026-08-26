/// Маппинг канала → band, дуплекс и частоты.
/// LTE EARFCN — 3GPP TS 36.101; NR/WCDMA/GSM — основные бэнды РФ/Европы.
class BandMapper {
  const BandMapper._();

  static const _tddBands = {33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 48};

  /// LTE: [band, earfcnFrom, earfcnTo, dlLowMhz, ulLowMhz (0 для TDD)].
  static const List<List<num>> _lteBands = [
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

  /// NR: [n-band, nrarfcnFrom, nrarfcnTo].
  static const List<List<num>> _nrBands = [
    [1, 422000, 434000],
    [3, 361000, 376000],
    [7, 524000, 538000],
    [8, 185000, 192000],
    [20, 158200, 164200],
    [28, 151600, 160600],
    [40, 460000, 480000],
    [41, 499200, 537999],
    [78, 620000, 653333],
    [79, 693334, 733333],
  ];

  /// WCDMA: [band, uarfcnFrom, uarfcnTo].
  static const List<List<num>> _wcdmaBands = [
    [1, 10562, 10838],
    [2, 9662, 9938],
    [3, 1162, 1513],
    [5, 4357, 4458],
    [8, 2937, 3088],
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
    78: '3500 TDD',
    79: '4700 TDD',
    900: 'GSM 900',
    1800: 'GSM 1800',
  };

  /// Band по технологии и каналу. Для LTE — EARFCN, NR — NRARFCN,
  /// WCDMA — UARFCN, GSM — ARFCN (900/1800).
  static int? bandFor(String technology, int? channel) {
    if (channel == null) return null;
    switch (technology) {
      case 'NR':
        for (final r in _nrBands) {
          if (channel >= r[1] && channel <= r[2]) return r[0].toInt();
        }
        return null;
      case 'WCDMA':
        for (final r in _wcdmaBands) {
          if (channel >= r[1] && channel <= r[2]) return r[0].toInt();
        }
        return null;
      case 'GSM':
        if ((channel >= 1 && channel <= 124) ||
            (channel >= 975 && channel <= 1023)) {
          return 900;
        }
        if (channel >= 512 && channel <= 885) return 1800;
        return null;
      default: // LTE и прочие
        return bandForEarfcn(channel);
    }
  }

  static List<num>? _lteRow(int? earfcn) {
    if (earfcn == null) return null;
    for (final r in _lteBands) {
      if (earfcn >= r[1] && earfcn <= r[2]) return r;
    }
    return null;
  }

  static int? bandForEarfcn(int? earfcn) => _lteRow(earfcn)?[0].toInt();

  /// TDD или FDD по номеру band (LTE-нумерация).
  static String? duplexForBand(int? band) {
    if (band == null) return null;
    return _tddBands.contains(band) ? 'TDD' : 'FDD';
  }

  /// Частота downlink, МГц: FDL = FDL_low + 0.1·(EARFCN − NOffsDL).
  static double? rxFreqMhz(int? earfcn) {
    final r = _lteRow(earfcn);
    if (r == null) return null;
    return r[3] + 0.1 * (earfcn! - r[1]);
  }

  /// Частота uplink, МГц. Для TDD совпадает с downlink.
  static double? txFreqMhz(int? earfcn) {
    final r = _lteRow(earfcn);
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
