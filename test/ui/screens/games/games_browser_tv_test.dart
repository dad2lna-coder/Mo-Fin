import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
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

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _MockGamesApi extends Mock implements GamesApi {}

/// Answers the plugin's logos route with a 1x1 PNG so the carousel has a real
/// `data:` URI to draw.
class _LogoAdapter implements HttpClientAdapter {
  _LogoAdapter(this.logos);

  final Map<String, String> logos;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      jsonEncode({'ok': true, 'kind': 'consoles', 'logos': logos}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _pngDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

const String _nesName = 'Nintendo Entertainment System';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMediaServerClient client;
  late _MockGamesApi gamesApi;

  final systems = const [
    GameSystem(id: 'nes', name: _nesName, core: 'fceumm', gameCount: 3),
    GameSystem(id: 'snes', name: 'Super Nintendo', core: 'snes9x', gameCount: 2),
  ];

  final nesGames = const [
    GameSummary(
      id: 'g1',
      title: 'Zelda',
      fileName: 'zelda.nes',
      system: 'nes',
      core: 'fceumm',
    ),
    GameSummary(
      id: 'g2',
      title: 'Mario',
      fileName: 'mario.nes',
      system: 'nes',
      core: 'fceumm',
    ),
    GameSummary(
      id: 'g3',
      title: 'Metroid',
      fileName: 'metroid.nes',
      system: 'nes',
      core: 'fceumm',
    ),
  ];

  setUp(() async {
    await GetIt.instance.reset();
    RomManagerLogoService.resetSessionCache();
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    client = _MockMediaServerClient();
    gamesApi = _MockGamesApi();
    when(() => client.gamesApi).thenReturn(gamesApi);
    when(() => client.baseUrl).thenReturn('http://tv:8096');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'tv',
        name: 'Living Room',
        appName: 'MoFin',
        appVersion: '2.7.0',
      ),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);
    PlatformDetection.setTvMode(true);
    GameLocalData.instance.resetForTest(favorites: {}, recents: const []);

    when(() => gamesApi.getSystems('retro')).thenAnswer((_) async => systems);
    when(
      () => gamesApi.getGames('retro', system: 'nes'),
    ).thenAnswer((_) async => nesGames);
    when(
      () => gamesApi.getGames('retro', system: 'snes'),
    ).thenAnswer((_) async => const []);
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Widget app({Widget? home}) => MaterialApp(
    theme: AppTheme.buildTheme(ThemeRegistry.active),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home ?? const GamesBrowserScreen(libraryId: 'retro'),
  );

  /// A logo service whose plugin route answers with [logos]. Every case uses
  /// one, so no test reaches for the network.
  RomManagerLogoService logoService([Map<String, String> logos = const {}]) =>
      RomManagerLogoService(
        dio: Dio()..httpClientAdapter = _LogoAdapter(logos),
      );

  Future<void> pumpTv(WidgetTester tester, {RomManagerLogoService? logos}) async {
    logos ??= logoService();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        home: GamesBrowserScreen(libraryId: 'retro', logoService: logos),
      ),
    );
    // Systems, then the selected console's games, then any logo answers.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('sidebar shows the Total Games and Storage Usage cards', (
    tester,
  ) async {
    await pumpTv(tester);

    // The sidebar starts expanded on TV, so the cards are visible at once.
    expect(find.text('Total Games'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.text('Total Games'), findsOneWidget);
    // 3 NES games + 2 SNES games from the systems response.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Downloaded Storage'), findsOneWidget);
    expect(find.text('Downloaded Games'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('games-sidebar-storage')),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    // The opened rail lands on Library.
    expect(focusedLabel(), 'games_nav_library');
  });

  testWidgets('console card carries the plugin logo, name and game count', (
    tester,
  ) async {
    final adapter = _LogoAdapter({_nesName: _pngDataUri});
    final logos = RomManagerLogoService(
      dio: Dio()..httpClientAdapter = adapter,
    );
    await pumpTv(tester, logos: logos);
    await tester.pump(const Duration(milliseconds: 50));

    final card = find.byKey(const ValueKey('console-card-nes'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text(_nesName)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('3 Games')),
      findsOneWidget,
    );
    // The logo is drawn from the data URI the route returned, never a URL.
    expect(
      find.descendant(of: card, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(adapter.calls, hasLength(1));

    // The section header repeats the same console and its visible count.
    expect(find.text('| 3 Games'), findsOneWidget);
  });

  testWidgets('tabs and sort follow the D-pad and Select', (tester) async {
    await pumpTv(tester);

    // Carousel → tabs.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_all');

    // All → Favorites, which also selects the tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_fav');
    expect(find.text('No favorites yet'), findsOneWidget);

    // Favorites → Recently Played → Sort.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_recent');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_sort');

    // Select cycles the three sorts; the label is the visible result.
    expect(find.text('Name A–Z'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Name Z–A'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Recently played'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Name A–Z'), findsOneWidget);

    // Sort → filter, and Left walks back.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_filter');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_sort');

    // Back off the sort row returns to the tabs, not out of the screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_recent');
  });

  testWidgets('Back walks grid → tabs → carousel → sidebar → out of Games', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/games/retro',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('/home')),
        ),
        GoRoute(
          path: '/games/:libraryId',
          builder: (_, _) => GamesBrowserScreen(
            libraryId: 'retro',
            logoService: logoService(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(focusedLabel(), 'console_carousel_0');

    // Down into the tabs, then again into the first poster.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_all');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'game_poster:0');

    // The first poster is the leftmost column: Left cannot leave the grid.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'game_poster:0');

    // Back climbs back to the tab row.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_tab_all');

    // Back again to the carousel.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'console_carousel_0');

    // Back again opens the rail.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_nav_library');
    expect(find.text('Total Games'), findsOneWidget);

    // And the last Back leaves Games for Home.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home');
  });

  testWidgets('carousel Left reaches the rail and Right walks the arrows', (
    tester,
  ) async {
    await pumpTv(tester);

    // Right at the last console lands on the next-arrow button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'console_carousel_1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_carousel_next');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'console_carousel_1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'console_carousel_0');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'games_nav_library');
    // The leading arrow is one step right of the rail and one left of the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('console_carousel_'));
    // Right closes the rail and hands focus back to the carousel.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Total Games'), findsNothing);
    expect(focusedLabel(), startsWith('console_carousel_'));
  });

  testWidgets('Select on a later console loads that console by D-pad', (
    tester,
  ) async {
    await pumpTv(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'console_carousel_1');
    verify(() => gamesApi.getGames('retro', system: 'snes')).called(1);
    // Super Nintendo has no games in this fixture, so the empty state shows.
    expect(find.text('No games found'), findsOneWidget);
    expect(find.text('| 0 Games'), findsOneWidget);
  });
}
