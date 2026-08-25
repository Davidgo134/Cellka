import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cell_info.dart';
import 'app_database.dart';

/// Сводка трека для списка History (Фаза 5).
class TrackSummary {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int pointCount;
  final double distanceM;
  final String? operator;

  const TrackSummary({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.pointCount,
    required this.distanceM,
    this.operator,
  });

  factory TrackSummary.fromRow(Map<String, Object?> row) => TrackSummary(
        id: row['id'] as String,
        startedAt: DateTime.parse(row['started_at'] as String),
        endedAt: row['ended_at'] != null
            ? DateTime.parse(row['ended_at'] as String)
            : null,
        pointCount: (row['point_count'] as num).toInt(),
        distanceM: (row['distance_m'] as num).toDouble(),
        operator: row['operator'] as String?,
      );
}

/// Доступ к локальной БД треков и измерений.
class TrackRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<void> createTrack(String id, DateTime startedAt) async {
    final db = await _db;
    await db.insert('tracks', {
      'id': id,
      'started_at': startedAt.toIso8601String(),
    });
  }

  Future<void> finishTrack(
    String id,
    DateTime endedAt,
    int pointCount,
    double distanceM,
    String? operator,
  ) async {
    final db = await _db;
    await db.update(
      'tracks',
      {
        'ended_at': endedAt.toIso8601String(),
        'point_count': pointCount,
        'distance_m': distanceM,
        'operator': operator,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Batch-insert измерений одной транзакцией.
  Future<void> insertMeasurements(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert('measurements', row);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> insertHandover(
    String trackId, {
    required DateTime ts,
    required String fromKey,
    required String toKey,
    int? fromPci,
    int? toPci,
    int? fromBand,
    int? toBand,
    String? technology,
  }) async {
    final db = await _db;
    await db.insert('handovers', {
      'track_id': trackId,
      'ts': ts.toIso8601String(),
      'from_key': fromKey,
      'to_key': toKey,
      'from_pci': fromPci,
      'to_pci': toPci,
      'from_band': fromBand,
      'to_band': toBand,
      'technology': technology,
    });
  }

  Future<List<TrackSummary>> listTracks() async {
    final db = await _db;
    final rows = await db.query('tracks', orderBy: 'started_at DESC');
    return rows.map(TrackSummary.fromRow).toList();
  }

  Future<List<Map<String, Object?>>> trackPoints(String trackId) async {
    final db = await _db;
    return db.query(
      'measurements',
      where: 'track_id = ?',
      whereArgs: [trackId],
      orderBy: 'ts ASC',
    );
  }

  Future<void> deleteTrack(String id) async {
    final db = await _db;
    await db.delete('tracks', where: 'id = ?', whereArgs: [id]);
  }
}

/// Строка measurements из CellInfo + текущей позиции.
Map<String, Object?> measurementRow(
  String trackId,
  CellInfo c,
  Position? pos,
) =>
    {
      'track_id': trackId,
      'ts': DateTime.now().toIso8601String(),
      'lat': pos?.latitude,
      'lon': pos?.longitude,
      'accuracy': pos?.accuracy,
      'speed': pos?.speed,
      'bearing': pos?.heading,
      'technology': c.technology,
      'registered': c.registered ? 1 : 0,
      'mcc': c.mcc,
      'mnc': c.mnc,
      'tac': c.tac,
      'lac': c.lac,
      'ci': c.ci,
      'nci': c.nci,
      'pci': c.pci,
      'psc': c.psc,
      'bsic': c.bsic,
      'earfcn': c.earfcn,
      'nrarfcn': c.nrarfcn,
      'uarfcn': c.uarfcn,
      'arfcn': c.arfcn,
      'band': c.band,
      'bandwidth': c.bandwidth,
      'rsrp': c.rsrp,
      'rsrq': c.rsrq,
      'rssi': c.rssi,
      'sinr': c.sinr,
      'dbm': c.dbm,
      'asu': c.asu,
      'ta': c.ta,
    };
