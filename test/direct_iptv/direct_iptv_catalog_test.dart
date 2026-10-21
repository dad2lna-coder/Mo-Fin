import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/direct_iptv_catalog.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport implements DirectIptvTransport {
  _Transport(this.handler);

  final DirectIptvHttpResult Function(Uri url) handler;
  final calls = <Uri>[];

  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls.add(url);
    return handler(url);
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

String _xmltv(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)} +0000';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryDirectIptvSnapshotStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = MemoryDirectIptvSnapshotStore();
  });

  DirectIptvSource source({String epgPath = ''}) => DirectIptvSource(
    id: 'src',
    name: 'Home',
    kind: DirectIptvKind.dispatcharr,
    baseUrl: 'http://dispatch.test',
    token: 'tok',
    epgPath: epgPath,
  );

  test('refresh caches channels and matches now and next', () async {
    final now = DateTime.now().toUtc();
    final m3u =
        '#EXTM3U\n#EXTINF:-1 tvg-id="news" tvg-chno="5" group-title="News",News\n'
        'http://dispatch.test/news.ts\n';
    final epg =
        '<tv><programme start="${_xmltv(now.subtract(const Duration(minutes: 5)))}" '
        'stop="${_xmltv(now.add(const Duration(minutes: 30)))}" channel="news">'
        '<title>Now</title></programme>'
        '<programme start="${_xmltv(now.add(const Duration(minutes: 30)))}" '
        'stop="${_xmltv(now.add(const Duration(minutes: 90)))}" channel="news">'
        '<title>Later</title></programme></tv>';
    final transport = _Transport((url) {
      if (url.path.contains('m3u')) return DirectIptvHttpResult(200, m3u);
      return DirectIptvHttpResult(200, epg);
    });
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );

    await catalog.upsert(source());

    final channel = catalog.snapshotFor('src')!.channels.single;
    expect(channel.id, 'direct:src:news');
    expect(channel.number, '5');
    expect(channel.group, 'News');
    expect(catalog.programOnNow(channel.id)?.title, 'Now');
    expect(catalog.upNext(channel.id)?.title, 'Later');
    expect(transport.calls, hasLength(2));
    expect(transport.calls.first.path, '/output/m3u/');
    expect(transport.calls.last.path, '/output/epg/');

    await catalog.refresh('src');
    expect(transport.calls, hasLength(2));

    final again = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await again.ensureLoaded();
    expect(again.snapshotFor('src')!.channels.single.name, 'News');
  });

  test('a rejected playlist is reported and the previous lineup stays', () async {
    final transport = _Transport((url) => const DirectIptvHttpResult(401, ''));
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await catalog.upsert(source(epgPath: '-'));
    expect(catalog.snapshotFor('src'), isNull);
    expect(catalog.errorFor('src'), contains('rejected'));
    expect(transport.calls.single.path, '/output/m3u/');
  });

  test('403 stops before the guide and is not retried until forced', () async {
    final transport = _Transport((url) => const DirectIptvHttpResult(403, 'no'));
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await catalog.upsert(source());
    expect(catalog.errorFor('src'), contains('403'));
    expect(transport.calls, hasLength(1));
    expect(transport.calls.single.path, '/output/m3u/');

    await catalog.refresh('src');
    expect(transport.calls, hasLength(1));

    await catalog.refresh('src', force: true);
    expect(transport.calls, hasLength(2));
  });

  test('pluto channels come from the guide and play on jmp2.uk', () async {
    final now = DateTime.now().toUtc();
    final xml =
        '<tv><channel id="plu-news"><display-name>News</display-name>'
        '<icon src="https://cdn/news.png"/></channel>'
        '<channel id="comedy"><display-name>Comedy</display-name></channel>'
        '<programme start="${_xmltv(now.subtract(const Duration(minutes: 5)))}" '
        'stop="${_xmltv(now.add(const Duration(minutes: 30)))}" channel="comedy">'
        '<title>Now</title></programme></tv>';
    final transport = _Transport((url) => DirectIptvHttpResult(200, xml));
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await catalog.upsert(
      const DirectIptvSource(
        id: 'src',
        name: 'Pluto',
        kind: DirectIptvKind.pluto,
        baseUrl: 'https://example.test/PlutoTV/us.xml',
      ),
    );

    expect(transport.calls, hasLength(1));
    expect(transport.calls.single.path, '/PlutoTV/us.xml');
    final channels = catalog.snapshotFor('src')!.channels;
    expect(channels.map((channel) => channel.streamUrl), [
      'https://jmp2.uk/plu-news.m3u8',
      'https://jmp2.uk/plu-comedy.m3u8',
    ]);
    expect(channels.first.logoUrl, 'https://cdn/news.png');
    expect(catalog.programOnNow(channels.last.id)?.title, 'Now');
  });
}
