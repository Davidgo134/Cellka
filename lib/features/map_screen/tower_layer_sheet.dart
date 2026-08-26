import 'package:flutter/material.dart';

import '../../core/towers/towers_repository.dart';

/// Bottom sheet слоя вышек: мастер-переключатель, чекбоксы операторов,
/// загрузка/обновление базы с прогрессом и текстом ошибки.
class TowerLayerSheet extends StatefulWidget {
  final bool enabled;
  final Set<int> selectedMncs;
  final int towersCount;
  final DateTime? loadedAt;
  final void Function(bool enabled, Set<int> mncs) onChanged;
  final Future<int> Function(void Function(String) onProgress) onDownload;

  const TowerLayerSheet({
    super.key,
    required this.enabled,
    required this.selectedMncs,
    required this.towersCount,
    required this.loadedAt,
    required this.onChanged,
    required this.onDownload,
  });

  @override
  State<TowerLayerSheet> createState() => _TowerLayerSheetState();
}

class _TowerLayerSheetState extends State<TowerLayerSheet> {
  late bool _enabled;
  late Set<int> _mncs;
  bool _downloading = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _mncs = Set.of(widget.selectedMncs);
  }

  void _apply() => widget.onChanged(_enabled, _mncs);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Показывать вышки'),
              subtitle: const Text('При зуме от 12 и ближе'),
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                _apply();
              },
            ),
            const Divider(),
            const Text(
              'ОПЕРАТОРЫ',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final op in kRuOperators)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(op.name),
                secondary: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: op.color,
                    shape: BoxShape.circle,
                  ),
                ),
                value: _mncs.contains(op.mnc),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _mncs.add(op.mnc);
                    } else {
                      _mncs.remove(op.mnc);
                    }
                  });
                  _apply();
                },
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.towersCount == 0
                        ? 'База вышек РФ не загружена'
                        : 'База: ${widget.towersCount} вышек'
                        '${widget.loadedAt != null ? '\nОбновлена: ${_fmtDate(widget.loadedAt!)}' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _downloading ? null : _runDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(widget.towersCount == 0 ? 'Загрузить' : 'Обновить'),
                ),
              ],
            ),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text(
                _progress!,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Данные вышек © OpenCelliD contributors, CC BY-SA 4.0',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDownload() async {
    setState(() {
      _downloading = true;
      _progress = 'Подключение…';
    });
    try {
      await widget.onDownload((s) {
        if (mounted) setState(() => _progress = s);
      });
    } catch (e) {
      if (mounted) {
        var msg = e.toString();
        if (msg.length > 140) msg = '${msg.substring(0, 140)}…';
        setState(() => _progress = 'Ошибка: $msg');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
