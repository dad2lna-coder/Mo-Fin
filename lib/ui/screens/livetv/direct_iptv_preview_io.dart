import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playback_core/playback_core.dart';

import '../../../playback/media_kit_player_backend.dart';
import '../../../util/platform_detection.dart';
import 'guide_preview_handoff.dart';

/// Small muted picture for the guide.
///
/// One player at a time. Focus, scroll, and leaving the guide drop the
/// previous decoder before another is created. A stream that will not open
/// leaves the logo tile in place instead of taking the process down.
///
/// Phones, desktop, and Fire TV all draw through media_kit's texture.
/// The native SurfaceView used for full-screen TV playback sits in its own
/// window and stays blank inside this clip, which is why the Fire TV box
/// used to freeze on the logo. Full-screen playback still uses its own
/// player, and only after this one has been disposed. Captions are left off
/// here (`sid=no`); the player turns them back on when it opens the channel.
class DirectIptvPreviewPlayer extends StatefulWidget {
  final String? streamUrl;
  final Map<String, String> headers;

  const DirectIptvPreviewPlayer({
    super.key,
    required this.streamUrl,
    this.headers = const {},
  });

  /// Completes once every preview player has been stopped and disposed.
  static Future<void> releaseActive() =>
      _DirectIptvPreviewPlayerState.releaseActive();

  @override
  State<DirectIptvPreviewPlayer> createState() =>
      _DirectIptvPreviewPlayerState();
}

class _DirectIptvPreviewPlayerState extends State<DirectIptvPreviewPlayer>
    with WidgetsBindingObserver {
  static Future<void> _tail = Future<void>.value();
  static _DirectIptvPreviewPlayerState? _owner;

  static Future<void> releaseActive() => _tail;

  static Future<void> _enqueue(Future<void> Function() action) {
    final done = _tail.then((_) async {
      try {
        await action();
      } catch (_) {}
    });
    _tail = done;
    return done;
  }

  Player? _owned;
  VideoController? _controller;
  MediaKitPlayerBackend? _borrowed;
  double? _savedVolume;
  int _token = 0;
  String? _opened;
  bool _ready = false;
  bool _held = false;
  bool _failed = false;
  bool _retired = false;
  void Function()? _stopWatching;

  /// Idle mpv backend, so OK can keep that stream. Android TV's backend has
  /// no texture (it renders on a SurfaceView), and a busy player is left
  /// alone. A borrowed player is remembered so leaving the guide does not
  /// depend on playback having already started.
  MediaKitPlayerBackend? get _idleShared {
    if (PlatformDetection.useNativeVideoSurface) return null;
    if (!GetIt.instance.isRegistered<MediaKitPlayerBackend>()) return null;
    if (!GetIt.instance.isRegistered<PlayerBackend>()) return null;
    final backend = GetIt.instance<MediaKitPlayerBackend>();
    if (!identical(GetIt.instance<PlayerBackend>(), backend)) return null;
    if (backend.videoController == null) return null;
    if (GetIt.instance.isRegistered<PlaybackManager>() &&
        GetIt.instance<PlaybackManager>().state.isPlaying) {
      return null;
    }
    return backend;
  }

  Player? get _player => _borrowed?.player ?? _owned;

  void _property(Player player, String key, String value) {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final dynamic target = platform;
    unawaited(
      Future<void>.value(
        target.setProperty(key, value, waitForInitialization: false),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final previous = _owner;
    _owner = this;
    if (previous != null && !identical(previous, this)) {
      previous._retire();
    }
    unawaited(_sync());
  }

  void _retire() {
    _retired = true;
    _held = true;
    _token++;
    unawaited(_enqueue(_halt));
  }

  void _ensurePlayer() {
    if (_borrowed != null || _owned != null) return;
    final shared = _idleShared;
    if (shared != null) {
      _borrowed = shared;
      _controller = shared.videoController;
      _savedVolume = shared.player.state.volume;
      return;
    }
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(libass: false),
    );
    _owned = player;
    _controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: _hwdec),
    );
    unawaited(player.setVolume(0));
    unawaited(player.setPlaylistMode(PlaylistMode.none));
    _property(player, 'mute', 'yes');
    _property(player, 'sid', 'no');
  }

  String? get _hwdec {
    if (PlatformDetection.isAndroid && PlatformDetection.isTV) {
      // auto-copy puts frames in the Flutter texture. Plain `auto` can
      // decode onto a SurfaceView the guide never shows.
      return 'auto-copy';
    }
    if (PlatformDetection.isLinux) return 'auto-safe';
    return null;
  }

  @override
  void didUpdateWidget(covariant DirectIptvPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl ||
        !_sameHeaders(oldWidget.headers, widget.headers)) {
      unawaited(_sync());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _held = true;
      _token++;
      unawaited(_enqueue(_halt));
      if (mounted) setState(() {});
      return;
    }
    if (state == AppLifecycleState.resumed && _held && !_retired) {
      _held = false;
      _opened = null;
      _ready = false;
      unawaited(_sync());
    }
  }

  bool _sameHeaders(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _halt() async {
    _opened = null;
    _ready = false;
    final stopWatching = _stopWatching;
    _stopWatching = null;
    stopWatching?.call();
    final borrowed = _borrowed;
    final owned = _owned;
    _borrowed = null;
    _owned = null;
    _controller = null;
    if (mounted && !_retired) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    if (borrowed != null) {
      await _releaseBorrowed(borrowed);
      return;
    }
    if (owned == null) return;
    try {
      await owned.dispose();
    } catch (_) {}
  }

  void _watch(Player player) {
    _stopWatching?.call();
    final sub = player.stream.error.listen((_) {
      if (_retired || _failed) return;
      _token++;
      unawaited(
        _enqueue(() async {
          await _halt();
          if (mounted && !_retired) setState(() => _failed = true);
        }),
      );
    });
    _stopWatching = () {
      unawaited(sub.cancel());
    };
  }

  Future<void> _sync() async {
    if (_held || _retired) return;
    final token = ++_token;
    if (mounted && _failed) setState(() => _failed = false);
    await _enqueue(() async {
      if (token != _token || !mounted || _held || _retired) return;
      final url = widget.streamUrl;
      if (url == null || url.isEmpty) {
        await _halt();
        if (mounted) setState(() {});
        return;
      }
      final signature = '$url\n${widget.headers}';
      if (_opened == signature && _player != null && !_failed) return;
      await _halt();
      if (token != _token || !mounted || _held || _retired) return;
      try {
        _ensurePlayer();
        final player = _player;
        if (player == null) return;
        _watch(player);
        _property(player, 'mute', 'yes');
        _property(player, 'sid', 'no');
        if (_borrowed == null) {
          try {
            await player.stop();
          } catch (_) {}
        }
        final headers = widget.headers;
        await player.open(
          headers.isEmpty ? Media(url) : Media(url, httpHeaders: headers),
        );
        if (token != _token || _retired) {
          await _halt();
          return;
        }
        _opened = signature;
        _ready = true;
        _property(player, 'mute', 'yes');
        _property(player, 'sid', 'no');
        if (mounted) setState(() => _failed = false);
      } catch (_) {
        await _halt();
        if (token == _token && mounted && !_retired) {
          setState(() => _failed = true);
        }
      }
    });
  }

  Future<void> _releaseBorrowed(MediaKitPlayerBackend backend) async {
    final player = backend.player;
    _property(player, 'mute', 'no');
    _property(player, 'sid', 'auto');
    try {
      await player.setVolume(_savedVolume ?? 100);
    } catch (_) {}
    try {
      await player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _retired = true;
    _token++;
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_owner, this)) _owner = null;
    final url = _opened?.split('\n').first;
    final borrowed = _borrowed;
    if (borrowed != null && _ready && GuidePreviewHandoff.armedFor(url)) {
      GuidePreviewHandoff.present(
        borrowed.player,
        url!,
        volume: _savedVolume ?? 100,
      );
      _borrowed = null;
    } else {
      GuidePreviewHandoff.disarm();
      unawaited(_enqueue(_halt));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || _held || controller == null) return const SizedBox.shrink();
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: BoxFit.cover,
      fill: const Color(0xFF000000),
      pauseUponEnteringBackgroundMode: true,
    );
  }
}
