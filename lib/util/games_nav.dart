import 'package:get_it/get_it.dart';
import 'package:plugin_host/plugin_host.dart';

import '../data/models/aggregated_library.dart';
import '../preference/user_preferences.dart';
import '../ui/navigation/destinations.dart';
import 'game_library.dart';
import 'platform_detection.dart';

/// Where the Games item in the sidebar and toolbar should open.
///
/// The plugin host stays off on TV. A TV with a game library opens the native
/// browser; everywhere else Games is the ROM Manager hub.
class GamesNav {
  static String? routeFor({
    required bool isTv,
    required bool kidsMode,
    required List<AggregatedLibrary> libraries,
  }) {
    if (kidsMode) return null;
    if (isTv) {
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
    if (!hubAvailable) return null;
    return Destinations.games;
  }

  static bool get hubAvailable {
    if (!PlatformDetection.pluginHostSupported) return false;
    if (PlatformDetection.isTV) return false;
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
