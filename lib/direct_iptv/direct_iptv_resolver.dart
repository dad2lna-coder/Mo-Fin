import 'package:playback_core/playback_core.dart';

import 'direct_iptv_client.dart';
import 'direct_iptv_playback.dart';

/// Answers direct IPTV items itself and leaves every other item on the
/// server resolver. Unmapped library playback is unchanged.
class DirectIptvMediaStreamResolver extends MediaStreamResolver {
  final MediaStreamResolver _inner;

  /// Kept so a caller can still inject a transport. Playback does not open
  /// the playlist: that second GET started another Pluto session and attached
  /// the live WebVTT rendition as a file.
  // ignore: unused_field
  final DirectIptvTransport? _transport;

  DirectIptvMediaStreamResolver(this._inner, {DirectIptvTransport? transport})
    : _transport = transport;

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) {
    if (isDirectIptvItem(mediaItem)) {
      return resolveDirectIptvItem(mediaItem);
    }
    return _inner.resolve(
      mediaItem,
      deviceProfile: deviceProfile,
      maxStreamingBitrate: maxStreamingBitrate,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      startTimeTicks: startTimeTicks,
      mediaSourceId: mediaSourceId,
      enableDirectPlay: enableDirectPlay,
      enableDirectStream: enableDirectStream,
      enableTranscoding: enableTranscoding,
    );
  }
}