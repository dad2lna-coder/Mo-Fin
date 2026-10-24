import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/guide_tmdb.dart';
import 'package:moonfin/direct_iptv/guide_tmdb_client.dart';

void main() {
  group('title normalization', () {
    test('strips broadcast tags, quality, and episode suffixes', () {
      expect(
        normalizeGuideTitle('New: The Office (HD) S6E19'),
        'the office',
      );
      expect(cleanGuideTitle('New: The Office (HD) S6E19'), 'The Office');
      expect(normalizeGuideTitle('Live: Cops 6x12 (HDTV)'), 'cops');
      expect(
        normalizeGuideTitle('Premiere: Grey\'s Anatomy Season 2 Episode 5'),
        'greys anatomy',
      );
      expect(normalizeGuideTitle('Encore: The Office (1080p)'), 'the office');
      expect(extractGuideYear('The Office (2005)'), 2005);
      expect(extractGuideYear('1917'), isNull);
    });

    test('reads season and episode from the title and from xmltv', () {
      expect(parseSeasonEpisode('The Office S6E19')?.season, 6);
      expect(parseSeasonEpisode('The Office S6E19')?.episode, 19);
      expect(parseSeasonEpisode('Cops 6x12')?.episode, 12);
      expect(parseSeasonEpisode('Season 2 Episode 5')?.season, 2);
      expect(parseEpisodeNum('5.18.', system: 'xmltv_ns')?.season, 6);
      expect(parseEpisodeNum('5.18.', system: 'xmltv_ns')?.episode, 19);
      expect(parseEpisodeNum('S06E19', system: 'onscreen')?.episode, 19);

      final query = GuideQuery.resolve(
        title: 'New: The Office (HD)',
        episodeNum: '5.18.',
      );
      expect(query.searchTitle, 'The Office');
      expect(query.season, 6);
      expect(query.episode, 19);
      expect(query.hasEpisode, isTrue);
    });

    test('the same cleaned title shares a cache key', () {
      expect(
        guideTmdbCacheKey(GuideQuery.resolve(title: 'New: The Office (HD)')),
        guideTmdbCacheKey(GuideQuery.resolve(title: 'The Office')),
      );
      expect(
        guideTmdbCacheKey(
          GuideQuery.resolve(title: 'The Office', season: 2, episode: 5),
        ),
        'the office|2|5',
      );
      expect(
        guideTmdbCacheKey(GuideQuery.resolve(title: 'New: The Office (HD)')),
        isNot('the office|2|5'),
      );
    });
  });

  group('match confidence', () {
    test('accepts the same show and rejects a spin-off or the wrong year', () {
      expect(titlesConfidentlyMatch('The Office', 'The Office'), isTrue);
      expect(titlesConfidentlyMatch('The Office', 'Office'), isTrue);
      expect(
        titlesConfidentlyMatch('Law & Order', 'Law & Order: SVU'),
        isFalse,
      );
      expect(titlesConfidentlyMatch('Cops', 'Cops Reloaded'), isFalse);
      expect(
        titlesConfidentlyMatch(
          'The Office (2005)',
          'The Office',
          queryYear: 2005,
          candidateYear: 2013,
        ),
        isFalse,
      );
      expect(
        titlesConfidentlyMatch(
          'The Office',
          'The Office',
          queryYear: 2005,
          candidateYear: 2006,
        ),
        isTrue,
      );
    });

    test('prefers a TV match, and a known episode never takes a movie', () {
      const tv = TmdbCandidate(id: 2, mediaType: 'tv', title: 'The Office');
      const movie = TmdbCandidate(
        id: 1,
        mediaType: 'movie',
        title: 'The Office',
      );
      expect(
        pickGuideMatch(GuideQuery.resolve(title: 'The Office'), [
          movie,
          tv,
        ])?.id,
        2,
      );
      expect(
        pickGuideMatch(
          GuideQuery.resolve(title: 'The Office', season: 2, episode: 1),
          [movie],
        ),
        isNull,
      );
      expect(
        pickGuideMatch(GuideQuery.resolve(title: 'Dune'), [
          const TmdbCandidate(id: 8, mediaType: 'movie', title: 'Dune'),
        ])?.mediaType,
        'movie',
      );
      expect(
        pickGuideMatch(GuideQuery.resolve(title: 'The Office'), [
          const TmdbCandidate(
            id: 3,
            mediaType: 'tv',
            title: 'The Office: An American Workplace Extra',
          ),
        ]),
        isNull,
      );
    });
  });

  group('cache', () {
    test('keeps a hit and a confident miss for 24 hours', () {
      var now = DateTime.utc(2026, 10, 21, 12);
      final cache = GuideTmdbCache(now: () => now);
      const hit = GuideTmdbHit(id: 1, mediaType: 'tv', title: 'The Office');
      cache.write('the office', hit);
      cache.write('missing', null);

      expect(cache.read('the office')?.hit, same(hit));
      expect(cache.read('missing'), isNotNull);
      expect(cache.read('missing')!.hit, isNull);
      expect(cache.read('never'), isNull);

      now = now.add(const Duration(hours: 23, minutes: 59));
      expect(cache.read('the office')?.hit?.title, 'The Office');

      now = now.add(const Duration(minutes: 2));
      expect(cache.read('the office'), isNull);
      expect(cache.read('missing'), isNull);
    });

    test('an empty key does not call the network or surface an error', () async {
      var calls = 0;
      final lookup = GuideTmdbLookup(
        readKey: () async => '   ',
        fetch: (uri) async {
          calls++;
          throw StateError(uri.toString());
        },
      );
      expect(
        await lookup.lookup(GuideQuery.resolve(title: 'The Office')),
        isNull,
      );
      expect(calls, 0);
    });

    test('a failed request is not cached and the key stays inside the client', () async {
      const secret = 'guide-tmdb-test-key';
      var calls = 0;
      final lookup = GuideTmdbLookup(
        readKey: () async => secret,
        fetch: (uri) async {
          calls++;
          throw StateError('transport');
        },
      );
      expect(
        await lookup.lookup(GuideQuery.resolve(title: 'The Office')),
        isNull,
      );
      expect(calls, 1);
      expect(
        await lookup.lookup(GuideQuery.resolve(title: 'The Office')),
        isNull,
      );
      expect(calls, 2);
    });

    test('a weak match is remembered and a details failure is not', () async {
      var calls = 0;
      final weak = GuideTmdbLookup(
        readKey: () async => 'k',
        fetch: (uri) async {
          calls++;
          return const GuideTmdbResponse(
            200,
            '{"results":[{"id":4,"media_type":"tv","name":"Cops Reloaded"}]}',
          );
        },
      );
      expect(
        await weak.lookup(GuideQuery.resolve(title: 'Cops')),
        isNull,
      );
      expect(calls, 1);
      expect(await weak.lookup(GuideQuery.resolve(title: 'Cops')), isNull);
      expect(calls, 1);

      var detailCalls = 0;
      final flaky = GuideTmdbLookup(
        readKey: () async => 'k',
        fetch: (uri) async {
          detailCalls++;
          if (uri.path.contains('search')) {
            return const GuideTmdbResponse(
              200,
              '{"results":[{"id":9,"media_type":"tv","name":"The Office","first_air_date":"2005-03-24"}]}',
            );
          }
          return const GuideTmdbResponse(500, '');
        },
      );
      expect(
        await flaky.lookup(GuideQuery.resolve(title: 'The Office')),
        isNull,
      );
      final afterFailure = detailCalls;
      expect(afterFailure, greaterThan(1));
      expect(
        await flaky.lookup(GuideQuery.resolve(title: 'The Office')),
        isNull,
      );
      expect(detailCalls, greaterThan(afterFailure));
    });

    test('a confident episode is cached and not fetched again', () async {
      var calls = 0;
      final paths = <String>[];
      final lookup = GuideTmdbLookup(
        readKey: () async => 'k',
        fetch: (uri) async {
          calls++;
          paths.add(uri.path);
          if (uri.path.contains('search')) {
            return const GuideTmdbResponse(
              200,
              '{"results":['
              '{"id":1,"media_type":"movie","title":"The Office","release_date":"2005-01-01"},'
              '{"id":2,"media_type":"tv","name":"The Office","first_air_date":"2005-03-24"}'
              ']}',
            );
          }
          if (uri.path.contains('episode')) {
            return const GuideTmdbResponse(
              200,
              '{"name":"Stress Relief","overview":"Dwight starts a fire.","still_path":"/still.jpg"}',
            );
          }
          return const GuideTmdbResponse(
            200,
            '{"name":"The Office","first_air_date":"2005-03-24","vote_average":8.5,'
            '"overview":"A mockumentary about a paper company.",'
            '"poster_path":"/poster.jpg",'
            '"genres":[{"name":"Comedy"}],'
            '"credits":{"cast":[{"name":"Steve Carell","order":0},{"name":"Rainn Wilson","order":1}]}}',
          );
        },
      );
      final hit = await lookup.lookup(
        GuideQuery.resolve(title: 'New: The Office (HD)', season: 2, episode: 5),
      );
      expect(hit, isNotNull);
      expect(hit!.mediaType, 'tv');
      expect(hit.id, 2);
      expect(hit.year, 2005);
      expect(hit.rating, 8.5);
      expect(hit.genres, ['Comedy']);
      expect(hit.cast.first, 'Steve Carell');
      expect(hit.episodeName, 'Stress Relief');
      expect(hit.displayOverview, 'Dwight starts a fire.');
      expect(hit.imageUrl, 'https://image.tmdb.org/t/p/w300/still.jpg');
      expect(hit.posterUrl, 'https://image.tmdb.org/t/p/w342/poster.jpg');
      expect(paths, [
        '/3/search/multi',
        '/3/tv/2',
        '/3/tv/2/season/2/episode/5',
      ]);
      expect(paths.every((path) => !path.contains('api_key')), isTrue);

      final fetched = calls;
      final again = await lookup.lookup(
        GuideQuery.resolve(title: 'The Office', season: 2, episode: 5),
      );
      expect(again?.episodeName, 'Stress Relief');
      expect(calls, fetched);
    });

    test('at most four lookups run at once', () async {
      var active = 0;
      var peak = 0;
      final waiting = <Completer<void>>[];
      final lookup = GuideTmdbLookup(
        maxInFlight: 4,
        readKey: () async => 'k',
        fetch: (uri) async {
          active++;
          if (active > peak) peak = active;
          final gate = Completer<void>();
          waiting.add(gate);
          await gate.future;
          active--;
          return const GuideTmdbResponse(200, '{"results":[]}');
        },
      );
      final pending = [
        for (var i = 0; i < 6)
          lookup.lookup(GuideQuery.resolve(title: 'Show $i')),
      ];
      await _until(() => waiting.length >= 4 && active == 4);
      expect(peak, 4);
      expect(waiting, hasLength(4));
      for (final gate in List<Completer<void>>.of(waiting)) {
        if (!gate.isCompleted) gate.complete();
      }
      await _until(() => waiting.length == 6);
      for (final gate in waiting) {
        if (!gate.isCompleted) gate.complete();
      }
      final hits = await Future.wait(pending);
      expect(hits, everyElement(isNull));
      expect(peak, 4);
    });
  });
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 40; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not met');
}
