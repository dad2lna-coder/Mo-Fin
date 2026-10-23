import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/mofin_report.dart';
import 'package:moonfin/direct_iptv/playlist_parse.dart';

void main() {
  test('m3u keeps channel number, group, logo, and sidecar urls', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="pluto-news" tvg-chno="5" tvg-name="News" tvg-logo="https://cdn/news.png" group-title="News" tvg-cc-url="https://cdn/news.vtt" tvg-cc-lang="en",News Channel
https://dispatch/stream/5.ts
#EXTINF:-1 tvg-id="quoted" group-title="Kids",A, B
#EXTVLCOPT:sub-file=https://cdn/extra.srt
#EXTSUB:https://cdn/extra.ass
https://dispatch/stream/7.ts
''';

    final channels = parseM3u(playlist);

    expect(channels, hasLength(2));
    expect(channels.first.tvgId, 'pluto-news');
    expect(channels.first.number, '5');
    expect(channels.first.group, 'News');
    expect(channels.first.logoUrl, 'https://cdn/news.png');
    expect(channels.first.name, 'News Channel');
    expect(channels.first.subtitles.single.url, 'https://cdn/news.vtt');
    expect(channels.first.subtitles.single.language, 'en');
    expect(channels.first.subtitles.single.codec, 'vtt');
    expect(channels.last.name, 'A, B');
    expect(channels.last.subtitles.map((track) => track.url), [
      'https://cdn/extra.srt',
      'https://cdn/extra.ass',
    ]);
    expect(channels.last.subtitles.map((track) => track.codec), ['srt', 'ass']);
  });

  test('xmltv times and entities match a channel by tvg-id', () {
    const amp =
        '&'
        'amp;';
    final start = parseXmltvTime('20261021120000 -0500')!;
    expect(start.toUtc(), DateTime.utc(2026, 10, 21, 17));
    expect(
      parseXmltvTime('20261021120000 +00:00')!.toUtc(),
      DateTime.utc(2026, 10, 21, 12),
    );

    final xml =
        '<tv><programme start="20261021120000 +0000" stop="20261021130000 +0000" channel="pluto-news">'
        '<title>Noon News</title><sub-title>The hour</sub-title>'
        '<desc>Today $amp tomorrow</desc><category>News</category></programme>'
        '<programme start="20261021130000 +0000" stop="20261021140000 +0000" channel="other">'
        '<title>Skip</title></programme></tv>';
    final programmes = parseXmltv(xml);
    expect(programmes, hasLength(2));
    expect(programmes.first.overview, 'Today & tomorrow');
    expect(programmes.first.episodeTitle, 'The hour');
    expect(programmes.first.categories, ['News']);

    final source = DirectIptvSource(
      id: 'src',
      name: 'Dispatcharr',
      kind: DirectIptvKind.dispatcharr,
      baseUrl: 'http://dispatch.test',
    );
    final snapshot = assembleSnapshot(
      source: source,
      m3u: '#EXTM3U\n#EXTINF:-1 tvg-id="pluto-news" tvg-logo="logos/news.png",News\n/stream/5.ts\n',
      epg: xml,
      fetchedAt: DateTime.utc(2026, 10, 21, 12),
    );
    expect(snapshot.channels.single.id, 'direct:src:pluto-news');
    expect(
      snapshot.channels.single.streamUrl,
      'http://dispatch.test/stream/5.ts',
    );
    expect(
      snapshot.channels.single.logoUrl,
      'http://dispatch.test/logos/news.png',
    );
    expect(snapshot.programs, hasLength(1));
    expect(snapshot.programs.single.title, 'Noon News');
    expect(snapshot.programs.single.channelKey, 'direct:src:pluto-news');
    expect(source.effectiveM3uPath, '/output/m3u/');
    expect(source.effectiveEpgPath, '/output/epg/');
    expect(source.copyWith(epgPath: '-').effectiveEpgPath, isEmpty);
  });

  test('a relative rendition resolves against the url after the redirect', () {
    const relative = 'subtitle/en/playlist.m3u8?s=1';
    const master =
        '''
#EXTM3U
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",DEFAULT=NO,URI="$relative"
#EXT-X-STREAM-INF:BANDWIDTH=1000
index.m3u8
''';
    final requested = Uri.parse('https://jmp2.uk/plu-abc.m3u8');
    final redirected = Uri.parse(
      'https://stitcher.pluto.tv/v1/channel/abc/master.m3u8',
    );
    expect(requested.resolve(relative).host, 'jmp2.uk');

    final tracks = hlsSubtitleTracks(master, redirected);
    expect(tracks.single.url, redirected.resolve(relative).toString());
    expect(tracks.single.url, isNot(startsWith('https://jmp2.uk/')));
    expect(tracks.single.language, 'en');
    expect(tracks.single.title, 'English');
  });

  test('xmltv scan keeps a window and a tag split across chunks', () {
    final now = DateTime.utc(2026, 10, 21, 18);
    final keptStart = DateTime.utc(2026, 10, 21, 17, 30);
    final keptStop = DateTime.utc(2026, 10, 21, 18, 30);
    final oldStart = DateTime.utc(2026, 10, 21, 1);
    final oldStop = DateTime.utc(2026, 10, 21, 2);
    String stamp(DateTime time) {
      String two(int value) => value.toString().padLeft(2, '0');
      return '${time.year}${two(time.month)}${two(time.day)}'
          '${two(time.hour)}${two(time.minute)}${two(time.second)} +0000';
    }

    final xml =
        '<tv><channel id="plu-news"><display-name>News</display-name>'
        '<icon src="https://cdn/news.png"/></channel>'
        '<programme start="${stamp(oldStart)}" stop="${stamp(oldStop)}" channel="plu-news">'
        '<title>Old</title></programme>'
        '<programme start="${stamp(keptStart)}" stop="${stamp(keptStop)}" channel="plu-news">'
        '<title>Now</title></programme></tv>';
    final scan = XmltvScan(now: now);
    for (var i = 0; i < xml.length; i += 17) {
      final end = i + 17 < xml.length ? i + 17 : xml.length;
      scan.add(xml.substring(i, end));
    }
    scan.close();
    expect(scan.channels.single.id, 'plu-news');
    expect(scan.channels.single.name, 'News');
    expect(scan.channels.single.iconUrl, 'https://cdn/news.png');
    expect(scan.programmes.single.title, 'Now');
    expect(plutoStreamUrl('plu-news'), 'https://jmp2.uk/plu-news.m3u8');
    expect(plutoStreamUrl('news'), 'https://jmp2.uk/plu-news.m3u8');
    expect(
      plutoWebProxyUrl(
        'news',
        page: Uri.parse('https://dad2lna.duckdns.org:8443/mofin/#/live'),
      ),
      'https://dad2lna.duckdns.org:8443/mofin/pluto/plu-news.m3u8',
    );
    expect(
      plutoWebProxyUrl('news', page: Uri.parse('https://example.test/mofin/')),
      'https://example.test/mofin/pluto/plu-news.m3u8',
    );

    final source = DirectIptvSource(
      id: 'src',
      name: 'Pluto',
      kind: DirectIptvKind.pluto,
      baseUrl: 'https://example.test/us.xml',
    );
    final snapshot = assembleSnapshot(
      source: source,
      m3u: '',
      epg: null,
      programmes: scan.programmes,
      xmlChannels: scan.channels,
      fetchedAt: now,
    );
    expect(snapshot.channels.single.streamUrl, 'https://jmp2.uk/plu-news.m3u8');
    expect(snapshot.channels.single.logoUrl, 'https://cdn/news.png');
    expect(snapshot.programs.single.title, 'Now');
    expect(source.effectiveM3uPath, isEmpty);
    expect(source.usesBaseAsGuide, isTrue);
  });

  test('playback headers omit credentials for a different host', () {
    final kept = headersForPlayback(
      headers: {'Authorization': 'Bearer tok', 'User-Agent': 'Moonfin'},
      streamUri: Uri.parse('https://dispatch.test/live.m3u8'),
      credentialHost: 'dispatch.test',
    );
    expect(kept['Authorization'], 'Bearer tok');

    final stripped = headersForPlayback(
      headers: {'Authorization': 'Bearer tok', 'User-Agent': 'Moonfin'},
      streamUri: Uri.parse('https://stitcher.pluto.tv/master.m3u8'),
      credentialHost: 'dispatch.test',
    );
    expect(stripped.containsKey('Authorization'), isFalse);
    expect(stripped['User-Agent'], 'Moonfin');

    final child = headersForPlayback(
      headers: {'Authorization': 'Basic abc'},
      streamUri: Uri.parse('https://edge.dispatch.test/live'),
      credentialHost: 'dispatch.test',
    );
    expect(child['Authorization'], 'Basic abc');
  });

  test('a token is sent as a bearer and otherwise basic auth is used', () {
    final token = authHeaders(
      const DirectIptvSource(
        id: 'a',
        name: 'A',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://example.test/list.m3u',
        username: 'user',
        password: 'secret',
        token: 'tok',
      ),
    );
    expect(token['Authorization'], 'Bearer tok');

    final basic = authHeaders(
      const DirectIptvSource(
        id: 'a',
        name: 'A',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://example.test/list.m3u',
        username: 'user',
        password: 'secret',
      ),
    );
    expect(basic['Authorization'], 'Basic dXNlcjpzZWNyZXQ=');
    expect(
      const DirectIptvSource(
        id: 'a',
        name: 'A',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://example.test/list.m3u',
      ).effectiveM3uPath,
      isEmpty,
    );
  });

  test('a large guide in one chunk parses the same as in small chunks', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    String stamp(DateTime t) =>
        '${t.year}${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}'
        '${t.hour.toString().padLeft(2, '0')}'
        '${t.minute.toString().padLeft(2, '0')}00 +0000';
    final buffer = StringBuffer('<tv>');
    for (var c = 0; c < 50; c++) {
      buffer.write(
        '<CHANNEL id="c$c"><display-name>C$c</display-name></CHANNEL>',
      );
    }
    for (var c = 0; c < 50; c++) {
      for (var h = -8; h < 16; h++) {
        final start = now.add(Duration(hours: h));
        buffer.write(
          '<programme channel="c$c" start="${stamp(start)}" '
          'stop="${stamp(start.add(const Duration(hours: 1)))}">'
          '<title>T$c/$h</title><category>Series</category></Programme>',
        );
      }
    }
    buffer.write('</tv>');
    final xml = buffer.toString();
    final whole = XmltvScan(now: now)..add(xml);
    final pieces = XmltvScan(now: now);
    for (var i = 0; i < xml.length; i += 5) {
      pieces.add(xml.substring(i, i + 5 < xml.length ? i + 5 : xml.length));
    }
    expect(whole.channels.length, 50);
    expect(whole.programmes.length, 50 * 18);
    expect(pieces.channels.length, 50);
    expect(
      pieces.programmes.map((p) => p.title).toList(),
      whole.programmes.map((p) => p.title).toList(),
    );
  });

  test('m3u keeps resolution and the last mo fin report', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cnn" tvg-resolution="1080P" x-mofin-working="TRUE" x-mofin-checked="2026-10-22",CNN
http://example/cnn.ts
#EXTINF:-1 tvg-id="bad" tvg-resolution="4K" x-mofin-working="false" x-mofin-checked="2026-1-2",Bad
http://example/bad.ts
#EXTINF:-1 tvg-id="sd" tvg-resolution="sd" x-mofin-working="yes",Local
http://example/sd.ts
#EXTINF:-1 tvg-id="plain" group-title="News",Plain
http://example/plain.ts
''';

    final channels = parseM3u(playlist);
    expect(channels, hasLength(4));
    expect(channels[0].resolution, '1080p');
    expect(channels[0].mofinWorking, isTrue);
    expect(channels[0].mofinChecked, '2026-10-22');
    expect(channels[1].resolution, isNull);
    expect(channels[1].mofinWorking, isFalse);
    expect(channels[1].mofinChecked, isNull);
    expect(channels[2].resolution, 'SD');
    expect(channels[2].mofinWorking, isNull);
    expect(channels[2].mofinChecked, isNull);
    expect(channels[3].resolution, isNull);
    expect(channels[3].mofinWorking, isNull);
    expect(channels[3].mofinChecked, isNull);

    final source = DirectIptvSource(
      id: 'mo',
      name: 'Mo Fin',
      kind: DirectIptvKind.m3u,
      baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
    );
    final snapshot = assembleSnapshot(
      source: source,
      m3u: playlist,
      epg: null,
      fetchedAt: DateTime.utc(2026, 10, 22),
    );
    expect(snapshot.channels.first.resolution, '1080p');
    expect(snapshot.channels.first.mofinWorking, isTrue);
    expect(snapshot.channels[1].mofinWorking, isFalse);
    expect(snapshot.channels[2].resolution, 'SD');

    final stored = snapshot.toJson();
    final encoded = (stored['channels'] as List).cast<Map>();
    expect(encoded.first['resolution'], '1080p');
    expect(encoded.first['mofinWorking'], isTrue);
    expect(encoded.first['mofinChecked'], '2026-10-22');
    expect(encoded.last.containsKey('resolution'), isFalse);
    expect(encoded.last.containsKey('mofinWorking'), isFalse);
    expect(encoded.last.containsKey('mofinChecked'), isFalse);
    expect(encoded.last.keys, [
      'id',
      'sourceId',
      'name',
      'streamUrl',
      'tvgId',
      'group',
      'subtitles',
    ]);

    final restored = DirectIptvSnapshot.fromJson(stored);
    expect(restored.channels.first.resolution, '1080p');
    expect(restored.channels.first.mofinWorking, isTrue);
    expect(restored.channels.first.mofinChecked, '2026-10-22');
    expect(restored.channels[1].resolution, isNull);

    final legacy = DirectChannel.fromJson(const {
      'id': 'direct:mo:old',
      'sourceId': 'mo',
      'name': 'Old',
      'streamUrl': 'http://example/old.ts',
      'tvgId': 'old',
      'subtitles': <dynamic>[],
    });
    expect(legacy.resolution, isNull);
    expect(legacy.mofinWorking, isNull);
    expect(legacy.mofinChecked, isNull);

    expect(
      mofinReportUri('https://dad2lna.duckdns.org:8443/mofin/free/'),
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/report'),
    );
    expect(
      mofinReportUri('https://dad2lna.duckdns.org:8443/mofin/free'),
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/report'),
    );
    expect(mofinReportUri('http://dispatch.test'), isNull);
    expect(classifyMofinReport(200, '{"ok":true}'), MofinReportStatus.saved);
    expect(classifyMofinReport(200, '{"ok":false}'), MofinReportStatus.failed);
    expect(classifyMofinReport(200, 'nope'), MofinReportStatus.failed);
    expect(classifyMofinReport(429, ''), MofinReportStatus.limited);
    expect(classifyMofinReport(500, '{"ok":true}'), MofinReportStatus.failed);
  });

  test('m3u keeps a stack and does not store it in the catalog', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="stack-news" tvg-chno="5" group-title="News" x-mofin-stack="3" x-mofin-members="cnn,msnbc,bbc" x-mofin-rec-url="https://rec.example/news.ts",News Stack
http://example/stack.ts
#EXTINF:-1 tvg-id="plain" group-title="News" x-mofin-stack="0" x-mofin-members="" x-mofin-rec-url="",Plain
http://example/plain.ts
#EXTINF:-1 tvg-id="stack-kids" x-mofin-stack="nope" x-mofin-members="a, b",Kids
http://example/kids.ts
''';

    final channels = parseM3u(playlist);
    expect(channels[0].tvgId, 'stack-news');
    expect(channels[0].stackSize, 3);
    expect(channels[0].stackMembers, ['cnn', 'msnbc', 'bbc']);
    expect(channels[0].mofinRecUrl, 'https://rec.example/news.ts');
    expect(channels[0].streamUrl, 'http://example/stack.ts');
    expect(channels[1].stackSize, isNull);
    expect(channels[1].stackMembers, isEmpty);
    expect(channels[1].mofinRecUrl, isNull);
    expect(channels[2].stackSize, isNull);
    expect(channels[2].stackMembers, ['a', 'b']);
    expect(channels[2].mofinRecUrl, isNull);

    final source = DirectIptvSource(
      id: 'mo',
      name: 'Mo Fin',
      kind: DirectIptvKind.m3u,
      baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
    );
    final snapshot = assembleSnapshot(
      source: source,
      m3u: playlist,
      epg: null,
      fetchedAt: DateTime.utc(2026, 10, 23),
    );
    final stacked = snapshot.channels.first;
    expect(stacked.tvgId, 'stack-news');
    expect(stacked.stackSize, 3);
    expect(stacked.stackMembers, ['cnn', 'msnbc', 'bbc']);
    expect(stacked.mofinRecUrl, 'https://rec.example/news.ts');
    expect(stacked.streamUrl, 'http://example/stack.ts');
    expect(snapshot.channels[1].stackSize, isNull);
    expect(snapshot.channels[2].stackMembers, ['a', 'b']);

    final stored = stacked.toJson();
    expect(stored.containsKey('stackSize'), isFalse);
    expect(stored.containsKey('stackMembers'), isFalse);
    expect(stored.containsKey('mofinRecUrl'), isFalse);
    expect(stored.keys, [
      'id',
      'sourceId',
      'name',
      'streamUrl',
      'number',
      'tvgId',
      'group',
      'subtitles',
    ]);
    final restored = DirectChannel.fromJson(stored);
    expect(restored.stackSize, isNull);
    expect(restored.stackMembers, isEmpty);
    expect(restored.mofinRecUrl, isNull);
    expect(restored.tvgId, 'stack-news');
    expect(restored.streamUrl, 'http://example/stack.ts');

    expect(
      mofinRemoveUri('https://dad2lna.duckdns.org:8443/mofin/free/'),
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/remove'),
    );
    expect(mofinRemoveUri('http://dispatch.test'), isNull);
    expect(mofinRemoveHeaders('secret')['X-Mofin-Key'], 'secret');
    expect(mofinRemoveHeaders('  ')['X-Mofin-Key'], isNull);
    expect(mofinRemoveBody(tvgId: 'stack-news', name: 'News Stack'),
        '{"tvg_id":"stack-news","name":"News Stack"}');
    expect(
      classifyMofinRemove(200, '{"ok":true}'),
      MofinRemoveStatus.removed,
    );
    expect(classifyMofinRemove(200, '{"ok":false}'), MofinRemoveStatus.failed);
    expect(classifyMofinRemove(403, ''), MofinRemoveStatus.forbidden);
    expect(classifyMofinRemove(404, ''), MofinRemoveStatus.missing);
    expect(classifyMofinRemove(429, ''), MofinRemoveStatus.limited);
    expect(classifyMofinRemove(500, '{"ok":true}'), MofinRemoveStatus.failed);
  });

  test('resolution height, body, and member header stay out of badges', () {
    expect(
      mofinResolutionUri('https://dad2lna.duckdns.org:8443/mofin/free/'),
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/resolution'),
    );
    expect(
      mofinResolutionUri('https://dad2lna.duckdns.org:8443/mofin/free'),
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/resolution'),
    );
    expect(mofinResolutionUri('http://dispatch.test'), isNull);
    expect(mofinResolutions.contains('1440p'), isFalse);

    expect(mofinResolutionForHeight(0), isNull);
    expect(mofinResolutionForHeight(-1), isNull);
    expect(mofinResolutionForHeight(360), 'SD');
    expect(mofinResolutionForHeight(479), 'SD');
    expect(mofinResolutionForHeight(480), '480p');
    expect(mofinResolutionForHeight(576), '480p');
    expect(mofinResolutionForHeight(720), '720p');
    expect(mofinResolutionForHeight(1080), '1080p');
    expect(mofinResolutionForHeight(1088), '1080p');
    expect(mofinResolutionForHeight(1440), '1440p');
    expect(mofinResolutionForHeight(2160), '2160p');
    expect(mofinResolutionForHeight(4320), '2160p');

    expect(
      mofinResolutionBody(tvgId: 'cnn', res: '1080p'),
      '{"tvg_id":"cnn","res":"1080p"}',
    );
    expect(
      mofinResolutionBody(tvgId: 'stack-news', res: '1440p', member: ' bbc '),
      '{"tvg_id":"stack-news","res":"1440p","member":"bbc"}',
    );
    expect(
      mofinResolutionBody(tvgId: 'cnn', res: '720p', member: '  '),
      '{"tvg_id":"cnn","res":"720p"}',
    );
    expect(
      mofinMemberFromHeaders({'X-Mofin-Member': ' cnn '}),
      'cnn',
    );
    expect(mofinMemberFromHeaders({'x-mofin-member': ''}), isNull);
    expect(mofinMemberFromHeaders({'Content-Type': 'video/mp2t'}), isNull);
  });
}
