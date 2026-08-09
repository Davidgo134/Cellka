import 'package:cellka/core/telephony/band_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BandMapper LTE', () {
    test('B3 (1800 МГц)', () {
      expect(BandMapper.bandFor(technology: 'LTE', earfcn: 1800), 3);
    });
    test('B7 (2600 МГц)', () {
      expect(BandMapper.bandFor(technology: 'LTE', earfcn: 3100), 7);
    });
    test('B20 (800 МГц)', () {
      expect(BandMapper.bandFor(technology: 'LTE', earfcn: 6300), 20);
    });
    test('B40 (TDD 2300)', () {
      expect(BandMapper.bandFor(technology: 'LTE', earfcn: 39000), 40);
    });
    test('неизвестный EARFCN → null', () {
      expect(BandMapper.bandFor(technology: 'LTE', earfcn: 999999), isNull);
    });
    test('null EARFCN → null', () {
      expect(BandMapper.bandFor(technology: 'LTE'), isNull);
    });
  });

  group('BandMapper NR', () {
    test('n78 (3.5 ГГц)', () {
      expect(BandMapper.bandFor(technology: 'NR', nrarfcn: 632000), 78);
    });
    test('null NRARFCN → null', () {
      expect(BandMapper.bandFor(technology: 'NR'), isNull);
    });
  });

  group('BandMapper UMTS', () {
    test('B1 (2100 МГц)', () {
      expect(BandMapper.bandFor(technology: 'UMTS', uarfcn: 10700), 1);
    });
    test('B8 (900 МГц)', () {
      expect(BandMapper.bandFor(technology: 'UMTS', uarfcn: 3000), 8);
    });
  });

  group('BandMapper прочее', () {
    test('GSM не маппится → null', () {
      expect(BandMapper.bandFor(technology: 'GSM', arfcn: 800), isNull);
    });
    test('неизвестная технология → null', () {
      expect(BandMapper.bandFor(technology: 'UNKNOWN'), isNull);
    });
  });
}
