import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../core/db/track_repository.dart';
import '../map_screen/signal_strip.dart';

/// Просмотр сохранённого трека: полилиния маршрута + точки замеров
/// с цветом по уровню сигнала.
class TrackViewScreen extends StatefulWidget {
  final TrackSummary track;

  const TrackViewScreen({super.key, required this.track});

  @override
  State<TrackViewScreen> createState() => _TrackViewScreenState();
}

class _TrackViewScreenState extends State<TrackViewScreen> {
  final _repo = TrackRepository();
  List<Map<String, Object?>> _points = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.trackPoints(widget.track.id);
    final pts = rows.where((r) => r['lat'] != null && r['lon'] != null).toList();
    if (mounted) {
      setState(() {
        _points = pts;
        _loading = false;
      });
    }
  }

  List<MapObject> _objects() {
    if (_points.isEmpty) return [];
    final pts = [
      for (final p in _points)
        Point(
          latitude: (p['lat'] as num).toDouble(),
          longitude: (p['lon'] as num).toDouble(),
        ),
    ];
    final objects = <MapObject>[
      PolylineMapObject(
        mapId: const MapObjectId('track_line'),
        polyline: Polyline(points: pts),
        strokeColor: Colors.white60,
        strokeWidth: 2,
        zIndex: 0,
      ),
    ];
    // Не более ~600 маркеров — прореживание по шагу.
    final stride = (_points.length / 600).ceil();
    for (var i = 0; i < _points.length; i += stride) {
      final p = _points[i];
      final dbm = (p['rsrp'] as int?) ?? (p['dbm'] as int?);
      objects.add(
        CircleMapObject(
          mapId: MapObjectId('pt_$i'),
          circle: Circle(
            center: Point(
              latitude: (p['lat'] as num).toDouble(),
              longitude: (p['lon'] as num).toDouble(),
            ),
            radius: 4,
          ),
          fillColor: signalColor(dbm),
          strokeColor: Colors.transparent,
          strokeWidth: 0,
          zIndex: 1,
        ),
      );
    }
    return objects;
  }

  CameraPosition _fitCamera() {
    if (_points.isEmpty) {
      return const CameraPosition(
        target: Point(latitude: 55.751244, longitude: 37.618423),
        zoom: 10,
      );
    }
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in _points) {
      final lat = (p['lat'] as num).toDouble();
      final lon = (p['lon'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }
    final span = math.max(maxLat - minLat, maxLon - minLon);
    var zoom = 17.0;
    while (zoom > 8 && 360 / math.pow(2, zoom) < span) {
      zoom--;
    }
    return CameraPosition(
      target: Point(
        latitude: (minLat + maxLat) / 2,
        longitude: (minLon + maxLon) / 2,
      ),
      zoom: zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Трек ${t.startedAt.day.toString().padLeft(2, '0')}.'
          '${t.startedAt.month.toString().padLeft(2, '0')} '
          '${t.startedAt.hour.toString().padLeft(2, '0')}:'
          '${t.startedAt.minute.toString().padLeft(2, '0')}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                YandexMap(
                  mapType: MapType.map,
                  mapObjects: _objects(),
                  onMapCreated: (controller) async {
                    await controller.moveCamera(
                      CameraUpdate.newCameraPosition(_fitCamera()),
                    );
                  },
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${t.pointCount} точек · ${_fmtDistance(t.distanceM)}'
                      '${t.operator != null ? ' · ${t.operator}' : ''}'
                      '\nТочки окрашены по уровню сигнала (зелёный — хороший)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                if (_points.isEmpty)
                  const Center(
                    child: Text('В этом треке нет точек с координатами'),
                  ),
              ],
            ),
    );
  }

  String _fmtDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} км' : '${m.round()} м';
}
