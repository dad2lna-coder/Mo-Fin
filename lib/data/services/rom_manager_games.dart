import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

/// One page of the ROM Manager catalog the phone Games page already shows.
///
/// `POST /Moonfin/Plugins/rom-manager/games` reads the Channel Manager index.
/// Rows are grouped on `mg` and titled from `t`, so an arcade clone is not its
/// own tile and the caption is the MAME name rather than the zip. The plugin
/// refuses a limit above [pageSize].
class RomManagerGames {
  RomManagerGames({Dio? dio, Duration? timeout})
    : _dio = dio ?? Dio(),
      _timeout = timeout ?? requestTimeout {
    if (dio == null) configureServerDio(_dio);
  }

  static const String pluginId = 'rom-manager';

  /// [RomQuery.MaxPage]. Asking for more is clamped, so the next offset would
  /// skip rows if the client assumed a larger window.
  static const int pageSize = 60;

  /// Page size the phone hub uses. Kept at or under [pageSize].
  static const int libraryPageSize = 48;

  /// Systems with more games than this open on the six letter ranges.
  static const int bucketThreshold = 1000;

  static const letterBuckets = <({String id, String label})>[
    (id: '#-D', label: '# – D'),
    (id: 'E-H', label: 'E – H'),
    (id: 'I-L', label: 'I – L'),
    (id: 'M-P', label: 'M – P'),
    (id: 'Q-S', label: 'Q – S'),
    (id: 'T-Z', label: 'T – Z'),
  ];

  /// [RomChannel.MaxCovers].
  static const int maxCovers = 24;

  static const Duration requestTimeout = Duration(seconds: 60);

  /// Why the last [page] returned null. Unset after a successful page, and
  /// left unset when a test double returns null without going through [page].
  RomCatalogFailure? lastFailure;

  final Dio _dio;
  final Duration _timeout;

  /// Null when the plugin is missing or the body is not a catalog page.
  /// An empty page with `ok: true` is a real answer (unknown system, or the
  /// index is still building) and is not null.
  ///
  /// [lastFailure] is [RomCatalogFailure.missing] only for HTTP 404. A timeout
  /// or any other error is [RomCatalogFailure.failed] so the screen can show
  /// a retry instead of the raw file list.
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    lastFailure = null;
    final reply = await _post(client, 'games', <String, dynamic>{
      'system': system,
      'sort': sort,
      'offset': offset,
      'limit': limit ?? pageSize,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (letter != null && letter.isNotEmpty) 'letter': letter,
      if (bucket != null && bucket.isNotEmpty) 'bucket': bucket,
      if (developer != null && developer.isNotEmpty) 'developer': developer,
      if (includeBuckets) 'includeBuckets': 1,
      if (keys != null) 'keys': keys,
    });
    if (reply.missing) {
      lastFailure = RomCatalogFailure.missing;
      return null;
    }
    final data = reply.data;
    if (data == null || data['ok'] != true) {
      lastFailure = RomCatalogFailure.failed;
      return null;
    }
    final raw = data['items'];
    if (raw is! List) {
      lastFailure = RomCatalogFailure.failed;
      return null;
    }
    final items = <RomManagerGame>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final key = row['key'];
      if (key is! String || key.isEmpty) continue;
      items.add(
        RomManagerGame(
          key: key,
          title: row['title'] is String ? row['title'] as String : '',
          system: row['system'] is String ? row['system'] as String : system,
          path: row['coverPath'] is String ? row['coverPath'] as String : '',
          versions: row['versions'] is num
              ? (row['versions'] as num).toInt()
              : 1,
          cheat: _flag(row['cheat']),
          hack: _flag(row['hack']),
        ),
      );
    }
    final total = data['total'];
    return RomManagerGamePage(
      items: items,
      total: total is num ? total.toInt() : items.length,
      indexing: data['indexing'] == true,
      message: data['message'] is String ? data['message'] as String : null,
      buckets: _buckets(data['buckets']),
    );
  }

  /// Index platform names. [RomSystemList.pluginMissing] is HTTP 404.
  Future<RomSystemList> systems(MediaServerClient client) async {
    final reply = await _post(client, 'systems', const <String, dynamic>{});
    if (reply.missing) return const RomSystemList(pluginMissing: true);
    final data = reply.data;
    final raw = data == null || data['ok'] != true ? null : data['systems'];
    if (raw is! List) return const RomSystemList(failed: true);
    final systems = <RomSystemCount>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final name = row['system'];
      if (name is! String || name.isEmpty) continue;
      final games = row['games'];
      systems.add(
        RomSystemCount(
          name: name,
          games: games is num ? games.toInt() : 0,
        ),
      );
    }
    return RomSystemList(systems: systems);
  }

  /// Most games first. An empty list means the route failed or there are none.
  Future<List<RomDeveloper>> developers(
    MediaServerClient client, {
    int limit = 40,
  }) async {
    final reply = await _post(client, 'developers', <String, dynamic>{
      'min': 1,
      'limit': limit,
    });
    final data = reply.data;
    final raw = data == null || data['ok'] != true ? null : data['developers'];
    if (raw is! List) return const [];
    final rows = <RomDeveloper>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final name = row['name'];
      if (name is! String || name.isEmpty) continue;
      final games = row['games'];
      rows.add(
        RomDeveloper(
          key: row['key'] is String ? row['key'] as String : name,
          name: name,
          games: games is num ? games.toInt() : 0,
        ),
      );
    }
    return rows;
  }

  /// Versions for one grouped game. Empty when the route does not answer.
  Future<List<RomVersion>> versions({
    required MediaServerClient client,
    required String key,
  }) async {
    final reply = await _post(client, 'game', <String, dynamic>{'key': key});
    final data = reply.data;
    final game = data == null || data['ok'] != true ? null : data['game'];
    if (game is! Map) return const [];
    final raw = game['versions'];
    if (raw is! List) return const [];
    final versions = <RomVersion>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final path = row['p'];
      if (path is! String || path.isEmpty) continue;
      final file = row['file'] is String ? row['file'] as String : path;
      versions.add(
        RomVersion(path: path, label: _versionLabel(file), best: row['best'] == true),
      );
    }
    return versions;
  }

  /// Box art for the visible page, keyed by ROM path. Failures yield an empty
  /// map; the poster falls back to its color.
  Future<Map<String, Uint8List>> covers(
    MediaServerClient client,
    List<String> paths,
  ) async {
    final wanted = <String>[];
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || wanted.contains(trimmed)) continue;
      wanted.add(trimmed);
    }
    final out = <String, Uint8List>{};
    for (var start = 0; start < wanted.length; start += maxCovers) {
      final batch = wanted.skip(start).take(maxCovers).toList(growable: false);
      final reply = await _post(client, 'covers', <String, dynamic>{
        'items': [
          for (final path in batch) {'p': path, 'w': 200},
        ],
      });
      final raw = reply.data?['covers'];
      if (raw is! Map) continue;
      for (final entry in raw.entries) {
        final path = entry.key;
        final uri = entry.value;
        if (path is! String || uri is! String) continue;
        final bytes = decodeCover(uri);
        if (bytes != null) out[path] = bytes;
      }
    }
    return out;
  }

  /// Resolves the grouped row to the Moonbase id the native player already
  /// uses. [RomLaunch.playable] is false, with [RomLaunch.reason], when the
  /// ROM cannot start; the ids are still set when the file was located.
  Future<RomLaunch?> launch({
    required MediaServerClient client,
    required String key,
    required String path,
  }) async {
    final reply = await _post(client, 'launch', <String, dynamic>{
      'key': key,
      'p': path,
    });
    final data = reply.data;
    if (data == null || data['ok'] != true) return null;
    return RomLaunch(
      libraryId: data['libraryId'] is String
          ? data['libraryId'] as String
          : null,
      gameId: data['gameId'] is String ? data['gameId'] as String : null,
      core: data['core'] is String ? data['core'] as String : null,
      fileName: data['fileName'] is String ? data['fileName'] as String : null,
      playable: data['playable'] == true,
      reason: data['reason'] is String ? data['reason'] as String : null,
    );
  }

  /// A `data:image/...;base64,...` payload, or null when it is not one.
  @visibleForTesting
  static Uint8List? decodeCover(String uri) {
    final comma = uri.indexOf(',');
    if (comma <= 0) return null;
    final header = uri.substring(0, comma).toLowerCase();
    if (!header.startsWith('data:image/') || !header.contains(';base64')) {
      return null;
    }
    try {
      return base64Decode(uri.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<_PluginReply> _post(
    MediaServerClient client,
    String route,
    Map<String, dynamic> body,
  ) async {
    final server = client.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (server.isEmpty) return const _PluginReply.failed();
    final token = client.accessToken;
    try {
      final response = await _dio
          .post<dynamic>(
            '$server/Moonfin/Plugins/$pluginId/$route',
            data: body,
            options: Options(
              headers: <String, String>{
                Headers.contentTypeHeader: Headers.jsonContentType,
                if (token != null && token.isNotEmpty)
                  'Authorization': buildServerAuthorizationHeader(
                    scheme: client.serverType == ServerType.emby
                        ? 'Emby'
                        : 'MediaBrowser',
                    deviceInfo: client.deviceInfo,
                    accessToken: token,
                  ),
              },
              responseType: ResponseType.json,
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
            ),
          )
          .timeout(_timeout);
      final data = response.data;
      if (data is Map) return _PluginReply(data.cast<String, dynamic>());
      return const _PluginReply.failed();
    } on DioException catch (error) {
      debugPrint('ROM Manager $route unavailable: $error');
      if (error.response?.statusCode == 404) return const _PluginReply.missing();
      return const _PluginReply.failed();
    } catch (error) {
      debugPrint('ROM Manager $route unavailable: $error');
      return const _PluginReply.failed();
    }
  }

  static List<RomLetterBucket> _buckets(Object? raw) {
    if (raw is! List) return const [];
    final rows = <RomLetterBucket>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final id = row['id'];
      if (id is! String || id.isEmpty) continue;
      final games = row['games'];
      rows.add(
        RomLetterBucket(
          id: id,
          label: row['label'] is String ? row['label'] as String : id,
          games: games is num ? games.toInt() : 0,
        ),
      );
    }
    return rows;
  }

  static String _versionLabel(String file) {
    var name = file;
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) name = name.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String? _flag(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }
}

class RomManagerGamePage {
  const RomManagerGamePage({
    required this.items,
    required this.total,
    required this.indexing,
    this.message,
    this.buckets = const [],
  });

  final List<RomManagerGame> items;
  final int total;
  final bool indexing;
  final String? message;
  final List<RomLetterBucket> buckets;
}

class RomLetterBucket {
  const RomLetterBucket({
    required this.id,
    required this.label,
    required this.games,
  });

  final String id;
  final String label;
  final int games;
}

enum RomCatalogFailure { missing, failed }

class RomSystemList {
  const RomSystemList({
    this.systems = const [],
    this.pluginMissing = false,
    this.failed = false,
  });

  final List<RomSystemCount> systems;
  final bool pluginMissing;
  final bool failed;
}

class RomSystemCount {
  const RomSystemCount({required this.name, required this.games});

  final String name;
  final int games;
}

class RomDeveloper {
  const RomDeveloper({
    required this.key,
    required this.name,
    required this.games,
  });

  final String key;
  final String name;
  final int games;
}

class RomVersion {
  const RomVersion({
    required this.path,
    required this.label,
    required this.best,
  });

  final String path;
  final String label;
  final bool best;
}

class _PluginReply {
  const _PluginReply(this.data) : missing = false;

  const _PluginReply.missing() : data = null, missing = true;

  const _PluginReply.failed() : data = null, missing = false;

  final Map<String, dynamic>? data;
  final bool missing;
}

class RomManagerGame {
  const RomManagerGame({
    required this.key,
    required this.title,
    required this.system,
    required this.path,
    required this.versions,
    this.cheat,
    this.hack,
  });

  final String key;
  final String title;
  final String system;

  /// Index path of the best version. This is the `p` the launch route expects.
  final String path;
  final int versions;
  final String? cheat;
  final String? hack;

  GameSummary toSummary(String core) {
    final slash = path.lastIndexOf('/');
    final stem = slash >= 0 ? path.substring(slash + 1) : path;
    return GameSummary(
      id: key,
      title: title,
      system: system,
      core: core,
      fileName: stem,
      versionsCount: versions,
      cheatFlag: cheat,
      hackFlag: hack,
    );
  }
}

class RomLaunch {
  const RomLaunch({
    required this.libraryId,
    required this.gameId,
    required this.core,
    required this.fileName,
    required this.playable,
    required this.reason,
  });

  final String? libraryId;
  final String? gameId;
  final String? core;
  final String? fileName;
  final bool playable;
  final String? reason;
}
