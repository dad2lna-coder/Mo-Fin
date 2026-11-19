import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/channel_feeds.dart';
import 'package:moonfin/direct_iptv/jellyfin_lineup.dart';
import 'package:moonfin/direct_iptv/models.dart';

DirectIptvSource _source(String id, String name, {bool enabled = true}) {
  return DirectIptvSource(
    id: id,
    name: name,
    kind: DirectIptvKind.m3u,
    baseUrl: 'https://$id.example/mofin/free/',
    enabled: enabled,
  );
}

DirectChannel _channel({
  required String sourceId,
  required String name,
  String? tvgId,
  String? streamUrl,
}) {
  final tvg = tvgId ?? name.toLowerCase();
  return DirectChannel(
    id: 'direct:$sourceId:$tvg',
    sourceId: sourceId,
    name: name,
    streamUrl: streamUrl ?? 'https://$sourceId.example/$tvg.ts',
    tvgId: tvgId,
  );
}

DirectIptvSnapshot _snap(String sourceId, List<DirectChannel> channels) {
  return DirectIptvSnapshot(
    sourceId: sourceId,
    fetchedAt: DateTime.utc(2026, 11, 18),
    channels: channels,
    programs: const [],
  );
}

void main() {
  test('the same station on two sources is one group', () {
    final primary = _source('a', 'Mo Fin');
    final backup = _source('b', 'Backup');
    final index = buildDirectFeedIndex(
      sources: [primary, backup],
      snapshotFor: (id) => _snap(id, [
        _channel(sourceId: id, name: 'CNN', tvgId: id == 'a' ? 'cnn' : 'CNN'),
        _channel(sourceId: id, name: 'ESPN', tvgId: 'espn'),
      ]),
    );

    final cnn = index.groupForChannel('direct:a:cnn')!;
    expect(cnn.id, 'tvg:cnn');
    expect(cnn.feeds.map((feed) => feed.sourceName), ['Mo Fin', 'Backup']);
    expect(index.groupForChannel('direct:b:CNN')!.id, cnn.id);
    expect(index.groupForChannel('direct:a:espn')!.feeds, hasLength(2));
    expect(index.groupForChannel('direct:a:espn')!.id, isNot(cnn.id));
  });

  test('a shared name groups sources whose tvg-ids differ', () {
    final index = buildDirectFeedIndex(
      sources: [_source('a', 'East'), _source('b', 'West')],
      snapshotFor: (id) => _snap(id, [
        _channel(
          sourceId: id,
          name: 'City News',
          tvgId: id == 'a' ? 'news.east' : 'news.west',
        ),
      ]),
    );

    final group = index.groupForChannel('direct:a:news.east')!;
    expect(group.id, 'tvg:news.east');
    expect(group.feeds, hasLength(2));
    expect(index.groupForChannel('direct:b:news.west')!.id, group.id);
  });

  test('disabled sources, empty urls, and Jellyfin are not feeds', () {
    final jellyfin = _source(jellyfinLiveSourceId, 'Jellyfin');
    final index = buildDirectFeedIndex(
      sources: [
        _source('a', 'Mo Fin'),
        _source('off', 'Off', enabled: false),
        jellyfin,
      ],
      snapshotFor: (id) => _snap(id, [
        _channel(sourceId: id, name: 'CNN', tvgId: 'cnn'),
        _channel(sourceId: id, name: 'Dead', tvgId: 'dead', streamUrl: '  '),
      ]),
    );

    expect(index.groupForChannel('direct:a:cnn')!.feeds, hasLength(1));
    expect(index.groupForChannel('direct:off:cnn'), isNull);
    expect(index.groupForChannel('direct:$jellyfinLiveSourceId:cnn'), isNull);
    expect(index.groupForChannel('direct:a:dead'), isNull);
  });

  test('one source keeps a single feed when the station is listed twice', () {
    final index = buildDirectFeedIndex(
      sources: [_source('a', 'Mo Fin'), _source('b', 'Backup')],
      snapshotFor: (id) {
        if (id == 'b') {
          return _snap(id, [_channel(sourceId: id, name: 'CNN', tvgId: 'cnn')]);
        }
        return _snap(id, [
          _channel(sourceId: id, name: 'CNN', tvgId: 'cnn'),
          DirectChannel(
            id: 'direct:a:cnn~2',
            sourceId: id,
            name: 'CNN',
            streamUrl: 'https://a.example/cnn-2.ts',
            tvgId: 'cnn',
          ),
        ]);
      },
    );

    final group = index.groupForChannel('direct:a:cnn')!;
    expect(group.feeds.map((feed) => feed.channelId), [
      'direct:a:cnn',
      'direct:b:cnn',
    ]);
    expect(index.groupForChannel('direct:a:cnn~2')!.id, group.id);
  });

  test('cycling wraps and a missing save does not invent a feed', () {
    expect(cycleDirectFeedIndex(current: 1, count: 3, delta: 1), 2);
    expect(cycleDirectFeedIndex(current: 0, count: 3, delta: -1), 2);
    expect(cycleDirectFeedIndex(current: -1, count: 3, delta: 1), 0);
    expect(directFeedStallTimeout, const Duration(seconds: 8));

    final feeds = [
      DirectChannelFeed(
        groupId: 'tvg:cnn',
        channel: _channel(sourceId: 'a', name: 'CNN', tvgId: 'cnn'),
        source: _source('a', 'Mo Fin'),
      ),
    ];
    expect(
      savedFeedChannelId(saved: 'direct:missing:cnn', feeds: feeds),
      isNull,
    );
    expect(
      savedFeedChannelId(saved: 'direct:a:cnn', feeds: feeds),
      'direct:a:cnn',
    );
  });
}
