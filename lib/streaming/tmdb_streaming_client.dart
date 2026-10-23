import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import 'streaming_service.dart';

const String kStreamingMissingKeyMessage = 'Add a TMDB key in Settings';

const _tmdbHost = 'api.themoviedb.org';
const _region = 'US';
const _defaultTtl = Duration(hours: 6);
const _providerLookupLimit = 8;

class TmdbFetchResult {
  final int statusCode;
  final String body;

  const TmdbFetchResult(this.statusCode, this.body);
}

/// A TMDB failure that is safe to show. It never carries the request URL.
class TmdbRequestException implements Exception {
  final int? statusCode;

  const TmdbRequestException(this.statusCode);

  String get display => statusCode == null
      ? "Couldn't reach TMDB"
      : "Couldn't reach TMDB ($statusCode)";
}

/// Text for a Streaming error. Anything that might contain `api_key` or a
/// [ClientException] is replaced.
String streamingErrorText(Object error) {
  if (error is TmdbRequestException) return error.display;
  final text = error.toString();
  if (text.startsWith("Couldn't reach TMDB") &&
      !text.contains('api_key') &&
      !text.contains('http')) {
    return text;
  }
  return "Couldn't reach TMDB";
}

typedef TmdbFetch = Future<TmdbFetchResult> Function(Uri uri);

class StreamingTitle {
  final int id;
  final String mediaType;
  final String title;
  final int? year;
  final String? posterPath;
  final String? overview;
  final double? rating;
  final int? runtimeMinutes;
  final int? seasons;
  final List<StreamingService> services;

  const StreamingTitle({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
    this.posterPath,
    this.overview,
    this.rating,
    this.runtimeMinutes,
    this.seasons,
    this.services = const [],
  });

  String? get posterUrl {
    final path = posterPath;
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w342$path';
  }

  String get detailLine {
    final bits = <String>[];
    if (rating != null && rating! > 0) {
      bits.add('${rating!.toStringAsFixed(1)} / 10');
    }
    if (mediaType == 'tv') {
      final count = seasons;
      if (count != null && count > 0) {
        bits.add(count == 1 ? '1 season' : '$count seasons');
      }
    } else if (runtimeMinutes != null && runtimeMinutes! > 0) {
      final hours = runtimeMinutes! ~/ 60;
      final minutes = runtimeMinutes! % 60;
      if (hours > 0 && minutes > 0) {
        bits.add('${hours}h ${minutes}m');
      } else if (hours > 0) {
        bits.add('${hours}h');
      } else {
        bits.add('${minutes}m');
      }
    }
    return bits.join(' · ');
  }
}

class StreamingRow {
  final String title;
  final StreamingService? service;
  final List<StreamingTitle> titles;

  const StreamingRow({
    required this.title,
    required this.titles,
    this.service,
  });
}

class StreamingPage {
  final bool needsKey;
  final String? error;
  final List<StreamingRow> rows;
  final List<StreamingTitle> titles;

  const StreamingPage({
    this.needsKey = false,
    this.error,
    this.rows = const [],
    this.titles = const [],
  });

  String get message =>
      needsKey ? kStreamingMissingKeyMessage : (error ?? '');
}

class _CacheEntry {
  final DateTime at;
  final Object? json;

  const _CacheEntry(this.at, this.json);
}

class _ProviderIds {
  final Map<StreamingService, int> movie;
  final Map<StreamingService, int> tv;

  const _ProviderIds(this.movie, this.tv);

  int? idFor(StreamingService service, String mediaType) =>
      (mediaType == 'tv' ? tv : movie)[service];
}

/// TMDB v3 client for the Streaming tab. It only calls api.themoviedb.org.
class TmdbStreamingClient {
  TmdbStreamingClient({
    required this.apiKey,
    required TmdbFetch fetch,
    Clock? clock,
    Duration? ttl,
  })  : _fetch = fetch,
        _clock = clock ?? const Clock(),
        _ttl = ttl ?? _defaultTtl;

  static final Map<String, TmdbStreamingClient> _byKey = {};

  /// One client per key so home, search, and details share the 6-hour cache.
  /// A different key replaces it. [create] is for tests.
  static TmdbStreamingClient forKey(
    String apiKey, {
    TmdbStreamingClient Function(String apiKey)? create,
  }) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return TmdbStreamingClient(
        apiKey: '',
        fetch: (_) async => const TmdbFetchResult(0, ''),
      );
    }
    final existing = _byKey[trimmed];
    if (existing != null) return existing;
    final client = create?.call(trimmed) ?? TmdbStreamingClient.network(trimmed);
    _byKey
      ..clear()
      ..[trimmed] = client;
    return client;
  }

  static void resetSharedClients() => _byKey.clear();

  factory TmdbStreamingClient.network(
    String apiKey, {
    http.Client? client,
    Clock? clock,
  }) {
    final httpClient = client ?? http.Client();
    return TmdbStreamingClient(
      apiKey: apiKey,
      clock: clock,
      fetch: (uri) async {
        final response = await httpClient.get(uri);
        return TmdbFetchResult(response.statusCode, response.body);
      },
    );
  }

  final String apiKey;
  final TmdbFetch _fetch;
  final Clock _clock;
  final Duration _ttl;
  final Map<String, _CacheEntry> _cache = {};

  bool get hasKey => apiKey.trim().isNotEmpty;

  Future<StreamingPage> loadHome() async {
    if (!hasKey) {
      return const StreamingPage(needsKey: true);
    }
    try {
      final ids = await _providerIds();
      final trending = await _trending(ids);
      final rows = <StreamingRow>[
        StreamingRow(title: 'Trending', titles: trending),
      ];
      for (final service in kStreamingServices) {
        final titles = await _discoverService(service, ids);
        if (titles.isEmpty &&
            ids.movie[service] == null &&
            ids.tv[service] == null) {
          continue;
        }
        rows.add(StreamingRow(
          title: service.label,
          service: service,
          titles: titles,
        ));
      }
      return StreamingPage(rows: rows);
    } on TmdbRequestException catch (error) {
      return StreamingPage(error: error.display);
    } catch (error) {
      return StreamingPage(error: streamingErrorText(error));
    }
  }

  Future<StreamingPage> search(String query) async {
    if (!hasKey) {
      return const StreamingPage(needsKey: true);
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const StreamingPage();
    try {
      final ids = await _providerIds();
      final json = await _get('/search/multi', {
        'query': trimmed,
        'include_adult': 'false',
        'language': 'en-US',
      });
      final results = _list(json, 'results');
      final pending = <_PendingTitle>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final type = raw['media_type']?.toString() ?? '';
        if (type != 'movie' && type != 'tv') continue;
        final id = _int(raw['id']);
        if (id == null) continue;
        pending.add(_PendingTitle(raw, type, id));
      }
      final matches = await _mapPool(pending, (item) async {
        final services = await _servicesFor(item.type, item.id, ids);
        if (services.isEmpty) return null;
        return _titleFrom(item.raw, item.type, services: services);
      });
      return StreamingPage(titles: matches);
    } on TmdbRequestException catch (error) {
      return StreamingPage(error: error.display);
    } catch (error) {
      return StreamingPage(error: streamingErrorText(error));
    }
  }

  Future<StreamingTitle?> details({
    required String mediaType,
    required int id,
  }) async {
    if (!hasKey || (mediaType != 'movie' && mediaType != 'tv') || id <= 0) {
      return null;
    }
    final ids = await _providerIds();
    final path = mediaType == 'tv' ? '/tv/$id' : '/movie/$id';
    final json = await _get(path, {'language': 'en-US'});
    if (json is! Map) return null;
    final services = await _servicesFor(mediaType, id, ids);
    return _titleFrom(
      json,
      mediaType,
      services: services,
      overview: json['overview']?.toString(),
      rating: _double(json['vote_average']),
      runtimeMinutes: _int(json['runtime']),
      seasons: _int(json['number_of_seasons']),
    );
  }

  Future<List<StreamingTitle>> _trending(_ProviderIds ids) async {
    final json = await _get('/trending/all/week', {'language': 'en-US'});
    final pending = <_PendingTitle>[];
    for (final raw in _list(json, 'results')) {
      if (raw is! Map) continue;
      final type = raw['media_type']?.toString() ?? '';
      if (type != 'movie' && type != 'tv') continue;
      final id = _int(raw['id']);
      if (id == null) continue;
      pending.add(_PendingTitle(raw, type, id));
    }
    return _mapPool(pending, (item) async {
      final services = await _servicesFor(item.type, item.id, ids);
      if (services.isEmpty) return null;
      return _titleFrom(item.raw, item.type, services: services);
    });
  }

  Future<List<StreamingTitle>> _discoverService(
    StreamingService service,
    _ProviderIds ids,
  ) async {
    final found = <String, StreamingTitle>{};
    for (final type in const ['movie', 'tv']) {
      final providerId = ids.idFor(service, type);
      if (providerId == null) continue;
      final json = await _get('/discover/$type', {
        'with_watch_providers': '$providerId',
        'watch_region': _region,
        'with_watch_monetization_types': 'flatrate',
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'language': 'en-US',
      });
      final pending = <_PendingTitle>[];
      for (final raw in _list(json, 'results')) {
        if (raw is! Map) continue;
        final id = _int(raw['id']);
        if (id == null) continue;
        pending.add(_PendingTitle(raw, type, id));
      }
      final titles = await _mapPool(pending, (item) async {
        final services = await _servicesFor(item.type, item.id, ids);
        if (!services.contains(service)) return null;
        return _titleFrom(item.raw, item.type, services: services);
      });
      for (final title in titles) {
        found['${title.mediaType}:${title.id}'] = title;
      }
    }
    final titles = found.values.toList();
    return titles.length > 20 ? titles.sublist(0, 20) : titles;
  }

  Future<List<StreamingService>> _servicesFor(
    String mediaType,
    int id,
    _ProviderIds ids,
  ) async {
    final json = await _get('/$mediaType/$id/watch/providers', const {});
    return _flatrateServices(json, mediaType: mediaType, ids: ids);
  }

  List<StreamingService> _flatrateServices(
    Object? json, {
    required String mediaType,
    required _ProviderIds ids,
  }) {
    if (json is! Map) return const [];
    final results = json['results'];
    if (results is! Map) return const [];
    final region = results[_region];
    if (region is! Map) return const [];
    final flatrate = region['flatrate'];
    if (flatrate is! List) return const [];
    final matched = <StreamingService>[];
    for (final entry in flatrate) {
      if (entry is! Map) continue;
      final name = entry['provider_name']?.toString() ?? '';
      final service = streamingServiceForProviderName(name);
      if (service == null) continue;
      final providerId = _int(entry['provider_id']);
      final expected = ids.idFor(service, mediaType);
      if (expected == null || providerId != expected) continue;
      if (!matched.contains(service)) matched.add(service);
    }
    return matched;
  }

  Future<_ProviderIds> _providerIds() async {
    final movie = await _idsFor('/watch/providers/movie');
    final tv = await _idsFor('/watch/providers/tv');
    return _ProviderIds(movie, tv);
  }

  Future<Map<StreamingService, int>> _idsFor(String path) async {
    final json = await _get(path, {'watch_region': _region});
    final found = <StreamingService, int>{};
    for (final entry in _list(json, 'results')) {
      if (entry is! Map) continue;
      final service = streamingServiceForProviderName(
        entry['provider_name']?.toString() ?? '',
      );
      final id = _int(entry['provider_id']);
      if (service == null || id == null || found.containsKey(service)) {
        continue;
      }
      found[service] = id;
    }
    return found;
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    final key = _cacheKey(path, query);
    final cached = _cache[key];
    final now = _clock.now();
    if (cached != null && now.difference(cached.at) < _ttl) {
      return cached.json;
    }
    final uri = Uri.https(_tmdbHost, '/3$path', {
      ...query,
      'api_key': apiKey.trim(),
    });
    final TmdbFetchResult response;
    try {
      response = await _fetch(uri);
    } catch (_) {
      throw const TmdbRequestException(null);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbRequestException(response.statusCode);
    }
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    _cache[key] = _CacheEntry(now, decoded);
    return decoded;
  }

  String _cacheKey(String path, Map<String, String> query) {
    final keys = query.keys.toList()..sort();
    final parts = [path];
    for (final key in keys) {
      parts.add('$key=${query[key]}');
    }
    return parts.join('&');
  }

  Future<List<StreamingTitle>> _mapPool(
    List<_PendingTitle> items,
    Future<StreamingTitle?> Function(_PendingTitle item) work,
  ) async {
    if (items.isEmpty) return const [];
    final results = List<StreamingTitle?>.filled(items.length, null);
    var cursor = 0;
    Future<void> run() async {
      while (true) {
        final index = cursor;
        if (index >= items.length) return;
        cursor += 1;
        results[index] = await work(items[index]);
      }
    }

    final workers = items.length < _providerLookupLimit
        ? items.length
        : _providerLookupLimit;
    await Future.wait(List.generate(workers, (_) => run()));
    return [for (final title in results) if (title != null) title];
  }

  StreamingTitle _titleFrom(
    Map raw,
    String mediaType, {
    required List<StreamingService> services,
    String? overview,
    double? rating,
    int? runtimeMinutes,
    int? seasons,
  }) {
    final title = mediaType == 'tv'
        ? (raw['name']?.toString() ?? raw['title']?.toString() ?? '')
        : (raw['title']?.toString() ?? raw['name']?.toString() ?? '');
    final date = mediaType == 'tv'
        ? raw['first_air_date']?.toString()
        : raw['release_date']?.toString();
    return StreamingTitle(
      id: _int(raw['id']) ?? 0,
      mediaType: mediaType,
      title: title,
      year: _year(date),
      posterPath: raw['poster_path']?.toString(),
      overview: overview,
      rating: rating,
      runtimeMinutes: runtimeMinutes,
      seasons: seasons,
      services: services,
    );
  }
}

class _PendingTitle {
  final Map raw;
  final String type;
  final int id;

  const _PendingTitle(this.raw, this.type, this.id);
}

List<dynamic> _list(Object? json, String key) {
  if (json is! Map) return const [];
  final value = json[key];
  return value is List ? value : const [];
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _year(String? date) {
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}
