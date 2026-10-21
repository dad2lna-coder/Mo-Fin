import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../direct_iptv/direct_guide.dart';
import '../../../direct_iptv/direct_iptv_catalog.dart';
import '../../../direct_iptv/models.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../navigation/destinations.dart';
import 'direct_iptv_settings_screen.dart';

/// Channel list for a Dispatcharr or raw M3U source. Now and next come from
/// the cached XMLTV. Playback reuses the existing live TV player.
class DirectIptvGuideScreen extends StatefulWidget {
  const DirectIptvGuideScreen({super.key});

  @override
  State<DirectIptvGuideScreen> createState() => _DirectIptvGuideScreenState();
}

class _DirectIptvGuideScreenState extends State<DirectIptvGuideScreen> {
  final _search = TextEditingController();
  late final DirectIptvCatalog _catalog;
  String? _sourceId;
  String? _group;

  @override
  void initState() {
    super.initState();
    _catalog = GetIt.instance<DirectIptvCatalog>();
    _catalog.addListener(_onCatalog);
    _search.addListener(_onSearch);
    if (_catalog.loaded) _selectDefaultSource();
    unawaited(
      _catalog.ensureLoaded().then((_) async {
        if (!mounted) return;
        setState(_selectDefaultSource);
        await _catalog.refreshStale();
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onCatalog() {
    if (mounted) setState(_selectDefaultSource);
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  void _selectDefaultSource() {
    final enabled = _catalog.sources.where((source) => source.enabled);
    if (_sourceId != null && enabled.any((source) => source.id == _sourceId)) {
      return;
    }
    _sourceId = enabled.isEmpty ? null : enabled.first.id;
    _group = null;
  }

  DirectIptvSource? get _source {
    final id = _sourceId;
    if (id == null) return null;
    return _catalog.sourceById(id);
  }

  List<DirectChannel> get _channels {
    final source = _source;
    if (source == null) return const [];
    final snapshot = _catalog.snapshotFor(source.id);
    if (snapshot == null) return const [];
    final query = _search.text.trim().toLowerCase();
    final channels = snapshot.channels.where((channel) {
      if (_group != null && channel.group != _group) return false;
      if (query.isEmpty) return true;
      final number = channel.number ?? '';
      return channel.name.toLowerCase().contains(query) ||
          number.toLowerCase().contains(query);
    }).toList();
    channels.sort(_compareChannels);
    return channels;
  }

  List<String> get _groups {
    final source = _source;
    if (source == null) return const [];
    final names = <String>{
      for (final channel in _catalog.snapshotFor(source.id)?.channels ?? const [])
        ?channel.group,
    }.toList()..sort();
    return names;
  }

  int _compareChannels(DirectChannel a, DirectChannel b) {
    final left = double.tryParse(a.number ?? '');
    final right = double.tryParse(b.number ?? '');
    if (left != null && right != null) return left.compareTo(right);
    if (left != null) return -1;
    if (right != null) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> _openSettings({DirectIptvSource? source}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DirectIptvSettingsScreen(editSourceId: source?.id),
      ),
    );
  }

  void _play(DirectChannel channel) {
    final source = _source;
    if (source == null) return;
    final visible = _channels;
    final channels = [
      for (final item in visible) guideChannelFromDirect(item, source),
    ];
    final index = visible.indexWhere((item) => item.id == channel.id);
    context.push(
      Destinations.liveTvPlayer,
      extra: {
        'channels': channels,
        'startIndex': index < 0 ? 0 : index,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final channels = _channels;
    final error = source == null ? null : _catalog.errorFor(source.id);
    final refreshing = source != null && _catalog.isRefreshing(source.id);
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: const Text('Direct IPTV'),
        actions: [
          if (source != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: refreshing
                  ? null
                  : () => unawaited(_catalog.refresh(source.id, force: true)),
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'Sources',
            onPressed: () => unawaited(_openSettings()),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: !_catalog.loaded
          ? const Center(child: CircularProgressIndicator())
          : _catalog.sources.isEmpty
          ? _EmptySources(
              onAdd: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const DirectIptvSettingsScreen(createOnOpen: true),
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'These channels play directly and skip the server tuner.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ),
                if (_catalog.sources.where((item) => item.enabled).length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: source?.id,
                      dropdownColor: const Color(0xFF101822),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        for (final item in _catalog.sources)
                          if (item.enabled)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                      ],
                      onChanged: (id) => setState(() {
                        _sourceId = id;
                        _group = null;
                      }),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search channels',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (_groups.isNotEmpty)
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: const Text('All'),
                            selected: _group == null,
                            onSelected: (_) => setState(() => _group = null),
                          ),
                        ),
                        for (final group in _groups)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(group),
                              selected: _group == group,
                              onSelected: (_) => setState(() => _group = group),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(error, style: const TextStyle(color: Colors.orangeAccent)),
                  ),
                Expanded(
                  child: channels.isEmpty
                      ? const Center(
                          child: Text(
                            'No channels yet',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: channels.length,
                          itemBuilder: (context, index) {
                            final channel = channels[index];
                            return _ChannelTile(
                              channel: channel,
                              now: _catalog.programOnNow(channel.id)?.title,
                              next: _catalog.upNext(channel.id)?.title,
                              autofocus: index == 0,
                              onTap: () => _play(channel),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _EmptySources extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptySources({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.satellite_alt, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              'Add a Dispatcharr server or an M3U playlist',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add source')),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  final DirectChannel channel;
  final String? now;
  final String? next;
  final bool autofocus;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.now,
    required this.next,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final subtitle = [
      if ((widget.now ?? '').isNotEmpty) widget.now,
      if ((widget.next ?? '').isNotEmpty) 'Next: ${widget.next}',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) => handleOneShotSelect(event, widget.onTap),
        child: Material(
          color: _focused ? const Color(0xFF1C3148) : const Color(0xFF101822),
          borderRadius: AppRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      channel.number ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Logo(url: channel.logoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? url;

  const _Logo({required this.url});

  @override
  Widget build(BuildContext context) {
    final logo = url;
    return SizedBox(
      width: 48,
      height: 36,
      child: logo == null || logo.isEmpty
          ? const Icon(Icons.tv, color: Colors.white38)
          : Image.network(
              logo,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.tv, color: Colors.white38),
            ),
    );
  }
}
