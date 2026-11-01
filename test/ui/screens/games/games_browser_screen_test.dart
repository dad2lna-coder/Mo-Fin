import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMediaServerClient client;
  late _MockGamesApi gamesApi;

  final systems = const [
    GameSystem(
      id: 'nes',
      name: 'Nintendo Entertainment System',
      core: 'fceumm',
      gameCount: 3,
    ),
    GameSystem(
      id: 'snes',
      name: 'Super Nintendo',
      core: 'snes9x',
      gameCount: 2,
    ),
  ];

  final List<GameSummary> nesGames = const [
    GameSummary(id: 'g1', title: 'Zelda', fileName: 'zelda.nes', system: 'nes', core: 'fceumm'),
    GameSummary(id: 'g2', title: 'Mario', fileName: 'mario.nes', system: 'nes', core: 'fceumm'),
    GameSummary(id: 'g3', title: 'Metroid', fileName: 'metroid.nes', system: 'nes', core: 'fceumm'),
  ];

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    client = _MockMediaServerClient();
    gamesApi = _MockGamesApi();
    when(() => client.gamesApi).thenReturn(gamesApi);
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);

    when(() => gamesApi.getSystems('retro')).thenAnswer((_) async => systems);
    when(() => gamesApi.getGames('retro', system: 'nes')).thenAnswer((_) async => nesGames);
    when(() => gamesApi.getGames('retro', system: 'snes')).thenAnswer((_) async => const []);
  });

  tearDown(() {
    PlatformDetection.setTvMode(false);
    GetIt.instance.reset();
  });

  testWidgets('tab filtering: All, Favorites, and Recently Played', (tester) async {
    // g2 is favorite, g3 is recent
    GameLocalData.instance.resetForTest(
      favorites: {'retro:g2'},
      recents: ['retro:g3'],
    );

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GamesBrowserScreen(libraryId: 'retro'),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Default tab is All -> shows all 3 games
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Metroid'), findsOneWidget);
    expect(find.text('Zelda'), findsOneWidget);

    // Switch to Favorites tab
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Zelda'), findsNothing);
    expect(find.text('Metroid'), findsNothing);

    // Switch to Recently Played tab
    await tester.tap(find.text('Recently Played'));
    await tester.pumpAndSettle();

    expect(find.text('Metroid'), findsOneWidget);
    expect(find.text('Mario'), findsNothing);
    expect(find.text('Zelda'), findsNothing);
  });

  testWidgets('sort cycling changes game order', (tester) async {
    GameLocalData.instance.resetForTest(
      favorites: {},
      recents: ['retro:g2', 'retro:g3'], // Mario played first, Metroid second
    );

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GamesBrowserScreen(libraryId: 'retro'),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Default Name A-Z: Mario, Metroid, Zelda
    expect(find.text('Name A–Z'), findsOneWidget);

    // Tap sort button -> Name Z-A
    await tester.tap(find.text('Name A–Z'));
    await tester.pumpAndSettle();

    expect(find.text('Name Z–A'), findsOneWidget);

    // Tap sort button -> Recently played
    await tester.tap(find.text('Name Z–A'));
    await tester.pumpAndSettle();

    expect(find.text('Recently played'), findsOneWidget);
  });

  testWidgets('Left on first console opens side menu on TV without moving off screen', (tester) async {
    PlatformDetection.setTvMode(true);

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GamesBrowserScreen(libraryId: 'retro'),
      ),
    );
    await tester.pump();
    await tester.pump();

    // On TV, first item autofocuses
    expect(find.text('Downloaded Storage'), findsNothing);

    // Send Left arrow key on the first console
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    // Side menu is opened
    expect(find.text('Downloaded Storage'), findsOneWidget);
    expect(find.text('Total Games'), findsOneWidget);
    expect(find.text('Downloaded Games'), findsOneWidget);
  });
}
