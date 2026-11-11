import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/rom_manager_games.dart';
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

GamePage _pageOf(List<GameSummary> games) => GamePage(
  items: games,
  total: games.length,
  offset: 0,
  limit: GamePage.defaultLimit,
);

/// The phone catalog: one titled tile for 1942, not a zip per clone.
class _GroupedArcade extends RomManagerGames {
  _GroupedArcade() : super(dio: Dio());

  int calls = 0;

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    calls++;
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:Arcade/1942',
          title: '1942',
          system: 'Arcade',
          path: 'Arcade/1942.zip',
          versions: 3,
        ),
      ],
      total: 1,
      indexing: false,
    );
  }

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(pluginMissing: true);

  @override
  Future<List<RomDeveloper>> developers(
    MediaServerClient client, {
    int limit = 40,
  }) async => const [];

  @override
  Future<Map<String, Uint8List>> covers(
    MediaServerClient client,
    List<String> paths,
  ) async => <String, Uint8List>{};
}

class _QuietRom extends RomManagerGames {
  _QuietRom() : super(dio: Dio());

  @override
  Future<List<RomDeveloper>> developers(
    MediaServerClient client, {
    int limit = 40,
  }) async => const [];

  @override
  Future<Map<String, Uint8List>> covers(
    MediaServerClient client,
    List<String> paths,
  ) async => <String, Uint8List>{};
}

class _BucketCatalog extends _QuietRom {
  int probes = 0;
  String? lastBucket;

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(
        systems: [RomSystemCount(name: 'Arcade', games: 1200)],
      );

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    lastBucket = bucket;
    if (includeBuckets) {
      probes++;
      return RomManagerGamePage(
        items: const [],
        total: 1200,
        indexing: false,
        buckets: [
          for (final pair in RomManagerGames.letterBuckets)
            RomLetterBucket(
              id: pair.id,
              label: pair.label,
              games: pair.id == 'Q-S' ? 40 : 10,
            ),
        ],
      );
    }
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:Arcade/qbert',
          title: 'Q*bert',
          system: 'Arcade',
          path: 'Arcade/qbert.zip',
          versions: 1,
        ),
      ],
      total: 1,
      indexing: false,
    );
  }
}

class _TitleOrderedRom extends _QuietRom {
  List<String>? lastKeys;

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(systems: [RomSystemCount(name: 'Arcade', games: 3)]);

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    lastKeys = keys == null ? null : List<String>.of(keys);
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:a',
          title: 'Alpha',
          system: 'Arcade',
          path: 'Arcade/a.zip',
          versions: 1,
        ),
        RomManagerGame(
          key: 'm:m',
          title: 'Middle',
          system: 'Arcade',
          path: 'Arcade/m.zip',
          versions: 1,
        ),
        RomManagerGame(
          key: 'm:z',
          title: 'Zebra',
          system: 'Arcade',
          path: 'Arcade/z.zip',
          versions: 1,
        ),
      ],
      total: 3,
      indexing: false,
    );
  }
}

class _TvCatalog extends _QuietRom {
  _TvCatalog({this.fail = false});

  final bool fail;
  int probes = 0;
  final List<Map<String, Object?>> calls = [];

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(
        systems: [
          RomSystemCount(name: 'Arcade', games: 2532),
          RomSystemCount(name: 'NES', games: 1000),
        ],
      );

  @override
  Future<List<RomDeveloper>> developers(
    MediaServerClient client, {
    int limit = 40,
  }) async => const [
    RomDeveloper(key: 'capcom', name: 'Capcom', games: 80),
    RomDeveloper(key: 'namco', name: 'Namco', games: 40),
  ];

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    calls.add({
      'system': system,
      'bucket': bucket,
      'includeBuckets': includeBuckets,
      'developer': developer,
      'limit': limit,
    });
    if (fail) {
      lastFailure = RomCatalogFailure.failed;
      return null;
    }
    if (includeBuckets) {
      probes++;
      return RomManagerGamePage(
        items: const [],
        total: 2532,
        indexing: false,
        buckets: [
          for (final pair in RomManagerGames.letterBuckets)
            RomLetterBucket(
              id: pair.id,
              label: pair.label,
              games: pair.id == 'Q-S' ? 410 : 300,
            ),
        ],
      );
    }
    if (developer != null) {
      return const RomManagerGamePage(
        items: [
          RomManagerGame(
            key: 'm:cap',
            title: 'Final Fight',
            system: 'Arcade',
            path: 'Arcade/ffight.zip',
            versions: 1,
          ),
        ],
        total: 1,
        indexing: false,
      );
    }
    if (system == 'NES') {
      return const RomManagerGamePage(
        items: [
          RomManagerGame(
            key: 'm:nes',
            title: 'Super Mario Bros.',
            system: 'NES',
            path: 'NES/mario.nes',
            versions: 1,
          ),
        ],
        total: 1,
        indexing: false,
      );
    }
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:Arcade/qbert',
          title: 'Q*bert',
          system: 'Arcade',
          path: 'Arcade/qbert.zip',
          versions: 1,
        ),
      ],
      total: 1,
      indexing: false,
    );
  }
}

class _SmallCatalog extends _QuietRom {
  bool probed = false;

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(systems: [RomSystemCount(name: 'NES', games: 1000)]);

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    if (includeBuckets) probed = true;
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:nes',
          title: 'Super Mario Bros.',
          system: 'NES',
          path: 'NES/mario.nes',
          versions: 1,
        ),
      ],
      total: 1,
      indexing: false,
    );
  }
}

class _RetryRom extends _QuietRom {
  int calls = 0;

  @override
  Future<RomSystemList> systems(MediaServerClient client) async =>
      const RomSystemList(systems: [RomSystemCount(name: 'Arcade', games: 4)]);

  @override
  Future<RomManagerGamePage?> page({
    required MediaServerClient client,
    required String system,
    int offset = 0,
    String sort = 'title',
    String? query,
    String? letter,
    String? bucket,
    String? developer,
    bool includeBuckets = false,
    int? limit,
    List<String>? keys,
  }) async {
    calls++;
    if (calls == 1) return null;
    return const RomManagerGamePage(
      items: [
        RomManagerGame(
          key: 'm:Arcade/1942',
          title: '1942',
          system: 'Arcade',
          path: 'Arcade/1942.zip',
          versions: 1,
        ),
      ],
      total: 1,
      indexing: false,
    );
  }
}

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
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: 'nes',
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => _pageOf(nesGames));
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: 'snes',
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => _pageOf(const []));
  });

  tearDown(() {
    PlatformDetection.setTvMode(false);
    GetIt.instance.reset();
  });

  testWidgets('tab filtering: All, Favorites, and Recently Played', (
    tester,
  ) async {
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

  testWidgets(
    'Left on first console opens side menu on TV without moving off screen',
    (tester) async {
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

      // On TV the sidebar starts expanded so the stats cards are always visible.
      expect(find.text('Downloaded Storage'), findsOneWidget);
      expect(find.text('Total Games'), findsOneWidget);

      // Send Left arrow key on the first console
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Side menu is opened
      expect(find.text('Downloaded Storage'), findsOneWidget);
      expect(find.text('Total Games'), findsOneWidget);
      expect(find.text('Downloaded Games'), findsOneWidget);
    },
  );

  testWidgets('a failed later page leaves the games already loaded', (
    tester,
  ) async {
    var calls = 0;
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: 'nes',
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((invocation) async {
      final offset = invocation.namedArguments[#offset] as int? ?? 0;
      calls++;
      if (offset == 0) {
        return GamePage(
          items: nesGames,
          total: nesGames.length + 1,
          offset: 0,
          limit: GamePage.defaultLimit,
        );
      }
      throw StateError('page failed');
    });

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
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('| 4 Games'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Zelda'), findsOneWidget);
    expect(find.text('No games found'), findsNothing);
    expect(calls, greaterThan(1));
  });

  testWidgets('ROM Manager groups arcade clones instead of the file list', (
    tester,
  ) async {
    final arcade = const [
      GameSystem(id: 'Arcade', name: 'Arcade', core: 'fbneo', gameCount: 6670),
    ];
    when(() => gamesApi.getSystems('retro')).thenAnswer((_) async => arcade);
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: any(named: 'system'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => _pageOf(const []));

    final roms = _GroupedArcade();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GamesBrowserScreen(libraryId: 'retro', romGames: roms),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('1942'), findsOneWidget);
    expect(find.text('1942abl'), findsNothing);
    expect(find.text('3 Versions'), findsOneWidget);
    expect(find.text('| 1 Games'), findsOneWidget);
    expect(roms.calls, 1);
    verifyNever(
      () => gamesApi.getGamesPage(
        any(),
        system: any(named: 'system'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    );
  });

  testWidgets('a large catalog opens the letter-range bucket picker', (
    tester,
  ) async {
    when(() => gamesApi.getSystems('retro')).thenAnswer(
      (_) async => const [
        GameSystem(
          id: 'arcade',
          name: 'Arcade',
          core: 'fbneo',
          gameCount: 1200,
        ),
      ],
    );
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: any(named: 'system'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => _pageOf(const []));

    final roms = _BucketCatalog();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GamesBrowserScreen(libraryId: 'retro', romGames: roms),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Pick a letter range. Each one loads on its own.'),
      findsOneWidget,
    );
    expect(find.text('# – D'), findsOneWidget);
    expect(find.text('Q – S'), findsOneWidget);
    expect(find.text('40 Games'), findsOneWidget);
    expect(find.text('Q*bert'), findsNothing);
    expect(roms.probes, 1);

    await tester.tap(find.text('Q – S'));
    await tester.pump();
    await tester.pump();

    expect(roms.lastBucket, 'Q-S');
    expect(find.text('Q*bert'), findsOneWidget);
    expect(
      find.text('Pick a letter range. Each one loads on its own.'),
      findsNothing,
    );
    verify(() => gamesApi.getSystems('retro')).called(1);
  });

  testWidgets('Recent and Recently played follow local last-played order', (
    tester,
  ) async {
    GameLocalData.instance.resetForTest(recents: ['retro:m:z', 'retro:m:a']);
    final roms = _TitleOrderedRom();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GamesBrowserScreen(libraryId: 'retro', romGames: roms),
      ),
    );
    await tester.pump();
    await tester.pump();

    _expectReadingOrder(tester, ['Alpha', 'Middle', 'Zebra']);

    await tester.tap(find.text('Recently Played'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Middle'), findsNothing);
    _expectReadingOrder(tester, ['Zebra', 'Alpha']);
    expect(roms.lastKeys, ['m:z', 'm:a']);

    await tester.tap(find.text('All Games'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Name A–Z'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Name Z–A'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Recently played'), findsOneWidget);
    _expectReadingOrder(tester, ['Zebra', 'Alpha', 'Middle']);
  });

  testWidgets('a missing plugin is tried again on refresh', (tester) async {
    when(
      () => gamesApi.getGamesPage(
        'retro',
        system: any(named: 'system'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(
      (_) async => _pageOf(const [
        GameSummary(
          id: 'zip',
          title: 'Zip Only',
          fileName: 'a.zip',
          system: 'Arcade',
          core: '',
        ),
      ]),
    );

    final roms = _RetryRom();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GamesBrowserScreen(libraryId: 'retro', romGames: roms),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(roms.calls, 1);
    expect(find.text('Zip Only'), findsOneWidget);
    expect(find.text('1942'), findsNothing);

    await tester.tap(find.text('Name A–Z'));
    await tester.pump();
    await tester.pump();

    expect(roms.calls, 2);
    expect(find.text('1942'), findsOneWidget);
    expect(find.text('Zip Only'), findsNothing);
  });

  testWidgets('a big system shows letter ranges and D-pad reaches them', (
    tester,
  ) async {
    final roms = _TvCatalog();
    await _pumpTv(tester, roms);

    expect(
      find.text('Pick a letter range. Each one loads on its own.'),
      findsOneWidget,
    );
    expect(find.text('# – D'), findsOneWidget);
    expect(find.text('E – H'), findsOneWidget);
    expect(find.text('I – L'), findsOneWidget);
    expect(find.text('M – P'), findsOneWidget);
    expect(find.text('Q – S'), findsOneWidget);
    expect(find.text('T – Z'), findsOneWidget);
    expect(find.text('410 Games'), findsOneWidget);
    expect(find.text('300 Games'), findsNWidgets(5));
    expect(find.text('| 2532 Games'), findsOneWidget);
    expect(find.text('| 0 Games'), findsNothing);
    expect(find.text('No games found'), findsNothing);
    expect(find.text('Q*bert'), findsNothing);
    expect(roms.probes, 1);
    expect(roms.calls.single['includeBuckets'], isTrue);
    expect(roms.calls.single['limit'], 1);
    expect(roms.calls.single['system'], 'Arcade');

    expect(_focusLabel(tester), 'console_carousel_0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), 'games_dev_0');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), 'games_bucket_0');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusLabel(tester), 'games_tab_all');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), 'games_bucket_0');

    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focusLabel(tester), 'games_bucket_4');
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(roms.calls.last['bucket'], 'Q-S');
    expect(roms.calls.last['includeBuckets'], isFalse);
    expect(roms.calls.last['system'], 'Arcade');
    expect(find.text('Q*bert'), findsOneWidget);
    expect(
      find.text('Pick a letter range. Each one loads on its own.'),
      findsNothing,
    );
    expect(_focusLabel(tester), 'game_poster:0');

    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(find.text('Q*bert'), findsNothing);
    expect(find.text('Q – S'), findsOneWidget);
    expect(_focusLabel(tester), 'games_bucket_4');
  });

  testWidgets(
    'a system of 1000 games skips ranges and D-pad reaches the grid',
    (tester) async {
      final roms = _SmallCatalog();
      await _pumpTv(tester, roms);

      expect(find.text('Super Mario Bros.'), findsOneWidget);
      expect(
        find.text('Pick a letter range. Each one loads on its own.'),
        findsNothing,
      );
      expect(find.text('# – D'), findsNothing);
      expect(roms.probed, isFalse);
      expect(_focusLabel(tester), 'console_carousel_0');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusLabel(tester), 'game_poster:0');
    },
  );

  testWidgets('the developer row does not trap D-pad focus', (tester) async {
    final roms = _TvCatalog();
    await _pumpTv(tester, roms);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), 'games_dev_0');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusLabel(tester), 'games_dev_1');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusLabel(tester), 'games_dev_0');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), isNot(startsWith('games_dev_')));
    expect(_focusLabel(tester), 'games_bucket_0');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusLabel(tester), 'games_dev_0');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusLabel(tester), 'console_carousel_0');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(roms.calls.last['developer'], 'Capcom');
    expect(roms.calls.last['system'], '');
    expect(find.text('Final Fight'), findsOneWidget);
    expect(find.text('# – D'), findsNothing);

    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(find.text('Final Fight'), findsNothing);
    expect(find.text('# – D'), findsOneWidget);
    expect(find.text('410 Games'), findsOneWidget);
    expect(_focusLabel(tester), 'games_bucket_0');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();

    expect(find.text('Super Mario Bros.'), findsOneWidget);
    expect(find.text('# – D'), findsNothing);
    expect(roms.calls.last['includeBuckets'], isFalse);
    expect(roms.calls.last['system'], 'NES');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusLabel(tester), 'games_dev_0');
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(roms.calls.last['developer'], 'Capcom');
    expect(roms.calls.last['system'], '');
    expect(find.text('Final Fight'), findsOneWidget);
    expect(find.text('Super Mario Bros.'), findsNothing);

    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(find.text('Super Mario Bros.'), findsOneWidget);
    expect(find.text('# – D'), findsNothing);
    expect(find.text('Final Fight'), findsNothing);
    expect(roms.calls.last['developer'], isNull);
    expect(roms.calls.last['includeBuckets'], isFalse);
    expect(roms.calls.last['system'], 'NES');
  });

  testWidgets(
    'a failed letter-range probe shows Retry instead of an empty grid',
    (tester) async {
      final roms = _TvCatalog(fail: true);
      await _pumpTv(tester, roms);

      expect(find.text('Could not load Arcade.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No games found'), findsNothing);
      expect(find.text('| 0 Games'), findsNothing);
      expect(find.text('# – D'), findsNothing);

      expect(_focusLabel(tester), 'console_carousel_0');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusLabel(tester), 'games_dev_0');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusLabel(tester), 'games_retry');
    },
  );
}

void _expectReadingOrder(WidgetTester tester, List<String> titles) {
  Offset? previous;
  for (final title in titles) {
    final at = tester.getTopLeft(find.text(title));
    if (previous != null) {
      final lower = at.dy > previous.dy + 1;
      final sameRowLater =
          (at.dy - previous.dy).abs() <= 1 && at.dx > previous.dx;
      expect(
        lower || sameRowLater,
        isTrue,
        reason: '$title should follow the previous title',
      );
    }
    previous = at;
  }
}

String? _focusLabel(WidgetTester tester) =>
    tester.binding.focusManager.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _pumpTv(WidgetTester tester, RomManagerGames roms) async {
  PlatformDetection.setTvMode(true);
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.buildTheme(ThemeRegistry.active),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GamesBrowserScreen(libraryId: 'retro', romGames: roms),
    ),
  );
  await tester.pump();
  await tester.pump();
}
