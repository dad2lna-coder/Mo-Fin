import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/games/games_hub_screen.dart';
import 'package:moonfin/util/game_launch.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _MockGamesApi extends Mock implements GamesApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMediaServerClient client;
  late _MockGamesApi gamesApi;

  setUp(() async {
    await GetIt.instance.reset();
    client = _MockMediaServerClient();
    gamesApi = _MockGamesApi();
    when(() => client.gamesApi).thenReturn(gamesApi);
    when(() => gamesApi.getGame('nes-lib', 'super-mario')).thenAnswer(
      (_) async => const GameDetail(
        id: 'super-mario',
        title: 'Super Mario Bros.',
        system: 'nes',
        core: 'nes',
        fileName: 'super-mario.nes',
        sizeBytes: 40960,
        bios: [
          GameBios(id: 'bios-nes', fileName: 'disksys.rom', sizeBytes: 8192),
        ],
      ),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('Games hub has no app bar and play hands off to the emulator', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: Destinations.games,
      routes: [
        GoRoute(
          path: Destinations.games,
          builder: (context, state) =>
              const GamesHubScreen(useNavigationChrome: false),
        ),
        GoRoute(
          path: '/game-player/:libraryId/:gameId',
          builder: (context, state) => Scaffold(body: Text(state.uri.toString())),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Install ROM Manager to see games here'), findsOneWidget);

    final pushed = await playGameFromPlugin(
      context: tester.element(find.byType(GamesHubScreen)),
      pluginId: 'rom-manager',
      libraryId: 'nes-lib',
      gameId: 'super-mario',
    );
    expect(pushed, isTrue);
    await tester.pumpAndSettle();

    expect(find.textContaining('/game-player/'), findsOneWidget);
    expect(find.textContaining('core=nes'), findsOneWidget);
    expect(find.textContaining('bios=bios-nes'), findsOneWidget);
  });
}
