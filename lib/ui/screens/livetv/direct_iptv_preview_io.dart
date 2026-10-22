import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moonfin_native_video/moonfin_native_video.dart';

import '../../../util/platform_detection.dart';

/// Small live picture for the guide. Apple builds do not ship libmpv, so
/// those keep the logo. Fire TV draws through the same native surface as
/// playback; phones and desktop use the texture widget. Full-screen playback
/// still goes through the existing player.
class DirectIptvPreviewPlayer extends StatefulWidget {
  final String? streamUrl;
  final Map<String, String> headers;

  const DirectIptvPreviewPlayer({
    super.key,
    required this.streamUrl,
    this.headers = const {},
  });

  @override
  State<DirectIptvPreviewPlayer> createState() =>
      _DirectIptvPreviewPlayerState();
}

class _DirectIptvPreviewPlayerState extends State<DirectIptvPreviewPlayer> {
  Player? _player;
  VideoController? _controller;
  int _token = 0;
  String? _opened;

  bool get _canPlay => !PlatformDetection.useApplePreviewPlayer;

  void _tvProperty(NativePlayer platform, String key, String value) {
    final dynamic target = platform;
    unawaited(Future<void>.value(target.setProperty(key, value)));
  }

  @override
  void initState() {
    super.initState();
    if (!_canPlay) return;
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(libass: false),
    );
    _player = player;
    if (PlatformDetection.useNativeVideoSurface) {
      final platform = player.platform;
      if (platform is NativePlayer) {
        // The TV picture is a native surface, not a texture. open() waits
        // until a controller claims the player, so mark it attached the
        // same way the full-screen backend does.
        platform.isVideoControllerAttached = true;
        if (!platform.videoControllerCompleter.isCompleted) {
          platform.videoControllerCompleter.complete();
        }
        _tvProperty(platform, 'vo', 'null');
        _tvProperty(platform, 'hwdec', 'auto-copy');
        _tvProperty(platform, 'vid', 'auto');
        _tvProperty(platform, 'force-window', 'yes');
        _tvProperty(platform, 'ao', 'audiotrack');
      }
    } else {
      _controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          hwdec: PlatformDetection.isLinux ? 'auto-safe' : null,
        ),
      );
    }
    unawaited(player.setVolume(PlatformDetection.isTV ? 100 : 0));
    unawaited(player.setPlaylistMode(PlaylistMode.none));
    unawaited(_sync());
  }

  @override
  void didUpdateWidget(covariant DirectIptvPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl ||
        !_sameHeaders(oldWidget.headers, widget.headers)) {
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

  Future<void> _sync() async {
    final player = _player;
    if (player == null) return;
    final token = ++_token;
    final url = widget.streamUrl;
    if (url == null || url.isEmpty) {
      _opened = null;
      try {
        await player.stop();
      } catch (_) {}
      return;
    }
    final signature = '$url\n${widget.headers}';
    if (_opened == signature) return;
    _opened = signature;
    try {
      final headers = widget.headers;
      await player.open(
        headers.isEmpty ? Media(url) : Media(url, httpHeaders: headers),
      );
    } catch (_) {
      if (token == _token) _opened = null;
    }
  }

  @override
  void dispose() {
    _token++;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (player == null) return const SizedBox.expand();
    if (PlatformDetection.useNativeVideoSurface) {
      return NativeVideoView(
        player: player,
        fill: const Color(0xFF000000),
        videoOutput: 'gpu',
        zoomMode: NativeVideoZoomMode.zoomToFill,
        hardwareDecodingEnabled: true,
      );
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: BoxFit.cover,
      fill: const Color(0xFF000000),
      pauseUponEnteringBackgroundMode: false,
    );
  }
}
