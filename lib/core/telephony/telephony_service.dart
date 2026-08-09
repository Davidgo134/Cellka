import 'dart:async';

import 'package:flutter/services.dart';

import '../models/cell_info.dart';
import 'band_mapper.dart';

/// Информация об операторе и текущем типе сети.
class OperatorInfo {
  final String operatorName; // сетевое имя оператора ("MTS RUS")
  final String simOperatorName;
  final String networkOperator; // "25001" = MCC+MNC
  final String networkTypeName; // "LTE", "NR", ...
  final bool isRoaming;

  const OperatorInfo({
    required this.operatorName,
    required this.simOperatorName,
    required this.networkOperator,
    required this.networkTypeName,
    required this.isRoaming,
  });

  factory OperatorInfo.fromMap(Map<String, dynamic> map) => OperatorInfo(
        operatorName: map['operatorName'] as String? ?? '',
        simOperatorName: map['simOperatorName'] as String? ?? '',
        networkOperator: map['networkOperator'] as String? ?? '',
        networkTypeName: map['networkTypeName'] as String? ?? 'UNKNOWN',
        isRoaming: map['isRoaming'] as bool? ?? false,
      );
}

/// Сервис доступа к TelephonyManager через MethodChannel `cellka/telephony`.
/// Платформенная реализация — CellInfoPlugin.kt (Android).
class TelephonyService {
  static const _channel = MethodChannel('cellka/telephony');

  /// Одноразовый снимок всех видимых сот (обслуживающая + соседние).
  Future<List<CellInfo>> getAllCellInfo() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getAllCellInfo');
    return (raw ?? const [])
        .map((e) => CellInfo.fromMap(Map<String, dynamic>.from(e as Map)))
        .map(
          (c) => c.copyWith(
            band: BandMapper.bandFor(
              technology: c.technology,
              earfcn: c.earfcn,
              nrarfcn: c.nrarfcn,
              uarfcn: c.uarfcn,
              arfcn: c.arfcn,
            ),
          ),
        )
        .toList();
  }

  Future<OperatorInfo> getOperatorInfo() async {
    final raw =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('getOperatorInfo');
    return OperatorInfo.fromMap(Map<String, dynamic>.from(raw ?? const {}));
  }

  /// Polling-стрим: новый снимок сот каждые [interval].
  /// Ошибки канала (нет разрешений, радио выключено) дают пустой список —
  /// UI по нему показывает состояние «нет данных».
  Stream<List<CellInfo>> watchCells({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      var cells = const <CellInfo>[];
      try {
        cells = await getAllCellInfo();
      } on PlatformException {
        // ожидаемо при отсутствии разрешений — проглатываем
      }
      yield cells;
      await Future<void>.delayed(interval);
    }
  }
}
