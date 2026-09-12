import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Встроенный спидтест: download (HTTP GET) + ping. Без зависимости.
class SpeedResult {
  final DateTime ts;
  final double downMbps;
  final double? pingMs;
  final String server;

  const SpeedResult({
    required this.ts,
    required this.downMbps,
    this.pingMs,
    required this.server,
  });
}

class SpeedTestService {
  SpeedTestService._();

  /// Быстрый замер: ping (TCP connect RTT) + download за [bytes] байт.
  static Future<SpeedResult> run({
    String host = 'speedtest.alwyzon.net',
    int port = 443,
    int bytes = 25 * 1024 * 1024, // 25 МБ — коротко и достаточно
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      // Ping: RTT TCP connect ×3, берём минимум.
      final pings = <double>[];
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        try {
          final sock = await Socket.connect(
            host,
            port,
            timeout: const Duration(seconds: 5),
          );
          await sock.close();
          pings.add(sw.elapsedMilliseconds.toDouble());
        } catch (_) {}
      }
      final ping = pings.isEmpty ? null : pings.reduce(min);

      // Download: стрим-ответ, считаем по реально принятым байтам.
      final uri = Uri.https(host, '/${bytes}bytes');
      final req = await client.getUrl(uri);
      final sw = Stopwatch()..start();
      final res = await req.close();
      var got = 0;
      await for (final chunk in res) {
        got += chunk.length;
        if (sw.elapsed > const Duration(seconds: 15)) break;
      }
      final sec = sw.elapsedMilliseconds / 1000;
      if (got == 0 || sec <= 0) {
        throw StateError('no data');
      }
      final mbps = (got * 8) / sec / 1e6;
      return SpeedResult(
        ts: DateTime.now(),
        downMbps: mbps,
        pingMs: ping,
        server: host,
      );
    } finally {
      client.close(force: true);
    }
  }
}
