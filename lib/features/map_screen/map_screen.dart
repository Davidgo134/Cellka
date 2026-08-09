import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../core/models/cell_info.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/telephony/telephony_service.dart';
import 'signal_strip.dart';

/// Главный экран: спутниковая карта Yandex + signal strip + FAB-стек.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _telephony = TelephonyService();
  final _permissions = PermissionService();

  YandexMapController? _mapController;
  StreamSubscription<List<CellInfo>>? _cellsSub;

  MapType _mapType = MapType.satellite;
  CellInfo? _servingCell;
  int _cellCount = 0;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _initPermissionsAndStream();
  }

  Future<void> _initPermissionsAndStream() async {
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);

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
          _cellCount = cells.length;
        });
      }
    });
  }

  Future<void> _centerOnUser() async {
    final controller = _mapController;
    if (controller == null) return;
    final position = await controller.getUserCameraPosition();
    if (position == null) return;
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position.target, zoom: 16),
      ),
      animation: const MapAnimation(duration: 0.5),
    );
  }

  void _toggleMapType() {
    setState(() {
      _mapType =
          _mapType == MapType.satellite ? MapType.hybrid : MapType.satellite;
    });
  }

  Future<void> _requestPermissions() async {
    if (await _permissions.isPermanentlyDenied) {
      await _permissions.openSettings();
      return;
    }
    final granted = await _permissions.ensureTelephonyPermissions();
    if (mounted) setState(() => _permissionsGranted = granted);
  }

  @override
  void dispose() {
    _cellsSub?.cancel();
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
            nightModeEnabled: true,
            onMapCreated: (controller) async {
              _mapController = controller;
              await controller.toggleUserLayer(
                visible: true,
                autoZoomEnabled: true,
              );
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16 + bottomPadding,
            child: SignalStrip(
              cell: _servingCell,
              cellCount: _cellCount,
              permissionsGranted: _permissionsGranted,
              onRequestPermissions: _requestPermissions,
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
              tooltip: 'Слой: спутник / гибрид',
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
