import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
import 'signal_strip.dart';
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

  /// Минимальный зум для слоя вышек (иначе слишком плотно).
  static const _towersMinZoom = 12.0;

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
  bool _towersEnabled = false;
  Set<int> _selectedMncs = {};
  int _towersCount = 0;
  DateTime? _towersLoadedAt;

  bool get _isRecording => _recorder.isRecording;

  @override
  void initState() {
    super.initState();
    _recorder = RecordingService(_telephony);
    _recorder.addListener(_onRecorderChanged);
    _initPermissionsAndStream();
    _loadTowerLayerSettings();
  }

  void _onRecorderChanged() {
    if (mounted) setState(() {});
  }

  // ─── Слой вышек ──────────────────────────────────────────────────────────

  Future<void> _loadTowerLayerSettings() async {
    final repo = TrackRepository();
    final enabled = await repo.getSetting('towers_enabled') == '1';
    final mncsRaw = await repo.getSetting('towers_mncs');
    final count = await _towersRepo.count();
    final loadedAtRaw = await repo.getSetting('towers_loaded_at');
    if (!mounted) return;
    setState(() {
      _towersEnabled = enabled;
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
  }

  Future<void> _saveTowerLayerSettings(bool enabled, Set<int> mncs) async {
    final repo = TrackRepository();
    await repo.setSetting('towers_enabled', enabled ? '1' : '0');
    await repo.setSetting('towers_mncs', mncs.join(','));
  }

  Future<void> _openTowerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TowerLayerSheet(
        enabled: _towersEnabled,
        selectedMncs: _selectedMncs,
        towersCount: _towersCount,
        loadedAt: _towersLoadedAt,
        onChanged: (enabled, mncs) {
          setState(() {
            _towersEnabled = enabled;
            _selectedMncs = mncs;
          });
          _saveTowerLayerSettings(enabled, mncs);
          if (enabled) {
            _loadTowersInView();
          } else if (mounted) {
            setState(() => _towerLayerObjects = []);
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
            });
            if (_towersEnabled) _loadTowersInView();
          }
          return count;
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
      if (cam.zoom < _towersMinZoom) {
        if (_towerLayerObjects.isNotEmpty && mounted) {
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
      // Запас 25% за края экрана — меньше дозагрузок при панорамировании.
      final latPad = (ne.latitude - sw.latitude) * 0.25;
      final lonPad = (ne.longitude - sw.longitude) * 0.25;

      final towers = await _towersRepo.inBbox(
        southLat: sw.latitude - latPad,
        northLat: ne.latitude + latPad,
        westLon: sw.longitude - lonPad,
        eastLon: ne.longitude + lonPad,
        mncs: _selectedMncs,
      );
      if (!mounted) return;

      // Радиус в метрах по ярусам зума — иначе точки незаметны.
      final radius = cam.zoom < 13 ? 60.0 : cam.zoom < 15 ? 25.0 : 12.0;
      setState(() {
        _towerLayerObjects = [
          for (final t in towers)
            CircleMapObject(
              mapId: MapObjectId(
                'tower_${t.radio}_${t.mnc}_${t.lat}_${t.lon}',
              ),
              circle: Circle(
                center: Point(latitude: t.lat, longitude: t.lon),
                radius: radius,
              ),
              fillColor: colorForMnc(t.mnc).withValues(alpha: 0.9),
              strokeColor: Colors.white,
              strokeWidth: 1.5,
              zIndex: 0,
            ),
        ];
      });
      _warnOnce(
        'layercount',
        'Вышек в области: ${towers.length} (база: $_towersCount)',
      );
    } catch (e, st) {
      debugPrint('tower layer load failed: $e\n$st');
      _warnOnce('layererror', 'Слой вышек: ошибка загрузки — $e');
    }
  }

  // ─── Запись ───────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recorder.isRecording) {
      await _recorder.stop();
      if (mounted) {
        var text = 'Трек сохранён: ${_recorder.pointCount} точек · '
            '${_recorder.distanceM.round()} м';
        if (_recorder.lastShareOk == true) {
          text += ' · отправлен в OpenCelliD';
        } else if (_recorder.lastShareOk == false) {
          text += ' · OpenCelliD: ошибка отправки';
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
            mapObjects: [..._towerLayerObjects, ..._linkObjects],
            onCameraPositionChanged: (position, reason, finished) {
              if (finished) _loadTowersInView();
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
              // Если слой вышек включён — грузим сразу после создания карты.
              _loadTowersInView();
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
              heroTag: 'towers',
              tooltip: 'Слой вышек',
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
