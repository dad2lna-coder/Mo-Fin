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

  /// [RomChannel.MaxCovers].
  static const int maxCovers = 24;

  static const Duration requestTimeout = Duration(seconds: 20);

  final Dio _dio;
  final Duration _timeout;

  /// Null when the plugin is missing or the body is not a catalog page.
  /// An empty page with `ok: true` is a real answer (unknown system, or the
  /// index is still building) and is not null.
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
  }) async {
    final data = await _post(client, 'games', <String, dynamic>{
      'system': system,
      'sort': sort,
      'offset': offset,
      'limit': pageSize,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    if (data == null || data['ok'] != true) return null;
    final raw = data['items'];
    if (raw is! List) return null;
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
    );
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
      final data = await _post(client, 'covers', <String, dynamic>{
        'items': [
          for (final path in batch) {'p': path, 'w': 200},
        ],
      });
      final raw = data?['covers'];
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
    final data = await _post(client, 'launch', <String, dynamic>{
      'key': key,
      'p': path,
    });
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

  Future<Map<String, dynamic>?> _post(
    MediaServerClient client,
    String route,
    Map<String, dynamic> body,
  ) async {
    final server = client.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (server.isEmpty) return null;
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
      if (data is Map) return data.cast<String, dynamic>();
      return null;
    } catch (error) {
      debugPrint('ROM Manager $route unavailable: $error');
      return null;
    }
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
  });

  final List<RomManagerGame> items;
  final int total;
  final bool indexing;
  final String? message;
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
