import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/track_repository.dart';

/// Экспорт треков в GeoJSON и CSV.
class ExportService {
  final _repo = TrackRepository();

  /// GeoJSON FeatureCollection: LineString маршрута + Point на каждый
  /// замер с параметрами сети. Координаты по стандарту — [lon, lat].
  Future<File> exportGeoJson(TrackSummary track) async {
    final points = await _repo.trackPoints(track.id);
    final lineCoords = <List<double>>[];
    final features = <Map<String, Object?>>[];

    for (final p in points) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lon = (p['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      lineCoords.add([lon, lat]);
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
        'properties': _pointProps(p),
      });
    }

    if (lineCoords.length >= 2) {
      features.insert(0, {
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': lineCoords},
        'properties': {
          'track_id': track.id,
          'started_at': track.startedAt.toIso8601String(),
          'ended_at': track.endedAt?.toIso8601String(),
          'operator': track.operator,
          'distance_m': track.distanceM,
          'point_count': track.pointCount,
        },
      });
    }

    final geojson = {'type': 'FeatureCollection', 'features': features};
    return _write(
      'track_${_safeId(track.id)}.geojson',
      const JsonEncoder.withIndent('  ').convert(geojson),
    );
  }

  /// CSV со всеми полями замеров — для таблиц и скриптов.
  Future<File> exportCsv(TrackSummary track) async {
    final points = await _repo.trackPoints(track.id);
    const cols = [
      'ts', 'lat', 'lon', 'accuracy', 'speed', 'bearing',
      'technology', 'mcc', 'mnc', 'tac', 'lac', 'ci', 'nci', 'pci',
      'earfcn', 'nrarfcn', 'band', 'bandwidth',
      'rsrp', 'rsrq', 'rssi', 'sinr', 'dbm', 'ta',
    ];
    final buf = StringBuffer(cols.join(','));
    for (final p in points) {
      buf.writeln();
      buf.write(cols.map((c) => _csvVal(p[c])).join(','));
    }
    return _write('track_${_safeId(track.id)}.csv', buf.toString());
  }

  Map<String, Object?> _pointProps(Map<String, Object?> p) => {
        'ts': p['ts'],
        'technology': p['technology'],
        'mcc': p['mcc'],
        'mnc': p['mnc'],
        'tac': p['tac'],
        'lac': p['lac'],
        'cell_id': p['ci'] ?? p['nci'],
        'pci': p['pci'],
        'band': p['band'],
        'earfcn': p['earfcn'],
        'nrarfcn': p['nrarfcn'],
        'rsrp_dbm': p['rsrp'],
        'rsrq_db': p['rsrq'],
        'sinr_db': p['sinr'],
        'dbm': p['dbm'],
        'speed_ms': p['speed'],
      };

  String _csvVal(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _safeId(String id) => id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '');

  Future<File> _write(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    return file.writeAsString(content);
  }
}
