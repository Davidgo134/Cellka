import 'package:flutter/material.dart';

import '../../core/db/track_repository.dart';
import 'export_sheet.dart';
import 'track_view_screen.dart';

/// Экран истории записанных треков.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = TrackRepository();
  List<TrackSummary>? _tracks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracks = await _repo.listTracks();
    if (mounted) setState(() => _tracks = tracks);
  }

  Future<void> _delete(TrackSummary t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить трек?'),
        content: Text(
          '${_fmtDateTime(t.startedAt)} · ${t.pointCount} точек · '
          '${_fmtDistance(t.distanceM)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.deleteTrack(t.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История треков')),
      body: _tracks == null
          ? const Center(child: CircularProgressIndicator())
          : _tracks!.isEmpty
              ? const Center(
                  child: Text(
                    'Треков пока нет.\nНажми красную кнопку записи на карте.',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _tracks!.length,
                    itemBuilder: (context, i) {
                      final t = _tracks![i];
                      return Dismissible(
                        key: ValueKey(t.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.redAccent,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await _delete(t);
                          return false; // список перечитывается сам
                        },
                        child: ListTile(
                          leading: const Icon(Icons.route),
                          title: Text(_fmtDateTime(t.startedAt)),
                          subtitle: Text(
                            '${_fmtDistance(t.distanceM)} · ${t.pointCount} точек'
                            '${t.operator != null ? ' · ${t.operator}' : ''}'
                            '${_fmtDuration(t)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.ios_share, size: 20),
                            tooltip: 'Экспорт',
                            onPressed: () => showExportSheet(context, t),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TrackViewScreen(track: t),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _fmtDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} км' : '${m.round()} м';

  String _fmtDuration(TrackSummary t) {
    final end = t.endedAt;
    if (end == null) return '';
    final mins = end.difference(t.startedAt).inMinutes;
    return mins > 0 ? ' · $mins мин' : '';
  }
}
