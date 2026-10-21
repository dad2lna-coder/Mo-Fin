import 'package:playback_core/playback_core.dart';

import 'models.dart';
import 'playlist_parse.dart';

/// Marker stored on the guide item the existing Live TV player already
/// hands to [MediaStreamResolver]. Playback never asks Jellyfin or Emby
/// for a tuner stream when this is set.
const directIptvMarker = 'MoonfinDirectSource';

bool isDirectIptvItem(dynamic mediaItem) {
  final raw = _raw(mediaItem);
  return raw != null && raw[directIptvMarker] == true;
}

Map<String, dynamic> playbackRawData({
  required DirectChannel channel,
  required DirectIptvSource source,
}) {
  final audioLanguage = source.preferredAudioLanguage.trim();
  final host = Uri.tryParse(source.baseUrl.trim())?.host;
  return {
    'Id': channel.id,
    'Name': channel.name,
    'Type': 'TvChannel',
    'ChannelNumber': channel.number,
    directIptvMarker: true,
    'StreamUrl': channel.streamUrl,
    'Container': looksLikeHls(channel.streamUrl) ? 'hls' : 'ts',
    'RequestHeaders': authHeaders(source),
    if (host != null && host.isNotEmpty) 'SourceHost': host,
    'CaptionsOnByDefault': source.captionsOnByDefault,
    'PreferredSubtitleLanguage': source.preferredSubtitleLanguage,
    'Subtitles': channel.subtitles.map((track) => track.toJson()).toList(),
    if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
      'LogoUrl': channel.logoUrl,
    if (audioLanguage.isNotEmpty) 'PreferredAudioLanguage': audioLanguage,
  };
}

/// Builds the resolution the player backends already consume: a direct URL
/// plus file sidecars. An HLS subtitle rendition is a live playlist, not a
/// WebVTT file, so it is left for the player's own HLS reader.
Future<StreamResolutionResult> resolveDirectIptvItem(
  dynamic mediaItem,
) async {
  final raw = _raw(mediaItem);
  if (raw == null || raw[directIptvMarker] != true) {
    throw const DirectIptvException('Not a direct IPTV item');
  }
  final url = raw['StreamUrl']?.toString() ?? '';
  if (url.isEmpty) {
    throw const DirectIptvException('This channel has no stream URL');
  }
  final sourceHost = raw['SourceHost']?.toString();
  final streamUri = Uri.tryParse(url) ?? Uri();
  final headers = headersForPlayback(
    headers: _stringMap(raw['RequestHeaders']),
    streamUri: streamUri,
    credentialHost: sourceHost,
  );
  final tracks = _fileSubtitles(_subtitles(raw['Subtitles']));
  final preferred = raw['PreferredSubtitleLanguage']?.toString().trim() ?? '';
  final captionsOn = raw['CaptionsOnByDefault'] != false;
  final textLanguage = preferred.isEmpty ? 'en' : preferred;
  final audioLanguage = raw['PreferredAudioLanguage']?.toString().trim() ?? '';

  final mediaStreams = <Map<String, dynamic>>[
    {'Type': 'Video', 'Index': 0, 'Codec': 'h264'},
    {
      'Type': 'Audio',
      'Index': 1,
      'Codec': 'aac',
      if (audioLanguage.isNotEmpty) 'Language': audioLanguage,
    },
  ];
  final external = <ExternalSubtitle>[];
  int? selectedSubtitle;
  for (var i = 0; i < tracks.length; i++) {
    final track = tracks[i];
    final index = i + 2;
    final isDefault = preferred.isNotEmpty &&
        _languageMatches(track.language, preferred);
    if (isDefault && selectedSubtitle == null) selectedSubtitle = index;
    mediaStreams.add({
      'Type': 'Subtitle',
      'Index': index,
      'Codec': track.codec,
      'Language': track.language,
      'Title': track.title,
      'DisplayTitle': track.title,
      'IsExternal': true,
      'IsDefault': isDefault,
      'DeliveryMethod': 'External',
      'DeliveryUrl': track.url,
    });
    external.add(
      ExternalSubtitle(
        deliveryUrl: track.url,
        title: track.title,
        language: track.language,
        codec: track.codec,
        isDefault: isDefault,
        streamIndex: index,
      ),
    );
  }

  return StreamResolutionResult(
    streamUrl: url,
    mediaSourceId: raw['Id']?.toString() ?? url,
    requestHeaders: headers,
    playMethod: StreamPlayMethod.directPlay,
    container: raw['Container']?.toString(),
    mediaType: 'video',
    externalSubtitles: external,
    mediaStreams: mediaStreams,
    selectedAudioStreamIndex: 1,
    selectedSubtitleStreamIndex: selectedSubtitle,
    bypassServerPlayback: true,
    selectNativeTextRendition: captionsOn,
    nativeTextLanguage: captionsOn ? textLanguage : null,
    credentialHost: sourceHost,
  );
}

Map<String, dynamic>? _raw(dynamic mediaItem) {
  if (mediaItem is Map) {
    return Map<String, dynamic>.from(mediaItem);
  }
  try {
    final raw = (mediaItem as dynamic).rawData;
    if (raw is Map) return Map<String, dynamic>.from(raw);
  } catch (_) {}
  return null;
}

Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map(
    (key, entry) => MapEntry(key.toString(), entry.toString()),
  );
}

List<DirectSubtitle> _subtitles(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => DirectSubtitle.fromJson(Map<String, dynamic>.from(entry)))
      .where((track) => track.url.isNotEmpty)
      .toList();
}

/// A real sidecar file. A `.m3u8` rendition is the live playlist Media3
/// already loads from the master, and loading it once as WebVTT fails.
List<DirectSubtitle> _fileSubtitles(List<DirectSubtitle> tracks) {
  return tracks.where((track) => !looksLikeHls(track.url)).toList();
}

bool _languageMatches(String? track, String preferred) {
  if (track == null || track.isEmpty || preferred.isEmpty) return false;
  final left = track.toLowerCase();
  final right = preferred.toLowerCase();
  if (left == right) return true;
  return left.startsWith(right) || right.startsWith(left);
}
