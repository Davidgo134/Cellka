import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

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

/// Главный экран: карта Yandex + signal strip + FAB-стек.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Дефолтная точка (центр Москвы), если нет ни кэша позиции, ни фикса.
  static const _fallbackTarget =
      Point(latitude: 55.751244, longitude: 37.618423);

  final _telephony = TelephonyService();
  final _permissions = PermissionService();
  final _towers = TowerService();
  final _towersRepo = TowersRepository();
  final _downloader = TowerDownloadService();
  late final RecordingService _recorder;

  YandexMapController? _mapController;
  StreamSubscription<List<CellInfo>>? _cellsSub;
  Timer? _fixCheckTimer;

  MapType _mapType = MapType.hybrid;
  CellInfo? _servingCell;
  List<CellInfo> _allCells = [];
  bool _permissionsGranted = false;
  bool _hasFix = false;
  bool _autoMovedToUser = false;

  /// Линия к обслуживающей вышке + её маркер.
  List<MapObject> _linkObjects = [];
  String? _lastTowerKey;
  String? _lastErrorKey;
  DateTime _lastErrorAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _warned = {};

  /// Слой вышек выбранных операторов.
  List<MapObject> _towerLayerObjects = [];
  final Map<String, Tower> _towersById = {};
  bool _towersEnabled = false;
  Set<int> _selectedMncs = {};
  int _towersCount = 0;
  DateTime? _towersLoadedAt;
  List<double>? _lastQueryBbox;

  /// Heatmap собственных замеров.
  List<MapObject> _measurementObjects = [];
  bool _showMeasurements = false;
  List<double>? _lastMeasBbox;

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
    if (enabled) _loadTowersInView();
    if (showMeas) _loadMeasurementsInView();
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
          if (enabled) {
            _loadTowersInView();
          } else if (mounted) {
            setState(() => _towerLayerObjects = []);
          }
          if (showMeas) {
            _loadMeasurementsInView();
          } else if (mounted) {
            setState(() => _measurementObjects = []);
          }
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
            if (_towersEnabled) _loadTowersInView();
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
          _mapController?.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: t.lat, longitude: t.lon),
                zoom: 16.5,
              ),
            ),
            animation: const MapAnimation(duration: 0.5),
          );
        },
      ),
    );
  }

  /// Загрузка вышек видимой области из локальной базы (после дампа).
  Future<void> _loadTowersInView() async {
    if (!_towersEnabled) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      final cam = await controller.getCameraPosition();
      // Гистерезис зума: показываем от 12, скрываем ниже 11.
      final shown = _towerLayerObjects.isNotEmpty;
      final threshold = shown ? 11.0 : 12.0;
      if (cam.zoom < threshold) {
        if (shown && mounted) {
          setState(() => _towerLayerObjects = []);
        }
        return;
      }
      if (_towersCount == 0) {
        _warnOnce('emptydb', 'База вышек пуста — скачай её в меню слоя');
        return;
      }
      final region = await controller.getVisibleRegion();
      final sw = region.bottomLeft;
      final ne = region.topRight;
      final latPad = (ne.latitude - sw.latitude) * 0.25;
      final lonPad = (ne.longitude - sw.longitude) * 0.25;
      final south = sw.latitude - latPad;
      final north = ne.latitude + latPad;
      final west = sw.longitude - lonPad;
      final east = ne.longitude + lonPad;

      // Уже покрыто прошлой загрузкой — не пересоздаём слой.
      final b = _lastQueryBbox;
      if (b != null &&
          shown &&
          south >= b[0] &&
          north <= b[1] &&
          west >= b[2] &&
          east <= b[3]) {
        return;
      }

      final towers = await _towersRepo.inBbox(
        southLat: south,
        northLat: north,
        westLon: west,
        eastLon: east,
        mncs: _selectedMncs,
      );
      if (!mounted) return;

      // Радиус в метрах по ярусам зума — иначе точки незаметны.
      final radius = cam.zoom < 13 ? 60.0 : cam.zoom < 15 ? 25.0 : 12.0;
      _towersById.clear();
      setState(() {
        _towerLayerObjects = [
          for (final t in towers)
            () {
              final id = 'tower_${t.radio}_${t.mnc}_${t.area}_${t.cell}';
              _towersById[id] = t;
              return CircleMapObject(
                mapId: MapObjectId(id),
                circle: Circle(
                  center: Point(latitude: t.lat, longitude: t.lon),
                  radius: radius,
                ),
                fillColor: colorForMnc(t.mnc).withValues(alpha: 0.9),
                strokeColor: Colors.white,
                strokeWidth: 1.5,
                zIndex: 0,
                onTap: (self, point) {
                  final tower = _towersById[self.mapId.value];
                  if (tower != null) _showTowerInfo(tower);
                },
              );
            }(),
        ];
      });
      _lastQueryBbox = [south, north, west, east];
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
    if (!_showMeasurements) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      final cam = await controller.getCameraPosition();
      final shown = _measurementObjects.isNotEmpty;
      final threshold = shown ? 11.0 : 12.0;
      if (cam.zoom < threshold) {
        if (shown && mounted) {
          setState(() => _measurementObjects = []);
        }
        return;
      }
      final region = await controller.getVisibleRegion();
      final sw = region.bottomLeft;
      final ne = region.topRight;
      final latPad = (ne.latitude - sw.latitude) * 0.25;
      final lonPad = (ne.longitude - sw.longitude) * 0.25;
      final south = sw.latitude - latPad;
      final north = ne.latitude + latPad;
      final west = sw.longitude - lonPad;
      final east = ne.longitude + lonPad;

      final b = _lastMeasBbox;
      if (b != null &&
          shown &&
          south >= b[0] &&
          north <= b[1] &&
          west >= b[2] &&
          east <= b[3]) {
        return;
      }

      final rows = await TrackRepository().measurementsInBbox(
        southLat: south,
        northLat: north,
        westLon: west,
        eastLon: east,
      );
      if (!mounted) return;

      final radius = cam.zoom < 14 ? 15.0 : cam.zoom < 16 ? 6.0 : 3.0;
      setState(() {
        _measurementObjects = [
          for (var i = 0; i < rows.length; i++)
            CircleMapObject(
              mapId: MapObjectId('meas_$i'),
              circle: Circle(
                center: Point(
                  latitude: (rows[i]['lat'] as num).toDouble(),
                  longitude: (rows[i]['lon'] as num).toDouble(),
                ),
                radius: radius,
              ),
              fillColor: signalColor(
                (rows[i]['rsrp'] as int?) ?? (rows[i]['dbm'] as int?),
              ).withValues(alpha: 0.55),
              strokeColor: Colors.transparent,
              strokeWidth: 0,
              zIndex: 0,
            ),
        ];
      });
      _lastMeasBbox = [south, north, west, east];
    } catch (e) {
      debugPrint('measurement layer load failed: $e');
    }
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
      await _enableUserLayer();
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

    // Проверяем наличие GPS-фикса каждые 3 секунды
    _fixCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final controller = _mapController;
      if (controller == null) return;
      try {
        final pos = await controller.getUserCameraPosition();
        if (mounted) setState(() => _hasFix = pos != null);
      } catch (_) {
        if (mounted) setState(() => _hasFix = false);
      }
    });
  }

  /// Линия «пользователь → обслуживающая вышка» как в CellMapper.
  /// Источники координат по приоритету: OpenCelliD → наша оценка.
  Future<void> _updateTowerLink(CellInfo? serving) async {
    if (serving == null) {
      _lastTowerKey = null;
      if (_linkObjects.isNotEmpty && mounted) {
        setState(() => _linkObjects = []);
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

    final result = await _towers.locate(serving);
    if (!mounted || key != _lastTowerKey) return;

    switch (result.status) {
      case TowerLookupStatus.ok:
        await _drawTowerLink(serving, result.location!);
      case TowerLookupStatus.noKey:
        _warnOnce('nokey', 'Нет ключа OpenCelliD — линия к вышке отключена');
        setState(() => _linkObjects = []);
      case TowerLookupStatus.invalidKey:
        _warnOnce(
          'badkey',
          'OpenCelliD: ключ не принят (401) — проверь секрет в CI',
        );
        setState(() => _linkObjects = []);
      case TowerLookupStatus.forbidden:
        _warnOnce(
          'forbidden',
          'OpenCelliD: ключ не в белом списке (403). Лечится отправкой '
          'замеров — диалог при старте записи',
        );
        setState(() => _linkObjects = []);
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
        } else {
          _warnOnce(
            'notfound',
            'Соты нет в базе OpenCelliD — оценка позиции появится '
            'после ≥5 замеров с ней',
          );
          setState(() => _linkObjects = []);
        }
      case TowerLookupStatus.error:
        // Молча: ретрай через 30 с по троттлингу выше.
        _lastTowerKey = null;
        _lastErrorKey = key;
        _lastErrorAt = DateTime.now();
    }
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
      setState(() => _linkObjects = []);
      return;
    }

    final towerPoint = Point(latitude: loc.lat, longitude: loc.lon);
    final color = estimated ? Colors.white70 : signalColor(serving.rsrp);
    setState(() {
      _linkObjects = [
        CircleMapObject(
          mapId: const MapObjectId('serving_tower'),
          circle: Circle(center: towerPoint, radius: 25),
          fillColor:
              estimated ? Colors.transparent : color.withValues(alpha: 0.35),
          strokeColor: color,
          strokeWidth: 2,
          zIndex: 2,
        ),
        PolylineMapObject(
          mapId: const MapObjectId('serving_link'),
          polyline: Polyline(points: [userPoint, towerPoint]),
          strokeColor: color,
          strokeWidth: estimated ? 2 : 3,
          zIndex: 1,
        ),
      ];
    });
  }

  Future<Point?> _userPoint() async {
    try {
      final cam = await _mapController?.getUserCameraPosition();
      if (cam != null) return cam.target;
    } catch (_) {}
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) return Point(latitude: p.latitude, longitude: p.longitude);
    } catch (_) {}
    return null;
  }

  Future<void> _enableUserLayer() async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.toggleUserLayer(visible: true, autoZoomEnabled: false);
    } catch (_) {}
  }

  /// Перелёт камеры к пользователю: сначала кэшированная позиция
  /// (мгновенно), затем свежая с геолокатора. Автоматически — один раз.
  Future<void> _moveToUser({bool force = false}) async {
    if (_autoMovedToUser && !force) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      _autoMovedToUser = true;
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: Point(latitude: pos.latitude, longitude: pos.longitude),
            zoom: 15.5,
          ),
        ),
        animation: const MapAnimation(duration: 0.6),
      );
    } catch (_) {
      // Позиции нет — остаёмся на стартовом виде.
    }
  }

  Future<void> _centerOnUser() async {
    final controller = _mapController;
    if (controller == null) return;
    final position = await controller.getUserCameraPosition();
    if (position != null) {
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position.target, zoom: 16),
        ),
        animation: const MapAnimation(duration: 0.5),
      );
      return;
    }
    await _moveToUser(force: true);
  }

  void _toggleMapType() {
    setState(() {
      _mapType =
          _mapType == MapType.hybrid ? MapType.satellite : MapType.hybrid;
    });
  }

  Future<void> _requestPermissions() async {
    if (await _permissions.isPermanentlyDenied) {
      await _permissions.openSettings();
      return;
    }
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);
    if (granted) {
      await _enableUserLayer();
      await _moveToUser();
    }
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    _cellsSub?.cancel();
    _fixCheckTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          YandexMap(
            mapType: _mapType,
            nightModeEnabled: false,
            mapObjects: [
              ..._towerLayerObjects,
              ..._measurementObjects,
              ..._linkObjects,
            ],
            onCameraPositionChanged: (position, reason, finished) {
              if (finished) {
                _loadTowersInView();
                _loadMeasurementsInView();
              }
            },
            onMapCreated: (controller) async {
              _mapController = controller;
              // Стартовый вид: кэшированная позиция или центр Москвы,
              // чтобы не показывать «всю планету».
              var start = _fallbackTarget;
              var zoom = 10.0;
              try {
                final cached = await Geolocator.getLastKnownPosition();
                if (cached != null) {
                  start = Point(
                    latitude: cached.latitude,
                    longitude: cached.longitude,
                  );
                  zoom = 14;
                }
              } catch (_) {}
              await controller.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: start, zoom: zoom),
                ),
              );
              if (_permissionsGranted) {
                await _enableUserLayer();
                await _moveToUser();
              }
              // Если слои включены — грузим сразу после создания карты.
              _loadTowersInView();
              _loadMeasurementsInView();
            },
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
              tooltip: 'Слой: гибрид / спутник',
              onPressed: _toggleMapType,
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
