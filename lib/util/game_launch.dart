import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../l10n/app_localizations.dart';
import '../preference/user_preferences.dart';
import '../ui/navigation/destinations.dart';
import 'game_cores.dart';
import 'platform_detection.dart';
import 'web_game_full_page_launch.dart';

/// Pushes MoFin's full-screen game player and returns true once that route is
/// on the stack. The push is not awaited, so the caller returns while the
/// player is up. [onPopped] runs when the player is popped back.
///
/// On web, iOS/iPadOS Safari (and other browsers when "Open games full page"
/// is on) does not push. It assigns the player document so the Flutter app,
/// including its iframe, is unloaded.
bool launchGame(
  BuildContext context,
  String libraryId,
  GameDetail game, {
  bool fresh = false,
  bool? hardwareRenderingEnabled,
  String? name,
  String? pluginId,
  VoidCallback? onPopped,
}) {
  if (!context.mounted) return false;
  final blocked = gamePlaybackBlockedMessage(game.core);
  if (!PlatformDetection.gamesPlaybackSupported ||
      !gameCoreSupported(game.core)) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(blocked ?? l10n.gamePlaybackUnsupported)),
    );
    return false;
  }

  final displayName = (name != null && name.isNotEmpty) ? name : game.title;
  if (webGameFullPageEnabled() && browserCanLeavePage() && _hasGamesApi()) {
    final route = routerLocationOf(context);
    unawaited(
      openGameFullPage(
        libraryId: libraryId,
        gameId: game.id,
        core: game.core,
        romFileName: game.fileName,
        biosId: emulatorJsBiosId(game.core, game.bios),
        gameName: displayName,
        startFresh: fresh,
        pluginId: pluginId,
        returnRoute: route,
      ),
    );
    return true;
  }

  final hardware =
      hardwareRenderingEnabled ??
      (GetIt.instance.isRegistered<UserPreferences>()
          ? GetIt.instance<UserPreferences>().get(
              UserPreferences.useHardwareRendering,
            )
          : true);
  final popped = context.push<void>(
    Destinations.gamePlayerOf(
      libraryId,
      game.id,
      core: game.core,
      romFileName: game.fileName,
      biosId: emulatorJsBiosId(game.core, game.bios),
      name: displayName,
      startFresh: fresh,
      forceEmulatorJs: game.userBackendOverride == 'emulatorjs',
      hardwareRenderingEnabled: hardware == true,
    ),
  );
  if (onPopped != null) {
    unawaited(popped.whenComplete(onPopped));
  }
  return true;
}

bool _hasGamesApi() {
  try {
    if (!GetIt.instance.isRegistered<MediaServerClient>()) return false;
    return GetIt.instance<MediaServerClient>().gamesApi != null;
  } catch (_) {
    return false;
  }
}

/// Host `playGame` handoff: load the game, push the player, and tell the
/// plugin when the player pops. A missing game shows "Game not found".
///
/// A full-page launch unloads this document, so [onPopped] does not run. The
/// plugin reloads with the rest of MoFin when the player comes back.
Future<bool> playGameFromPlugin({
  required BuildContext context,
  required String pluginId,
  required String libraryId,
  required String gameId,
  String? title,
  void Function(String message)? toast,
  void Function(Map<String, dynamic> event)? dispatch,
}) async {
  GamesApi? api;
  try {
    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      api = GetIt.instance<MediaServerClient>().gamesApi;
    }
  } catch (_) {}

  GameDetail? game;
  try {
    game = await api?.getGame(libraryId, gameId);
  } catch (_) {
    game = null;
  }
  if (game == null) {
    const message = 'Game not found';
    toast?.call(message);
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text(message)));
    }
    return false;
  }
  if (!context.mounted) return false;
  return launchGame(
    context,
    libraryId,
    game,
    name: title,
    pluginId: pluginId,
    onPopped: () {
      dispatch?.call({'type': 'gameExited', 'gameId': gameId});
    },
  );
}
