import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/streaming/streaming_service.dart';
import 'package:moonfin/streaming/tmdb_streaming_client.dart';

void main() {
  group('provider names', () {
    test('only the four subscription names match', () {
      expect(
        streamingServiceForProviderName('Netflix'),
        StreamingService.netflix,
      );
      expect(
        streamingServiceForProviderName(' Disney Plus '),
        StreamingService.disneyPlus,
      );
      expect(streamingServiceForProviderName('Disney+'), StreamingService.disneyPlus);
      expect(streamingServiceForProviderName('Max'), StreamingService.max);
      expect(
        streamingServiceForProviderName('Amazon Prime Video'),
        StreamingService.primeVideo,
      );
      expect(
        streamingServiceForProviderName('Prime Video'),
        StreamingService.primeVideo,
      );

      for (final rejected in [
        'Netflix Standard with Ads',
        'Max Amazon Channel',
        'Amazon Prime Video with Ads',
        'Hulu',
        'Apple TV Plus',
        'HBO Max',
        '',
      ]) {
        expect(streamingServiceForProviderName(rejected), isNull, reason: rejected);
      }
    });
  });

  group('TmdbStreamingClient', () {
    late List<Uri> calls;
    late TmdbStreamingClient client;

    TmdbFetchResult ok(Object json) => TmdbFetchResult(200, jsonEncode(json));

    Map<String, Object> providers({required int netflixId}) => {
          'results': [
            {'provider_id': netflixId, 'provider_name': 'Netflix'},
            {'provider_id': 77, 'provider_name': 'Disney Plus'},
            {'provider_id': 55, 'provider_name': 'Max'},
            {'provider_id': 99, 'provider_name': 'Amazon Prime Video'},
            {'provider_id': 100, 'provider_name': 'Hulu'},
            {
              'provider_id': 101,
              'provider_name': 'Netflix Standard with Ads',
            },
            {'provider_id': 102, 'provider_name': 'Max Amazon Channel'},
          ],
        };

    Map<String, Object> watch({
      List<Map<String, Object>> flatrate = const [],
      List<Map<String, Object>> rent = const [],
      List<Map<String, Object>> buy = const [],
      List<Map<String, Object>> ads = const [],
    }) =>
        {
          'results': {
            'US': {
              'flatrate': flatrate,
              'rent': rent,
              'buy': buy,
              'ads': ads,
            },
          },
        };

    setUp(() {
      calls = [];
      client = TmdbStreamingClient(
        apiKey: 'test-key',
        fetch: (uri) async {
          calls.add(uri);
          final path = uri.path;
          if (path.endsWith('/watch/providers/movie')) {
            return ok(providers(netflixId: 4242));
          }
          if (path.endsWith('/watch/providers/tv')) {
            return ok(providers(netflixId: 4243));
          }
          if (path.endsWith('/trending/all/week')) {
            return ok({
              'results': [
                {
                  'id': 1,
                  'media_type': 'movie',
                  'title': 'On Netflix',
                  'release_date': '2024-05-02',
                  'poster_path': '/netflix.jpg',
                },
                {
                  'id': 2,
                  'media_type': 'movie',
                  'title': 'Ads Only',
                  'release_date': '2023-01-01',
                },
                {
                  'id': 3,
                  'media_type': 'movie',
                  'title': 'Hulu Only',
                  'release_date': '2022-01-01',
                },
                {
                  'id': 4,
                  'media_type': 'movie',
                  'title': 'Rent Only',
                  'release_date': '2021-01-01',
                },
                {
                  'id': 5,
                  'media_type': 'tv',
                  'name': 'On Disney',
                  'first_air_date': '2020-02-02',
                },
                {'id': 6, 'media_type': 'person', 'name': 'Someone'},
              ],
            });
          }
          if (path.endsWith('/movie/1/watch/providers')) {
            return ok(watch(flatrate: [
              {'provider_id': 4242, 'provider_name': 'Netflix'},
              {'provider_id': 55, 'provider_name': 'Max'},
            ]));
          }
          if (path.endsWith('/movie/2/watch/providers')) {
            return ok(watch(ads: [
              {'provider_id': 4242, 'provider_name': 'Netflix'},
            ], buy: [
              {'provider_id': 99, 'provider_name': 'Amazon Prime Video'},
            ]));
          }
          if (path.endsWith('/movie/3/watch/providers')) {
            return ok(watch(flatrate: [
              {'provider_id': 100, 'provider_name': 'Hulu'},
            ]));
          }
          if (path.endsWith('/movie/4/watch/providers')) {
            return ok(watch(rent: [
              {'provider_id': 99, 'provider_name': 'Amazon Prime Video'},
            ]));
          }
          if (path.endsWith('/tv/5/watch/providers')) {
            return ok(watch(flatrate: [
              {'provider_id': 77, 'provider_name': 'Disney Plus'},
            ]));
          }
          if (path.contains('/discover/movie')) {
            return ok({
              'results': [
                {
                  'id': 1,
                  'title': 'On Netflix',
                  'release_date': '2024-05-02',
                },
                {
                  'id': 9,
                  'title': 'Also Netflix',
                  'release_date': '2019-08-08',
                },
              ],
            });
          }
          if (path.contains('/discover/tv')) {
            return ok({'results': []});
          }
          if (path.endsWith('/movie/9/watch/providers')) {
            return ok(watch(flatrate: [
              {'provider_id': 4242, 'provider_name': 'Netflix'},
            ]));
          }
          if (path.endsWith('/search/multi')) {
            return ok({
              'results': [
                {
                  'id': 1,
                  'media_type': 'movie',
                  'title': 'On Netflix',
                  'release_date': '2024-05-02',
                },
                {
                  'id': 3,
                  'media_type': 'movie',
                  'title': 'Hulu Only',
                  'release_date': '2022-01-01',
                },
                {'id': 6, 'media_type': 'person', 'name': 'Someone'},
              ],
            });
          }
          return ok({'results': []});
        },
      );
    });

    test('trending keeps only flatrate titles on the four services', () async {
      final page = await client.loadHome();

      expect(page.needsKey, isFalse);
      expect(page.error, isNull);
      final trending = page.rows.first.titles;
      expect(trending.map((title) => title.title), [
        'On Netflix',
        'On Disney',
      ]);
      expect(trending.first.year, 2024);
      expect(trending.first.services, [
        StreamingService.netflix,
        StreamingService.max,
      ]);
      expect(trending.last.services, [StreamingService.disneyPlus]);
      expect(
        calls.any((uri) => uri.path.contains('/person/')),
        isFalse,
      );
    });

    test('discover uses the looked-up id and flatrate only', () async {
      await client.loadHome();

      final movie = calls.where(
        (uri) => uri.path == '/3/discover/movie',
      );
      final netflixMovie = movie.where(
        (uri) => uri.queryParameters['with_watch_providers'] == '4242',
      );
      expect(netflixMovie, isNotEmpty);
      for (final uri in movie) {
        expect(uri.queryParameters['watch_region'], 'US');
        expect(
          uri.queryParameters['with_watch_monetization_types'],
          'flatrate',
        );
        expect(uri.queryParameters['with_watch_providers'], isNot('8'));
      }

      final tv = calls.where((uri) => uri.path == '/3/discover/tv');
      expect(
        tv.any(
          (uri) => uri.queryParameters['with_watch_providers'] == '4243',
        ),
        isTrue,
      );
      expect(
        tv.any(
          (uri) => uri.queryParameters['with_watch_providers'] == '4242',
        ),
        isFalse,
      );

      final netflixRow = pageRow(pageRows: (await client.loadHome()).rows);
      expect(netflixRow.map((title) => title.title), [
        'On Netflix',
        'Also Netflix',
      ]);
    });

    test('search drops anything not on flatrate for those four', () async {
      final page = await client.search('netflix');
      expect(page.titles.map((title) => title.title), ['On Netflix']);
    });

    test('responses stay cached for six hours and then expire', () async {
      var now = DateTime.utc(2026, 1, 1, 12);
      final timed = TmdbStreamingClient(
        apiKey: 'test-key',
        clock: Clock(() => now),
        fetch: clientFetch(),
      );

      await timed.loadHome();
      final afterFirst = _fetchCount;
      expect(afterFirst, greaterThan(0));

      await timed.loadHome();
      expect(_fetchCount, afterFirst);

      now = now.add(const Duration(hours: 6) - const Duration(milliseconds: 1));
      await timed.loadHome();
      expect(_fetchCount, afterFirst);

      now = DateTime.utc(2026, 1, 1, 12).add(const Duration(hours: 6));
      await timed.loadHome();
      expect(_fetchCount, greaterThan(afterFirst));
    });

    test('an empty key never calls TMDB', () async {
      final calls = <Uri>[];
      final empty = TmdbStreamingClient(
        apiKey: '   ',
        fetch: (uri) async {
          calls.add(uri);
          return const TmdbFetchResult(500, '');
        },
      );

      final home = await empty.loadHome();
      final searched = await empty.search('dune');

      expect(home.needsKey, isTrue);
      expect(home.message, 'Add a TMDB key in Settings');
      expect(searched.needsKey, isTrue);
      expect(searched.message, kStreamingMissingKeyMessage);
      expect(calls, isEmpty);
    });
  });
}

int _fetchCount = 0;

TmdbFetch clientFetch() {
  _fetchCount = 0;
  return (uri) async {
    _fetchCount++;
    return const TmdbFetchResult(
      200,
      '{"results":[{"provider_id":1,"provider_name":"Netflix"},'
      '{"provider_id":2,"provider_name":"Disney Plus"},'
      '{"provider_id":3,"provider_name":"Max"},'
      '{"provider_id":4,"provider_name":"Amazon Prime Video"}]}',
    );
  };
}

List<StreamingTitle> pageRow({required List<StreamingRow> pageRows}) {
  return pageRows.firstWhere((row) => row.title == 'Netflix').titles;
}
