import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../db/track_repository.dart';

/// Опт-in отправка записанных замеров в OpenCelliD.
/// Основной путь — bulk `measure/uploadJson`; при 403 — фолбэк на
/// точечный `measure/add` (он не требует белого ключа).
class OpenCelliDUploader {
  static const _apiKey =
      String.fromEnvironment('OPENCELLID_API_KEY', defaultValue: '');
  static const _host = 'opencellid.org';
  static const _timeout = Duration(seconds: 30);

  final TrackRepository _repo = TrackRepository();
  final HttpClient _http = HttpClient();

  bool get hasKey => _apiKey.isNotEmpty;

  static const _actMap = {
    'GSM': 'GSM',
    'UMTS': 'UMTS',
    'LTE': 'LTE',
    'NR': 'NR',
    'CDMA': 'CDMA',
    'TDSCDMA': 'TDSCDMA',
  };

  /// null — успех; иначе человекочитаемая ошибка для UI.
  Future<String?> uploadTrack(String trackId) async {
    if (!hasKey) return 'нет ключа OpenCelliD';
    final rows = await _repo.measurementsForUpload(trackId);
    final items = <Map<String, Object?>>[];
    for (final r in rows) {
      final m = _toMeasurement(r);
      if (m != null) items.add(m);
    }
    if (items.isEmpty) return 'нет валидных точек с координатами';

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
      final code = res.statusCode;
      final text = await res.transform(utf8.decoder).join().timeout(_timeout);
      if (code == 200) return null;
      if (code == 403) {
        // Белый ключ нужен для чтения, но вклад принимают и без него —
        // пробуем точечный measure/add для первых 20 точек.
        final ok = await _addSingle(items);
        return ok ? null : '403: ключ отклонён и на measure/add';
      }
      final short = text.length > 60 ? '${text.substring(0, 60)}…' : text;
      return 'HTTP $code: $short';
    } on TimeoutException {
      return 'таймаут (проверь VPN/сеть)';
    } catch (e) {
      return '$e';
    }
  }

  /// Точечная отправка — эндпоинт вклада, не требующий белого ключа.
  Future<bool> _addSingle(List<Map<String, Object?>> items) async {
    var ok = 0;
    final limit = items.length > 20 ? 20 : items.length;
    for (var i = 0; i < limit; i++) {
      try {
        final params = <String, String>{'key': _apiKey};
        items[i].forEach((k, v) {
          if (v != null) params[k] = '$v';
        });
        final req = await _http.getUrl(Uri.https(_host, '/measure/add', params));
        final res = await req.close().timeout(const Duration(seconds: 10));
        await res.drain<void>();
        if (res.statusCode == 200) ok++;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (_) {}
    }
    return ok > 0;
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
