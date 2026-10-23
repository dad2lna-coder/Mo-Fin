import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'direct_iptv_client.dart';
import 'models.dart';
import 'mofin_report.dart';
import 'playlist_parse.dart';
import 'snapshot_store_stub.dart' if (dart.library.io) 'snapshot_store_io.dart';

/// What a finished guide refresh should tell the user.
class DirectIptvRefreshResult {
  final int channelCount;
  final String? error;

  const DirectIptvRefreshResult({required this.channelCount, this.error});

  String get message =>
      directGuideRefreshMessage(channelCount: channelCount, error: error);
}

/// "Updated · N channels", or [error] when the refresh did not succeed.
String directGuideRefreshMessage({required int channelCount, String? error}) {
  final problem = error?.trim();
  if (problem != null && problem.isNotEmpty) return problem;
  return 'Updated · $channelCount channels';
}

/// Saved Dispatcharr and raw M3U accounts, plus the cached lineup for each.
///
/// Source records, including the password or token, live in
/// [SharedPreferences]. The parsed lineup is a separate snapshot so a large
/// guide is not rewritten into preferences. Refresh runs the parsers in an
/// isolate.
class DirectIptvCatalog extends ChangeNotifier {
  static const prefsKey = 'moonfin.direct_iptv.sources';

  DirectIptvCatalog({
    SharedPreferences? preferences,
    DirectIptvTransport? transport,
    DirectIptvSnapshotStore? store,
  }) : _preferences = preferences,
       _transport = transport ?? HttpDirectIptvTransport(),
       _store = store ?? createDirectIptvSnapshotStore();

  SharedPreferences? _preferences;
  final DirectIptvTransport _transport;
  final DirectIptvSnapshotStore _store;

  final List<DirectIptvSource> _sources = [];
  final Map<String, DirectIptvSnapshot> _snapshots = {};
  final Map<String, List<DirectProgram>> _programsByChannel = {};
  final Map<String, String> _errors = {};
  final Set<String> _refreshing = {};
  final Map<String, int> _generation = {};
  final Map<String, DateTime> _refusedUntil = {};

  /// tvg-ids already posted to `<base>resolution` this process.
  final Set<String> _resolutionReported = {};
  Future<void>? _loadFuture;
  bool _loaded = false;

  List<DirectIptvSource> get sources => List.unmodifiable(_sources);
  bool get loaded => _loaded;

  DirectIptvSnapshot? snapshotFor(String sourceId) => _snapshots[sourceId];
  String? errorFor(String sourceId) => _errors[sourceId];
  bool isRefreshing(String sourceId) => _refreshing.contains(sourceId);

  DirectIptvSource? sourceById(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    _preferences ??= await SharedPreferences.getInstance();
    final raw = _preferences!.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _sources
            ..clear()
            ..addAll(
              decoded.whereType<Map>().map(
                (entry) =>
                    DirectIptvSource.fromJson(Map<String, dynamic>.from(entry)),
              ),
            );
        }
      } catch (_) {}
    }
    for (final source in _sources) {
      final snapshot = await _store.read(source.id);
      if (snapshot != null) _remember(snapshot);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> upsert(DirectIptvSource source) async {
    await ensureLoaded();
    final index = _sources.indexWhere((item) => item.id == source.id);
    if (index < 0) {
      _sources.add(source);
    } else {
      _sources[index] = source;
    }
    await _persistSources();
    notifyListeners();
    if (source.enabled) await refresh(source.id, force: true);
  }

  Future<void> delete(String id) async {
    await ensureLoaded();
    _sources.removeWhere((source) => source.id == id);
    _snapshots.remove(id);
    _errors.remove(id);
    _refusedUntil.remove(id);
    _programsByChannel.removeWhere(
      (channelId, _) => channelId.startsWith('direct:$id:'),
    );
    await _persistSources();
    await _store.delete(id);
    notifyListeners();
  }

  Future<void> refreshStale() async {
    await ensureLoaded();
    final now = DateTime.now();
    for (final source in List<DirectIptvSource>.of(_sources)) {
      if (!source.enabled) continue;
      final snapshot = _snapshots[source.id];
      final stale =
          snapshot == null ||
          now.difference(snapshot.fetchedAt) >= source.refreshInterval;
      if (stale) await refresh(source.id);
    }
  }

  /// Manual refresh ([force]) always hits the server. The result is what the
  /// guide snackbar says: the channel count, or the error string.
  Future<DirectIptvRefreshResult?> refresh(
    String sourceId, {
    bool force = false,
  }) async {
    await ensureLoaded();
    final source = sourceById(sourceId);
    if (source == null || !source.enabled) return null;
    if (!force) {
      final refused = _refusedUntil[sourceId];
      if (refused != null && DateTime.now().isBefore(refused)) return null;
      final snapshot = _snapshots[sourceId];
      final fresh =
          snapshot != null &&
          DateTime.now().difference(snapshot.fetchedAt) <
              source.refreshInterval;
      if (fresh) return null;
    }

    final generation = (_generation[sourceId] ?? 0) + 1;
    _generation[sourceId] = generation;
    _refreshing.add(sourceId);
    _errors.remove(sourceId);
    notifyListeners();
    try {
      final built = await _fetch(source);
      if (_generation[sourceId] != generation) return null;
      _refusedUntil.remove(sourceId);
      _remember(built);
      await _store.write(built);
      final empty = built.channels.isEmpty
          ? 'The playlist has no channels'
          : null;
      if (empty != null) _errors[sourceId] = empty;
      return DirectIptvRefreshResult(
        channelCount: built.channels.length,
        error: empty,
      );
    } on DirectIptvException catch (error) {
      if (_generation[sourceId] != generation) return null;
      if (error is DirectIptvRejected) {
        _refusedUntil[sourceId] = DateTime.now().add(source.refreshInterval);
      }
      _errors[sourceId] = error.message;
      return DirectIptvRefreshResult(
        channelCount: _snapshots[sourceId]?.channels.length ?? 0,
        error: error.message,
      );
    } on FormatException {
      if (_generation[sourceId] != generation) return null;
      const message = 'The base URL is not a valid address';
      _errors[sourceId] = message;
      return const DirectIptvRefreshResult(channelCount: 0, error: message);
    } on TimeoutException {
      if (_generation[sourceId] != generation) return null;
      const message = 'The server took too long to answer';
      _errors[sourceId] = message;
      return const DirectIptvRefreshResult(channelCount: 0, error: message);
    } catch (_) {
      if (_generation[sourceId] != generation) return null;
      const message = 'Could not reach the server';
      _errors[sourceId] = message;
      return const DirectIptvRefreshResult(channelCount: 0, error: message);
    } finally {
      if (_generation[sourceId] == generation) {
        _refreshing.remove(sourceId);
        notifyListeners();
      }
    }
  }

  Future<DirectIptvSnapshot> _fetch(DirectIptvSource source) async {
    final base = source.baseUrl.trim();
    if (base.isEmpty) {
      throw const DirectIptvException('A base URL is required');
    }
    final headers = authHeaders(source);
    final fetchedAt = DateTime.now().toUtc();
    if (source.kind == DirectIptvKind.pluto) {
      final guide = await _openGuide(source, headers);
      if (guide == null) {
        throw const DirectIptvException('A guide address is required');
      }
      return assembleSnapshot(
        source: source,
        m3u: '',
        epg: null,
        programmes: guide.programmes,
        xmlChannels: guide.channels,
        fetchedAt: fetchedAt,
      );
    }

    final m3uUri = resolveSourceUri(base, source.effectiveM3uPath);
    final m3u = await _transport.get(m3uUri, headers);
    _throwIfRefused(m3u.statusCode, 'playlist');
    if (m3u.statusCode == 401) {
      throw const DirectIptvException(
        'The playlist rejected the username, password, or token',
      );
    }
    if (m3u.statusCode < 200 || m3u.statusCode >= 300) {
      throw DirectIptvException('Playlist request failed (${m3u.statusCode})');
    }
    if (!m3u.body.contains('#EXTM3U') && !m3u.body.contains('#EXTINF')) {
      throw const DirectIptvException('The playlist response was not an M3U');
    }

    final guide = await _openGuide(source, headers);
    return assembleSnapshot(
      source: source,
      m3u: m3u.body,
      epg: null,
      programmes: guide?.programmes ?? const [],
      fetchedAt: fetchedAt,
    );
  }

  Future<XmltvScan?> _openGuide(
    DirectIptvSource source,
    Map<String, String> headers,
  ) async {
    final base = source.baseUrl.trim();
    final Uri? uri;
    if (source.usesBaseAsGuide) {
      uri = resolveSourceUri(base, '');
    } else if (source.effectiveEpgPath.isNotEmpty) {
      uri = resolveSourceUri(base, source.effectiveEpgPath);
    } else {
      uri = null;
    }
    if (uri == null) {
      if (source.kind == DirectIptvKind.pluto) {
        throw const DirectIptvException('A guide address is required');
      }
      return null;
    }
    final opened = await _transport.open(
      uri,
      headers,
      timeout: const Duration(seconds: 45),
    );
    if (opened.statusCode == 403 || opened.statusCode == 429) {
      await _drain(opened);
      _throwIfRefused(opened.statusCode, 'guide');
    }
    if (opened.statusCode == 401) {
      await _drain(opened);
      throw const DirectIptvException(
        'The guide rejected the username, password, or token',
      );
    }
    if (opened.statusCode < 200 || opened.statusCode >= 300) {
      await _drain(opened);
      throw DirectIptvException('Guide request failed (${opened.statusCode})');
    }
    final scan = XmltvScan(now: DateTime.now());
    try {
      var chunks = 0;
      await for (final chunk in opened.bytes.transform(utf8.decoder)) {
        scan.add(chunk);
        if (++chunks % 32 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      scan.close();
    }
    return scan;
  }

  Future<void> _drain(DirectIptvByteSource source) async {
    try {
      await source.bytes.drain<void>();
    } catch (_) {}
  }

  void _throwIfRefused(int statusCode, String document) {
    if (statusCode != 403 && statusCode != 429) return;
    final reason = statusCode == 429
        ? 'The $document asked us to slow down (429). Refresh is paused.'
        : 'The $document refused the request (403). Refresh is paused.';
    throw DirectIptvRejected(statusCode, reason);
  }

  void _remember(DirectIptvSnapshot snapshot) {
    _snapshots[snapshot.sourceId] = snapshot;
    _programsByChannel.removeWhere(
      (channelId, _) => channelId.startsWith('direct:${snapshot.sourceId}:'),
    );
    for (final program in snapshot.programs) {
      (_programsByChannel[program.channelKey] ??= []).add(program);
    }
    for (final programs in _programsByChannel.values) {
      programs.sort((a, b) => a.start.compareTo(b.start));
    }
  }

  DirectProgram? programOnNow(String channelId, [DateTime? at]) {
    final moment = at ?? DateTime.now();
    for (final program in _programsByChannel[channelId] ?? const []) {
      if (program.airsAt(moment)) return program;
    }
    return null;
  }

  DirectProgram? upNext(String channelId, [DateTime? at]) {
    final moment = at ?? DateTime.now();
    final programs = _programsByChannel[channelId] ?? const <DirectProgram>[];
    final current = programOnNow(channelId, moment);
    if (current != null) {
      final index = programs.indexWhere((program) => program.id == current.id);
      if (index >= 0 && index + 1 < programs.length) return programs[index + 1];
    }
    for (final program in programs) {
      if (program.start.isAfter(moment)) return program;
    }
    return null;
  }

  DirectChannel? channelById(String channelId) {
    for (final snapshot in _snapshots.values) {
      for (final channel in snapshot.channels) {
        if (channel.id == channelId) return channel;
      }
    }
    return null;
  }

  /// True when this channel belongs to the Mo Fin free playlist and has a
  /// tvg-id the report endpoint can store.
  bool mofinReportAvailable(String channelId) {
    final channel = channelById(channelId);
    final tvgId = channel?.tvgId;
    if (channel == null || tvgId == null || tvgId.isEmpty) return false;
    final source = sourceById(channel.sourceId);
    if (source == null) return false;
    return mofinReportUri(source.baseUrl) != null;
  }

  /// True once this channel's resolution was posted during this process.
  bool mofinResolutionSent(String channelId) {
    final tvgId = channelById(channelId)?.tvgId;
    if (tvgId == null || tvgId.isEmpty) return false;
    return _resolutionReported.contains(tvgId);
  }

  /// `X-Mofin-Member` on a stack's stream, or null when this channel is not
  /// a stack or the header never arrived. Errors are ignored.
  Future<String?> peekMofinMember(String channelId) async {
    final channel = channelById(channelId);
    if (channel == null || (channel.stackSize ?? 0) < 1) return null;
    final source = sourceById(channel.sourceId);
    final uri = Uri.tryParse(channel.streamUrl);
    if (source == null || uri == null || !uri.hasScheme) return null;
    try {
      final headers = await _transport.peekHeaders(
        uri,
        headersForPlayback(
          headers: authHeaders(source),
          streamUri: uri,
          credentialHost: Uri.tryParse(source.baseUrl.trim())?.host,
        ),
        timeout: const Duration(seconds: 4),
      );
      return mofinMemberFromHeaders(headers);
    } catch (_) {
      return null;
    }
  }

  /// POST `<base>resolution`. Fire and forget: a failure is swallowed and
  /// is not retried. Nothing is written into the lineup snapshot.
  Future<void> reportMofinResolution({
    required String channelId,
    required int height,
    String? member,
  }) async {
    final channel = channelById(channelId);
    final source = channel == null ? null : sourceById(channel.sourceId);
    final tvgId = channel?.tvgId;
    if (channel == null || source == null || tvgId == null || tvgId.isEmpty) {
      return;
    }
    if (_resolutionReported.contains(tvgId)) return;
    final res = mofinResolutionForHeight(height);
    final uri = mofinResolutionUri(source.baseUrl);
    if (res == null || uri == null) return;
    final who = (channel.stackSize ?? 0) >= 1 ? member?.trim() : null;
    _resolutionReported.add(tvgId);
    try {
      await _transport.send(
        'POST',
        uri,
        authHeaders(source),
        body: mofinResolutionBody(
          tvgId: tvgId,
          res: res,
          member: (who == null || who.isEmpty) ? null : who,
        ),
      );
    } catch (_) {}
  }

  bool? mofinWorking(String channelId) => channelById(channelId)?.mofinWorking;

  String? mofinChecked(String channelId) =>
      channelById(channelId)?.mofinChecked;

  /// POST `<base>report`. A saved report updates the in-memory channel and
  /// the existing lineup snapshot. It does not touch the source list.
  Future<MofinReportStatus> submitMofinReport({
    required String channelId,
    required bool working,
  }) async {
    final channel = channelById(channelId);
    final source = channel == null ? null : sourceById(channel.sourceId);
    final tvgId = channel?.tvgId;
    if (channel == null || source == null || tvgId == null || tvgId.isEmpty) {
      return MofinReportStatus.failed;
    }
    final uri = mofinReportUri(source.baseUrl);
    if (uri == null) return MofinReportStatus.failed;
    try {
      final result = await _transport.send(
        'POST',
        uri,
        authHeaders(source),
        body: mofinReportBody(
          tvgId: tvgId,
          working: working,
          name: channel.name,
        ),
      );
      final status = classifyMofinReport(result.statusCode, result.body);
      if (status == MofinReportStatus.saved) {
        await _applyMofinReport(
          channelId,
          working: working,
          checked: mofinToday(),
        );
      }
      return status;
    } catch (_) {
      return MofinReportStatus.failed;
    }
  }

  /// POST `<base>remove`. A removed channel leaves the in-memory lineup
  /// immediately. The snapshot on disk is left alone; the caller refreshes
  /// the playlist, which is what rewrites catalog storage.
  Future<MofinRemoveStatus> removeMofinChannel(String channelId) async {
    final channel = channelById(channelId);
    final source = channel == null ? null : sourceById(channel.sourceId);
    final tvgId = channel?.tvgId;
    if (channel == null || source == null || tvgId == null || tvgId.isEmpty) {
      return MofinRemoveStatus.failed;
    }
    final uri = mofinRemoveUri(source.baseUrl);
    if (uri == null) return MofinRemoveStatus.failed;
    try {
      final result = await _transport.send(
        'POST',
        uri,
        mofinRemoveHeaders(source.token),
        body: mofinRemoveBody(tvgId: tvgId, name: channel.name),
      );
      final status = classifyMofinRemove(result.statusCode, result.body);
      if (status == MofinRemoveStatus.removed) {
        _dropChannel(channelId);
      }
      return status;
    } catch (_) {
      return MofinRemoveStatus.failed;
    }
  }

  void _dropChannel(String channelId) {
    for (final snapshot in _snapshots.values) {
      final index = snapshot.channels.indexWhere(
        (channel) => channel.id == channelId,
      );
      if (index < 0) continue;
      snapshot.channels.removeAt(index);
      snapshot.programs.removeWhere(
        (program) => program.channelKey == channelId,
      );
      _programsByChannel.remove(channelId);
      notifyListeners();
      return;
    }
  }

  Future<void> _applyMofinReport(
    String channelId, {
    required bool working,
    required String checked,
  }) async {
    for (final snapshot in _snapshots.values) {
      final index = snapshot.channels.indexWhere(
        (channel) => channel.id == channelId,
      );
      if (index < 0) continue;
      snapshot.channels[index] = snapshot.channels[index].withMofinReport(
        working: working,
        checked: checked,
      );
      await _store.write(snapshot);
      notifyListeners();
      return;
    }
  }

  Future<void> _persistSources() async {
    _preferences ??= await SharedPreferences.getInstance();
    await _preferences!.setString(
      prefsKey,
      jsonEncode(_sources.map((source) => source.toJson()).toList()),
    );
  }
}
