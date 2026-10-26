import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../../util/server_url.dart';
import 'retro_artwork_activity_gate.dart';
import 'retro_artwork_cache.dart';
import 'retro_artwork_transport.dart';

/// Selects the artwork protocol once for a particular authenticated server
/// session. A new login, user, token, or server URL deliberately gets a fresh
/// capability lookup even when the [MediaServerClient] object is reused.
class RetroArtworkDataSourceFactory {
  RetroArtworkDataSourceFactory._();

  static final Expando<_CapabilityCacheEntry> _capabilityCache =
      Expando<_CapabilityCacheEntry>('retroArtworkCapabilities');
  static final Set<RetroArtworkDataSource> _activeDataSources =
      <RetroArtworkDataSource>{};

  static void notifyAppResumed() {
    for (final dataSource in List<RetroArtworkDataSource>.of(
      _activeDataSources,
    )) {
      dataSource.onAppResumed();
    }
  }

  static T _track<T extends RetroArtworkDataSource>(T dataSource) {
    _activeDataSources.add(dataSource);
    return dataSource;
  }

  static void _untrack(RetroArtworkDataSource dataSource) {
    _activeDataSources.remove(dataSource);
  }

  static Future<RetroArtworkDataSource?> create({
    required MediaServerClient client,
    required RetroArtworkActivityGate activityGate,
    required RetroArtworkTransport transport,
    Duration priorityDebounce = const Duration(milliseconds: 180),
  }) async {
    final gamesApi = client.gamesApi;
    if (gamesApi == null) return null;

    final capabilities = await _capabilitiesFor(client, gamesApi);
    if (capabilities.supportsManifest && capabilities.supportsVersionedAssets) {
      return _track(
        ManifestArtworkAdapter(
          gamesApi: gamesApi,
          serverIdentity: normalizeRetroArtworkServerIdentity(client.baseUrl),
          activityGate: activityGate,
          transport: transport,
          supportsPriorityHints: capabilities.supportsPriorityHints,
          reportsDimensions: capabilities.supportsDimensions,
          priorityDebounce: priorityDebounce,
          folderCovers: (libraryId) =>
              loadLibraryFolderCovers(client, libraryId),
        ),
      );
    }

    return _track(LegacyArtworkAdapter(gamesApi: gamesApi));
  }

  static Future<GameArtworkCapabilities> _capabilitiesFor(
    MediaServerClient client,
    GamesApi gamesApi,
  ) {
    final sessionKey =
        '${client.baseUrl}\u0000${client.userId}\u0000${client.accessToken}';
    final cached = _capabilityCache[client];
    if (cached?.sessionKey == sessionKey) return cached!.capabilities;

    final capabilities = _readCapabilities(gamesApi);
    _capabilityCache[client] = _CapabilityCacheEntry(sessionKey, capabilities);
    return capabilities;
  }

  static Future<GameArtworkCapabilities> _readCapabilities(GamesApi api) async {
    try {
      return await api.getArtworkCapabilities() ??
          const GameArtworkCapabilities();
    } catch (_) {
      // A capability probe must not make established protocol-1 artwork
      // unavailable during a transient server failure.
      return const GameArtworkCapabilities();
    }
  }
}

class _CapabilityCacheEntry {
  const _CapabilityCacheEntry(this.sessionKey, this.capabilities);

  final String sessionKey;
  final Future<GameArtworkCapabilities> capabilities;
}

enum RetroArtworkProtocol { manifest, legacy }

typedef RetroArtworkSnapshotListener = void Function();

/// A renderable image reference. A null value from [imageFor] means artwork
/// is missing or pending, and callers must not create an image provider.
class RetroArtworkImageReference {
  const RetroArtworkImageReference._({this.source, this.legacyUrl})
    : assert(source != null || legacyUrl != null);

  const RetroArtworkImageReference.manifest(RetroArtworkSource source)
    : this._(source: source);

  const RetroArtworkImageReference.legacy(String legacyUrl)
    : this._(legacyUrl: legacyUrl);

  final RetroArtworkSource? source;
  final String? legacyUrl;

  bool get isManifest => source != null;
}

/// Current server state for the one system owned by a screen.
class RetroArtworkSystemSnapshot {
  RetroArtworkSystemSnapshot({
    required this.libraryId,
    required this.systemId,
    required this.generation,
    Map<String, Map<String, GameArtworkDescriptor>> descriptors = const {},
    Map<String, Map<String, RetroArtworkImageReference>> images = const {},
    Map<String, double> decodedBoxartAspects = const {},
    Map<String, double> folderCoverAspects = const {},
  }) : _descriptors = _freeze(descriptors),
       _images = _freeze(images),
       _decodedBoxartAspects = Map<String, double>.unmodifiable(
         decodedBoxartAspects,
       ),
       _folderCoverAspects = Map<String, double>.unmodifiable(
         folderCoverAspects,
       );

  final String libraryId;
  final String systemId;
  final String? generation;
  final Map<String, Map<String, GameArtworkDescriptor>> _descriptors;
  final Map<String, Map<String, RetroArtworkImageReference>> _images;
  final Map<String, double> _decodedBoxartAspects;
  final Map<String, double> _folderCoverAspects;

  GameArtworkDescriptor? descriptorFor(String gameId, String role) =>
      _descriptors[gameId]?[role];

  RetroArtworkImageReference? imageFor(
    String gameId, {
    String role = 'boxart',
  }) => _images[gameId]?[role];

  /// Width over height. Server-reported size wins; otherwise a size read from
  /// the decoded image, then the Jellyfin folder poster standing in for a
  /// missing thumbnail.
  double? aspectRatioFor(String gameId, {String role = 'boxart'}) {
    final reported = _descriptors[gameId]?[role]?.aspectRatio;
    if (reported != null) return reported;
    if (role != 'boxart') return null;
    return _decodedBoxartAspects[gameId] ?? _folderCoverAspects[gameId];
  }

  /// Server-reported box art shape only, ignoring sizes learned later.
  double? reportedBoxartAspect(String gameId) =>
      _descriptors[gameId]?['boxart']?.aspectRatio;

  /// Box art that will decode but did not come with a size. Folder posters are
  /// legacy URLs and do not count.
  int get unsizedRenderableBoxartCount {
    var count = 0;
    for (final roles in _descriptors.values) {
      final boxart = roles['boxart'];
      if (boxart != null && boxart.isRenderable && boxart.aspectRatio == null) {
        count++;
      }
    }
    return count;
  }

  /// Median box art shape, so one odd box can't reshape a whole system grid.
  /// Folder-poster stand-ins are left out: they are portrait covers, not the
  /// system's libretro box shape.
  late final double? medianBoxartAspectRatio = () {
    final ratios = <double>[
      for (final roles in _descriptors.values)
        if (roles['boxart'] case final descriptor?
            when descriptor.isRenderable && descriptor.aspectRatio != null)
          descriptor.aspectRatio!,
      for (final entry in _decodedBoxartAspects.entries)
        if (_descriptors[entry.key]?['boxart']?.aspectRatio == null &&
            entry.value.isFinite &&
            entry.value > 0)
          entry.value,
    ]..sort();
    if (ratios.isEmpty) return null;
    final mid = ratios.length ~/ 2;
    return ratios.length.isOdd
        ? ratios[mid]
        : (ratios[mid - 1] + ratios[mid]) / 2;
  }();

  RetroArtworkSystemSnapshot withLearnedBoxart({
    Map<String, double>? decodedBoxartAspects,
    Map<String, double>? folderCoverAspects,
    Map<String, Map<String, RetroArtworkImageReference>>? images,
  }) => RetroArtworkSystemSnapshot(
    libraryId: libraryId,
    systemId: systemId,
    generation: generation,
    descriptors: _descriptors,
    images: images ?? _images,
    decodedBoxartAspects: decodedBoxartAspects ?? _decodedBoxartAspects,
    folderCoverAspects: folderCoverAspects ?? _folderCoverAspects,
  );

  List<GameArtworkPriorityItem> pendingPriorityItems(
    Iterable<String> orderedGameIds, {
    required Iterable<String> roles,
  }) {
    final items = <GameArtworkPriorityItem>[];
    final seenGames = <String>{};
    for (final gameId in orderedGameIds) {
      if (!seenGames.add(gameId)) continue;
      final descriptors = _descriptors[gameId];
      if (descriptors == null) continue;
      final pendingRoles = <String>[
        for (final role in roles)
          if (descriptors[role]?.state == 'pending') role,
      ];
      if (pendingRoles.isNotEmpty) {
        items.add(GameArtworkPriorityItem(gameId: gameId, roles: pendingRoles));
      }
    }
    return items;
  }

  static Map<String, Map<String, T>> _freeze<T>(
    Map<String, Map<String, T>> value,
  ) => Map<String, Map<String, T>>.unmodifiable({
    for (final entry in value.entries)
      entry.key: Map<String, T>.unmodifiable(entry.value),
  });
}

/// The screen-owned surface shared by manifest and legacy artwork protocols.
abstract interface class RetroArtworkDataSource {
  RetroArtworkProtocol get protocol;
  RetroArtworkSystemSnapshot? get snapshot;

  /// Whether the server reports artwork sizes (protocol 3).
  bool get reportsDimensions;

  void addSnapshotListener(RetroArtworkSnapshotListener listener);
  void removeSnapshotListener(RetroArtworkSnapshotListener listener);

  /// Fetches only [systemId]'s manifest. Legacy returns an empty snapshot and
  /// never contacts a manifest endpoint.
  Future<RetroArtworkSystemSnapshot> refreshSystem({
    required String libraryId,
    required String systemId,
  });

  RetroArtworkImageReference? imageFor(String gameId, {String role = 'boxart'});

  /// Gives the manifest protocol one ordered, generation-bound chance to
  /// promote pending artifacts in the active row band. Legacy is a no-op.
  Future<void> submitActiveBandPriority(
    Iterable<String> orderedGameIds, {
    Iterable<String> roles = const <String>['boxart'],
    int? planGeneration,
  });

  /// The UI reports image outcomes here because ImageProvider does not expose
  /// its HTTP status to the adapter automatically. Protocol-1 suppresses 404s
  /// for the screen's lifetime and retries transient failures only at the
  /// lifecycle boundaries below; protocol-2 grants one bounded, backed-off
  /// retry per descriptor revision and then latches the same way.
  void reportImageFailure(
    String gameId, {
    String role = 'boxart',
    int? statusCode,
  });

  void reportImageLoaded(String gameId, {String role = 'boxart'});

  /// Width/height read from a decoded box when the server did not report one.
  void reportDecodedBoxartAspect(String gameId, double aspectRatio);

  /// Jellyfin folder name standing in for a ROM whose thumbnail isn't ready.
  /// Null when the plugin title should be kept.
  String? folderTitleFor(String gameId);

  /// Resolves folder posters for games whose box art is not thumbnail-ready.
  /// [gameIds] may include ROMs the manifest omitted. Cached per library.
  Future<void> considerFolderCovers(Iterable<String> gameIds);

  /// Transient failures become eligible for another attempt at these
  /// explicit lifecycle boundaries. Beyond its single bounded retry,
  /// protocol-2 state remains owned by its manifest refresh.
  void onRouteCovered();
  void onRouteReentered();
  void onAppResumed();
  void dispose();
}

/// Protocol-2 adapter. It maps role-keyed descriptors but only creates a
/// transport source for a ready descriptor, never for pending or missing art.
class ManifestArtworkAdapter implements RetroArtworkDataSource {
  ManifestArtworkAdapter({
    required GamesApi gamesApi,
    required String serverIdentity,
    required RetroArtworkActivityGate activityGate,
    required RetroArtworkTransport transport,
    required bool supportsPriorityHints,
    this.reportsDimensions = false,
    this.priorityDebounce = const Duration(milliseconds: 180),
    this.imageRetryBackoff = const Duration(milliseconds: 750),
    this.folderCovers,
  }) : _gamesApi = gamesApi,
       _serverIdentity = serverIdentity,
       _activityGate = activityGate,
       _transport = transport,
       _supportsPriorityHints = supportsPriorityHints {
    _activityGate.addListener(_onActivityChanged);
  }

  final GamesApi _gamesApi;
  final String _serverIdentity;
  final RetroArtworkActivityGate _activityGate;
  final RetroArtworkTransport _transport;
  final bool _supportsPriorityHints;
  final Duration priorityDebounce;

  /// A transient image-transfer failure (HTTP blip, not a pending/missing
  /// descriptor) gets exactly one retry after this backoff. The manifest's
  /// own refresh/retry metadata still owns everything past that single
  /// attempt — see the comment in [_submitPriority].
  final Duration imageRetryBackoff;

  /// Library folder posters used when a game's box art isn't thumbnail-ready.
  /// Null in tests and on a client that cannot list items.
  final Future<List<RomFolderCover>> Function(String libraryId)? folderCovers;

  @override
  RetroArtworkProtocol get protocol => RetroArtworkProtocol.manifest;

  @override
  final bool reportsDimensions;

  @override
  RetroArtworkSystemSnapshot? get snapshot => _snapshot;

  RetroArtworkSystemSnapshot? _snapshot;
  Timer? _refreshTimer;
  Timer? _priorityTimer;
  bool _disposed = false;
  bool _routeCovered = false;
  bool _resumeRefreshScheduled = false;
  int _refreshEpoch = 0;
  int _priorityEpoch = 0;
  int? _priorityPlanGeneration;
  bool _priorityDrainActive = false;
  _QueuedArtworkPriority? _activePriority;
  final Queue<_QueuedArtworkPriority> _priorityQueue =
      Queue<_QueuedArtworkPriority>();
  final Object _manifestRequestOwner = Object();
  final Object _priorityRequestOwner = Object();
  final Set<RetroArtworkSnapshotListener> _listeners =
      <RetroArtworkSnapshotListener>{};

  /// Images currently withheld from [imageFor] while their single bounded
  /// retry is in flight, keyed by `gameId\x00role`. Withholding (rather than
  /// re-emitting an equal [RetroArtworkSource]) is what actually makes the
  /// consumer widget restart the transfer: an unchanged descriptor maps to a
  /// value-equal source, so a plain rebuild would not otherwise be noticed.
  final Set<String> _withheldImages = <String>{};

  /// Counts the bounded retry spent per image key so a second failure on the
  /// same descriptor revision latches instead of retrying again.
  final Map<String, int> _imageRetryAttempts = <String, int>{};
  final Map<String, Timer> _imageRetryTimers = <String, Timer>{};
  final Map<String, double> _decodedBoxartAspects = <String, double>{};
  final Map<String, String> _folderTitles = <String, String>{};
  final Map<String, Future<Map<String, RomFolderCover>>> _folderCoverCache =
      <String, Future<Map<String, RomFolderCover>>>{};
  bool _decodedPublished = false;
  bool _decodedNotifyQueued = false;
  int _folderEpoch = 0;

  @override
  void addSnapshotListener(RetroArtworkSnapshotListener listener) =>
      _listeners.add(listener);

  @override
  void removeSnapshotListener(RetroArtworkSnapshotListener listener) =>
      _listeners.remove(listener);

  @override
  Future<RetroArtworkSystemSnapshot> refreshSystem({
    required String libraryId,
    required String systemId,
  }) async {
    final existing = _snapshot;
    final sameSystem =
        existing?.libraryId == libraryId && existing?.systemId == systemId;
    if (_disposed || _routeCovered || !_activityGate.isOpen) {
      return sameSystem
          ? existing!
          : RetroArtworkSystemSnapshot(
              libraryId: libraryId,
              systemId: systemId,
              generation: null,
            );
    }

    final permit = _activityGate.tryAcquire(
      RetroArtworkActivityKind.manifestRefresh,
    );
    if (permit == null) {
      return sameSystem
          ? existing!
          : RetroArtworkSystemSnapshot(
              libraryId: libraryId,
              systemId: systemId,
              generation: null,
            );
    }
    final epoch = ++_refreshEpoch;
    try {
      final GameArtworkManifest? manifest;
      try {
        manifest = await _gamesApi.getArtworkManifest(
          libraryId,
          systemId: systemId,
          knownGeneration: sameSystem ? existing?.generation : null,
          cancellationOwner: _manifestRequestOwner,
        );
      } catch (_) {
        if (_disposed ||
            _routeCovered ||
            epoch != _refreshEpoch ||
            permit.signal.isCancelled ||
            !_activityGate.isOpen) {
          return sameSystem
              ? existing!
              : RetroArtworkSystemSnapshot(
                  libraryId: libraryId,
                  systemId: systemId,
                  generation: null,
                );
        }
        rethrow;
      }
      if (_disposed ||
          permit.signal.isCancelled ||
          !_activityGate.isOpen ||
          epoch != _refreshEpoch) {
        return sameSystem
            ? existing!
            : RetroArtworkSystemSnapshot(
                libraryId: libraryId,
                systemId: systemId,
                generation: null,
              );
      }
      if (manifest != null) {
        var mapped = _mapManifest(libraryId, systemId, manifest);
        if (_decodedPublished && _decodedBoxartAspects.isNotEmpty) {
          // A refresh rebuilds descriptors from the server and would otherwise
          // drop sizes already read from decoded images. Those sizes stay valid
          // for the same game ids.
          mapped = mapped.withLearnedBoxart(
            decodedBoxartAspects: Map<String, double>.of(_decodedBoxartAspects),
          );
        }
        if (_snapshot?.generation != mapped.generation) {
          _clearPriorityQueue(cancelActive: true);
        }
        _snapshot = mapped;
        // A fresh manifest carries fresh descriptor revisions, so any bounded
        // retry latch from a previous failure no longer applies.
        _clearImageRetryState();
        if (existing?.generation != mapped.generation) _folderEpoch++;
        _notifySnapshotChanged();
      }
      final current =
          _snapshot ??
          RetroArtworkSystemSnapshot(
            libraryId: libraryId,
            systemId: systemId,
            generation: null,
          );
      _snapshot = current;
      _scheduleManifestRefresh(current);
      unawaited(considerFolderCovers(const <String>[]));
      return current;
    } finally {
      permit.dispose();
    }
  }

  RetroArtworkSystemSnapshot _mapManifest(
    String libraryId,
    String systemId,
    GameArtworkManifest manifest,
  ) {
    final descriptors = <String, Map<String, GameArtworkDescriptor>>{};
    final images = <String, Map<String, RetroArtworkImageReference>>{};
    for (final entry in manifest.entries) {
      if (entry.gameId.isEmpty) continue;
      descriptors[entry.gameId] = Map<String, GameArtworkDescriptor>.from(
        entry.artwork,
      );
      for (final artwork in entry.artwork.entries) {
        final descriptor = artwork.value;
        if (!descriptor.isRenderable) continue;
        RetroArtworkSource? source;
        try {
          source = RetroArtworkSource.fromDescriptor(
            serverIdentity: _serverIdentity,
            libraryId: libraryId,
            gameId: entry.gameId,
            role: artwork.key,
            descriptor: descriptor,
          );
        } on FormatException {
          source = null;
        }
        if (source == null) continue;
        _transport.adoptSource(source);
        (images[entry.gameId] ??=
                <String, RetroArtworkImageReference>{})[artwork.key] =
            RetroArtworkImageReference.manifest(source);
      }
    }
    return RetroArtworkSystemSnapshot(
      libraryId: libraryId,
      systemId: systemId,
      generation: manifest.generation.isEmpty ? null : manifest.generation,
      descriptors: descriptors,
      images: images,
    );
  }

  @override
  RetroArtworkImageReference? imageFor(
    String gameId, {
    String role = 'boxart',
  }) {
    if (_withheldImages.contains(_imageKey(gameId, role))) return null;
    return _snapshot?.imageFor(gameId, role: role);
  }

  @override
  Future<void> submitActiveBandPriority(
    Iterable<String> orderedGameIds, {
    Iterable<String> roles = const <String>['boxart'],
    int? planGeneration,
  }) {
    if (_disposed ||
        _routeCovered ||
        !_supportsPriorityHints ||
        !_activityGate.isOpen) {
      return Future<void>.value();
    }
    final current = _snapshot;
    if (current == null || current.generation == null) {
      return Future<void>.value();
    }
    if (planGeneration != null && planGeneration != _priorityPlanGeneration) {
      _priorityPlanGeneration = planGeneration;
      _clearPriorityQueue(cancelActive: true);
    }
    final request = _QueuedArtworkPriority(
      List<String>.unmodifiable(orderedGameIds),
      List<String>.unmodifiable(roles),
    );
    _priorityQueue.addLast(request);
    _schedulePriorityDrain();
    return request.completion.future;
  }

  void _schedulePriorityDrain() {
    if (_priorityDrainActive ||
        _priorityTimer != null ||
        _priorityQueue.isEmpty) {
      return;
    }
    final epoch = _priorityEpoch;
    _priorityTimer = Timer(priorityDebounce, () {
      _priorityTimer = null;
      unawaited(_drainPriority(epoch));
    });
  }

  Future<void> _drainPriority(int epoch) async {
    if (_priorityDrainActive) return;
    _priorityDrainActive = true;
    try {
      while (!_disposed &&
          !_routeCovered &&
          _activityGate.isOpen &&
          epoch == _priorityEpoch &&
          _priorityQueue.isNotEmpty) {
        final request = _priorityQueue.removeFirst();
        _activePriority = request;
        try {
          await _submitPriority(epoch, request.gameIds, request.roles);
        } finally {
          if (identical(_activePriority, request)) {
            _activePriority = null;
          }
          request.complete();
        }
      }
    } finally {
      _priorityDrainActive = false;
      _schedulePriorityDrain();
    }
  }

  Future<void> _submitPriority(
    int epoch,
    List<String> orderedGameIds,
    List<String> roles,
  ) async {
    final current = _snapshot;
    if (_disposed ||
        epoch != _priorityEpoch ||
        _routeCovered ||
        current == null ||
        current.generation == null ||
        !_activityGate.isOpen) {
      return;
    }
    final items = current.pendingPriorityItems(orderedGameIds, roles: roles);
    if (items.isEmpty) return;
    final permit = _activityGate.tryAcquire(
      RetroArtworkActivityKind.priorityCall,
    );
    if (permit == null) return;
    try {
      await _gamesApi.submitArtworkPriority(
        current.libraryId,
        GameArtworkPriorityRequest(
          systemId: current.systemId,
          knownGeneration: current.generation!,
          items: items,
        ),
        cancellationOwner: _priorityRequestOwner,
      );
      // The endpoint has no response state to apply. Checking cancellation
      // still makes late completions observationally inert.
      if (permit.signal.isCancelled || !_activityGate.isOpen) return;
    } catch (_) {
      // Manifest retry/refresh metadata, not blind client retries, controls
      // the next protocol-2 attempt.
    } finally {
      permit.dispose();
    }
  }

  void _scheduleManifestRefresh(RetroArtworkSystemSnapshot current) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final delays = <Duration>[];
    for (final game in current._descriptors.values) {
      for (final descriptor in game.values) {
        for (final seconds in <int?>[
          descriptor.retryAfterSeconds,
          descriptor.refreshAfterSeconds,
        ]) {
          if (seconds != null && seconds > 0) {
            delays.add(Duration(seconds: seconds));
          }
        }
      }
    }
    if (delays.isEmpty) return;
    delays.sort((left, right) => left.compareTo(right));
    _refreshTimer = Timer(delays.first, () {
      _refreshTimer = null;
      if (_disposed || _routeCovered || !_activityGate.isOpen) return;
      unawaited(
        refreshSystem(libraryId: current.libraryId, systemId: current.systemId),
      );
    });
  }

  void _onActivityChanged() {
    if (_activityGate.isOpen) {
      if (!_routeCovered) _scheduleResumeRefresh();
      return;
    }
    ++_refreshEpoch;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _clearPriorityQueue(cancelActive: true);
    _gamesApi.cancelArtworkRequests(cancellationOwner: _manifestRequestOwner);
  }

  void _clearPriorityQueue({required bool cancelActive}) {
    ++_priorityEpoch;
    _priorityTimer?.cancel();
    _priorityTimer = null;
    for (final request in _priorityQueue) {
      request.complete();
    }
    _priorityQueue.clear();
    _activePriority?.complete();
    if (cancelActive) {
      _gamesApi.cancelArtworkRequests(cancellationOwner: _priorityRequestOwner);
    }
  }

  void _scheduleResumeRefresh() {
    if (_resumeRefreshScheduled || _disposed || _routeCovered) return;
    final current = _snapshot;
    if (current == null) return;
    _resumeRefreshScheduled = true;
    scheduleMicrotask(() {
      _resumeRefreshScheduled = false;
      if (_disposed || _routeCovered || !_activityGate.isOpen) return;
      unawaited(
        refreshSystem(libraryId: current.libraryId, systemId: current.systemId),
      );
    });
  }

  void _notifySnapshotChanged() {
    for (final listener in List<RetroArtworkSnapshotListener>.of(_listeners)) {
      listener();
    }
  }

  @override
  void reportImageFailure(
    String gameId, {
    String role = 'boxart',
    int? statusCode,
  }) {
    if (_disposed || _routeCovered) return;
    final key = _imageKey(gameId, role);
    final wasNewlyWithheld = _withheldImages.add(key);
    if ((_imageRetryAttempts[key] ?? 0) > 0) {
      // The bounded retry for this descriptor revision is already spent.
      // Manifest retry/refresh metadata, not a second blind client retry,
      // owns recovery from here — see [_submitPriority]. Stay latched
      // (withheld) rather than scheduling another attempt.
      _imageRetryTimers.remove(key)?.cancel();
      if (wasNewlyWithheld) _notifySnapshotChanged();
      return;
    }
    _imageRetryAttempts[key] = 1;
    if (wasNewlyWithheld) _notifySnapshotChanged();
    _imageRetryTimers[key]?.cancel();
    _imageRetryTimers[key] = Timer(imageRetryBackoff, () {
      _imageRetryTimers.remove(key);
      if (_disposed || _routeCovered) return;
      _withheldImages.remove(key);
      _notifySnapshotChanged();
    });
  }

  @override
  void reportImageLoaded(String gameId, {String role = 'boxart'}) {
    _imageRetryAttempts.remove(_imageKey(gameId, role));
  }

  @override
  void reportDecodedBoxartAspect(String gameId, double aspectRatio) {
    if (_disposed || reportsDimensions) return;
    if (!aspectRatio.isFinite || aspectRatio < 0.2 || aspectRatio > 5) return;
    if (_decodedBoxartAspects.containsKey(gameId)) return;
    if (_snapshot?.reportedBoxartAspect(gameId) != null) return;
    _decodedBoxartAspects[gameId] = aspectRatio;
    final unsized = _snapshot?.unsizedRenderableBoxartCount ?? 0;
    final target = unsized <= 0
        ? _decodedAdoptionCount
        : (unsized < _decodedAdoptionCount ? unsized : _decodedAdoptionCount);
    if (!_decodedPublished && _decodedBoxartAspects.length < target) return;
    _decodedPublished = true;
    _queueDecodedSnapshot();
  }

  void _queueDecodedSnapshot() {
    if (_decodedNotifyQueued || _disposed) return;
    _decodedNotifyQueued = true;
    scheduleMicrotask(() {
      _decodedNotifyQueued = false;
      final current = _snapshot;
      if (_disposed || current == null) return;
      _snapshot = current.withLearnedBoxart(
        decodedBoxartAspects: Map<String, double>.of(_decodedBoxartAspects),
      );
      _notifySnapshotChanged();
    });
  }

  @override
  String? folderTitleFor(String gameId) => _folderTitles[gameId];

  @override
  Future<void> considerFolderCovers(Iterable<String> gameIds) async {
    final lookup = folderCovers;
    final snapshot = _snapshot;
    if (lookup == null || snapshot == null || _disposed || _routeCovered) {
      return;
    }
    final wanted = <String>{
      ...gameIds,
      for (final id in snapshot._descriptors.keys)
        if (!_hasRenderableBoxart(snapshot._descriptors[id]?['boxart'])) id,
    };
    final parents = <String, String>{};
    for (final id in wanted) {
      if (_hasRenderableBoxart(snapshot._descriptors[id]?['boxart'])) continue;
      final path = romPathFromGameId(id);
      final parent = path == null ? null : romParentDirectory(path);
      if (parent == null) continue;
      parents[id] = normalizeRomPath(parent);
    }
    if (parents.isEmpty) return;
    final epoch = _folderEpoch;
    final generation = snapshot.generation;
    final Map<String, RomFolderCover> index;
    try {
      index = await _coversFor(snapshot.libraryId, lookup);
    } catch (_) {
      return;
    }
    if (_disposed || epoch != _folderEpoch || _routeCovered) return;
    final current = _snapshot;
    if (current == null || current.generation != generation) return;
    _applyFolderCovers(current, parents, index);
  }

  Future<Map<String, RomFolderCover>> _coversFor(
    String libraryId,
    Future<List<RomFolderCover>> Function(String libraryId) lookup,
  ) {
    final existing = _folderCoverCache[libraryId];
    if (existing != null) return existing;
    final future = () async {
      final covers = await lookup(libraryId);
      return <String, RomFolderCover>{
        for (final cover in covers)
          if (normalizeRomPath(cover.path).isNotEmpty)
            normalizeRomPath(cover.path): cover,
      };
    }();
    _folderCoverCache[libraryId] = future;
    future.then(
      (_) {},
      onError: (_) {
        _folderCoverCache.remove(libraryId);
      },
    );
    return future;
  }

  void _applyFolderCovers(
    RetroArtworkSystemSnapshot current,
    Map<String, String> parents,
    Map<String, RomFolderCover> index,
  ) {
    final images = <String, Map<String, RetroArtworkImageReference>>{
      for (final entry in current._images.entries)
        entry.key: Map<String, RetroArtworkImageReference>.of(entry.value),
    };
    final aspects = Map<String, double>.of(current._folderCoverAspects);
    var changed = false;
    for (final entry in parents.entries) {
      if (_hasRenderableBoxart(current._descriptors[entry.key]?['boxart'])) {
        continue;
      }
      final cover = index[entry.value];
      if (cover == null) continue;
      final reference = RetroArtworkImageReference.legacy(cover.imageUrl);
      final existing = images[entry.key]?['boxart'];
      if (existing?.legacyUrl != cover.imageUrl) {
        (images[entry.key] ??=
                <String, RetroArtworkImageReference>{})['boxart'] =
            reference;
        changed = true;
      }
      final aspect = cover.aspectRatio;
      if (aspect != null &&
          aspect.isFinite &&
          aspect > 0 &&
          aspects[entry.key] != aspect) {
        aspects[entry.key] = aspect;
        changed = true;
      }
      final name = cover.name.trim();
      if (name.isNotEmpty && _folderTitles[entry.key] != name) {
        _folderTitles[entry.key] = name;
        changed = true;
      }
    }
    if (!changed) return;
    _snapshot = current.withLearnedBoxart(
      images: images,
      folderCoverAspects: aspects,
    );
    _notifySnapshotChanged();
  }

  @override
  void onRouteCovered() {
    if (_disposed || _routeCovered) return;
    _routeCovered = true;
    ++_refreshEpoch;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _clearPriorityQueue(cancelActive: true);
    _gamesApi.cancelArtworkRequests(cancellationOwner: _manifestRequestOwner);
    for (final timer in _imageRetryTimers.values) {
      timer.cancel();
    }
    _imageRetryTimers.clear();
  }

  @override
  void onRouteReentered() {
    _routeCovered = false;
    final hadWithheldImages = _withheldImages.isNotEmpty;
    _clearImageRetryState();
    if (hadWithheldImages) _notifySnapshotChanged();
    if (_activityGate.isOpen) _scheduleResumeRefresh();
  }

  @override
  void onAppResumed() {
    if (!_routeCovered) onRouteReentered();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_refreshEpoch;
    _refreshTimer?.cancel();
    _clearPriorityQueue(cancelActive: true);
    _gamesApi.cancelArtworkRequests(cancellationOwner: _manifestRequestOwner);
    _activityGate.removeListener(_onActivityChanged);
    _listeners.clear();
    _clearImageRetryState();
    RetroArtworkDataSourceFactory._untrack(this);
  }

  void _clearImageRetryState() {
    if (_imageRetryAttempts.isEmpty &&
        _withheldImages.isEmpty &&
        _imageRetryTimers.isEmpty) {
      return;
    }
    _imageRetryAttempts.clear();
    _withheldImages.clear();
    for (final timer in _imageRetryTimers.values) {
      timer.cancel();
    }
    _imageRetryTimers.clear();
  }

  // NUL separates the parts because it cannot occur in a game id or a role, so no pair of
  // inputs can collide onto one key. Written as an escape, not a literal byte: a raw 0x00 in
  // the source makes git treat this whole file as binary and stop rendering its diffs.
  String _imageKey(String gameId, String role) => '$gameId\u0000$role';
}

/// Protocol-1 adapter. It only creates the established Thumb endpoint URLs.
/// Per-screen 404 knowledge is permanent; transient errors become eligible for
/// one retry only when the route re-enters or the app resumes.
class LegacyArtworkAdapter implements RetroArtworkDataSource {
  LegacyArtworkAdapter({required GamesApi gamesApi}) : _gamesApi = gamesApi;

  final GamesApi _gamesApi;
  final Set<String> _missing = <String>{};
  final Set<String> _transientFailures = <String>{};
  bool _routeCovered = false;
  RetroArtworkSystemSnapshot? _snapshot;
  final Set<RetroArtworkSnapshotListener> _listeners =
      <RetroArtworkSnapshotListener>{};

  @override
  void addSnapshotListener(RetroArtworkSnapshotListener listener) =>
      _listeners.add(listener);

  @override
  void removeSnapshotListener(RetroArtworkSnapshotListener listener) =>
      _listeners.remove(listener);

  @override
  RetroArtworkProtocol get protocol => RetroArtworkProtocol.legacy;

  @override
  bool get reportsDimensions => false;

  @override
  RetroArtworkSystemSnapshot? get snapshot => _snapshot;

  @override
  Future<RetroArtworkSystemSnapshot> refreshSystem({
    required String libraryId,
    required String systemId,
  }) async {
    return _snapshot = RetroArtworkSystemSnapshot(
      libraryId: libraryId,
      systemId: systemId,
      generation: null,
    );
  }

  @override
  RetroArtworkImageReference? imageFor(
    String gameId, {
    String role = 'boxart',
  }) {
    final current = _snapshot;
    if (current == null) return null;
    final key = _key(gameId, role);
    if (_missing.contains(key) || _transientFailures.contains(key)) return null;
    return RetroArtworkImageReference.legacy(
      _gamesApi.thumbUrl(
        libraryId: current.libraryId,
        gameId: gameId,
        kind: role,
      ),
    );
  }

  @override
  Future<void> submitActiveBandPriority(
    Iterable<String> orderedGameIds, {
    Iterable<String> roles = const <String>['boxart'],
    int? planGeneration,
  }) => Future<void>.value();

  @override
  void reportImageFailure(
    String gameId, {
    String role = 'boxart',
    int? statusCode,
  }) {
    final key = _key(gameId, role);
    if (statusCode == 404) {
      _missing.add(key);
      _transientFailures.remove(key);
    } else {
      _transientFailures.add(key);
    }
    _notifySnapshotChanged();
  }

  @override
  void reportImageLoaded(String gameId, {String role = 'boxart'}) {
    _transientFailures.remove(_key(gameId, role));
  }

  @override
  void reportDecodedBoxartAspect(String gameId, double aspectRatio) {}

  @override
  String? folderTitleFor(String gameId) => null;

  @override
  Future<void> considerFolderCovers(Iterable<String> gameIds) async {}

  @override
  void onRouteCovered() {
    _routeCovered = true;
  }

  @override
  void onRouteReentered() {
    _routeCovered = false;
    if (_transientFailures.isEmpty) return;
    _transientFailures.clear();
    _notifySnapshotChanged();
  }

  @override
  void onAppResumed() {
    if (!_routeCovered) onRouteReentered();
  }

  @override
  void dispose() {
    _missing.clear();
    _transientFailures.clear();
    _snapshot = null;
    _listeners.clear();
    RetroArtworkDataSourceFactory._untrack(this);
  }

  void _notifySnapshotChanged() {
    for (final listener in List<RetroArtworkSnapshotListener>.of(_listeners)) {
      listener();
    }
  }

  String _key(String gameId, String role) => '$gameId\u0000$role';
}

class _QueuedArtworkPriority {
  _QueuedArtworkPriority(this.gameIds, this.roles);

  final List<String> gameIds;
  final List<String> roles;
  final Completer<void> completion = Completer<void>();

  void complete() {
    if (!completion.isCompleted) completion.complete();
  }
}

/// How many decoded boxes are enough to adopt a grid shape when the server
/// never reported one. Below this, cells stay portrait and art is contained.
const int _decodedAdoptionCount = 6;

/// A plugin image the card can already paint. Anything else (missing, pending,
/// or no descriptor) is the controller-icon case and may use the ROM folder poster.
bool _hasRenderableBoxart(GameArtworkDescriptor? boxart) =>
    boxart != null && boxart.isRenderable;

/// A Jellyfin folder that holds one ROM and has a Primary poster.
class RomFolderCover {
  const RomFolderCover({
    required this.path,
    required this.name,
    required this.imageUrl,
    this.aspectRatio,
  });

  final String path;
  final String name;
  final String imageUrl;
  final double? aspectRatio;
}

/// ROM path encoded as the game id (URL-safe base64). Null when [gameId] is
/// not a path, which is the case for tests and any id the plugin didn't encode.
String? romPathFromGameId(String gameId) {
  if (gameId.isEmpty) return null;
  final bytes = _decodeGameId(gameId);
  if (bytes == null || bytes.isEmpty) return null;
  String path;
  try {
    path = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  if (path.isEmpty || path.contains('\u0000')) return null;
  if (!path.contains('/') && !path.contains('\\')) return null;
  return path;
}

Uint8List? _decodeGameId(String gameId) {
  final urlSafe = _decode64(gameId, urlSafe: true);
  if (urlSafe != null) return urlSafe;
  if (gameId.contains('+') || gameId.contains('/')) {
    return _decode64(gameId, urlSafe: false);
  }
  return null;
}

Uint8List? _decode64(String value, {required bool urlSafe}) {
  try {
    final normalized = urlSafe
        ? base64Url.normalize(value)
        : base64.normalize(value);
    return Uint8List.fromList(
      (urlSafe ? base64Url : base64).decode(normalized),
    );
  } catch (_) {
    return null;
  }
}

/// Directory that contains the ROM file, or null when there is no parent.
String? romParentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return null;
  final trimmed = normalized.length > 1 && normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  if (slash <= 0) return null;
  return trimmed.substring(0, slash);
}

/// Slash-folded, case-insensitive path with no trailing separator.
String normalizeRomPath(String path) => path
    .replaceAll('\\', '/')
    .trim()
    .replaceAll(RegExp(r'/+$'), '')
    .toLowerCase();

final Map<String, Future<List<RomFolderCover>>> _libraryFolderCoverCache =
    <String, Future<List<RomFolderCover>>>{};

@visibleForTesting
void resetLibraryFolderCoverCache() => _libraryFolderCoverCache.clear();

/// Folders under a Retro Games library, cached for every system in it.
///
/// `GET /Users/{id}/Items?ParentId=<library>&Recursive=true&IncludeItemTypes=Folder&Fields=Path`
/// (the app's items client is the user-scoped form of `/Items`). Matched by
/// [RomFolderCover.path] against the ROM's parent directory.
Future<List<RomFolderCover>> loadLibraryFolderCovers(
  MediaServerClient client,
  String libraryId,
) {
  final existing = _libraryFolderCoverCache[libraryId];
  if (existing != null) return existing;
  final future = _fetchLibraryFolderCovers(client, libraryId);
  _libraryFolderCoverCache[libraryId] = future;
  future.then(
    (_) {},
    onError: (_) {
      _libraryFolderCoverCache.remove(libraryId);
    },
  );
  return future;
}

const int _folderCoverPageSize = 200;

Future<List<RomFolderCover>> _fetchLibraryFolderCovers(
  MediaServerClient client,
  String libraryId,
) async {
  final covers = <RomFolderCover>[];
  var start = 0;
  while (start < 20000) {
    final page = await client.itemsApi.getItems(
      parentId: libraryId,
      recursive: true,
      includeItemTypes: const <String>['Folder'],
      fields: 'Path,PrimaryImageAspectRatio',
      enableImageTypes: 'Primary',
      imageTypeLimit: 1,
      startIndex: start,
      limit: _folderCoverPageSize,
      enableTotalRecordCount: start == 0,
    );
    final items = page['Items'];
    if (items is! List || items.isEmpty) break;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      final cover = _folderCoverFromItem(client, item);
      if (cover != null) covers.add(cover);
    }
    if (items.length < _folderCoverPageSize) break;
    start += items.length;
  }
  return covers;
}

RomFolderCover? _folderCoverFromItem(
  MediaServerClient client,
  Map<String, dynamic> item,
) {
  final path = item['Path'];
  final id = item['Id'];
  if (path is! String || path.trim().isEmpty) return null;
  if (id is! String || id.isEmpty) return null;
  final tags = item['ImageTags'];
  final primary = tags is Map ? tags['Primary'] : null;
  if (primary is! String || primary.isEmpty) return null;
  final name = item['Name'];
  final reported = item['PrimaryImageAspectRatio'];
  final aspect = reported is num && reported > 0
      ? reported.toDouble()
      : 680 / 1000;
  final url = tokenAuthedUrl(
    client,
    client.imageApi.getPrimaryImageUrl(
      id,
      maxWidth: 680,
      maxHeight: 1000,
      tag: primary,
    ),
  );
  if (url == null || url.isEmpty) return null;
  return RomFolderCover(
    path: path,
    name: name is String ? name : '',
    imageUrl: url,
    aspectRatio: aspect,
  );
}
