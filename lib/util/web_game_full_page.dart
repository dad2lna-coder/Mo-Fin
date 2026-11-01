import 'dart:convert';

/// Whether this browser is iPhone, iPod, or iPad Safari, including iPadOS
/// desktop mode (a Macintosh UA with a touch screen).
///
/// Other iOS browsers (Chrome, Firefox, Edge) are WebKit too, but they are
/// left to the "Open games full page" setting. Desktop Safari is not included.
bool isIosOrIpadOsSafari({
  required String userAgent,
  int maxTouchPoints = 0,
}) {
  final ua = userAgent.toLowerCase();
  if (_isBrandedNonSafari(ua)) return false;
  if (!_isIosOrIpadOs(ua, maxTouchPoints)) return false;
  return ua.contains('safari/') || ua.contains('applewebkit');
}

bool _isBrandedNonSafari(String ua) {
  const markers = [
    'crios/',
    'fxios/',
    'edgios/',
    'opios/',
    'opr/',
    'edg/',
    'chrome/',
    'chromium/',
    'firefox/',
    'duckduckgo',
    'gsa/',
  ];
  for (final marker in markers) {
    if (ua.contains(marker)) return true;
  }
  return false;
}

bool _isIosOrIpadOs(String ua, int maxTouchPoints) {
  final iphone = ua.contains('iphone');
  final ipod = ua.contains('ipod');
  var ipad = ua.contains('ipad');
  final mac = ua.contains('mac os x') || ua.contains('macintosh');
  // iPadOS 13+ reports a desktop Macintosh UA. Touch points distinguish it
  // from a Mac, which stays at 0 (or 1 with a mouse).
  if (mac && !iphone && !ipad && !ipod && maxTouchPoints > 1) {
    ipad = true;
  }
  return iphone || ipad || ipod;
}

/// Web only. iOS/iPadOS Safari always leaves the app. Every other browser
/// follows [openGamesFullPage], which defaults off.
bool shouldOpenGameFullPage({
  required bool isWeb,
  required bool iosSafari,
  required bool openGamesFullPage,
}) {
  if (!isWeb) return false;
  return iosSafari || openGamesFullPage;
}

/// Player URL for a top-level launch.
///
/// [playerUrl] must already be the iframe URL built with a state endpoint
/// (`save`), including core, rom, bios, name, and ApiKey. This adds:
///
/// * `returnUrl` — absolute MoFin URL, hash route included.
/// * `saveWrite` — same endpoint as `save`, always, so Exit can PUT a state
///   even when there is nothing to load yet. Today's player ignores this name.
/// * `sramWrite` — that endpoint with `kind=sram`. Not named `sram`, because
///   player.html already GETs `sram` and a Restart must not resume battery.
/// * `fresh=1` and no `save` when [loadState] is false, so the current
///   player (which sets `EJS_loadStateURL` from `save`) does not resume.
///
/// Nothing here talks to the player over postMessage. Loading an existing
/// state still works with today's player.html (`save`). Writing the new state
/// and battery save, and leaving the page, requires [kWebGamePlayerExitContract].
const String kWebGamePlayerExitContract = '''
player.html (Moonbase EmulatorJS), when returnUrl is present:
1. Show a visible Exit control (fixed, above the canvas, inside the safe area).
2. On Exit, Escape, and pagehide: PUT moonfinGetState() bytes (base64-decoded,
   application/octet-stream) to saveWrite, or to save if saveWrite is absent.
   PUT moonfinGetSram() the same way to sramWrite when it returns bytes.
   Await the Exit-button writes, then location.assign(returnUrl) if it is
   http(s). Ignore a 404 on the earlier GET. If fresh=1, do not load save.
   Do not GET sramWrite on the way in unless save was absent and fresh is not 1.
3. Do not postMessage a host. The Flutter app has been unloaded.
''';

String fullPagePlayerUrl({
  required String playerUrl,
  required String returnUrl,
  required bool loadState,
}) {
  final uri = Uri.parse(playerUrl);
  final params = Map<String, String>.from(uri.queryParameters);
  final save = params['save'];
  if (save != null && save.isNotEmpty) {
    params['saveWrite'] = save;
    final sram = sramUrlFromStateUrl(save);
    if (sram != save) params['sramWrite'] = sram;
    if (!loadState) {
      params.remove('save');
      params['fresh'] = '1';
    }
  }
  params['returnUrl'] = returnUrl;
  return uri.replace(queryParameters: params).toString();
}

/// `.../Saves/{id}?kind=state` → `kind=sram`. Returns [stateUrl] unchanged
/// when it is not that endpoint, so a bad value is not copied over as SRAM.
String sramUrlFromStateUrl(String stateUrl) {
  if (!stateUrl.contains('kind=state')) return stateUrl;
  return stateUrl.replaceFirst('kind=state', 'kind=sram');
}

/// Where the player should send the user. If [route] is already the in-app
/// player, point at the game instead of the player so coming back does not
/// immediately leave again.
String gameReturnHref({
  required String href,
  required String route,
  required String libraryId,
  required String gameId,
}) {
  if (!_isGamePlayerRoute(route)) return href;
  final back =
      '/game/${Uri.encodeComponent(libraryId)}/${Uri.encodeComponent(gameId)}';
  final hash = href.indexOf('#');
  if (hash >= 0) {
    // Keep the encoded fragment ourselves. Uri.replace would encode the
    // percent signs in [back] a second time.
    return '${href.substring(0, hash)}#$back';
  }
  final page = Uri.parse(href);
  return page
      .replace(
        pathSegments: ['game', libraryId, gameId],
        queryParameters: const <String, String>{},
      )
      .toString();
}

bool _isGamePlayerRoute(String route) {
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasScheme) return false;
  return uri.path == '/game-player' || uri.path.startsWith('/game-player/');
}

/// MoFin route to restore after the player navigates to [href].
///
/// The plugin iframe is sandboxed, so its own hash cannot be read. [route] is
/// MoFin's route: the Games tab, a plugin screen, or the open game.
class WebGameReturnSnapshot {
  const WebGameReturnSnapshot({
    required this.route,
    required this.href,
    this.pluginId,
    this.libraryId,
    this.gameId,
    this.title,
  });

  static const storageKey = 'mofin.webGameReturn';

  final String route;
  final String href;
  final String? pluginId;
  final String? libraryId;
  final String? gameId;
  final String? title;

  String encode() => jsonEncode({
    'route': route,
    'href': href,
    if (pluginId != null && pluginId!.isNotEmpty) 'pluginId': pluginId,
    if (libraryId != null && libraryId!.isNotEmpty) 'libraryId': libraryId,
    if (gameId != null && gameId!.isNotEmpty) 'gameId': gameId,
    if (title != null && title!.isNotEmpty) 'title': title,
  });

  static WebGameReturnSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final route = decoded['route'];
      final href = decoded['href'];
      if (route is! String || href is! String) return null;
      if (route.isEmpty || href.isEmpty) return null;
      return WebGameReturnSnapshot(
        route: route,
        href: href,
        pluginId: _stringOrNull(decoded['pluginId']),
        libraryId: _stringOrNull(decoded['libraryId']),
        gameId: _stringOrNull(decoded['gameId']),
        title: _stringOrNull(decoded['title']),
      );
    } catch (_) {
      return null;
    }
  }

  /// In-app location for `GoRouter.go`, or null when the stored value is not
  /// one of ours. A stored player route becomes the game page.
  String? get restoreRoute {
    final uri = Uri.tryParse(route.trim());
    if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
    if (!uri.path.startsWith('/') || uri.path.startsWith('//')) return null;
    if (uri.path == '/game-player' || uri.path.startsWith('/game-player/')) {
      final lib = libraryId;
      final id = gameId;
      if (lib != null && lib.isNotEmpty && id != null && id.isNotEmpty) {
        return '/game/${Uri.encodeComponent(lib)}/${Uri.encodeComponent(id)}';
      }
      return '/games-hub';
    }
    return uri.toString();
  }
}

String? _stringOrNull(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}

/// Reads and removes [store]'s snapshot. Used by tests; the browser store
/// does the same with sessionStorage.
String? takeStoredGameReturnRoute(Map<String, String> store) {
  final raw = store.remove(WebGameReturnSnapshot.storageKey);
  return WebGameReturnSnapshot.decode(raw)?.restoreRoute;
}
