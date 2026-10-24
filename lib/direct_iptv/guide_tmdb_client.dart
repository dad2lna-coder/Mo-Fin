import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../streaming/tmdb_key_store.dart';
import 'guide_tmdb.dart';

typedef GuideTmdbFetch = Future<GuideTmdbResponse> Function(Uri uri);

class GuideTmdbResponse {
  final int statusCode;
  final String body;

  const GuideTmdbResponse(this.statusCode, this.body);
}

/// TMDB v3 lookups for the guide and the channel overlay.
///
/// The key is a query parameter and is never written into an error, a log
/// line, or a widget. An empty key, a transport failure, or a weak title
/// match returns null so the caller keeps the EPG text.
class GuideTmdbLookup {
  GuideTmdbLookup({
    required GuideTmdbFetch fetch,
    GuideTmdbCache? cache,
    this.maxInFlight = 4,
    Future<String> Function()? readKey,
  }) : _fetch = fetch,
       _cache = cache ?? GuideTmdbCache(),
       _readKey = readKey ?? (() async => ''),
       _limiter = _RequestLimiter(maxInFlight);

  /// One shared cache for the guide and the player overlay.
  static final GuideTmdbLookup shared = GuideTmdbLookup.network();

  factory GuideTmdbLookup.network({http.Client? client}) {
    final httpClient = client ?? http.Client();
    final store = TmdbKeyStore();
    return GuideTmdbLookup(
      fetch: (uri) async {
        final response = await httpClient.get(uri);
        return GuideTmdbResponse(response.statusCode, response.body);
      },
      readKey: store.read,
    );
  }

  final GuideTmdbFetch _fetch;
  final GuideTmdbCache _cache;
  final int maxInFlight;
  final Future<String> Function() _readKey;
  final _RequestLimiter _limiter;
  String? _key;
  Future<String>? _keyRead;

  GuideTmdbCache get cache => _cache;

  Future<String> peekKey() {
    final pending = _keyRead;
    if (pending != null) return pending;
    final read = _loadKey();
    _keyRead = read;
    return read;
  }

  Future<String> _loadKey() async {
    final cached = _key;
    if (cached != null) return cached;
    try {
      final value = (await _readKey()).trim();
      _key = value;
      return value;
    } catch (_) {
      _key = '';
      return '';
    }
  }

  /// Synchronous peek. Null means "not cached" (or expired). A cached miss
  /// is also null here; [lookup] is what avoids the network in that case.
  GuideTmdbHit? cachedHit(GuideQuery query) {
    final key = guideTmdbCacheKey(query);
    if (key.isEmpty) return null;
    return _cache.read(key)?.hit;
  }

  Future<GuideTmdbHit?> lookup(GuideQuery query, {String? apiKey}) async {
    final cacheKey = guideTmdbCacheKey(query);
    if (cacheKey.isEmpty) return null;
    final stored = _cache.read(cacheKey);
    if (stored != null) return stored.hit;

    final key = (apiKey ?? await peekKey()).trim();
    if (key.isEmpty) return null;

    try {
      final found = await _search(query, key);
      if (found == null) return null;
      final picked = pickGuideMatch(query, found);
      if (picked == null) {
        _cache.write(cacheKey, null);
        return null;
      }
      final hit = await _details(query, picked, key);
      if (hit == null) return null;
      _cache.write(cacheKey, hit);
      return hit;
    } catch (_) {
      return null;
    }
  }

  Future<List<TmdbCandidate>?> _search(GuideQuery query, String apiKey) async {
    final json = await _get('/3/search/multi', {
      'api_key': apiKey,
      'query': query.searchTitle,
      'include_adult': 'false',
      'language': 'en-US',
    });
    if (json == null) return null;
    final results = json['results'];
    if (results is! List) return const [];
    final candidates = <TmdbCandidate>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final type = raw['media_type']?.toString() ?? '';
      if (type != 'tv' && type != 'movie') continue;
      final id = _asInt(raw['id']);
      if (id == null) continue;
      final title = type == 'tv'
          ? (raw['name'] ?? raw['original_name'])?.toString() ?? ''
          : (raw['title'] ?? raw['original_title'])?.toString() ?? '';
      if (title.isEmpty) continue;
      candidates.add(
        TmdbCandidate(
          id: id,
          mediaType: type,
          title: title,
          year: _yearFrom(raw['first_air_date'] ?? raw['release_date']),
        ),
      );
    }
    return candidates;
  }

  Future<GuideTmdbHit?> _details(
    GuideQuery query,
    TmdbCandidate picked,
    String apiKey,
  ) async {
    final path = picked.mediaType == 'tv'
        ? '/3/tv/${picked.id}'
        : '/3/movie/${picked.id}';
    final json = await _get(path, {
      'api_key': apiKey,
      'append_to_response': 'credits',
      'language': 'en-US',
    });
    if (json == null) return null;
    final title = picked.mediaType == 'tv'
        ? (json['name'] ?? picked.title).toString()
        : (json['title'] ?? picked.title).toString();
    if (!titlesConfidentlyMatch(
      query.searchTitle,
      title,
      queryYear: query.year,
      candidateYear: _yearFrom(json['first_air_date'] ?? json['release_date']),
    )) {
      return null;
    }
    var overview = shortenOverview(json['overview']?.toString() ?? '');
    var cast = _cast(json['credits']);
    final poster = _image(json['poster_path'], width: 'w342');
    String? episodeName;
    String? episodeOverview;
    String? still;
    if (picked.mediaType == 'tv' && query.hasEpisode) {
      final episode = await _get(
        '/3/tv/${picked.id}/season/${query.season}/episode/${query.episode}',
        {
          'api_key': apiKey,
          'append_to_response': 'credits',
          'language': 'en-US',
        },
      );
      if (episode != null) {
        episodeName = _blank(episode['name']?.toString());
        final episodeText = shortenOverview(
          episode['overview']?.toString() ?? '',
        );
        if (episodeText.isNotEmpty) episodeOverview = episodeText;
        still = _image(episode['still_path'], width: 'w300');
        final episodeCast = _cast(episode['credits']);
        if (episodeCast.isNotEmpty) cast = episodeCast;
      }
    }
    return GuideTmdbHit(
      id: picked.id,
      mediaType: picked.mediaType,
      title: title,
      year:
          _yearFrom(json['first_air_date'] ?? json['release_date']) ??
          picked.year,
      rating: _rating(json['vote_average']),
      genres: _genres(json['genres']),
      overview: overview,
      cast: cast,
      posterUrl: poster,
      episodeName: episodeName,
      episodeOverview: episodeOverview,
      stillUrl: still,
      season: query.season,
      episode: query.episode,
    );
  }

  Future<Map<String, dynamic>?> _get(
    String path,
    Map<String, String> query,
  ) async {
    await _limiter.acquire();
    try {
      final uri = Uri.https('api.themoviedb.org', path, query);
      final response = await _fetch(uri);
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    } finally {
      _limiter.release();
    }
  }
}

class _RequestLimiter {
  _RequestLimiter(this.max);

  final int max;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_active < max) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    if (_active > 0) _active--;
  }
}

List<String> _genres(Object? raw) {
  if (raw is! List) return const [];
  final names = <String>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    names.add(name);
    if (names.length == 3) break;
  }
  return names;
}

List<String> _cast(Object? raw) {
  if (raw is! Map) return const [];
  final list = raw['cast'];
  if (list is! List) return const [];
  final people = <({int order, String name})>[];
  for (final entry in list) {
    if (entry is! Map) continue;
    final name = entry['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    people.add((order: _asInt(entry['order']) ?? 999, name: name));
  }
  people.sort((a, b) => a.order.compareTo(b.order));
  return [for (final person in people.take(4)) person.name];
}

String? _image(Object? path, {required String width}) {
  final text = path?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  final suffix = text.startsWith('/') ? text : '/$text';
  return 'https://image.tmdb.org/t/p/$width$suffix';
}

double? _rating(Object? raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || value <= 0) return null;
  return value;
}

int? _yearFrom(Object? raw) {
  final text = raw?.toString() ?? '';
  if (text.length < 4) return null;
  return int.tryParse(text.substring(0, 4));
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

String? _blank(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
