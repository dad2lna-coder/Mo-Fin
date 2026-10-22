import 'dart:async';

import 'package:flutter/material.dart';

import '../../../direct_iptv/direct_iptv_recordings.dart';
import '../../../direct_iptv/models.dart';
import 'direct_guide_layout.dart';

/// Server recordings for one direct source. Deleting calls `DELETE rec/<id>`.
class DirectIptvRecordingsScreen extends StatefulWidget {
  final DirectIptvSource source;
  final DirectIptvRecordings recordings;
  final ValueChanged<List<DirectRecording>>? onChanged;

  const DirectIptvRecordingsScreen({
    super.key,
    required this.source,
    required this.recordings,
    this.onChanged,
  });

  @override
  State<DirectIptvRecordingsScreen> createState() =>
      _DirectIptvRecordingsScreenState();
}

class _DirectIptvRecordingsScreenState
    extends State<DirectIptvRecordingsScreen> {
  List<DirectRecording>? _items;
  String? _error;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.recordings.list(widget.source);
      if (!mounted) return;
      setState(() {
        _items = _sorted(items);
        _error = null;
      });
      widget.onChanged?.call(_items!);
    } on DirectIptvRecordingsException catch (error) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = error.message;
      });
      _snack(error.message);
    }
  }

  Future<void> _delete(DirectRecording item) async {
    if (_deleting.contains(item.id)) return;
    setState(() => _deleting.add(item.id));
    try {
      await widget.recordings.cancel(widget.source, item.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final recording in _items ?? const <DirectRecording>[])
            if (recording.id != item.id) recording,
        ];
        _deleting.remove(item.id);
      });
      widget.onChanged?.call(_items!);
      _snack('Recording cancelled');
    } on DirectIptvRecordingsException catch (error) {
      if (!mounted) return;
      setState(() => _deleting.remove(item.id));
      _snack(error.message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<DirectRecording> _sorted(List<DirectRecording> items) {
    final copy = List<DirectRecording>.of(items);
    copy.sort((a, b) {
      final rankA = a.status == 'recording'
          ? 0
          : a.status == 'scheduled'
          ? 1
          : 2;
      final rankB = b.status == 'recording'
          ? 0
          : b.status == 'scheduled'
          ? 1
          : 2;
      final rank = rankA.compareTo(rankB);
      if (rank != 0) return rank;
      return a.start.compareTo(b.start);
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: const Color(0xFF071422),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1A2E),
        foregroundColor: Colors.white,
        title: const Text('Recordings'),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'No recordings',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFF1E3A5F)),
              itemBuilder: (context, index) {
                final item = items[index];
                final start = item.start.toLocal();
                final deleting = _deleting.contains(item.id);
                return ListTile(
                  leading: Icon(
                    Icons.fiber_manual_record,
                    color: item.marksGuide
                        ? const Color(0xFFEF4444)
                        : Colors.white38,
                    size: 16,
                  ),
                  title: Text(
                    item.title.isEmpty ? item.tvgId : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${item.status} · ${formatGuideDate(start)} · '
                    '${formatGuideTime(start)} – ${formatGuideTime(item.end.toLocal())}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  trailing: deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Delete',
                          onPressed: () => unawaited(_delete(item)),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white70,
                          ),
                        ),
                );
              },
            ),
    );
  }
}
