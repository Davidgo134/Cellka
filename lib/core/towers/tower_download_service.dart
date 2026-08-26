import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'towers_repository.dart';

/// Загрузка bulk-дампа OpenCelliD для России (MCC 250) и импорт
/// в локальную таблицу towers. Данные © OpenCelliD, CC BY-SA 4.0.
///
/// Формат CSV: radio,mcc,net,area,cell,unit,lon,lat,range,samples,
/// changeable,created,updated,averageSignal
class TowerDownloadService {
  static const _apiKey =
      String.fromEnvironment('OPENCELLID_API_KEY', defaultValue: '');
  static const _host = 'opencellid.org';
  static const _mccFile = '250.csv.gz';
  static const _batchSize = 1000;

  final TowersRepository _repo = TowersRepository();
  final HttpClient _http = HttpClient();

  bool get hasKey => _apiKey.isNotEmpty;

  /// Скачать и импортировать дамп. [onProgress] получает человекочитаемый
  /// статус («3,2 МБ…», «Импорт: 45 000…»). Возвращает число вышек.
  Future<int> downloadAndImport({
    void Function(String status)? onProgress,
  }) async {
    if (!hasKey) throw StateError('Нет ключа OpenCelliD');

    final uri = Uri.https(_host, '/downloads.php', {
      'token': _apiKey,
      'type': 'mcc',
      'file': _mccFile,
    });
    final req = await _http.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }

    var received = 0;
    var imported = 0;
    var batch = <Map<String, Object?>>[];
    var isHeader = true;

    final byteStream = res.map((chunk) {
      received += chunk.length;
      if (received % (512 * 1024) < 8192) {
        onProgress?.call(
          'Скачано ${(received / 1048576).toStringAsFixed(1)} МБ…',
        );
      }
      return chunk;
    });

    final lines = byteStream
        .transform(gzip.decoder)
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (isHeader) {
        isHeader = false;
        continue;
      }
      if (line.isEmpty) continue;
      final row = _parseRow(line);
      if (row == null) continue;
      batch.add(row);
      if (batch.length >= _batchSize) {
        await _repo.insertBatch(batch);
        imported += batch.length;
        batch = <Map<String, Object?>>[];
        onProgress?.call('Импорт: $imported вышек…');
      }
    }
    if (batch.isNotEmpty) {
      await _repo.insertBatch(batch);
      imported += batch.length;
    }
    onProgress?.call('Готово: $imported вышек');
    return imported;
  }

  Map<String, Object?>? _parseRow(String line) {
    final f = line.split(',');
    if (f.length < 14) return null;
    final lat = double.tryParse(f[7]);
    final lon = double.tryParse(f[6]);
    final mnc = int.tryParse(f[2]);
    if (lat == null || lon == null || mnc == null) return null;
    if (lat == 0 && lon == 0) return null;
    return {
      'radio': f[0],
      'mcc': int.tryParse(f[1]) ?? 250,
      'mnc': mnc,
      'area': int.tryParse(f[3]) ?? 0,
      'cell': int.tryParse(f[4]) ?? 0,
      'lon': lon,
      'lat': lat,
      'range': int.tryParse(f[8]),
      'samples': int.tryParse(f[9]),
      'changeable': int.tryParse(f[10]),
      'updated': int.tryParse(f[12]),
      'avg_signal': int.tryParse(f[13]),
    };
  }
}
