import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/mofin_brand.dart';

import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../direct_iptv/direct_guide.dart';
import '../../../direct_iptv/direct_iptv_catalog.dart';
import '../../../direct_iptv/direct_iptv_recordings.dart';
import '../../../direct_iptv/models.dart';
import '../../../direct_iptv/playlist_parse.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../navigation/destinations.dart';
import 'direct_guide_layout.dart';
import 'direct_guide_source.dart';
import 'direct_iptv_preview.dart';
import 'direct_iptv_recordings_screen.dart';
import 'direct_iptv_settings_screen.dart';

const _navy = Color(0xFF071422);
const _navyRaised = Color(0xFF0C1A2E);
const _card = Color(0xFF14304E);
const _cardLive = Color(0xFF1A4068);
const _cardPast = Color(0xFF10263C);
const _accent = Color(0xFF3B82F6);
const _nowLine = Color(0xFF60A5FA);

/// Dispatcharr, raw M3U, and Pluto guide. Groups from the playlist replace
/// the old chips. OK on a program opens the existing full-screen player.
class DirectIptvGuideScreen extends StatefulWidget {
  const DirectIptvGuideScreen({super.key});

  @override
  State<DirectIptvGuideScreen> createState() => _DirectIptvGuideScreenState();
}

class _DirectIptvGuideScreenState extends State<DirectIptvGuideScreen> {
  final _searchNode = FocusNode(debugLabel: 'direct-guide-search');
  final _sourceNode = FocusNode(debugLabel: 'direct-guide-source');
  final _recordingsNode = FocusNode(debugLabel: 'direct-guide-recordings');
  final _settingsNode = FocusNode(debugLabel: 'direct-guide-settings');
  final _refreshNode = FocusNode(debugLabel: 'direct-guide-refresh');
  final _gridNode = FocusNode(debugLabel: 'direct-guide-grid');
  final _selectKeyHandler = LongPressSelectKeyHandler();
  final _recorder = DirectIptvRecordings();
  final Map<int, FocusNode> _groupNodes = {};
  final _rowsScroll = ScrollController();

  late final DirectIptvCatalog _catalog;
  String? _sourceId;
  String? _group;
  String _query = '';
  DirectGuideCursor _cursor = const DirectGuideCursor(row: 0);
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _previewDebounce;
  String? _previewUrl;
  Map<String, String> _previewHeaders = const {};
  bool _suspendPreview = false;
  bool _didAutoFocus = false;
  double _rowExtent = 68;
  List<DirectProgram>? _indexedFrom;
  Map<String, List<DirectProgram>> _programIndex = const {};
  List<DirectRecording> _recordings = const [];
  String? _recordingsSourceId;
  String? _savedSourceId;
  bool _lastSourceLoaded = false;

  @override
  void initState() {
    super.initState();
    _catalog = GetIt.instance<DirectIptvCatalog>();
    _catalog.addListener(_onCatalog);
    if (_catalog.loaded) _selectDefaultSource();
    unawaited(_loadLastSource());
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
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
    _clock?.cancel();
    _previewDebounce?.cancel();
    _catalog.removeListener(_onCatalog);
    _rowsScroll.dispose();
    _searchNode.dispose();
    _sourceNode.dispose();
    _recordingsNode.dispose();
    _settingsNode.dispose();
    _refreshNode.dispose();
    _gridNode.dispose();
    _selectKeyHandler.dispose();
    for (final node in _groupNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onCatalog() {
    _indexedFrom = null;
    if (!mounted) return;
    setState(_selectDefaultSource);
    _watchRecordings();
    _schedulePreview();
  }

  void _selectDefaultSource() {
    final enabled = _catalog.sources.where((source) => source.enabled);
    if (_sourceId != null && enabled.any((source) => source.id == _sourceId)) {
      return;
    }
    if (!_lastSourceLoaded) return;
    final next = chooseDefaultDirectSource(
      sources: _catalog.sources,
      savedId: _savedSourceId,
    );
    if (next == _sourceId) return;
    _sourceId = next;
    _group = null;
    _cursor = const DirectGuideCursor(row: 0);
    _indexedFrom = null;
  }

  Future<void> _loadLastSource() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _savedSourceId = prefs.getString(directIptvLastSourceKey);
    _lastSourceLoaded = true;
    setState(_selectDefaultSource);
  }

  Future<void> _rememberLastSource(String id) async {
    _savedSourceId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(directIptvLastSourceKey, id);
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
    return visibleDirectChannels(
      channels: snapshot.channels,
      group: _group,
      query: _query,
    );
  }

  List<String> get _groups {
    final source = _source;
    if (source == null) return const [];
    return directGuideGroups(
      _catalog.snapshotFor(source.id)?.channels ?? const [],
    );
  }

  List<DirectProgram> _programsFor(String channelId) {
    final programs =
        _catalog.snapshotFor(_sourceId ?? '')?.programs ?? const [];
    if (!identical(programs, _indexedFrom)) {
      _indexedFrom = programs;
      _programIndex = indexDirectPrograms(programs);
    }
    return _programIndex[channelId] ?? const [];
  }

  FocusNode _nodeForGroup(int index) {
    return _groupNodes.putIfAbsent(
      index,
      () => FocusNode(debugLabel: 'direct-guide-group-$index'),
    );
  }

  int _selectedGroupIndex(List<String> groups) {
    if (_group == null) return 0;
    final index = groups.indexOf(_group!);
    return index < 0 ? 0 : index + 1;
  }

  DirectGuideCursor _clampedCursor(List<DirectChannel> channels) {
    if (channels.isEmpty) return const DirectGuideCursor(row: 0);
    return DirectGuideCursor(
      row: _cursor.row.clamp(0, channels.length - 1),
      programId: _cursor.programId,
    );
  }

  List<DirectGuideBlock> _blocksFor(
    List<DirectChannel> channels,
    DirectGuideWindow window,
    int row,
  ) {
    if (channels.isEmpty) {
      return directGuideBlocks(programs: const [], window: window);
    }
    final clamped = row.clamp(0, channels.length - 1);
    return directGuideBlocks(
      programs: _programsFor(channels[clamped].id),
      window: window,
    );
  }

  DirectChannel? _channelAt(List<DirectChannel> channels, int row) {
    if (channels.isEmpty) return null;
    return channels[row.clamp(0, channels.length - 1)];
  }

  void _selectGroup(String? group) {
    if (_group == group) return;
    setState(() {
      _group = group;
      _cursor = const DirectGuideCursor(row: 0);
    });
    _schedulePreview();
    _revealRow(0);
  }

  void _applyCursor(DirectGuideCursor next) {
    if (next.row == _cursor.row && next.programId == _cursor.programId) {
      return;
    }
    setState(() => _cursor = next);
    _schedulePreview();
    _revealRow(next.row);
  }

  void _revealRow(int row) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_rowsScroll.hasClients) return;
      final height = _rowExtent;
      final target = row * height;
      final position = _rowsScroll.position;
      final start = position.pixels;
      final end = start + position.viewportDimension;
      double? next;
      if (target < start) {
        next = target;
      } else if (target + height > end) {
        next = target + height - position.viewportDimension;
      }
      if (next == null) return;
      unawaited(
        _rowsScroll.animateTo(
          next.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _focusGrid() {
    if (_channels.isEmpty) return;
    _gridNode.requestFocus();
  }

  KeyEventResult _sidebarArrows(
    KeyEvent event, {
    FocusNode? onUp,
    FocusNode? onDown,
  }) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isLeftKey) return KeyEventResult.handled;
    if (key.isRightKey) {
      _focusGrid();
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      onUp?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      onDown?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _schedulePreview() {
    final channel = _channelAt(_channels, _cursor.row);
    final id = channel?.id;
    _previewDebounce?.cancel();
    if (_suspendPreview) return;
    _previewDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _suspendPreview) return;
      final current = _channelAt(_channels, _cursor.row);
      if (current?.id != id) return;
      final source = _source;
      final url = current?.streamUrl;
      final headers = source == null || current == null
          ? const <String, String>{}
          : headersForPlayback(
              headers: authHeaders(source),
              streamUri: Uri.tryParse(current.streamUrl) ?? Uri(),
              credentialHost: Uri.tryParse(source.baseUrl.trim())?.host,
            );
      if (url == _previewUrl) return;
      setState(() {
        _previewUrl = url;
        _previewHeaders = headers;
      });
    });
  }

  Future<void> _suspendAndRun(Future<void> Function() action) async {
    _previewDebounce?.cancel();
    if (mounted) {
      setState(() {
        _suspendPreview = true;
        _previewUrl = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _suspendPreview = false);
        _schedulePreview();
      }
    }
  }

  Future<void> _openSettings({DirectIptvSource? source}) {
    return _suspendAndRun(() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DirectIptvSettingsScreen(editSourceId: source?.id),
        ),
      );
    });
  }

  Future<void> _play(DirectChannel channel) {
    return _suspendAndRun(() async {
      final source = _source;
      if (source == null) return;
      final visible = _channels;
      final channels = [
        for (final item in visible) guideChannelFromDirect(item, source),
      ];
      final index = visible.indexWhere((item) => item.id == channel.id);
      await context.push(
        Destinations.liveTvPlayer,
        extra: {'channels': channels, 'startIndex': index < 0 ? 0 : index},
      );
    });
  }

  Future<void> _search() async {
    final controller = TextEditingController(text: _query);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _navyRaised,
        title: const Text(
          'Search channels',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Name or number',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _query = result.trim();
      _cursor = const DirectGuideCursor(row: 0);
    });
    _schedulePreview();
  }

  Future<void> _pickSource() async {
    final enabled = [
      for (final source in _catalog.sources)
        if (source.enabled) source,
    ];
    if (enabled.length < 2) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _navyRaised,
        title: const Text('Source', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in enabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  autofocus: source.id == _sourceId,
                  onPressed: () => Navigator.pop(context, source.id),
                  child: Text(source.name),
                ),
              ),
          ],
        ),
      ),
    );
    if (id == null || !mounted) return;
    setState(() {
      _sourceId = id;
      _group = null;
      _cursor = const DirectGuideCursor(row: 0);
      _indexedFrom = null;
    });
    unawaited(_rememberLastSource(id));
    _watchRecordings();
    _schedulePreview();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _watchRecordings() {
    final id = _sourceId;
    if (id == _recordingsSourceId) return;
    _recordingsSourceId = id;
    _recordings = const [];
    if (mounted) setState(() {});
    if (id != null) unawaited(_loadRecordings());
  }

  Future<void> _loadRecordings() async {
    final source = _source;
    final id = source?.id;
    if (source == null) return;
    try {
      final list = await _recorder.list(source);
      if (!mounted || _source?.id != id) return;
      setState(() => _recordings = list);
    } on DirectIptvRecordingsException {
      // A missing recordings route stays quiet until the user records.
    }
  }

  DirectProgram? _focusedProgram(
    List<DirectChannel> channels,
    DirectGuideWindow window,
  ) {
    if (channels.isEmpty) return null;
    final cursor = _clampedCursor(channels);
    final blocks = _blocksFor(channels, window, cursor.row);
    if (blocks.isEmpty) return null;
    final index = directGuideBlockIndex(blocks, cursor.programId, _now);
    return blocks[index].program;
  }

  bool _programMarked(DirectChannel channel, DirectProgram? program) {
    if (program == null) return false;
    return directRecordingFor(
          recordings: _recordings,
          channel: channel,
          program: program,
        ) !=
        null;
  }

  Future<void> _recordFocused() async {
    final channels = _channels;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final window = directGuideWindow(_now, halfHours: compact ? 4 : 8);
    final channel = _channelAt(channels, _clampedCursor(channels).row);
    final program = _focusedProgram(channels, window);
    if (channel == null || program == null) {
      _snack('No program to record');
      return;
    }
    await _toggleRecord(channel, program);
  }

  Future<void> _toggleRecord(
    DirectChannel channel,
    DirectProgram program,
  ) async {
    final source = _source;
    if (source == null) return;
    final existing = directRecordingFor(
      recordings: _recordings,
      channel: channel,
      program: program,
    );
    try {
      if (existing != null) {
        await _recorder.cancel(source, existing.id);
        if (!mounted) return;
        setState(() {
          _recordings = [
            for (final item in _recordings)
              if (item.id != existing.id) item,
          ];
        });
        _snack('Recording cancelled');
      } else {
        final tvg = channel.tvgId?.trim() ?? '';
        if (tvg.isEmpty) {
          _snack('This channel has no guide id');
          return;
        }
        final created = await _recorder.schedule(
          source: source,
          tvgId: tvg,
          title: program.title,
          start: program.start,
          end: program.end,
        );
        if (!mounted) return;
        setState(() => _recordings = [..._recordings, created]);
        _snack('Recording scheduled');
      }
      await _loadRecordings();
    } on DirectIptvRecordingsException catch (error) {
      if (mounted) _snack(error.message);
    }
  }

  Future<void> _openRecordings() {
    return _suspendAndRun(() async {
      final source = _source;
      if (source == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DirectIptvRecordingsScreen(
            source: source,
            recordings: _recorder,
            onChanged: (list) {
              if (!mounted || _source?.id != source.id) return;
              setState(() => _recordings = list);
            },
          ),
        ),
      );
      await _loadRecordings();
    });
  }

  Future<void> _refreshGuide() async {
    final source = _source;
    if (source == null || _catalog.isRefreshing(source.id)) return;
    final result = await _catalog.refresh(source.id, force: true);
    if (!mounted || result == null) return;
    _snack(result.message);
    unawaited(_loadRecordings());
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    _rowExtent = compact ? 56 : 68;
    if (!_catalog.loaded) {
      return const Scaffold(
        backgroundColor: _navy,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_catalog.sources.isEmpty) {
      return Scaffold(
        backgroundColor: _navy,
        body: _EmptySources(
          onAdd: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const DirectIptvSettingsScreen(createOnOpen: true),
              ),
            ),
          ),
        ),
      );
    }

    final channels = _channels;
    final groups = _groups;
    final window = directGuideWindow(_now, halfHours: compact ? 4 : 8);
    final cursor = _clampedCursor(channels);
    final channel = _channelAt(channels, cursor.row);
    final blocks = channel == null
        ? const <DirectGuideBlock>[]
        : _blocksFor(channels, window, cursor.row);
    final blockIndex = blocks.isEmpty
        ? 0
        : directGuideBlockIndex(blocks, cursor.programId, _now);
    final program = blocks.isEmpty ? null : blocks[blockIndex].program;
    final source = _source;
    final error = source == null ? null : _catalog.errorFor(source.id);
    final refreshing = source != null && _catalog.isRefreshing(source.id);

    if (!_didAutoFocus && channels.isNotEmpty) {
      _didAutoFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _gridNode.requestFocus();
        _schedulePreview();
      });
    }

    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: compact ? 118 : 220,
              child: _sidebar(
                compact: compact,
                groups: groups,
                multipleSources:
                    _catalog.sources.where((item) => item.enabled).length > 1,
                refreshing: refreshing,
              ),
            ),
            const VerticalDivider(width: 1, color: Color(0xFF1E3A5F)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 16,
                  12,
                  compact ? 8 : 16,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(compact: compact, channel: channel, program: program),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    if (_query.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _query = '';
                              _cursor = const DirectGuideCursor(row: 0);
                            });
                            _schedulePreview();
                          },
                          child: Text('Clear search “$_query”'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _grid(
                        compact: compact,
                        channels: channels,
                        window: window,
                        cursor: cursor,
                        refreshing: refreshing,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar({
    required bool compact,
    required List<String> groups,
    required bool multipleSources,
    required bool refreshing,
  }) {
    final lastGroup = groups.length;
    return ColoredBox(
      color: _navyRaised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, compact ? 8 : 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  MoFinBrand(
                    width: compact ? 22 : 28,
                    height: compact ? 22 : 28,
                    wordmark: false,
                    onDark: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MoFin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 14 : 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (multipleSources)
              _SidebarTile(
                focusNode: _sourceNode,
                label: _source?.name ?? 'Source',
                icon: Icons.dns_outlined,
                onSelect: () => unawaited(_pickSource()),
                onKey: (event) => _sidebarArrows(event, onDown: _searchNode),
              ),
            _SidebarTile(
              focusNode: _searchNode,
              selected: _query.isNotEmpty,
              label: _query.isEmpty ? 'Search' : _query,
              icon: Icons.search,
              onSelect: () => unawaited(_search()),
              onKey: (event) => _sidebarArrows(
                event,
                onUp: multipleSources ? _sourceNode : null,
                onDown: _nodeForGroup(0),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i <= groups.length; i++)
                    _SidebarTile(
                      focusNode: _nodeForGroup(i),
                      scrollOnFocus: true,
                      selected: i == 0
                          ? _group == null
                          : _group == groups[i - 1],
                      label: i == 0 ? 'All Channels' : groups[i - 1],
                      onFocused: () =>
                          _selectGroup(i == 0 ? null : groups[i - 1]),
                      onSelect: () =>
                          _selectGroup(i == 0 ? null : groups[i - 1]),
                      onKey: (event) => _sidebarArrows(
                        event,
                        onUp: i == 0 ? _searchNode : _nodeForGroup(i - 1),
                        onDown: i == lastGroup
                            ? _recordingsNode
                            : _nodeForGroup(i + 1),
                      ),
                    ),
                ],
              ),
            ),
            _SidebarTile(
              focusNode: _recordingsNode,
              label: 'Recordings',
              icon: Icons.video_library_outlined,
              onSelect: () => unawaited(_openRecordings()),
              onKey: (event) => _sidebarArrows(
                event,
                onUp: _nodeForGroup(lastGroup),
                onDown: _settingsNode,
              ),
            ),
            _SidebarTile(
              focusNode: _settingsNode,
              label: 'Settings',
              icon: Icons.settings,
              onSelect: () => unawaited(_openSettings()),
              onKey: (event) => _sidebarArrows(
                event,
                onUp: _recordingsNode,
                onDown: _refreshNode,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _refreshButton(refreshing),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatGuideTime(_now),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 16 : 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        formatGuideDate(_now),
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: compact ? 11 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshButton(bool refreshing) {
    final source = _source;
    return _IconFocusButton(
      focusNode: _refreshNode,
      icon: Icons.refresh,
      busy: refreshing,
      onKey: (event) => _sidebarArrows(event, onUp: _settingsNode),
      onPressed: source == null || refreshing
          ? null
          : () => unawaited(_refreshGuide()),
    );
  }

  Widget _hero({
    required bool compact,
    required DirectChannel? channel,
    required DirectProgram? program,
  }) {
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: compact ? double.infinity : 300,
        height: compact ? 148 : 188,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Center(child: _Logo(url: channel?.logoUrl, width: 72, height: 48)),
            if (!_suspendPreview &&
                _previewUrl != null &&
                _previewUrl!.isNotEmpty)
              ExcludeFocus(
                child: IgnorePointer(
                  child: DirectIptvPreviewPlayer(
                    streamUrl: _previewUrl,
                    headers: _previewHeaders,
                  ),
                ),
              ),
            if (channel != null)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final title = program?.title ?? 'No program information';
    final episode = program?.episodeTitle;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Logo(url: channel?.logoUrl, width: 48, height: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                channel == null
                    ? 'No channel'
                    : [
                        if ((channel.number ?? '').isNotEmpty) channel.number,
                        channel.name,
                      ].join('   '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 16 : 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 15 : 18,
          ),
        ),
        if (episode != null && episode.isNotEmpty && episode != title)
          Text(
            episode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (program != null) _TypeTag(label: directProgramTypeTag(program)),
            Text(
              program == null ? '' : directProgramTimeRange(program),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (program != null && channel != null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => unawaited(_recordFocused()),
                icon: Icon(
                  Icons.fiber_manual_record,
                  size: 14,
                  color: _programMarked(channel, program)
                      ? const Color(0xFFEF4444)
                      : Colors.white70,
                ),
                label: Text(
                  _programMarked(channel, program) ? 'Cancel' : 'Record',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: program == null ? 0 : directProgramProgress(program, _now),
            minHeight: 4,
            backgroundColor: Colors.white12,
            color: _accent,
          ),
        ),
        if ((program?.overview ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            program!.overview!,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ],
    );

    final band = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: channel == null ? null : () => unawaited(_play(channel)),
                child: preview,
              ),
              const SizedBox(height: 10),
              details,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: channel == null ? null : () => unawaited(_play(channel)),
                child: preview,
              ),
              const SizedBox(width: 16),
              Expanded(child: details),
            ],
          );
    return band;
  }

  Widget _grid({
    required bool compact,
    required List<DirectChannel> channels,
    required DirectGuideWindow window,
    required DirectGuideCursor cursor,
    required bool refreshing,
  }) {
    final channelCol = compact ? 96.0 : 188.0;
    final headerHeight = compact ? 26.0 : 30.0;
    return Focus(
      focusNode: _gridNode,
      onKeyEvent: (node, event) => _onGridKey(
        event,
        channels: channels,
        window: window,
        groups: _groups,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timeline = math.max(1.0, constraints.maxWidth - channelCol);
          final fraction = directGuideFraction(window, _now);
          return Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: Row(
                      children: [
                        SizedBox(width: channelCol),
                        Expanded(child: _timeHeader(window, timeline)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: channels.isEmpty
                        ? Center(
                            child: Text(
                              refreshing
                                  ? 'Loading channels…'
                                  : 'No channels yet',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            controller: _rowsScroll,
                            padding: EdgeInsets.zero,
                            itemExtent: _rowExtent,
                            itemCount: channels.length,
                            itemBuilder: (context, index) {
                              return _guideRow(
                                index: index,
                                channel: channels[index],
                                channels: channels,
                                window: window,
                                timeline: timeline,
                                channelCol: channelCol,
                                selected: index == cursor.row,
                                programId: index == cursor.row
                                    ? cursor.programId
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
              if (channels.isNotEmpty)
                Positioned(
                  left: channelCol + timeline * fraction,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: SizedBox(
                        width: 36,
                        child: Column(
                          children: [
                            Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              color: _nowLine,
                              child: const Text(
                                'NOW',
                                style: TextStyle(
                                  color: Color(0xFF071422),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Center(
                                child: SizedBox(
                                  width: 2,
                                  child: ColoredBox(color: _nowLine),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  KeyEventResult _onGridKey(
    KeyEvent event, {
    required List<DirectChannel> channels,
    required DirectGuideWindow window,
    required List<String> groups,
  }) {
    if (channels.isEmpty) return KeyEventResult.ignored;
    final select = _selectKeyHandler.handleKeyEvent(
      event,
      onTap: () {
        final channel = _channelAt(channels, _cursor.row);
        if (channel != null) unawaited(_play(channel));
      },
      onLongPress: () => unawaited(_recordFocused()),
    );
    if (select != KeyEventResult.ignored) return select;
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final blocks = _blocksFor(channels, window, _cursor.row);
    final index = directGuideBlockIndex(blocks, _cursor.programId, _now);
    if (key.isLeftKey && index == 0) {
      _nodeForGroup(_selectedGroupIndex(groups)).requestFocus();
      return KeyEventResult.handled;
    }
    List<DirectGuideBlock> blocksForRow(int row) =>
        _blocksFor(channels, window, row);
    if (key.isLeftKey || key.isRightKey || key.isUpKey || key.isDownKey) {
      final move = key.isLeftKey
          ? DirectGuideMove.left
          : key.isRightKey
          ? DirectGuideMove.right
          : key.isUpKey
          ? DirectGuideMove.up
          : DirectGuideMove.down;
      _applyCursor(
        moveDirectGuideCursor(
          cursor: _clampedCursor(channels),
          move: move,
          rowCount: channels.length,
          blocksForRow: blocksForRow,
          now: _now,
        ),
      );
      return KeyEventResult.handled;
    }
    final page = key.pageDirection;
    if (page != 0) {
      final viewport = _rowsScroll.hasClients
          ? _rowsScroll.position.viewportDimension
          : _rowExtent * 6;
      final rows = math.max(1, (viewport / _rowExtent).floor() - 1);
      _applyCursor(
        pageDirectGuideCursor(
          cursor: _clampedCursor(channels),
          deltaRows: page * rows,
          rowCount: channels.length,
          blocksForRow: blocksForRow,
          now: _now,
        ),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _timeHeader(DirectGuideWindow window, double timeline) {
    final marks = directGuideHalfHours(window);
    return Stack(
      children: [
        for (final mark in marks)
          Positioned(
            left: directGuideFraction(window, mark) * timeline,
            top: 0,
            bottom: 0,
            child: Text(
              formatGuideTime(mark),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _guideRow({
    required int index,
    required DirectChannel channel,
    required List<DirectChannel> channels,
    required DirectGuideWindow window,
    required double timeline,
    required double channelCol,
    required bool selected,
    required String? programId,
  }) {
    final blocks = _blocksFor(channels, window, index);
    final focusedIndex = selected
        ? directGuideBlockIndex(blocks, programId, _now)
        : -1;
    return Row(
      children: [
        SizedBox(
          width: channelCol,
          child: Material(
            color: selected ? const Color(0xFF12263C) : Colors.transparent,
            child: InkWell(
              onTap: () {
                final atNow = directGuideBlockIndex(blocks, null, _now);
                _applyCursor(
                  DirectGuideCursor(
                    row: index,
                    programId: blocks[atNow].program?.id,
                  ),
                );
                _gridNode.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: channel.resolution == null ? 0 : 42,
                      ),
                      child: Row(
                        children: [
                          _Logo(url: channel.logoUrl, width: 36, height: 26),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((channel.number ?? '').isNotEmpty)
                                  Text(
                                    channel.number!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? _nowLine
                                          : Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                Text(
                                  channel.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (channel.resolution != null)
                      Positioned(
                        top: 3,
                        right: 0,
                        child: _ResolutionBadge(channel.resolution!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              for (final mark in directGuideHalfHours(window))
                Positioned(
                  left: directGuideFraction(window, mark) * timeline,
                  top: 0,
                  bottom: 0,
                  child: const SizedBox(
                    width: 1,
                    child: ColoredBox(color: Color(0x22FFFFFF)),
                  ),
                ),
              for (var i = 0; i < blocks.length; i++)
                _programBlock(
                  block: blocks[i],
                  window: window,
                  timeline: timeline,
                  focused: i == focusedIndex,
                  recording: _programMarked(channel, blocks[i].program),
                  onTap: () {
                    _applyCursor(
                      DirectGuideCursor(
                        row: index,
                        programId: blocks[i].program?.id,
                      ),
                    );
                    unawaited(_play(channel));
                  },
                  onLongPress: () {
                    final program = blocks[i].program;
                    _applyCursor(
                      DirectGuideCursor(row: index, programId: program?.id),
                    );
                    if (program == null) {
                      _snack('No program to record');
                      return;
                    }
                    unawaited(_toggleRecord(channel, program));
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _programBlock({
    required DirectGuideBlock block,
    required DirectGuideWindow window,
    required double timeline,
    required bool focused,
    required bool recording,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final program = block.program;
    final raw = block.width(window) * timeline;
    final width = math.max(8.0, raw - 4);
    final past = program != null && !program.end.isAfter(_now);
    final live = program != null && program.airsAt(_now);
    final color = focused
        ? _accent
        : past
        ? _cardPast
        : live
        ? _cardLive
        : _card;
    return Positioned(
      left: block.left(window) * timeline + 2,
      top: 4,
      bottom: 4,
      width: width,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: focused ? const Color(0xFFBFDBFE) : Colors.white10,
                width: focused ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(6, 4, recording ? 14 : 6, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        program?.title ?? 'No guide data',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: past && !focused
                              ? Colors.white54
                              : Colors.white,
                          fontWeight: focused
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      if (width > 96 && program != null)
                        Text(
                          formatGuideTime(program.start),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                if (recording)
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: SizedBox(
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconFocusButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final KeyEventResult Function(KeyEvent event)? onKey;

  const _IconFocusButton({
    required this.focusNode,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.onKey,
  });

  @override
  State<_IconFocusButton> createState() => _IconFocusButtonState();
}

class _IconFocusButtonState extends State<_IconFocusButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      onKeyEvent: (node, event) {
        final custom = widget.onKey?.call(event);
        if (custom != null && custom != KeyEventResult.ignored) return custom;
        if (widget.onPressed != null) {
          return handleOneShotSelect(event, widget.onPressed!);
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: _focused ? const Color(0xFF1E3A5F) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: widget.busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    widget.icon,
                    color: _focused ? Colors.white : Colors.white70,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final FocusNode focusNode;
  final bool selected;
  final String label;
  final IconData? icon;
  final bool scrollOnFocus;
  final VoidCallback? onSelect;
  final VoidCallback? onFocused;
  final KeyEventResult Function(KeyEvent event)? onKey;

  const _SidebarTile({
    required this.focusNode,
    required this.label,
    this.selected = false,
    this.icon,
    this.scrollOnFocus = false,
    this.onSelect,
    this.onFocused,
    this.onKey,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKey?.call(event);
    if (custom != null && custom != KeyEventResult.ignored) return custom;
    if (widget.onSelect != null) {
      return handleOneShotSelect(event, widget.onSelect!);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
          if (!focused) return;
          widget.onFocused?.call();
          if (!widget.scrollOnFocus) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.4,
              duration: const Duration(milliseconds: 160),
            );
          });
        },
        onKeyEvent: _onKey,
        child: Material(
          color: _focused
              ? const Color(0xFF1E3A5F)
              : widget.selected
              ? const Color(0xFF12263C)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              widget.focusNode.requestFocus();
              widget.onSelect?.call();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: highlighted ? _accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: 16,
                      color: highlighted ? Colors.white : Colors.white60,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlighted ? Colors.white : Colors.white70,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
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

class _TypeTag extends StatelessWidget {
  final String label;

  const _TypeTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _accent),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFBFDBFE),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResolutionBadge extends StatelessWidget {
  final String label;

  const _ResolutionBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xE6071422),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? url;
  final double width;
  final double height;

  const _Logo({required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final logo = url;
    return SizedBox(
      width: width,
      height: height,
      child: logo == null || logo.isEmpty
          ? Icon(Icons.tv, color: Colors.white38, size: height * 0.8)
          : Image.network(
              logo,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.tv, color: Colors.white38, size: height * 0.8),
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
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add source')),
          ],
        ),
      ),
    );
  }
}
