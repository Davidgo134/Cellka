import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/track_repository.dart';
import '../../core/export/export_service.dart';

/// Bottom sheet выбора формата экспорта трека + системный Share Sheet.
void showExportSheet(BuildContext context, TrackSummary track) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('GeoJSON (.geojson)'),
            subtitle: const Text('Линия маршрута + точки с параметрами сети'),
            onTap: () => _run(context, track, geo: true),
          ),
          ListTile(
            leading: const Icon(Icons.table_rows_outlined),
            title: const Text('CSV (.csv)'),
            subtitle: const Text('Все поля замеров — для таблиц и скриптов'),
            onTap: () => _run(context, track, geo: false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _run(
  BuildContext context,
  TrackSummary track, {
  required bool geo,
}) async {
  Navigator.pop(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final service = ExportService();
    final file = geo
        ? await service.exportGeoJson(track)
        : await service.exportCsv(track);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Cellka трек ${_fmt(track.startedAt)}',
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Экспорт не удался: $e')));
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
