import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../db/app_database.dart';
import '../models/cell_info.dart';

/// Оценка позиции вышки по нашим собственным замерам.
class CellEstimate {
  final double lat;
  final double lon;
  final int samples;
  final double weight;

  const CellEstimate({
    required this.lat,
    required this.lon,
    required this.samples,
    required this.weight,
  });
}

/// Взвешенный центроид наблюдений соты — тот же принцип, что у
/// OpenCelliD/CellMapper (changeable=1 = позиция вычислена из замеров).
/// Вес точки: 10^(RSRP/10) — замеры рядом с вышкой доминируют.
class CellEstimator {
  CellEstimator._();
  static final CellEstimator instance = CellEstimator._();

  /// Точки с худшей GPS-точностью в оценку не берём.
  static const maxAccuracyM = 50.0;

  /// Минимум замеров, чтобы показывать оценку на карте.
  static const minSamplesToShow = 5;

  static String? keyOf(CellInfo c) {
    final area = c.tac ?? c.lac;
    final id = c.ci ?? c.nci;
    if (c.mcc == null || c.mnc == null || area == null || id == null) {
      return null;
    }
    return '${c.technology}:${c.mcc}-${c.mnc}:$area:$id';
  }

  /// Обновить оценку новой точкой. Вызывается при каждой сохранённой
  /// точке трека (уже после децимации записи).
  Future<void> update(CellInfo serving, Position pos) async {
    if (pos.accuracy > maxAccuracyM) return;
    final key = keyOf(serving);
    if (key == null) return;

    final w = serving.rsrp != null
        ? pow(10.0, serving.rsrp! / 10.0).toDouble()
        : 1.0;

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cell_estimates',
        where: 'cell_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('cell_estimates', {
          'cell_key': key,
          'lat': pos.latitude,
          'lon': pos.longitude,
          'weight': w,
          'samples': 1,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        final r = rows.first;
        final oldW = (r['weight'] as num).toDouble();
        final newW = oldW + w;
        final lat =
            (((r['lat'] as num).toDouble() * oldW) + pos.latitude * w) / newW;
        final lon =
            (((r['lon'] as num).toDouble() * oldW) + pos.longitude * w) / newW;
        await txn.update(
          'cell_estimates',
          {
            'lat': lat,
            'lon': lon,
            'weight': newW,
            'samples': (r['samples'] as num).toInt() + 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'cell_key = ?',
          whereArgs: [key],
        );
      }
    });
  }

  /// Оценка для показа на карте; null — данных мало.
  Future<CellEstimate?> estimate(String? key) async {
    if (key == null) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'cell_estimates',
      where: 'cell_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final samples = (r['samples'] as num).toInt();
    if (samples < minSamplesToShow) return null;
    return CellEstimate(
      lat: (r['lat'] as num).toDouble(),
      lon: (r['lon'] as num).toDouble(),
      samples: samples,
      weight: (r['weight'] as num).toDouble(),
    );
  }
}
