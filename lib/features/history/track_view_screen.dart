import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/db/track_repository.dart';
import '../map_screen/signal_strip.dart';
import 'export_sheet.dart';

/// Просмотр сохранённого трека: полилиния маршрута + точки замеров
/// с цветом по уровню сигнала поверх спутника.
class TrackViewScreen extends StatefulWidget {
  final TrackSummary track;

  const TrackViewScreen({super.key, required this.track});

  @override
  State<TrackViewScreen> createState() => _TrackViewScreenState();
}

class _TrackViewScreenState extends State<TrackViewScreen> {
  static const _esriImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _esriLabels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  final _repo = TrackRepository();
  final _mapController = MapController();
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

  List<LatLng> get _latLngs => [
        for (final p in _points)
          LatLng(
            (p['lat'] as num).toDouble(),
            (p['lon'] as num).toDouble(),
          ),
      ];

  void _fitCamera() {
    if (_points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_latLngs),
        padding: const EdgeInsets.all(48),
      ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Экспорт',
            onPressed: () => showExportSheet(context, t),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _latLngs.isEmpty
                        ? const LatLng(55.751244, 37.618423)
                        : _latLngs.first,
                    initialZoom: 14,
                    onMapReady: _fitCamera,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _esriImagery,
                      userAgentPackageName: 'com.github.davidgo134.cellka',
                      maxZoom: 19,
                    ),
                    TileLayer(
                      urlTemplate: _esriLabels,
                      userAgentPackageName: 'com.github.davidgo134.cellka',
                      maxZoom: 19,
                    ),
                    if (_latLngs.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _latLngs,
                            color: Colors.white70,
                            strokeWidth: 2,
                          ),
                        ],
                      ),
                    CircleLayer(
                      circles: [
                        for (var i = 0; i < _points.length; i++)
                          CircleMarker(
                            point: _latLngs[i],
                            radius: 4,
                            useRadiusInMeter: true,
                            color: signalColor(
                              (_points[i]['rsrp'] as int?) ??
                                  (_points[i]['dbm'] as int?),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Атрибуция тайлов (лицензионно обязательна).
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.white.withValues(alpha: 0.6),
                    child: const Text(
                      'Tiles © Esri — Maxar, Earthstar Geographics',
                      style: TextStyle(fontSize: 10, color: Colors.black87),
                    ),
                  ),
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
