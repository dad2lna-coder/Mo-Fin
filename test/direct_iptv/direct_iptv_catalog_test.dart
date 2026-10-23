import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/direct_iptv_catalog.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/models.dart';
import 'package:moonfin/direct_iptv/mofin_report.dart';
import 'package:moonfin/direct_iptv/snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport extends DirectIptvTransport {
  _Transport(this.handler);

  final FutureOr<DirectIptvHttpResult> Function(Uri url) handler;
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

  test(
    'a rejected playlist is reported and the previous lineup stays',
    () async {
      final transport = _Transport(
        (url) => const DirectIptvHttpResult(401, ''),
      );
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
    },
  );

  test('403 stops before the guide and is not retried until forced', () async {
    final transport = _Transport(
      (url) => const DirectIptvHttpResult(403, 'no'),
    );
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

  test('refresh feedback names the channel count or the error', () {
    expect(
      directGuideRefreshMessage(channelCount: 12, error: null),
      'Updated · 12 channels',
    );
    expect(
      directGuideRefreshMessage(channelCount: 0, error: '  '),
      'Updated · 0 channels',
    );
    expect(
      directGuideRefreshMessage(
        channelCount: 4,
        error: 'Could not reach the server',
      ),
      'Could not reach the server',
    );
  });

  test('manual refresh stays busy, then reports the channel count', () async {
    final gate = Completer<void>();
    var held = false;
    final m3u =
        '#EXTM3U\n#EXTINF:-1 tvg-id="news" tvg-chno="5" group-title="News",News\n'
        'http://dispatch.test/news.ts\n';
    final transport = _Transport((url) async {
      if (!held && url.path.contains('m3u')) {
        held = true;
        await gate.future;
      }
      if (url.path.contains('m3u')) return DirectIptvHttpResult(200, m3u);
      return const DirectIptvHttpResult(200, '<tv></tv>');
    });
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );

    final pending = catalog.upsert(source());
    for (var i = 0; i < 30 && !catalog.isRefreshing('src'); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(catalog.isRefreshing('src'), isTrue);

    gate.complete();
    await pending;
    expect(catalog.isRefreshing('src'), isFalse);

    final result = await catalog.refresh('src', force: true);
    expect(result, isNotNull);
    expect(result!.channelCount, 1);
    expect(result.error, isNull);
    expect(result.message, 'Updated · 1 channels');
    expect(catalog.isRefreshing('src'), isFalse);
  });

  test(
    'a failed refresh reports the error instead of a channel count',
    () async {
      final transport = _Transport(
        (url) => const DirectIptvHttpResult(500, ''),
      );
      final prefs = await SharedPreferences.getInstance();
      final catalog = DirectIptvCatalog(
        preferences: prefs,
        transport: transport,
        store: store,
      );
      await catalog.upsert(source());
      final result = await catalog.refresh('src', force: true);
      expect(result!.message, 'Playlist request failed (500)');
      expect(result.message.contains('Updated'), isFalse);
      expect(catalog.isRefreshing('src'), isFalse);
    },
  );

  test(
    'a mo fin report posts beside the playlist and sticks locally',
    () async {
      const playlist =
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="cnn" tvg-resolution="720p" '
          'x-mofin-working="true" x-mofin-checked="2026-10-01",CNN\n'
          'http://example/cnn.ts\n';
      final transport = _ReportingTransport((method, url, body) async {
        expect(method, 'POST');
        expect(
          url,
          Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/report'),
        );
        expect(jsonDecode(body as String), {
          'tvg_id': 'cnn',
          'working': false,
          'name': 'CNN',
        });
        return const DirectIptvHttpResult(200, '{"ok":true}');
      }, playlist);
      final prefs = await SharedPreferences.getInstance();
      final catalog = DirectIptvCatalog(
        preferences: prefs,
        transport: transport,
        store: store,
      );
      await catalog.upsert(
        const DirectIptvSource(
          id: 'mo',
          name: 'Mo Fin',
          kind: DirectIptvKind.m3u,
          baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
        ),
      );
      final channel = catalog.snapshotFor('mo')!.channels.single;
      expect(channel.resolution, '720p');
      expect(channel.mofinWorking, isTrue);
      expect(catalog.mofinReportAvailable(channel.id), isTrue);

      final saved = await catalog.submitMofinReport(
        channelId: channel.id,
        working: false,
      );
      expect(saved, MofinReportStatus.saved);
      expect(transport.posts, hasLength(1));
      expect(catalog.mofinWorking(channel.id), isFalse);
      expect(catalog.mofinChecked(channel.id), mofinToday());

      final reloaded = DirectIptvSnapshot.fromJson(
        jsonDecode(jsonEncode(store.items['mo']!.toJson()))
            as Map<String, dynamic>,
      );
      expect(reloaded.channels.single.mofinWorking, isFalse);
      expect(reloaded.channels.single.resolution, '720p');
      expect(reloaded.channels.single.mofinChecked, mofinToday());

      transport.onSend = (method, url, body) async {
        return const DirectIptvHttpResult(429, '');
      };
      final limited = await catalog.submitMofinReport(
        channelId: channel.id,
        working: true,
      );
      expect(limited, MofinReportStatus.limited);
      expect(catalog.mofinWorking(channel.id), isFalse);

      transport.onSend = (method, url, body) async {
        return const DirectIptvHttpResult(500, 'no');
      };
      final failed = await catalog.submitMofinReport(
        channelId: channel.id,
        working: true,
      );
      expect(failed, MofinReportStatus.failed);
      expect(catalog.mofinWorking(channel.id), isFalse);
    },
  );

  test('remove posts the channel and hides it without rewriting storage', () async {
    const playlist =
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="stack-news" x-mofin-stack="2" x-mofin-members="cnn,bbc" x-mofin-rec-url="https://rec.example/news.ts",News Stack\n'
        'http://example/stack.ts\n'
        '#EXTINF:-1 tvg-id="espn" group-title="Sports",ESPN\n'
        'http://example/espn.ts\n';
    final transport = _ReportingTransport((method, url, body) async {
      expect(method, 'POST');
      expect(
        url,
        Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/remove'),
      );
      expect(jsonDecode(body as String), {
        'tvg_id': 'stack-news',
        'name': 'News Stack',
      });
      return const DirectIptvHttpResult(200, '{"ok":true}');
    }, playlist);
    final prefs = await SharedPreferences.getInstance();
    final counted = _CountingStore();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: counted,
    );
    await catalog.upsert(
      const DirectIptvSource(
        id: 'mo',
        name: 'Mo Fin',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
        token: 'lineup-key',
      ),
    );
    final beforeWrites = counted.writes;
    final storedBefore = counted.frozen;
    final stacked = catalog.snapshotFor('mo')!.channels.first;
    expect(stacked.stackSize, 2);
    expect(stacked.mofinRecUrl, 'https://rec.example/news.ts');
    expect(stacked.streamUrl, 'http://example/stack.ts');

    final removed = await catalog.removeMofinChannel(stacked.id);
    expect(removed, MofinRemoveStatus.removed);
    expect(transport.posts, hasLength(1));
    expect(transport.lastHeaders['X-Mofin-Key'], 'lineup-key');
    expect(transport.lastHeaders.containsKey('Authorization'), isFalse);
    expect(
      catalog.snapshotFor('mo')!.channels.map((channel) => channel.tvgId),
      ['espn'],
    );
    expect(catalog.channelById(stacked.id), isNull);
    expect(counted.writes, beforeWrites);
    expect(counted.frozen, storedBefore);
    expect(storedBefore, contains('stack-news'));

    transport.onSend = (method, url, body) async {
      return const DirectIptvHttpResult(403, '');
    };
    final espn = catalog.snapshotFor('mo')!.channels.single;
    expect(
      await catalog.removeMofinChannel(espn.id),
      MofinRemoveStatus.forbidden,
    );
    expect(catalog.snapshotFor('mo')!.channels, hasLength(1));

    transport.onSend = (method, url, body) async {
      return const DirectIptvHttpResult(404, '');
    };
    expect(
      await catalog.removeMofinChannel(espn.id),
      MofinRemoveStatus.missing,
    );

    transport.onSend = (method, url, body) async {
      return const DirectIptvHttpResult(429, '');
    };
    expect(
      await catalog.removeMofinChannel(espn.id),
      MofinRemoveStatus.limited,
    );
    expect(catalog.snapshotFor('mo')!.channels.single.tvgId, 'espn');
    expect(counted.writes, beforeWrites);
    expect(counted.frozen, storedBefore);
  });

  test('resolution posts once and does not touch catalog storage', () async {
    const playlist =
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="cnn" tvg-resolution="720p",CNN\n'
        'http://example/cnn.ts\n'
        '#EXTINF:-1 tvg-id="stack-news" x-mofin-stack="2" x-mofin-members="cnn,bbc",News Stack\n'
        'http://cdn.example/stack.ts\n'
        '#EXTINF:-1 tvg-id="espn",ESPN\n'
        'http://example/espn.ts\n'
        '#EXTINF:-1 tvg-id="plain",Plain\n'
        'http://example/plain.ts\n';
    final transport = _ReportingTransport((method, url, body) async {
      return const DirectIptvHttpResult(200, '{"ok":true}');
    }, playlist);
    final prefs = await SharedPreferences.getInstance();
    final counted = _CountingStore();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: counted,
    );
    await catalog.upsert(
      const DirectIptvSource(
        id: 'mo',
        name: 'Mo Fin',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free/',
        token: 'lineup-key',
      ),
    );
    final beforeWrites = counted.writes;
    final storedBefore = counted.frozen;
    final channels = catalog.snapshotFor('mo')!.channels;
    final cnn = channels[0];
    final stack = channels[1];
    final espn = channels[2];
    final plain = channels[3];

    await catalog.reportMofinResolution(channelId: plain.id, height: 0);
    expect(transport.posts, isEmpty);
    expect(catalog.mofinResolutionSent(plain.id), isFalse);
    await catalog.reportMofinResolution(channelId: plain.id, height: 720);
    expect(jsonDecode(transport.lastBody as String), {
      'tvg_id': 'plain',
      'res': '720p',
    });

    await catalog.reportMofinResolution(
      channelId: cnn.id,
      height: 1088,
      member: 'should-be-ignored',
    );
    expect(transport.posts, hasLength(2));
    expect(
      transport.posts.last,
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/resolution'),
    );
    expect(jsonDecode(transport.lastBody as String), {
      'tvg_id': 'cnn',
      'res': '1080p',
    });
    expect(transport.peeks, 0);
    expect(catalog.mofinResolutionSent(cnn.id), isTrue);
    expect(catalog.snapshotFor('mo')!.channels[0].resolution, '720p');

    await catalog.reportMofinResolution(channelId: cnn.id, height: 2160);
    expect(transport.posts, hasLength(2));

    transport.peekHeadersResult = {'X-Mofin-Member': ' bbc '};
    await catalog.reportMofinResolution(channelId: stack.id, height: 1440);
    expect(transport.peeks, 1);
    expect(transport.posts, hasLength(3));
    expect(jsonDecode(transport.lastBody as String), {
      'tvg_id': 'stack-news',
      'res': '1440p',
      'member': 'bbc',
    });
    expect(catalog.snapshotFor('mo')!.channels[1].resolution, isNull);
    expect(counted.writes, beforeWrites);
    expect(counted.frozen, storedBefore);
    expect(storedBefore.contains('1440p'), isFalse);

    transport.peekHeadersResult = const {};
    transport.onSend = (method, url, body) async {
      throw Exception('down');
    };
    await catalog.reportMofinResolution(channelId: espn.id, height: 480);
    expect(transport.posts, hasLength(4));
    expect(catalog.mofinResolutionSent(espn.id), isTrue);
    await catalog.reportMofinResolution(channelId: espn.id, height: 720);
    expect(transport.posts, hasLength(4));
    expect(counted.writes, beforeWrites);

    await catalog.reportMofinResolution(channelId: stack.id, height: 0);
    expect(catalog.mofinResolutionSent(stack.id), isTrue);
    expect(transport.posts, hasLength(4));
  });

  test('a non mo fin source does not post a resolution', () async {
    const playlist =
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="cnn",CNN\n'
        'http://example/cnn.ts\n';
    final transport = _ReportingTransport((method, url, body) async {
      return const DirectIptvHttpResult(200, '{}');
    }, playlist);
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await catalog.upsert(
      const DirectIptvSource(
        id: 'other',
        name: 'Other',
        kind: DirectIptvKind.m3u,
        baseUrl: 'http://other.test/live/',
      ),
    );
    final channel = catalog.snapshotFor('other')!.channels.single;
    await catalog.reportMofinResolution(channelId: channel.id, height: 1080);
    expect(transport.posts, isEmpty);
    expect(transport.peeks, 0);
    expect(catalog.mofinResolutionSent(channel.id), isFalse);
  });

  test('a stack with no member header still posts the height', () async {
    const playlist =
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="stack-news" x-mofin-stack="2",News Stack\n'
        'http://cdn.example/stack.ts\n';
    final transport = _ReportingTransport((method, url, body) async {
      throw Exception('header failed');
    }, playlist);
    transport.peekError = Exception('no headers');
    final prefs = await SharedPreferences.getInstance();
    final catalog = DirectIptvCatalog(
      preferences: prefs,
      transport: transport,
      store: store,
    );
    await catalog.upsert(
      const DirectIptvSource(
        id: 'mo',
        name: 'Mo Fin',
        kind: DirectIptvKind.m3u,
        baseUrl: 'https://dad2lna.duckdns.org:8443/mofin/free',
      ),
    );
    final channel = catalog.snapshotFor('mo')!.channels.single;
    final member = await catalog.peekMofinMember(channel.id);
    expect(member, isNull);
    expect(transport.peeks, 1);
    await catalog.reportMofinResolution(
      channelId: channel.id,
      height: 360,
      member: member,
    );
    expect(jsonDecode(transport.lastBody as String), {
      'tvg_id': 'stack-news',
      'res': 'SD',
    });
    expect(
      transport.posts.single,
      Uri.parse('https://dad2lna.duckdns.org:8443/mofin/free/resolution'),
    );
  });
}

class _CountingStore extends MemoryDirectIptvSnapshotStore {
  int writes = 0;
  String frozen = '';

  @override
  Future<void> write(DirectIptvSnapshot snapshot) async {
    writes++;
    frozen = jsonEncode(snapshot.toJson());
    await super.write(snapshot);
  }
}

class _ReportingTransport extends _Transport {
  _ReportingTransport(this.onSend, this.playlist)
    : super((url) => DirectIptvHttpResult(200, playlist));

  Future<DirectIptvHttpResult> Function(String method, Uri url, Object? body)
  onSend;
  final String playlist;
  final posts = <Uri>[];
  Map<String, String> lastHeaders = const {};
  Object? lastBody;
  int peeks = 0;
  Map<String, String> peekHeadersResult = const {};
  Object? peekError;

  @override
  Future<DirectIptvHttpResult> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) {
    posts.add(url);
    lastHeaders = headers;
    lastBody = body;
    return onSend(method, url, body);
  }

  @override
  Future<Map<String, String>> peekHeaders(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    peeks++;
    final error = peekError;
    if (error != null) throw error;
    return peekHeadersResult;
  }
}
