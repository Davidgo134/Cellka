import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/cell_info.dart';

/// Координаты базовой станции из OpenCelliD.
class TowerLocation {
  final double lat;
  final double lon;
  final int? rangeM;
  final int? samples;

  const TowerLocation({
    required this.lat,
    required this.lon,
    this.rangeM,
    this.samples,
  });
}

/// Статус поиска вышки — для явной диагностики на девайсе.
enum TowerLookupStatus {
  ok, // координаты найдены
  notFound, // соты нет в базе OpenCelliD
  noKey, // нет API-ключа (dart-define не передан)
  invalidKey, // 401 — ключ не принят
  forbidden, // 403 — ключ не в белом списке (нужно делиться замерами)
  error, // сеть/таймаут/парсинг
}

class TowerResult {
  final TowerLookupStatus status;
  final TowerLocation? location;
  const TowerResult(this.status, [this.location]);
}

/// Поиск координат вышки по идентификаторам соты через OpenCelliD API.
/// Успешные результаты кэшируются в sqflite (таблица tower_cache),
/// чтобы не дёргать API при каждом handover и не сжигать дневной лимит.
class TowerService {
  /// Ключ передаётся через --dart-define=OPENCELLID_API_KEY=...
  /// и не коммитится в репозиторий.
  static const _apiKey =
      String.fromEnvironment('OPENCELLID_API_KEY', defaultValue: '');

  static const _host = 'opencellid.org';
  static const _timeout = Duration(seconds: 6);

  /// Наша технология → radio OpenCelliD (TD-SCDMA не поддерживается).
  static const _radioMap = {
    'GSM': 'GSM',
    'UMTS': 'UMTS',
    'LTE': 'LTE',
    'NR': 'NR',
    'CDMA': 'CDMA',
  };

  final HttpClient _http = HttpClient()..connectionTimeout = _timeout;

  bool get hasKey => _apiKey.isNotEmpty;

  String? _keyOf(CellInfo c) {
    final area = c.tac ?? c.lac;
    final id = c.ci ?? c.nci;
    if (c.mcc == null || c.mnc == null || area == null || id == null) {
      return null;
    }
    return '${c.mcc}-${c.mnc}-$area-$id';
  }

  Future<TowerResult> locate(CellInfo serving) async {
    final cellKey = _keyOf(serving);
    if (cellKey == null) return const TowerResult(TowerLookupStatus.notFound);

    final cached = await _fromCache(cellKey);
    if (cached != null) return TowerResult(TowerLookupStatus.ok, cached);
    if (!hasKey) return const TowerResult(TowerLookupStatus.noKey);

    final area = serving.tac ?? serving.lac;
    final id = serving.ci ?? serving.nci;
    try {
      final params = <String, String>{
        'key': _apiKey,
        'mcc': '${serving.mcc}',
        'mnc': '${serving.mnc}',
        'lac': '$area',
        'cellid': '$id',
        'format': 'json',
      };
      final radio = _radioMap[serving.technology];
      if (radio != null) params['radio'] = radio;

      final uri = Uri.https(_host, '/cell/get', params);
      final req = await _http.getUrl(uri).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode == 401) {
        return const TowerResult(TowerLookupStatus.invalidKey);
      }
      if (res.statusCode == 403) {
        return const TowerResult(TowerLookupStatus.forbidden);
      }
      if (res.statusCode != 200) {
        return const TowerResult(TowerLookupStatus.error);
      }
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body);
      if (json is! Map) return const TowerResult(TowerLookupStatus.error);
      // «Cell not found» приходит с HTTP 200 и полем error/code=1.
      if (json['error'] != null || json['code'] == 1) {
        return const TowerResult(TowerLookupStatus.notFound);
      }
      final lat = (json['lat'] as num?)?.toDouble();
      final lon = (json['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        return const TowerResult(TowerLookupStatus.notFound);
      }
      final loc = TowerLocation(
        lat: lat,
        lon: lon,
        rangeM: (json['range'] as num?)?.toInt(),
        samples: (json['samples'] as num?)?.toInt(),
      );
      await _toCache(cellKey, loc);
      return TowerResult(TowerLookupStatus.ok, loc);
    } catch (_) {
      return const TowerResult(TowerLookupStatus.error);
    }
  }

  Future<TowerLocation?> _fromCache(String cellKey) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'tower_cache',
      where: 'cell_key = ?',
      whereArgs: [cellKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return TowerLocation(
      lat: (r['lat'] as num).toDouble(),
      lon: (r['lon'] as num).toDouble(),
      rangeM: (r['range_m'] as num?)?.toInt(),
      samples: (r['samples'] as num?)?.toInt(),
    );
  }

  Future<void> _toCache(String cellKey, TowerLocation loc) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'tower_cache',
      {
        'cell_key': cellKey,
        'lat': loc.lat,
        'lon': loc.lon,
        'range_m': loc.rangeM,
        'samples': loc.samples,
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
