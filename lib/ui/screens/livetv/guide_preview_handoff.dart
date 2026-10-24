import 'package:media_kit/media_kit.dart';

/// Lets full-screen playback keep a guide preview that is already on the
/// same media_kit player, instead of opening the stream a second time.
///
/// The preview arms this just before it leaves the tree. Dispose presents
/// the player only when that player is the shared backend and the open has
/// finished. Anything else is stopped so only one stream is live.
class GuidePreviewHandoff {
  static String? _armedUrl;
  static Player? _player;
  static String? _url;
  static double? _volume;
  static double? _restoredVolume;

  static void arm(String url) {
    _armedUrl = url;
    _player = null;
    _url = null;
    _volume = null;
    _restoredVolume = null;
  }

  static void disarm() {
    _armedUrl = null;
    _player = null;
    _url = null;
    _volume = null;
    _restoredVolume = null;
  }

  static bool armedFor(String? url) =>
      url != null && url.isNotEmpty && _armedUrl == url;

  /// [volume] is what the shared player used before the preview muted it.
  static void present(Player player, String url, {double? volume}) {
    if (!armedFor(url)) return;
    _player = player;
    _url = url;
    _volume = volume;
    _armedUrl = null;
  }

  /// True when [player] is already playing [url]. The arm is consumed
  /// either way so a later playback cannot skip its own open.
  static bool consume(Player player, String url) {
    final offered = _player;
    final offeredUrl = _url;
    final volume = _volume;
    _player = null;
    _url = null;
    _armedUrl = null;
    _volume = null;
    final samePlayer = offered != null && identical(offered, player);
    _restoredVolume = samePlayer ? volume : null;
    if (!samePlayer || offeredUrl == null) return false;
    return offeredUrl == url;
  }

  /// Volume to put back on the player [consume] just matched. Null when
  /// the preview was a private player and never changed this one.
  static double? takeRestoredVolume() {
    final volume = _restoredVolume;
    _restoredVolume = null;
    return volume;
  }
}
