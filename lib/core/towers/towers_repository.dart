import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// Вышка из справочника OpenCelliD (bulk-дамп).
class Tower {
  final String radio;
  final int mnc;
  final int area; // TAC (LTE/NR) или LAC
  final int cell; // Cell ID
  final double lat;
  final double lon;
  final int? range;
  final int? samples;
  final int? updated; // unix-секунды последнего наблюдения в OpenCelliD
  final int? changeable; // 1 — позиция вычислена из замеров

  const Tower({
    required this.radio,
    required this.mnc,
    required this.area,
    required this.cell,
    required this.lat,
    required this.lon,
    this.range,
    this.samples,
    this.updated,
    this.changeable,
  });
}

/// Операторы РФ для фильтра слоя вышек.
class RuOperator {
  final int mnc;
  final String name;
  final Color color;
  const RuOperator(this.mnc, this.name, this.color);
}

const kRuOperators = <RuOperator>[
  RuOperator(1, 'МТС', Colors.redAccent),
  RuOperator(2, 'МегаФон', Colors.green),
  RuOperator(20, 'T2', Colors.deepPurpleAccent),
  RuOperator(99, 'билайн', Colors.amber),
  RuOperator(11, 'Yota', Colors.cyan),
  RuOperator(15, 'Ростелеком', Colors.indigoAccent),
];

/// Цвет маркера вышки по MNC оператора.
Color colorForMnc(int? mnc) {
  for (final op in kRuOperators) {
    if (op.mnc == mnc) return op.color;
  }
  return Colors.grey;
}

/// Имя оператора по MNC (РФ).
String operatorNameForMnc(int? mnc) {
  for (final op in kRuOperators) {
    if (op.mnc == mnc) return op.name;
  }
  return mnc != null ? 'MNC $mnc' : '—';
}

/// Доступ к локальному справочнику вышек.
class TowersRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<int> count() async {
    final db = await _db;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM towers');
    return (r.first['c'] as num).toInt();
  }

  /// Вышки в видимой области. Пустой [mncs] — все операторы.
  Future<List<Tower>> inBbox({
    required double southLat,
    required double northLat,
    required double westLon,
    required double eastLon,
    Set<int>? mncs,
    int limit = 600,
  }) async {
    final db = await _db;
    final where = StringBuffer('lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?');
    final args = <Object?>[southLat, northLat, westLon, eastLon];
    if (mncs != null && mncs.isNotEmpty) {
      where.write(' AND mnc IN (${List.filled(mncs.length, '?').join(',')})');
      args.addAll(mncs);
    }
    final rows = await db.query(
      'towers',
      columns: [
        'radio', 'mnc', 'area', 'cell', 'lat', 'lon',
        'range', 'samples', 'updated', 'changeable',
      ],
      where: where.toString(),
      whereArgs: args,
      orderBy: 'samples DESC',
      limit: limit,
    );
    return rows
        .map(
          (r) => Tower(
            radio: r['radio'] as String,
            mnc: (r['mnc'] as num).toInt(),
            area: (r['area'] as num).toInt(),
            cell: (r['cell'] as num).toInt(),
            lat: (r['lat'] as num).toDouble(),
            lon: (r['lon'] as num).toDouble(),
            range: (r['range'] as num?)?.toInt(),
            samples: (r['samples'] as num?)?.toInt(),
            updated: (r['updated'] as num?)?.toInt(),
            changeable: (r['changeable'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  /// Batch-вставка строк дампа одной транзакцией.
  Future<void> insertBatch(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'towers',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clear() async {
    final db = await _db;
    await db.delete('towers');
  }
}
