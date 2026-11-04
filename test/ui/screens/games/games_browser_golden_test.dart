import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/rom_manager_logos.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/games/games_browser_screen.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/util/game_local_data.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The TV Games screen at 1920x1080, rendered from the same widgets the Fire TV
/// build draws, so a layout change can be compared against James's mockup
/// (`/workspace/romplugin/design-mockup.png`) without a device.
///
/// A golden depends on the host's text shaping, so this only runs when asked
/// for: `MOONFIN_TV_GAMES_GOLDEN=1 flutter test --update-goldens
/// test/ui/screens/games/games_browser_golden_test.dart`. The committed image
/// at `test/ui/screens/goldens/tv_games_browser.png` is the reference it writes.

class _MockClient extends Mock implements MediaServerClient {}

class _MockGamesApi extends Mock implements GamesApi {}

class _LogoAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'ok': true, 'kind': 'consoles', 'logos': <String, String>{}}),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Roboto': [
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/Roboto-Medium.ttf',
      'assets/fonts/Roboto-Bold.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['MOONFIN_TV_GAMES_GOLDEN'] == '1';

  testWidgets('TV Games screen matches the mockup at 1080p', skip: !enabled, (
    tester,
  ) async {
    await _loadFonts();
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    final client = _MockClient();
    final api = _MockGamesApi();
    when(() => client.gamesApi).thenReturn(api);
    when(() => client.baseUrl).thenReturn('http://tv:8096');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'tv',
        name: 'TV',
        appName: 'MoFin',
        appVersion: '2.7.0',
      ),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);
    PlatformDetection.setTvMode(true);
    GameLocalData.instance.resetForTest(
      favorites: {'retro:g2'},
      recents: const ['retro:g3'],
    );

    const systems = [
      GameSystem(
        id: 'nes',
        name: 'Nintendo Entertainment System',
        core: 'fceumm',
        gameCount: 42,
      ),
      GameSystem(
        id: 'snes',
        name: 'Super Nintendo',
        core: 'snes9x',
        gameCount: 31,
      ),
      GameSystem(
        id: 'genesis',
        name: 'Sega Genesis',
        core: 'genesis_plus_gx',
        gameCount: 28,
      ),
      GameSystem(
        id: 'psx',
        name: 'PlayStation',
        core: 'pcsx_rearmed',
        gameCount: 19,
      ),
      GameSystem(
        id: 'gba',
        name: 'Game Boy Advance',
        core: 'mgba',
        gameCount: 24,
      ),
    ];
    final games = [
      for (final name in [
        'Super Mario Bros.',
        'The Legend of Zelda',
        'Metroid',
        'Mega Man 2',
        'Castlevania',
        'Contra',
        'Kirby\'s Adventure',
        'Punch-Out!!',
        'Duck Tales',
        'Ninja Gaiden',
        'Final Fantasy',
        'Bubble Bobble',
      ])
        GameSummary(
          id: 'id-$name',
          title: name,
          system: 'nes',
          core: 'fceumm',
          fileName: '$name.nes',
        ),
    ];
    when(() => api.getSystems('retro')).thenAnswer((_) async => systems);
    when(() => api.getGames('retro', system: 'nes'))
        .thenAnswer((_) async => games);
    when(() => api.getGames('retro', system: 'snes'))
        .thenAnswer((_) async => const []);
    when(() => api.getGames('retro', system: 'genesis'))
        .thenAnswer((_) async => const []);
    when(() => api.getGames('retro', system: 'psx'))
        .thenAnswer((_) async => const []);
    when(() => api.getGames('retro', system: 'gba'))
        .thenAnswer((_) async => const []);

    // Pin the top-bar clock: a golden recorded at 5:37 AM would fail on the
    // next run at any other minute.
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 22, 24)), () async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(ThemeRegistry.active),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GamesBrowserScreen(
            libraryId: 'retro',
            logoService: RomManagerLogoService(
              dio: Dio()..httpClientAdapter = _LogoAdapter(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(GamesBrowserScreen),
        matchesGoldenFile('../goldens/tv_games_browser.png'),
      );
    });
  });
}
