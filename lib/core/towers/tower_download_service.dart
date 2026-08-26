import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'towers_repository.dart';

/// Загрузка базы вышек России (MCC 250) и импорт в таблицу towers.
/// Источник 1 — наше зеркало в GitHub Release (обновляет CI, без лимитов);
/// источник 2 (фолбэк) — OpenCelliD напрямую (лимит 2 скачивания/сутки).
/// Данные © OpenCelliD contributors, CC BY-SA 4.0.
///
/// Формат CSV: radio,mcc,net,area,cell,unit,lon,lat,range,samples,
/// changeable,created,updated,averageSignal
///
/// NB: файловый эндпоинт OpenCelliD — /ocid/downloads
/// (downloads.php отдаёт HTML-страницу, не файл).
class TowerDownloadService {
  static const _apiKey =
      String.fromEnvironment('OPENCELLID_API_KEY', defaultValue: '');
  static const _mirrorUrl =
      'https://github.com/Davidgo134/Cellka/releases/download/towers-db/250.csv.gz';
  static const _mccFile = '250.csv.gz';
  static const _batchSize = 1000;

  final TowersRepository _repo = TowersRepository();
  final HttpClient _http = HttpClient();

  bool get hasKey => _apiKey.isNotEmpty;

  /// Скачать и импортировать дамп. [onProgress] получает человекочитаемый
  /// статус. Ошибки — с понятным текстом для показа в UI.
  Future<int> downloadAndImport({
    void Function(String status)? onProgress,
  }) async {
    try {
      return await _importFrom(_mirrorUrl, onProgress: onProgress);
    } catch (e) {
      if (_apiKey.isEmpty) rethrow;
      onProgress?.call('Зеркало недоступно, пробую OpenCelliD…');
      final uri = Uri.https('opencellid.org', '/ocid/downloads', {
        'token': _apiKey,
        'type': 'mcc',
        'file': _mccFile,
      });
      return _importFrom(uri.toString(), onProgress: onProgress);
    }
  }

  Future<int> _importFrom(
    String url, {
    void Function(String status)? onProgress,
  }) async {
    final req = await _http.getUrl(Uri.parse(url));
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Cellka/0.1 (+github.com/Davidgo134/Cellka)',
    );
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException(
        'HTTP ${res.statusCode} при скачивании базы',
        uri: Uri.parse(url),
      );
    }

    var received = 0;
    var imported = 0;
    var checkedMagic = false;
    var batch = <Map<String, Object?>>[];
    var isHeader = true;

    final byteStream = res.map((chunk) {
      received += chunk.length;
      if (!checkedMagic) {
        checkedMagic = true;
        // gzip-сигнатура 1F 8B; иначе сервер вернул HTML/ошибку.
        if (chunk.length < 2 || chunk[0] != 0x1F || chunk[1] != 0x8B) {
          throw const FormatException(
            'Сервер вернул не gzip-файл (возможно, страницу ошибки)',
          );
        }
      }
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
