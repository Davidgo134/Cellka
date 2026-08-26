import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/db/track_repository.dart';
import '../../core/models/cell_info.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/recording/recording_service.dart';
import '../../core/telephony/telephony_service.dart';
import '../../core/towers/cell_estimator.dart';
import '../../core/towers/tower_download_service.dart';
import '../../core/towers/tower_service.dart';
import '../../core/towers/towers_repository.dart';
import '../history/history_screen.dart';
import 'signal_strip.dart';
import 'tower_info_sheet.dart';
import 'tower_layer_sheet.dart';

/// Режимы подложки карты.
enum CellkaMapMode { satellite, hybrid, scheme }

/// Главный экран: карта (flutter_map + Esri/OSM) + signal strip + FAB-стек.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Спутниковые тайлы Esri (z/y/x) и подписи для гибрида.
  static const _esriImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _esriLabels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
  static const _osmScheme = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Дефолтная точка (центр Москвы), если нет ни кэша позиции, ни фикса.
  static const _fallbackPoint = LatLng(55.751244, 37.618423);

  final _telephony = TelephonyService();
  final _permissions = PermissionService();
  final _towers = TowerService();
  final _towersRepo = TowersRepository();
  final _downloader = TowerDownloadService();
  late final RecordingService _recorder;

  final _mapController = MapController();
  StreamSubscription<List<CellInfo>>? _cellsSub;
  StreamSubscription<Position>? _posSub;
  Timer? _debounce;
  bool _mapReady = false;

  CellkaMapMode _mode = CellkaMapMode.hybrid;
  CellInfo? _servingCell;
  List<CellInfo> _allCells = [];
  bool _permissionsGranted = false;

  LatLng? _myPos;
  double _posAccuracy = 0;
  bool _hasFix = false;

  /// Линия к обслуживающей вышке + её маркер.
  List<Marker> _linkMarkers = [];
  List<Polyline> _linkLines = [];
  String? _lastTowerKey;
  String? _lastErrorKey;
  DateTime _lastErrorAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _warned = {};

  /// Постоянный статус вышки (нет в базе / оценка) — чип над signal strip.
  String? _towerStatusNote;

  /// Слой вышек выбранных операторов.
  List<Marker> _towerMarkers = [];
  bool _towersEnabled = false;
  Set<int> _selectedMncs = {};
  int _towersCount = 0;
  DateTime? _towersLoadedAt;
  List<double>? _lastQueryBbox;

  /// Heatmap собственных замеров.
  List<CircleMarker> _measurementCircles = [];
  bool _showMeasurements = false;
  List<double>? _lastMeasBbox;

  bool _autoMovedToUser = false;

  bool get _isRecording => _recorder.isRecording;

  @override
  void initState() {
    super.initState();
    _recorder = RecordingService(_telephony);
    _recorder.addListener(_onRecorderChanged);
    _initPermissionsAndStream();
    _loadLayerSettings();
  }

  void _onRecorderChanged() {
    if (mounted) setState(() {});
  }

  // ─── Слои карты ───────────────────────────────────────────────────────────

  Future<void> _loadLayerSettings() async {
    final repo = TrackRepository();
    final enabled = await repo.getSetting('towers_enabled') == '1';
    final mncsRaw = await repo.getSetting('towers_mncs');
    final showMeas = await repo.getSetting('show_measurements') == '1';
    final count = await _towersRepo.count();
    final loadedAtRaw = await repo.getSetting('towers_loaded_at');
    if (!mounted) return;
    setState(() {
      _towersEnabled = enabled;
      _showMeasurements = showMeas;
      _selectedMncs = mncsRaw == null || mncsRaw.isEmpty
          ? kRuOperators.map((o) => o.mnc).toSet()
          : mncsRaw
              .split(',')
              .map(int.tryParse)
              .whereType<int>()
              .toSet();
      _towersCount = count;
      _towersLoadedAt =
          loadedAtRaw != null ? DateTime.tryParse(loadedAtRaw) : null;
    });
    _loadTowersInView();
    _loadMeasurementsInView();
  }

  Future<void> _saveLayerSettings(
    bool enabled,
    Set<int> mncs,
    bool showMeasurements,
  ) async {
    final repo = TrackRepository();
    await repo.setSetting('towers_enabled', enabled ? '1' : '0');
    await repo.setSetting('towers_mncs', mncs.join(','));
    await repo.setSetting('show_measurements', showMeasurements ? '1' : '0');
  }

  Future<void> _openTowerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TowerLayerSheet(
        enabled: _towersEnabled,
        selectedMncs: _selectedMncs,
        showMeasurements: _showMeasurements,
        towersCount: _towersCount,
        loadedAt: _towersLoadedAt,
        onChanged: (enabled, mncs, showMeas) {
          setState(() {
            _towersEnabled = enabled;
            _selectedMncs = mncs;
            _showMeasurements = showMeas;
            _lastQueryBbox = null;
            _lastMeasBbox = null;
          });
          _saveLayerSettings(enabled, mncs, showMeas);
          if (!enabled) setState(() => _towerMarkers = []);
          if (!showMeas) setState(() => _measurementCircles = []);
          _loadTowersInView();
          _loadMeasurementsInView();
        },
        onDownload: (onProgress) async {
          final count = await _downloader.downloadAndImport(
            onProgress: onProgress,
          );
          final repo = TrackRepository();
          await repo.setSetting(
            'towers_loaded_at',
            DateTime.now().toIso8601String(),
          );
          if (mounted) {
            setState(() {
              _towersCount = count;
              _towersLoadedAt = DateTime.now();
              _lastQueryBbox = null;
            });
            _loadTowersInView();
          }
          return count;
        },
      ),
    );
  }

  void _showTowerInfo(Tower t) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => TowerInfoSheet(
        tower: t,
        onGoTo: () {
          Navigator.pop(context);
          _mapController.move(LatLng(t.lat, t.lon), 16.5);
        },
      ),
    );
  }

  /// Видимая область карты [south, north, west, east] с запасом 25%.
  List<double>? _paddedBounds() {
    if (!_mapReady) return null;
    try {
      final b = _mapController.camera.visibleBounds;
      final latPad = (b.north - b.south) * 0.25;
      final lonPad = (b.east - b.west) * 0.25;
      return [b.south - latPad, b.north + latPad, b.west - lonPad,
          b.east + lonPad];
    } catch (_) {
      return null;
    }
  }

  bool _covered(List<double>? last, List<double> cur) {
    if (last == null) return false;
    return cur[0] >= last[0] &&
        cur[1] <= last[1] &&
        cur[2] >= last[2] &&
        cur[3] <= last[3];
  }

  /// Загрузка вышек видимой области из локальной базы (после дампа).
  Future<void> _loadTowersInView() async {
    if (!_towersEnabled || !_mapReady) return;
    final zoom = _mapController.camera.zoom;

    // Гистерезис зума: показываем от 12, скрываем ниже 11.
    final shown = _towerMarkers.isNotEmpty;
    final threshold = shown ? 11.0 : 12.0;
    if (zoom < threshold) {
      if (shown && mounted) setState(() => _towerMarkers = []);
      return;
    }
    if (_towersCount == 0) {
      _warnOnce('emptydb', 'База вышек пуста — скачай её в меню слоя');
      return;
    }
    final bbox = _paddedBounds();
    if (bbox == null) return;
    if (_covered(_lastQueryBbox, bbox) && shown) return;

    try {
      final towers = await _towersRepo.inBbox(
        southLat: bbox[0],
        northLat: bbox[1],
        westLon: bbox[2],
        eastLon: bbox[3],
        mncs: _selectedMncs,
      );
      if (!mounted) return;

      // Точки фиксированного размера — видны на любом зуме.
      final size = zoom < 13 ? 22.0 : zoom < 15 ? 16.0 : 11.0;
      setState(() {
        _towerMarkers = [
          for (final t in towers)
            Marker(
              point: LatLng(t.lat, t.lon),
              width: size,
              height: size,
              child: GestureDetector(
                onTap: () => _showTowerInfo(t),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorForMnc(t.mnc).withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
        ];
      });
      _lastQueryBbox = bbox;
      _warnOnce(
        'layercount',
        'Вышек в области: ${towers.length} (база: $_towersCount)',
      );
    } catch (e, st) {
      debugPrint('tower layer load failed: $e\n$st');
      _warnOnce('layererror', 'Слой вышек: ошибка загрузки — $e');
    }
  }

  /// Heatmap собственных замеров в видимой области.
  Future<void> _loadMeasurementsInView() async {
    if (!_showMeasurements || !_mapReady) return;
    final zoom = _mapController.camera.zoom;

    final shown = _measurementCircles.isNotEmpty;
    final threshold = shown ? 11.0 : 12.0;
    if (zoom < threshold) {
      if (shown && mounted) setState(() => _measurementCircles = []);
      return;
    }
    final bbox = _paddedBounds();
    if (bbox == null) return;
    if (_covered(_lastMeasBbox, bbox) && shown) return;

    try {
      final rows = await TrackRepository().measurementsInBbox(
        southLat: bbox[0],
        northLat: bbox[1],
        westLon: bbox[2],
        eastLon: bbox[3],
      );
      if (!mounted) return;

      final radius = zoom < 14 ? 15.0 : zoom < 16 ? 6.0 : 3.0;
      setState(() {
        _measurementCircles = [
          for (final r in rows)
            CircleMarker(
              point: LatLng(
                (r['lat'] as num).toDouble(),
                (r['lon'] as num).toDouble(),
              ),
              radius: radius,
              useRadiusInMeter: true,
              color: signalColor(
                (r['rsrp'] as int?) ?? (r['dbm'] as int?),
              ).withValues(alpha: 0.55),
            ),
        ];
      });
      _lastMeasBbox = bbox;
    } catch (e) {
      debugPrint('measurement layer load failed: $e');
    }
  }

  void _onMapPosition(MapCamera camera, bool hasGesture) {
    // Дебаунс: грузим слои после остановки камеры.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadTowersInView();
      _loadMeasurementsInView();
    });
  }

  // ─── Запись ───────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recorder.isRecording) {
      await _recorder.stop();
      if (mounted) {
        var text = 'Трек сохранён: ${_recorder.pointCount} точек · '
            '${_recorder.distanceM.round()} м';
        final share = _recorder.lastShareResult;
        if (share == 'ok') {
          text += ' · отправлен в OpenCelliD';
        } else if (share != null) {
          text += ' · OpenCelliD: $share';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
      return;
    }
    if (!_permissionsGranted) {
      await _requestPermissions();
      if (!_permissionsGranted) return;
    }
    // Android 13+: постоянное уведомление FGS требует рантайм-пермишн.
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    await _maybeAskSharing();
    if (!mounted) return;
    await _recorder.start();
  }

  /// Опт-in на отправку замеров в OpenCelliD — спрашиваем один раз,
  /// ответ хранится в таблице settings.
  Future<void> _maybeAskSharing() async {
    if (!_towers.hasKey) return;
    final repo = TrackRepository();
    final current = await repo.getSetting('share_opencellid');
    if (current != null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Делиться замерами?'),
        content: const Text(
          'Cellka может отправлять записанные замеры в OpenCelliD после '
          'остановки трека. Это наполняет открытую базу вышек (в т.ч. '
          'добавит соты, которых там нет) и разблокирует полный доступ '
          'к их API для приложения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Делиться'),
          ),
        ],
      ),
    );
    await repo.setSetting('share_opencellid', yes == true ? '1' : '0');
  }

  Future<void> _initPermissionsAndStream() async {
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);

    if (granted) {
      _startPositionStream();
      await _moveToUser();
    }

    _cellsSub = _telephony.watchCells().listen((cells) {
      CellInfo? serving;
      for (final c in cells) {
        if (c.registered) {
          serving = c;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _servingCell = serving;
          _allCells = cells;
        });
        _updateTowerLink(serving);
      }
    });
  }

  /// Постоянный стрим позиции для маркера «я» (пока экран открыт).
  void _startPositionStream() {
    _posSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 3,
      ),
    ).listen((p) {
      if (mounted) {
        setState(() {
          _myPos = LatLng(p.latitude, p.longitude);
          _posAccuracy = p.accuracy;
          _hasFix = true;
        });
      }
    });
  }

  /// Линия «пользователь → обслуживающая вышка» как в CellMapper.
  /// Источники координат: кэш → локальный дамп → OpenCelliD → наша оценка.
  Future<void> _updateTowerLink(CellInfo? serving) async {
    if (serving == null) {
      _lastTowerKey = null;
      if ((_linkMarkers.isNotEmpty || _linkLines.isNotEmpty ||
              _towerStatusNote != null) &&
          mounted) {
        setState(() {
          _linkMarkers = [];
          _linkLines = [];
          _towerStatusNote = null;
        });
      }
      return;
    }

    final key = '${serving.technology}:${serving.mcc}-${serving.mnc}:'
        '${serving.tac ?? serving.lac}:${serving.ci ?? serving.nci}';
    if (key == _lastTowerKey) return;
    // После сетевой ошибки ретраим не чаще, чем раз в 30 с.
    if (key == _lastErrorKey &&
        DateTime.now().difference(_lastErrorAt) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastTowerKey = key;

    // Сота сменилась — старая линия недействительна, стираем сразу.
    if (_linkLines.isNotEmpty || _linkMarkers.isNotEmpty) {
      _clearLink();
    }

    final result = await _towers.locate(serving);
    if (!mounted || key != _lastTowerKey) return;

    switch (result.status) {
      case TowerLookupStatus.ok:
        _towerStatusNote = null;
        await _drawTowerLink(serving, result.location!);
      case TowerLookupStatus.noKey:
        _warnOnce('nokey', 'Нет ключа OpenCelliD — линия к вышке отключена');
        _towerStatusNote = null;
        _clearLink();
      case TowerLookupStatus.invalidKey:
        _warnOnce(
          'badkey',
          'OpenCelliD: ключ не принят (401) — проверь секрет в CI',
        );
        _towerStatusNote = null;
        _clearLink();
      case TowerLookupStatus.forbidden:
        _warnOnce(
          'forbidden',
          'OpenCelliD: ключ не в белом списке (403). Лечится отправкой '
          'замеров — диалог при старте записи',
        );
        _towerStatusNote = null;
        _clearLink();
      case TowerLookupStatus.notFound:
        // Соты нет в базе — пробуем собственную оценку позиции.
        final est = await CellEstimator.instance.estimate(
          CellEstimator.keyOf(serving),
        );
        if (!mounted || key != _lastTowerKey) return;
        if (est != null) {
          _warnOnce(
            'estimate',
            'Вышки нет в OpenCelliD — на карте наша оценка '
            '(${est.samples} замеров)',
          );
          await _drawTowerLink(
            serving,
            TowerLocation(lat: est.lat, lon: est.lon),
            estimated: true,
          );
          setState(() {
            _towerStatusNote =
                'Оценка позиции вышки (${est.samples} замеров)';
          });
        } else {
          _warnOnce(
            'notfound',
            'Соты нет в базе OpenCelliD — оценка позиции появится '
            'после ≥5 замеров с ней',
          );
          _clearLink();
          setState(() {
            _towerStatusNote =
                'Вышки нет в базе · оценка после ≥5 замеров';
          });
        }
      case TowerLookupStatus.error:
        // Молча: ретрай через 30 с по троттлингу выше.
        _lastTowerKey = null;
        _lastErrorKey = key;
        _lastErrorAt = DateTime.now();
    }
  }

  void _clearLink() {
    setState(() {
      _linkMarkers = [];
      _linkLines = [];
    });
  }

  void _warnOnce(String id, String text) {
    if (!mounted || !_warned.add(id)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _drawTowerLink(
    CellInfo serving,
    TowerLocation loc, {
    bool estimated = false,
  }) async {
    final userPoint = await _userPoint();
    if (!mounted) return;
    if (userPoint == null) {
      _clearLink();
      return;
    }

    final towerPoint = LatLng(loc.lat, loc.lon);
    final color = estimated ? Colors.white70 : signalColor(serving.rsrp);
    setState(() {
      _linkMarkers = [
        Marker(
          point: towerPoint,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: estimated
                  ? Colors.transparent
                  : color.withValues(alpha: 0.3),
              border: Border.all(color: color, width: 2.5),
            ),
          ),
        ),
      ];
      _linkLines = [
        Polyline(
          points: [userPoint, towerPoint],
          color: color,
          strokeWidth: estimated ? 2 : 3,
        ),
      ];
    });
  }

  Future<LatLng?> _userPoint() async {
    if (_myPos != null) return _myPos;
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) return LatLng(p.latitude, p.longitude);
    } catch (_) {}
    return null;
  }

  /// Перелёт камеры к пользователю: кэш → свежая позиция. Авто — один раз.
  Future<void> _moveToUser({bool force = false}) async {
    if (_autoMovedToUser && !force) return;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      _autoMovedToUser = true;
      if (_mapReady) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15.5);
      }
    } catch (_) {
      // Позиции нет — остаёмся на стартовом виде.
    }
  }

  Future<void> _centerOnUser() async {
    if (_myPos != null) {
      _mapController.move(_myPos!, 16);
      return;
    }
    await _moveToUser(force: true);
  }

  void _toggleMapMode() {
    setState(() {
      _mode = CellkaMapMode
          .values[(_mode.index + 1) % CellkaMapMode.values.length];
    });
  }

  String get _modeLabel => switch (_mode) {
        CellkaMapMode.satellite => 'Спутник',
        CellkaMapMode.hybrid => 'Гибрид',
        CellkaMapMode.scheme => 'Схема',
      };

  Future<void> _requestPermissions() async {
    if (await _permissions.isPermanentlyDenied) {
      await _permissions.openSettings();
      return;
    }
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);
    if (granted) {
      _startPositionStream();
      await _moveToUser();
    }
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    _cellsSub?.cancel();
    _posSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myPos ?? _fallbackPoint,
              initialZoom: _myPos != null ? 15 : 10,
              onMapReady: () {
                _mapReady = true;
                _loadTowersInView();
                _loadMeasurementsInView();
                _moveToUser();
              },
              onPositionChanged: _onMapPosition,
            ),
            children: [
              if (_mode == CellkaMapMode.scheme)
                TileLayer(
                  urlTemplate: _osmScheme,
                  userAgentPackageName: 'com.github.davidgo134.cellka',
                )
              else ...[
                TileLayer(
                  urlTemplate: _esriImagery,
                  userAgentPackageName: 'com.github.davidgo134.cellka',
                  maxZoom: 19,
                ),
                if (_mode == CellkaMapMode.hybrid)
                  TileLayer(
                    urlTemplate: _esriLabels,
                    userAgentPackageName: 'com.github.davidgo134.cellka',
                    maxZoom: 19,
                  ),
              ],
              // Heatmap своих замеров и круг точности позиции.
              CircleLayer(
                circles: [
                  ..._measurementCircles,
                  if (_myPos != null && _posAccuracy > 0)
                    CircleMarker(
                      point: _myPos!,
                      radius: _posAccuracy,
                      useRadiusInMeter: true,
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                    ),
                ],
              ),
              PolylineLayer(polylines: _linkLines),
              MarkerLayer(
                markers: [
                  ..._towerMarkers,
                  ..._linkMarkers,
                  if (_myPos != null)
                    Marker(
                      point: _myPos!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.white.withValues(alpha: 0.6),
              child: Text(
                _mode == CellkaMapMode.scheme
                    ? '© OpenStreetMap contributors'
                    : 'Tiles © Esri — Maxar, Earthstar Geographics',
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
          // Статус вышки: нет в базе / оценочная позиция.
          if (_towerStatusNote != null)
            Positioned(
              left: 12,
              bottom: 92 + bottomPadding,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cell_tower,
                      size: 14,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _towerStatusNote!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16 + bottomPadding,
            child: SignalStrip(
              cell: _servingCell,
              allCells: _allCells,
              permissionsGranted: _permissionsGranted,
              onRequestPermissions: _requestPermissions,
              hasFix: _hasFix,
              isRecording: _isRecording,
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        // FAB над signal strip
        padding: EdgeInsets.only(bottom: 92 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'history',
              tooltip: 'История треков',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
              child: const Icon(Icons.history),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'towers',
              tooltip: 'Слои карты',
              onPressed: _openTowerSheet,
              child: const Icon(Icons.cell_tower),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'record',
              tooltip: _isRecording ? 'Остановить запись' : 'Запись трека',
              backgroundColor: _isRecording ? Colors.redAccent : null,
              onPressed: _toggleRecording,
              child: Icon(
                _isRecording ? Icons.stop : Icons.fiber_manual_record,
              ),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'layers',
              tooltip: 'Подложка: $_modeLabel',
              onPressed: _toggleMapMode,
              child: const Icon(Icons.layers),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'locate',
              tooltip: 'К моей позиции',
              onPressed: _centerOnUser,
              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      ),
    );
  }
}
