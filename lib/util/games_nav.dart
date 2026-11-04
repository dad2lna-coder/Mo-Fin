import 'package:get_it/get_it.dart';
import 'package:plugin_host/plugin_host.dart';

import '../data/models/aggregated_library.dart';
import '../preference/user_preferences.dart';
import '../ui/navigation/destinations.dart';
import 'game_library.dart';
import 'platform_detection.dart';

/// Where the Games item in the sidebar and toolbar should open.
///
/// Phones and the web keep the games plugin's hub ([Destinations.games]).
/// Televisions go to the native library browser instead, because the hub is a
/// webview: it has no D-pad focus model, no remote Back handling and no 10-foot
/// type. The plugin stays installed and its other rows keep working.
///
/// Without a usable hub — or on a TV — this falls back to the native game
/// library browser if one is available in [libraries].
class GamesNav {
  static String? routeFor({
    required bool isTv,
    required bool kidsMode,
    required List<AggregatedLibrary> libraries,
  }) {
    if (kidsMode) return null;
    if (hubAvailable && !isTv) {
      return Destinations.games;
    }
    for (final lib in libraries) {
      if (!isGameLibrary(lib.id, lib.collectionType, lib.name)) continue;
      return libraryRoute(
        lib.id,
        lib.collectionType,
        lib.name,
        serverId: lib.serverId,
      );
    }
    return null;
  }

  static bool get hubAvailable {
    if (!PlatformDetection.pluginHostSupported) return false;
    if (!GetIt.instance.isRegistered<UserPreferences>()) return false;
    final prefs = GetIt.instance<UserPreferences>();
    if (prefs.get(UserPreferences.kidsModeEnabled)) return false;
    if (!prefs.get(UserPreferences.pluginsEnabled)) return false;
    if (GetIt.instance.isRegistered<PluginService>() &&
        !GetIt.instance<PluginService>().pluginsEnabled) {
      return false;
    }
    if (!GetIt.instance.isRegistered<PluginRegistry>()) return false;
    return GetIt.instance<PluginRegistry>().gamesSlotPlugin != null;
  }

  /// Plugin whose generic nav row should hide while the Games hub is showing.
  static String? get gamesPluginId {
    if (!hubAvailable) return null;
    return GetIt.instance<PluginRegistry>().gamesSlotPlugin?.id;
  }
}
