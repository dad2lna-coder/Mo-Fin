import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:server_core/server_core.dart';

/// Console logos as the ROM Manager plugin serves them.
///
/// The plugin's `logos` route is a POST that answers with small `data:` URIs
/// rather than image URLs, because the plugin host has no binary response path.
/// Its own web client asks once per console per session and keeps the answers in
/// memory; this does the same for the native TV screen, so the carousel and the
/// section header can show a real console mark instead of an icon. A batch per
/// page load at most, a short timeout so a slow server can't stall the screen,
/// and the styled console name stays in place for anything that comes back
/// empty.
///
/// None of this is required for the screen to work: every failure path leaves
/// the map empty and the caller draws its own badge.
class RomManagerLogoService {
  RomManagerLogoService({Dio? dio, Duration? timeout})
    : _dio = dio ?? Dio(),
      _timeout = timeout ?? requestTimeout {
    if (dio == null) configureServerDio(_dio);
  }

  /// The plugin id whose route table serves `logos`.
  static const String pluginId = 'rom-manager';

  /// A console logo is decoration. Three seconds is long enough for the plugin
  /// to answer over a Fire TV's network and short enough that a server which
  /// swallows the request doesn't hold up the section header.
  static const Duration requestTimeout = Duration(seconds: 3);

  /// The route ignores names past this count.
  static const int maxNamesPerRequest = 500;

  final Dio _dio;
  final Duration _timeout;

  /// Session-wide cache, keyed by `server|consoles|name`. The plugin serves the
  /// same files to everybody, so one screen's answer serves the next.
  static final Map<String, String> _sessionCache = <String, String>{};
  static final Set<String> _sessionAsked = <String>{};

  /// The server this instance last read logos from, so [logoFor] never has to
  /// touch the client again.
  String? _server;

  /// Forgets every logo this process fetched. Tests use it so one case's
  /// answers can't leak into the next.
  @visibleForTesting
  static void resetSessionCache() {
    _sessionCache.clear();
    _sessionAsked.clear();
  }

  static String? _serverKeyOf(MediaServerClient client) {
    final base = client.baseUrl.trim();
    if (base.isEmpty) return null;
    return base.replaceAll(RegExp(r'/+$'), '');
  }

  /// The cached `data:` URI for console [name] on the server this instance last
  /// fetched from, or null when there is none.
  String? logoFor(String name) {
    final server = _server;
    if (server == null) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return _sessionCache['$server|consoles|$trimmed'];
  }

  /// Requests logos for any of [names] this session hasn't asked about yet.
  ///
  /// Returns true when at least one new logo arrived, so the caller can decide
  /// whether a rebuild is worth it. Never throws: a missing route, a plugin
  /// that isn't installed, a timeout and a malformed body all just mean no
  /// logos.
  Future<bool> fetchConsoles(
    MediaServerClient client,
    Iterable<String> names,
  ) async {
    final server = _serverKeyOf(client);
    if (server == null) return false;
    _server = server;

    final wanted = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final key = '$server|consoles|$name';
      if (_sessionAsked.contains(key)) continue;
      _sessionAsked.add(key);
      wanted.add(name);
    }
    if (wanted.isEmpty) return false;

    var got = false;
    for (var start = 0; start < wanted.length; start += maxNamesPerRequest) {
      final batch = wanted.skip(start).take(maxNamesPerRequest).toList(
        growable: false,
      );
      final logos = await _post(client, server, batch);
      for (final entry in logos.entries) {
        _sessionCache['$server|consoles|${entry.key}'] = entry.value;
        got = true;
      }
    }
    return got;
  }

  Future<Map<String, String>> _post(
    MediaServerClient client,
    String server,
    List<String> names,
  ) async {
    final token = client.accessToken;
    final headers = <String, String>{
      Headers.contentTypeHeader: Headers.jsonContentType,
      if (token != null && token.isNotEmpty)
        'Authorization': buildServerAuthorizationHeader(
          scheme: client.serverType == ServerType.emby
              ? 'Emby'
              : 'MediaBrowser',
          deviceInfo: client.deviceInfo,
          accessToken: token,
        ),
    };
    try {
      final response = await _dio
          .post<dynamic>(
            '$server/Moonfin/Plugins/$pluginId/logos',
            data: <String, dynamic>{'kind': 'consoles', 'names': names},
            options: Options(
              headers: headers,
              responseType: ResponseType.json,
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
            ),
          )
          .timeout(_timeout);

      final data = response.data;
      if (data is! Map) return const {};
      final raw = data['logos'];
      if (raw is! Map) return const {};

      final result = <String, String>{};
      for (final entry in raw.entries) {
        final name = entry.key;
        final uri = entry.value;
        if (name is! String || uri is! String) continue;
        if (!isLogoDataUri(uri)) continue;
        result[name] = uri;
      }
      return result;
    } catch (error) {
      debugPrint('ROM Manager console logos unavailable: $error');
      return const {};
    }
  }

  /// Whether [uri] is an image `data:` URI this app will hand to an image
  /// widget. Anything else — an `http` URL, a non-image type — is refused, so a
  /// response can only ever produce a picture and never a network load.
  static bool isLogoDataUri(String uri) {
    final comma = uri.indexOf(',');
    if (comma <= 0) return false;
    final header = uri.substring(0, comma).toLowerCase();
    if (!header.startsWith('data:image/')) return false;
    return header.contains(';base64');
  }

  /// Decodes a `data:image/...;base64,...` URI, or null when it isn't one or
  /// the payload isn't valid base64.
  static Uint8List? decodeDataUri(String uri) {
    if (!isLogoDataUri(uri)) return null;
    final comma = uri.indexOf(',');
    try {
      return base64Decode(uri.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// Whether [uri] carries SVG, which needs [SvgPicture] rather than `Image`.
  static bool isSvgDataUri(String uri) {
    final comma = uri.indexOf(',');
    final header = comma > 0 ? uri.substring(0, comma).toLowerCase() : uri;
    return header.contains('svg');
  }
}

/// Draws a console logo from a `data:` URI, or nothing when there is none.
///
/// The bytes are decoded once and handed to an image widget; the URI itself is
/// never given to a network loader, so a logo can only ever be the picture the
/// plugin sent.
class ConsoleLogo extends StatelessWidget {
  const ConsoleLogo({
    super.key,
    required this.dataUri,
    required this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  final String? dataUri;
  final double? height;
  final double? width;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final uri = dataUri;
    if (uri == null) return const SizedBox.shrink();
    final bytes = RomManagerLogoService.decodeDataUri(uri);
    if (bytes == null) return const SizedBox.shrink();

    if (RomManagerLogoService.isSvgDataUri(uri)) {
      return SvgPicture.memory(bytes, height: height, width: width, fit: fit);
    }
    return Image.memory(
      bytes,
      height: height,
      width: width,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
