import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../preference/user_preferences.dart';
import 'game_cores.dart';
import 'web_game_browser.dart';
import 'web_game_full_page.dart';

/// True when this document can be replaced. The VM stub has no page URL.
bool browserCanLeavePage() => browserHref().isNotEmpty;

/// iOS/iPadOS Safari, or any other web browser with "Open games full page" on.
/// False on native builds and in VM tests.
bool webGameFullPageEnabled() {
  if (!kIsWeb) return false;
  final ios = isIosOrIpadOsSafari(
    userAgent: browserUserAgent(),
    maxTouchPoints: browserMaxTouchPoints(),
  );
  var setting = false;
  if (GetIt.instance.isRegistered<UserPreferences>()) {
    setting = GetIt.instance<UserPreferences>().get(
      UserPreferences.openGamesFullPage,
    );
  }
  return shouldOpenGameFullPage(
    isWeb: true,
    iosSafari: ios,
    openGamesFullPage: setting,
  );
}

String routerLocationOf(BuildContext context) {
  try {
    return GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.toString();
  } catch (_) {
    return '/games-hub';
  }
}

/// Builds the player URL, remembers where MoFin was, and navigates the tab
/// there. Returns false when there is no page to leave or no games API, so
/// the caller can keep the in-app player.
///
/// There is no iframe and no postMessage host after this. The player page
/// loads and, once Moonbase honors [kWebGamePlayerExitContract], writes the
/// state and battery save itself.
Future<bool> openGameFullPage({
  required String libraryId,
  required String gameId,
  required String core,
  String? romFileName,
  String? biosId,
  String? gameName,
  required bool startFresh,
  String? pluginId,
  required String returnRoute,
  GamesApi? games,
}) async {
  final href = browserHref();
  if (href.isEmpty) return false;
  final api = games ?? _gamesApi();
  if (api == null) return false;

  var hasSave = false;
  if (!startFresh) {
    try {
      final existing = await loadGameStateWithMigration(
        api,
        gameId,
        core,
        forceEmulatorJs: true,
      ).timeout(const Duration(seconds: 4));
      hasSave = existing != null && existing.isNotEmpty;
    } catch (_) {}
  }

  // Always include the state endpoint. [fullPagePlayerUrl] keeps it as `save`
  // only when we should actually load it.
  final player = api.playerUrl(
    libraryId: libraryId,
    gameId: gameId,
    core: core,
    romFileName: romFileName,
    biosId: biosId,
    gameName: gameName,
    includeSaveUrl: true,
    saveId: gameStateKey(gameId, core, forceEmulatorJs: true),
  );
  final returnHref = gameReturnHref(
    href: href,
    route: returnRoute,
    libraryId: libraryId,
    gameId: gameId,
  );
  final url = fullPagePlayerUrl(
    playerUrl: player,
    returnUrl: returnHref,
    loadState: hasSave && !startFresh,
  );
  rememberWebGameReturn(
    WebGameReturnSnapshot(
      route: returnRoute,
      href: returnHref,
      pluginId: pluginId,
      libraryId: libraryId,
      gameId: gameId,
      title: gameName,
    ),
  );
  assignBrowserLocation(url);
  return true;
}

GamesApi? _gamesApi() {
  try {
    if (!GetIt.instance.isRegistered<MediaServerClient>()) return null;
    return GetIt.instance<MediaServerClient>().gamesApi;
  } catch (_) {
    return null;
  }
}
