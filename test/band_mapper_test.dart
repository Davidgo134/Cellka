import 'package:flutter_test/flutter_test.dart';

import 'package:cellka/core/telephony/band_mapper.dart';

void main() {
  group('BandMapper.bandFor LTE (EARFCN)', () {
    test('band 1', () => expect(BandMapper.bandFor('LTE', 300), 1));
    test('band 3', () => expect(BandMapper.bandFor('LTE', 1602), 3));
    test('band 7', () => expect(BandMapper.bandFor('LTE', 3000), 7));
    test('band 8', () => expect(BandMapper.bandFor('LTE', 3600), 8));
    test('band 20', () => expect(BandMapper.bandFor('LTE', 6300), 20));
    test('band 38 TDD', () => expect(BandMapper.bandFor('LTE', 38000), 38));
    test('band 40 TDD', () => expect(BandMapper.bandFor('LTE', 38752), 40));
    test('unknown', () => expect(BandMapper.bandFor('LTE', 999999), isNull));
    test('null', () => expect(BandMapper.bandFor('LTE', null), isNull));
  });

  group('BandMapper.bandFor прочие технологии', () {
    test('NR n78', () => expect(BandMapper.bandFor('NR', 630000), 78));
    test('WCDMA B1', () => expect(BandMapper.bandFor('WCDMA', 10700), 1));
    test('WCDMA B8', () => expect(BandMapper.bandFor('WCDMA', 3000), 8));
    test('GSM 900', () => expect(BandMapper.bandFor('GSM', 100), 900));
    test('GSM 1800', () => expect(BandMapper.bandFor('GSM', 700), 1800));
  });

  group('BandMapper частоты и дуплекс', () {
    test('RX band 40 TDD', () {
      expect(BandMapper.rxFreqMhz(38752), closeTo(2310.2, 0.01));
      expect(BandMapper.txFreqMhz(38752), closeTo(2310.2, 0.01));
      expect(BandMapper.duplexForBand(40), 'TDD');
    });
    test('RX/TX band 3 FDD', () {
      expect(BandMapper.rxFreqMhz(1602), closeTo(1845.2, 0.01));
      expect(BandMapper.txFreqMhz(1602), closeTo(1750.2, 0.01));
      expect(BandMapper.duplexForBand(3), 'FDD');
    });
  });
}
