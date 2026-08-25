import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../core/models/cell_info.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/telephony/telephony_service.dart';
import 'signal_strip.dart';

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

  YandexMapController? _mapController;
  StreamSubscription<List<CellInfo>>? _cellsSub;
  Timer? _fixCheckTimer;

  MapType _mapType = MapType.hybrid;
  CellInfo? _servingCell;
  List<CellInfo> _allCells = [];
  bool _permissionsGranted = false;
  bool _hasFix = false;
  bool _autoMovedToUser = false;
  final bool _isRecording = false; // будет переключаться в Фазе 4

  @override
  void initState() {
    super.initState();
    _initPermissionsAndStream();
  }

  Future<void> _initPermissionsAndStream() async {
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);

    if (granted) {
      // User layer мог быть включён до выдачи пермишна — включаем повторно
      // и сразу летим к последней известной/текущей позиции.
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
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
    // User layer ещё без фикса — пробуем через геолокатор напрямую.
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
