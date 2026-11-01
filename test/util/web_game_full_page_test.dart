import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/web_game_full_page.dart';
import 'package:server_core/server_core.dart';
import 'package:dio/dio.dart';

void main() {
  const iphoneSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 '
      'Mobile/15E148 Safari/604.1';
  const ipadSafari =
      'Mozilla/5.0 (iPad; CPU OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 '
      'Mobile/15E148 Safari/604.1';
  const ipadDesktopSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15';
  const macSafari = ipadDesktopSafari;
  const iphoneChrome =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.103 '
      'Mobile/15E148 Safari/604.1';
  const iphoneFirefox =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/132.0 '
      'Mobile/15E148 Safari/605.1.15';
  const androidChrome =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  test('iPhone and iPad Safari are detected, other browsers are not', () {
    expect(isIosOrIpadOsSafari(userAgent: iphoneSafari), isTrue);
    expect(isIosOrIpadOsSafari(userAgent: ipadSafari), isTrue);
    expect(
      isIosOrIpadOsSafari(userAgent: ipadDesktopSafari, maxTouchPoints: 5),
      isTrue,
    );
    expect(
      isIosOrIpadOsSafari(userAgent: macSafari, maxTouchPoints: 0),
      isFalse,
    );
    expect(
      isIosOrIpadOsSafari(userAgent: macSafari, maxTouchPoints: 1),
      isFalse,
    );
    expect(isIosOrIpadOsSafari(userAgent: iphoneChrome), isFalse);
    expect(isIosOrIpadOsSafari(userAgent: iphoneFirefox), isFalse);
    expect(isIosOrIpadOsSafari(userAgent: androidChrome), isFalse);
    expect(
      isIosOrIpadOsSafari(
        userAgent:
            'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/131.0.2903.84 '
            'Version/18.0 Mobile/15E148 Safari/604.1',
      ),
      isFalse,
    );
    expect(isIosOrIpadOsSafari(userAgent: ''), isFalse);
  });

  test('full-page launch is iOS Safari on web, or an explicit setting', () {
    expect(
      shouldOpenGameFullPage(
        isWeb: true,
        iosSafari: true,
        openGamesFullPage: false,
      ),
      isTrue,
    );
    expect(
      shouldOpenGameFullPage(
        isWeb: true,
        iosSafari: false,
        openGamesFullPage: true,
      ),
      isTrue,
    );
    expect(
      shouldOpenGameFullPage(
        isWeb: true,
        iosSafari: false,
        openGamesFullPage: false,
      ),
      isFalse,
    );
    expect(
      shouldOpenGameFullPage(
        isWeb: false,
        iosSafari: true,
        openGamesFullPage: true,
      ),
      isFalse,
    );
  });

  test('full-page URL keeps the player params and adds a hash returnUrl', () {
    final api = MoonbaseGamesApi(
      Dio(),
      () => 'http://redstar.example:8101',
      () => 'test-token',
      ServerType.jellyfin,
    );
    final player = api.playerUrl(
      libraryId: 'Retro Games',
      gameId: 'mslug',
      core: 'fbneo',
      romFileName: 'mslug.zip',
      biosId: 'neogeo',
      gameName: 'Metal Slug',
      includeSaveUrl: true,
      saveId: 'ejs-fbneo-mslug',
    );
    const back = 'https://mofin.example/app/#/games-hub';
    final launched = Uri.parse(
      fullPagePlayerUrl(playerUrl: player, returnUrl: back, loadState: true),
    );

    expect(launched.path, endsWith('/Moonfin/EmulatorJS/player.html'));
    expect(launched.queryParameters['core'], 'fbneo');
    expect(launched.queryParameters['name'], 'Metal Slug');
    expect(launched.queryParameters['returnUrl'], back);
    expect(launched.queryParameters.containsKey('fresh'), isFalse);

    final rom = Uri.parse(launched.queryParameters['rom']!);
    expect(rom.pathSegments.last, 'mslug');
    expect(rom.queryParameters['ApiKey'], 'test-token');

    final bios = Uri.parse(launched.queryParameters['bios']!);
    expect(bios.path, contains('/Bios/neogeo'));
    expect(bios.queryParameters['ApiKey'], 'test-token');

    final save = Uri.parse(launched.queryParameters['save']!);
    expect(save.path, endsWith('/Saves/ejs-fbneo-mslug'));
    expect(save.queryParameters['kind'], 'state');
    expect(save.queryParameters['ApiKey'], 'test-token');

    final saveWrite = Uri.parse(launched.queryParameters['saveWrite']!);
    expect(saveWrite.toString(), save.toString());

    final sram = Uri.parse(launched.queryParameters['sramWrite']!);
    expect(sram.path, save.path);
    expect(sram.queryParameters['kind'], 'sram');
    expect(sram.queryParameters['ApiKey'], 'test-token');
    expect(launched.queryParameters.containsKey('sram'), isFalse);
  });

  test('full-page URL keeps an arcade zip filename through re-encoding', () {
    final api = MoonbaseGamesApi(
      Dio(),
      () => 'http://redstar.example:8101',
      () => 'test-token',
      ServerType.jellyfin,
    );
    final player = api.playerUrl(
      libraryId: 'Retro Games',
      gameId: 'opaque-token',
      core: 'arcade',
      romFileName: 'Atari Tetris (set 1).zip',
      includeSaveUrl: true,
      saveId: 'ejs-arcade-opaque-token',
    );
    final launched = Uri.parse(
      fullPagePlayerUrl(
        playerUrl: player,
        returnUrl: 'https://mofin.example/#/games-hub',
        loadState: true,
      ),
    );
    final rom = Uri.parse(launched.queryParameters['rom']!);
    expect(rom.pathSegments.last, 'Atari Tetris (set 1).zip');
    expect(rom.queryParameters['ApiKey'], 'test-token');
    expect(
      Uri.parse(launched.queryParameters['returnUrl']!).toString(),
      'https://mofin.example/#/games-hub',
    );
  });

  test('a fresh launch does not ask the current player to load a state', () {
    const player =
        'https://redstar.example/Moonfin/EmulatorJS/player.html'
        '?core=snes'
        '&rom=https%3A%2F%2Fredstar.example%2From%3FApiKey%3Dtok'
        '&save=https%3A%2F%2Fredstar.example%2FSaves%2Fid%3Fkind%3Dstate%26ApiKey%3Dtok';
    final launched = Uri.parse(
      fullPagePlayerUrl(
        playerUrl: player,
        returnUrl: 'https://mofin.example/#/game/lib/id',
        loadState: false,
      ),
    );

    expect(launched.queryParameters.containsKey('save'), isFalse);
    expect(launched.queryParameters['fresh'], '1');
    expect(launched.queryParameters['core'], 'snes');
    final write = Uri.parse(launched.queryParameters['saveWrite']!);
    expect(write.queryParameters['kind'], 'state');
    expect(write.queryParameters['ApiKey'], 'tok');
    final sram = Uri.parse(launched.queryParameters['sramWrite']!);
    expect(sram.queryParameters['kind'], 'sram');
    expect(launched.queryParameters.containsKey('sram'), isFalse);
  });

  test('return href leaves the hash route unless it is the player', () {
    expect(
      gameReturnHref(
        href: 'https://mofin.example/#/games-hub',
        route: '/games-hub',
        libraryId: 'lib',
        gameId: 'id',
      ),
      'https://mofin.example/#/games-hub',
    );
    expect(
      gameReturnHref(
        href: 'https://mofin.example/app/#/game-player/lib/id?core=fbneo',
        route: '/game-player/lib/id?core=fbneo',
        libraryId: 'Retro Games',
        gameId: 'mslug',
      ),
      'https://mofin.example/app/#/game/${Uri.encodeComponent('Retro Games')}/mslug',
    );
  });

  test('stored return route restores the Games tab, plugin, or game', () {
    final hub = WebGameReturnSnapshot(
      route: '/games-hub',
      href: 'https://mofin.example/#/games-hub',
      pluginId: 'rom-manager',
      libraryId: 'lib',
      gameId: 'mslug',
      title: 'Metal Slug',
    );
    final decoded = WebGameReturnSnapshot.decode(hub.encode());
    expect(decoded?.restoreRoute, '/games-hub');
    expect(decoded?.pluginId, 'rom-manager');
    expect(decoded?.gameId, 'mslug');
    expect(decoded?.title, 'Metal Slug');

    const plugin =
        '/plugin-screen?pluginId=rom-manager&url=https%3A%2F%2Fx%2Fp&title=ROM';
    final pluginRoute = WebGameReturnSnapshot(
      route: plugin,
      href: 'https://mofin.example/#$plugin',
    ).restoreRoute;
    expect(pluginRoute, isNotNull);
    expect(Uri.parse(pluginRoute!).queryParameters, {
      'pluginId': 'rom-manager',
      'url': 'https://x/p',
      'title': 'ROM',
    });

    expect(
      WebGameReturnSnapshot(
        route: '/game-player/lib/mslug?core=fbneo',
        href: 'https://mofin.example/#/game-player/lib/mslug?core=fbneo',
        libraryId: 'lib',
        gameId: 'mslug',
      ).restoreRoute,
      '/game/lib/mslug',
    );
    expect(
      const WebGameReturnSnapshot(
        route: '/game-player/lib/mslug',
        href: 'https://mofin.example/#/game-player/lib/mslug',
      ).restoreRoute,
      '/games-hub',
    );
    expect(
      const WebGameReturnSnapshot(
        route: 'https://evil.example/games-hub',
        href: 'https://mofin.example/',
      ).restoreRoute,
      isNull,
    );
    expect(
      const WebGameReturnSnapshot(
        route: '//evil.example/games-hub',
        href: 'https://mofin.example/',
      ).restoreRoute,
      isNull,
    );
    expect(WebGameReturnSnapshot.decode('not-json'), isNull);
    expect(WebGameReturnSnapshot.decode(null), isNull);

    final store = {WebGameReturnSnapshot.storageKey: hub.encode()};
    expect(takeStoredGameReturnRoute(store), '/games-hub');
    expect(store, isEmpty);
    expect(takeStoredGameReturnRoute(store), isNull);
  });
}
