import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/direct_iptv_playback.dart';
import 'package:moonfin/direct_iptv/direct_iptv_resolver.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:playback_core/playback_core.dart';

class _Transport implements DirectIptvTransport {
  _Transport(this.body);

  final String body;
  int calls = 0;

  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls++;
    return DirectIptvHttpResult(200, body);
  }

  @override
  Future<DirectIptvByteSource> open(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final result = await get(url, headers, timeout: timeout);
    return DirectIptvByteSource(
      statusCode: result.statusCode,
      bytes: Stream<List<int>>.value(utf8.encode(result.body)),
      finalUrl: url,
    );
  }
}

class _Inner extends MediaStreamResolver {
  int calls = 0;

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
  }) async {
    calls++;
    return const StreamResolutionResult(
      streamUrl: 'http://server.test/tuner',
      mediaSourceId: 'server',
      playMethod: StreamPlayMethod.transcode,
    );
  }
}

void main() {
  const source = DirectIptvSource(
    id: 'src',
    name: 'Dispatcharr',
    kind: DirectIptvKind.dispatcharr,
    baseUrl: 'http://dispatch.test',
    preferredSubtitleLanguage: 'en',
    token: 'tok',
  );

  test('a declared sidecar is attached and the server is not asked', () async {
    final channel = DirectChannel(
      id: 'direct:src:news',
      sourceId: 'src',
      name: 'News',
      number: '5',
      streamUrl: 'http://dispatch.test/stream/5.ts',
      subtitles: const [
        DirectSubtitle(
          url: 'http://dispatch.test/news.vtt',
          language: 'en',
          codec: 'vtt',
        ),
      ],
    );
    final item = playbackRawData(channel: channel, source: source);
    final transport = _Transport('#EXTM3U');
    final inner = _Inner();
    final resolved = await DirectIptvMediaStreamResolver(
      inner,
      transport: transport,
    ).resolve(item, enableTranscoding: true);

    expect(inner.calls, 0);
    expect(transport.calls, 0);
    expect(resolved.bypassServerPlayback, isTrue);
    expect(resolved.playMethod, StreamPlayMethod.directPlay);
    expect(resolved.streamUrl, channel.streamUrl);
    expect(resolved.requestHeaders['Authorization'], 'Bearer tok');
    expect(resolved.externalSubtitles.single.deliveryUrl, 'http://dispatch.test/news.vtt');
    expect(resolved.selectedSubtitleStreamIndex, 2);
    expect(resolved.mediaStreams[2]['IsExternal'], isTrue);
    expect(resolved.mediaStreams[2]['DeliveryMethod'], 'External');
    expect(resolved.mediaStreams[2]['IsDefault'], isTrue);
    expect(resolved.selectNativeTextRendition, isTrue);
    expect(resolved.nativeTextLanguage, 'en');
    expect(resolved.credentialHost, 'dispatch.test');
    expect(transport.calls, 0);
  });

  test('an hls rendition is not probed or attached as a sidecar', () async {
    const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1
video.m3u8
''';
    final transport = _Transport(master);
    final resolved = await DirectIptvMediaStreamResolver(
      _Inner(),
      transport: transport,
    ).resolve({
      'MoonfinDirectSource': true,
      'Id': 'direct:src:live',
      'StreamUrl': 'https://jmp2.uk/plu-live.m3u8',
      'Container': 'hls',
      'RequestHeaders': {
        'Authorization': 'Bearer tok',
        'User-Agent': 'Moonfin',
      },
      'SourceHost': 'dispatch.test',
      'Subtitles': [
        {
          'url': 'https://jmp2.uk/subtitle/en/playlist.m3u8',
          'title': 'English',
          'language': 'en',
          'codec': 'vtt',
        },
      ],
    });

    expect(transport.calls, 0);
    expect(resolved.externalSubtitles, isEmpty);
    expect(resolved.bypassServerPlayback, isTrue);
    expect(resolved.selectedSubtitleStreamIndex, isNull);
    expect(resolved.selectNativeTextRendition, isTrue);
    expect(resolved.nativeTextLanguage, 'en');
    expect(resolved.requestHeaders.containsKey('Authorization'), isFalse);
    expect(resolved.requestHeaders['User-Agent'], 'Moonfin');
    expect(resolved.credentialHost, 'dispatch.test');
  });

  test('credentials stay when the stream host is the source', () async {
    final resolved = await resolveDirectIptvItem({
      'MoonfinDirectSource': true,
      'Id': 'direct:src:live',
      'StreamUrl': 'https://dispatch.test/live/master.m3u8',
      'RequestHeaders': {'Authorization': 'Bearer tok', 'User-Agent': 'Moonfin'},
      'SourceHost': 'dispatch.test',
      'CaptionsOnByDefault': false,
    });

    expect(resolved.requestHeaders['Authorization'], 'Bearer tok');
    expect(resolved.selectNativeTextRendition, isFalse);
    expect(resolved.nativeTextLanguage, isNull);
  });

  test('anything else still uses the server resolver', () async {
    final inner = _Inner();
    final resolved = await DirectIptvMediaStreamResolver(inner).resolve({
      'Id': 'movie',
      'Type': 'Movie',
    });
    expect(inner.calls, 1);
    expect(resolved.streamUrl, 'http://server.test/tuner');
    expect(resolved.bypassServerPlayback, isFalse);
  });
}
