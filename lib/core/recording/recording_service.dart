import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
// Прямой импорт платформенного пакета: AndroidSettings с конфигом
// foreground-уведомления живёт здесь, а не в базовом geolocator.
// ignore: depend_on_referenced_packages
import 'package:geolocator_android/geolocator_android.dart';
import 'package:uuid/uuid.dart';

import '../db/track_repository.dart';
import '../models/cell_info.dart';
import '../telephony/telephony_service.dart';

/// Запись треков: GPS + телеметрия соты → локальная БД.
///
/// На Android стрим геолокации поднимается как foreground service
/// (постоянное уведомление) — запись продолжается при выключенном экране.
class RecordingService extends ChangeNotifier {
  RecordingService(this._telephony);

  final TelephonyService _telephony;
  final TrackRepository _repo = TrackRepository();

  static const _flushEvery = Duration(seconds: 10);
  static const _flushThreshold = 50; // порог batch-insert
  static const _minInterval = Duration(seconds: 15); // при неподвижности
  static const _minMoveM = 5.0;

  bool _recording = false;
  String? _trackId;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<CellInfo>>? _cellSub;
  Timer? _flushTimer;

  Position? _lastPos;
  Position? _lastSavedPos;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? _lastServingKey;
  int? _lastPci;
  int? _lastBand;
  String? _operator; // mcc-mnc обслуживающей соты

  int _pointCount = 0;
  double _distanceM = 0;
  final List<Map<String, Object?>> _buffer = [];

  bool get isRecording => _recording;
  int get pointCount => _pointCount;
  double get distanceM => _distanceM;

  Future<void> start() async {
    if (_recording) return;

    _trackId = const Uuid().v4();
    _pointCount = 0;
    _distanceM = 0;
    _buffer.clear();
    _lastPos = null;
    _lastSavedPos = null;
    _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastServingKey = null;
    _lastPci = null;
    _lastBand = null;
    _operator = null;

    await _repo.createTrack(_trackId!, DateTime.now());

    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Cellka — запись трека',
          notificationText: 'Идёт запись геолокации и параметров сети',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen((p) => _lastPos = p);

    _cellSub = _telephony.watchCells().listen(_onCells);
    _flushTimer = Timer.periodic(_flushEvery, (_) => _flush());

    _recording = true;
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_recording) return;
    _recording = false;

    await _posSub?.cancel();
    await _cellSub?.cancel();
    _flushTimer?.cancel();
    _posSub = null;
    _cellSub = null;
    _flushTimer = null;

    await _flush();
    final id = _trackId;
    if (id != null) {
      await _repo.finishTrack(
        id,
        DateTime.now(),
        _pointCount,
        _distanceM,
        _operator,
      );
    }
    _trackId = null;
    notifyListeners();
  }

  void _onCells(List<CellInfo> cells) {
    if (!_recording) return;
    final trackId = _trackId;
    if (trackId == null) return;

    CellInfo? serving;
    for (final c in cells) {
      if (c.registered) {
        serving = c;
        break;
      }
    }
    if (serving == null) return;

    if (serving.mcc != null && serving.mnc != null) {
      _operator = '${serving.mcc}-${serving.mnc.toString().padLeft(2, '0')}';
    }

    final key =
        '${serving.technology}:${serving.ci ?? serving.nci ?? serving.lac}';
    final handover = _lastServingKey != null && key != _lastServingKey;

    if (handover) {
      _repo.insertHandover(
        trackId,
        ts: DateTime.now(),
        fromKey: _lastServingKey!,
        toKey: key,
        fromPci: _lastPci,
        toPci: serving.pci,
        fromBand: _lastBand,
        toBand: serving.band,
        technology: serving.technology,
      );
    }

    final now = DateTime.now();
    final pos = _lastPos;

    var moved = double.infinity; // первую точку сохраняем всегда
    if (pos != null && _lastSavedPos != null) {
      moved = Geolocator.distanceBetween(
        _lastSavedPos!.latitude,
        _lastSavedPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
    }
    final dueByTime = now.difference(_lastSavedAt) >= _minInterval;

    // «Тише при неподвижности»: пишем только при handover,
    // сдвиге ≥ 5 м или если прошло ≥ 15 с с прошлой точки.
    if (!handover && moved < _minMoveM && !dueByTime) return;

    _buffer.add(measurementRow(trackId, serving, pos));
    _pointCount++;
    if (pos != null) {
      if (_lastSavedPos != null && moved.isFinite) _distanceM += moved;
      _lastSavedPos = pos;
    }
    _lastSavedAt = now;
    _lastServingKey = key;
    _lastPci = serving.pci;
    _lastBand = serving.band;

    if (_buffer.length >= _flushThreshold) _flush();
    notifyListeners();
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final rows = List<Map<String, Object?>>.from(_buffer);
    _buffer.clear();
    try {
      await _repo.insertMeasurements(rows);
    } catch (_) {
      _buffer.insertAll(0, rows); // вернуть в буфер при ошибке записи
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _cellSub?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }
}
