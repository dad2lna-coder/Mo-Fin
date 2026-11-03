import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/games_nav.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:plugin_host/plugin_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GamesNav', () {
    late PluginRegistry registry;
    late UserPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'pluginsEnabled': true,
        'kidsModeEnabled': false,
      });
      final store = PreferenceStore();
      await store.init();

      GetIt.instance.reset();
      registry = PluginRegistry(prefs: store);
      GetIt.instance.registerSingleton<PluginRegistry>(registry);

      prefs = UserPreferences(store);
      await prefs.set(UserPreferences.pluginsEnabled, true);
      await prefs.set(UserPreferences.kidsModeEnabled, false);
      GetIt.instance.registerSingleton<UserPreferences>(prefs);

      final pluginService = PluginService(
        registry: registry,
        prefs: store,
        userContextProvider: () => null,
        clientProvider: () => null,
        initialPluginsEnabled: true,
      );
      GetIt.instance.registerSingleton<PluginService>(pluginService);

      GetIt.instance.registerSingleton<GameLibraryRegistry>(
        GameLibraryRegistry()..seed(['retro-games']),
      );
    });

    tearDown(() {
      GetIt.instance.reset();
      PlatformDetection.setTvMode(false);
      debugDefaultTargetPlatformOverride = null;
    });

    final List<AggregatedLibrary> testLibraries = [
      const AggregatedLibrary(
        id: 'retro-games',
        name: 'Retro Games',
        collectionType: 'games',
        serverId: 'server-1',
      ),
      const AggregatedLibrary(
        id: 'movies',
        name: 'Movies',
        collectionType: 'movies',
        serverId: 'server-1',
      ),
    ];

    test('hubAvailable is true on Android TV / Fire TV when games plugin registered', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PlatformDetection.setTvMode(true);

      expect(GamesNav.hubAvailable, isFalse);

      registry.registerManifest(
        const PluginManifest(
          id: 'rom-manager',
          name: 'ROM Manager',
          version: '1.0.0',
          slots: PluginSlots(games: true),
          client: PluginClientInfo(html: 'index.html'),
        ),
      );

      expect(GamesNav.hubAvailable, isTrue);
    });

    test('routeFor returns Destinations.games on Fire TV when games plugin registered', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PlatformDetection.setTvMode(true);

      registry.registerManifest(
        const PluginManifest(
          id: 'rom-manager',
          name: 'ROM Manager',
          version: '1.0.0',
          slots: PluginSlots(games: true),
          client: PluginClientInfo(html: 'index.html'),
        ),
      );

      final route = GamesNav.routeFor(
        isTv: true,
        kidsMode: false,
        libraries: testLibraries,
      );

      expect(route, Destinations.games);
    });

    test('routeFor falls back to native game library on Fire TV when hub is unavailable', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PlatformDetection.setTvMode(true);

      // No plugin registered, hubAvailable is false
      final route = GamesNav.routeFor(
        isTv: true,
        kidsMode: false,
        libraries: testLibraries,
      );

      expect(route, '/games/retro-games?title=Retro+Games');
    });

    test('routeFor returns null when kidsMode is true', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PlatformDetection.setTvMode(true);

      registry.registerManifest(
        const PluginManifest(
          id: 'rom-manager',
          name: 'ROM Manager',
          version: '1.0.0',
          slots: PluginSlots(games: true),
          client: PluginClientInfo(html: 'index.html'),
        ),
      );

      final route = GamesNav.routeFor(
        isTv: true,
        kidsMode: true,
        libraries: testLibraries,
      );

      expect(route, isNull);
    });

    test('routeFor returns null if hub is unavailable and no game library exists', () {
      final route = GamesNav.routeFor(
        isTv: true,
        kidsMode: false,
        libraries: [
          const AggregatedLibrary(
            id: 'movies',
            name: 'Movies',
            collectionType: 'movies',
            serverId: 'server-1',
          ),
        ],
      );

      expect(route, isNull);
    });
  });
}
