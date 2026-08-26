import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../db/track_repository.dart';

/// Опт-in отправка записанных замеров в OpenCelliD (measure/uploadJson).
/// Наполняет открытую базу (в т.ч. добавляет соты, которых там нет)
/// и «белеет» API-ключ: cell/get и getInArea доступны только
/// приложениям, которые делятся данными.
class OpenCelliDUploader {
  static const _apiKey =
      String.fromEnvironment('OPENCELLID_API_KEY', defaultValue: '');
  static const _host = 'opencellid.org';
  static const _timeout = Duration(seconds: 30);

  final TrackRepository _repo = TrackRepository();
  final HttpClient _http = HttpClient()..connectionTimeout = _timeout;

  bool get hasKey => _apiKey.isNotEmpty;

  /// Наша технология → act OpenCelliD.
  static const _actMap = {
    'GSM': 'GSM',
    'UMTS': 'UMTS',
    'LTE': 'LTE',
    'NR': 'NR',
    'CDMA': 'CDMA',
    'TDSCDMA': 'TDSCDMA',
  };

  /// Отправить все валидные точки трека одним JSON-файлом.
  /// true — сервер принял (HTTP 200).
  Future<bool> uploadTrack(String trackId) async {
    if (!hasKey) return false;
    final rows = await _repo.measurementsForUpload(trackId);
    final items = <Map<String, Object?>>[];
    for (final r in rows) {
      final m = _toMeasurement(r);
      if (m != null) items.add(m);
    }
    if (items.isEmpty) return false;

    try {
      final payload = utf8.encode(jsonEncode({'measurements': items}));
      final boundary = 'cellka${DateTime.now().millisecondsSinceEpoch}';
      final body = <int>[
        ...utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="key"\r\n\r\n'
          '$_apiKey\r\n',
        ),
        ...utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="datafile"; '
          'filename="measurements.json"\r\n'
          'Content-Type: application/json\r\n\r\n',
        ),
        ...payload,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      final req = await _http.postUrl(Uri.https(_host, '/measure/uploadJson'));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      req.add(body);
      final res = await req.close().timeout(_timeout);
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?>? _toMeasurement(Map<String, Object?> r) {
    final lat = (r['lat'] as num?)?.toDouble();
    final lon = (r['lon'] as num?)?.toDouble();
    final mcc = r['mcc'] as int?;
    final mnc = r['mnc'] as int?;
    final area = (r['tac'] as int?) ?? (r['lac'] as int?);
    final id = (r['ci'] as int?) ?? (r['nci'] as int?);
    final act = _actMap[r['technology']];
    // Фильтры OpenCelliD: lat/lon float и != 0.
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;
    if (mcc == null || mnc == null || area == null || id == null) return null;
    if (act == null) return null;

    final m = <String, Object?>{
      'lat': lat,
      'lon': lon,
      'mcc': mcc,
      'mnc': mnc,
      'cellid': id,
      'act': act,
    };
    final tech = r['technology'] as String?;
    if (tech == 'LTE' || tech == 'NR') {
      m['tac'] = area;
    } else {
      m['lac'] = area;
    }
    final signal = (r['rsrp'] as int?) ?? (r['dbm'] as int?);
    if (signal != null) m['signal'] = signal;
    final acc = (r['accuracy'] as num?)?.toDouble();
    if (acc != null && acc >= 0 && acc <= 35000) m['rating'] = acc;
    final speed = (r['speed'] as num?)?.toDouble();
    if (speed != null && speed >= 0 && speed <= 300) m['speed'] = speed;
    final bearing = (r['bearing'] as num?)?.toDouble();
    if (bearing != null && bearing >= 0 && bearing <= 360) {
      m['direction'] = bearing;
    }
    if ((tech == 'LTE' || tech == 'NR') && r['pci'] != null) {
      m['pci'] = r['pci'];
    }
    if (tech == 'UMTS' && r['psc'] != null) m['psc'] = r['psc'];
    if ((tech == 'LTE' || tech == 'GSM') && r['ta'] != null) {
      final ta = r['ta'] as int;
      if (ta >= 0 && ta <= 63) m['ta'] = ta;
    }
    try {
      m['measured_at'] =
          DateTime.parse(r['ts'] as String).millisecondsSinceEpoch;
    } catch (_) {}
    return m;
  }
}
