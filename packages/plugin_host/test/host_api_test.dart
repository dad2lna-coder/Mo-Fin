import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HostApiHandler Tests', () {
    late PluginRegistry registry;
    late SharedPreferences prefs;
    late HostApiHandler handler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      registry = PluginRegistry();

      final manifest = const PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        provides: ['homeRow', 'settingsPage', 'navItem'],
        slots: PluginSlots(homeRow: true, settings: true),
        client: PluginClientInfo(html: 'index.html'),
      );
      registry.registerManifest(manifest);

      handler = HostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => const PluginUserContext(
          userId: 'u1',
          username: 'TestUser',
          serverName: 'MyServer',
        ),
        clientProvider: () => _MockClient('https://server.test'),
        prefs: prefs,
      );
    });

    test('getHostApiVersion returns current version 2', () async {
      final res = await handler.handleMessage('{"method": "getHostApiVersion"}');
      expect(res['ok'], isTrue);
      expect(res['result']['hostApi'], equals(2));
    });

    test('getUserContext returns user and server info WITHOUT token', () async {
      final res = await handler.handleMessage('{"method": "getUserContext"}');
      expect(res['ok'], isTrue);
      expect(res['result']['userId'], equals('u1'));
      expect(res['result']['username'], equals('TestUser'));
      expect(res['result']['serverName'], equals('MyServer'));
      expect(res['result'].containsKey('token'), isFalse);
      expect(res['result'].containsKey('accessToken'), isFalse);

      final jsonString = jsonEncode(res);
      expect(jsonString.contains('token123'), isFalse);
      expect(jsonString.contains('accessToken'), isFalse);
    });

    test('isUrlUnderPluginFilesPath restricts access to plugin files path and enforces origin', () {
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test/Moonfin/Plugins/test-plugin/files/index.html'),
        isTrue,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('files/index.html'),
        isTrue,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://foreign.com/malicious.html'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test.evil.net/Moonfin/Plugins/test-plugin/files/index.html'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test:8443/Moonfin/Plugins/test-plugin/files/index.html'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test/Moonfin/Plugins/other-plugin/files/index.html'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test/Admin/Settings'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test/Moonfin/Plugins/test-plugin/files/../secret'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://server.test/Moonfin/Plugins/test-plugin/files/%2e%2e/secret'),
        isFalse,
      );

      final emptyClientHandler = HostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        clientProvider: () => _MockClient(''),
        prefs: prefs,
      );
      expect(emptyClientHandler.isUrlUnderPluginFilesPath('files/index.html'), isFalse);
    });

    test('a plugin-files URL with fragment containing .. is accepted once the fragment is stripped', () {
      final rawUrl = 'https://server.test/Moonfin/Plugins/test-plugin/files/index.html#a..b';
      final strippedUrl = Uri.tryParse(rawUrl)?.removeFragment().toString() ?? '';

      // With fragment intact, isUrlUnderPluginFilesPath blocks it because of .. in fragment
      expect(handler.isUrlUnderPluginFilesPath(rawUrl), isFalse);
      // Once fragment is stripped, it is properly accepted
      expect(handler.isUrlUnderPluginFilesPath(strippedUrl), isTrue);
    });

    test('supports sub-path (base-path) servers in isUrlUnderPluginFilesPath and resolvePluginFileUrl', () {
      final subPathHandler = HostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => const PluginUserContext(
          userId: 'u1',
          username: 'TestUser',
          serverName: 'MyServer',
        ),
        clientProvider: () => _MockClient('https://host/jellyfin'),
        prefs: prefs,
      );

      expect(
        subPathHandler.resolvePluginFileUrl('index.html'),
        equals('https://host/jellyfin/Moonfin/Plugins/test-plugin/files/index.html'),
      );
      expect(
        subPathHandler.isUrlUnderPluginFilesPath('https://host/jellyfin/Moonfin/Plugins/test-plugin/files/index.html'),
        isTrue,
      );
      expect(
        subPathHandler.isUrlUnderPluginFilesPath('files/index.html'),
        isTrue,
      );
      expect(
        subPathHandler.isUrlUnderPluginFilesPath('https://host/jellyfin/Moonfin/Plugins/test-plugin/files/../secret'),
        isFalse,
      );
      expect(
        subPathHandler.isUrlUnderPluginFilesPath('https://host/jellyfin/Moonfin/Plugins/test-plugin/files/%2e%2e/secret'),
        isFalse,
      );
    });

    test('callPluginRoute rejects path traversal and reserved paths', () async {
      final res1 = await handler.handleMessage('''
      {
        "method": "callPluginRoute",
        "params": { "path": "../../Users", "method": "GET" }
      }
      ''');
      expect(res1['ok'], isFalse);
      expect(res1['error'], contains('Access denied'));

      final res2 = await handler.handleMessage('''
      {
        "method": "callPluginRoute",
        "params": { "path": "%2e%2e/Users", "method": "GET" }
      }
      ''');
      expect(res2['ok'], isFalse);
      expect(res2['error'], contains('Access denied'));

      final res3 = await handler.handleMessage('''
      {
        "method": "callPluginRoute",
        "params": { "path": "files/secret", "method": "GET" }
      }
      ''');
      expect(res3['ok'], isFalse);
      expect(res3['error'], contains('Access denied'));
    });

    test('openPluginScreen rejects foreign URLs', () async {
      final badRes = await handler.handleMessage('''
      {
        "method": "openPluginScreen",
        "params": { "title": "Evil", "url": "https://evil.com/phish" }
      }
      ''');
      expect(badRes['ok'], isFalse);
      expect(badRes['error'], contains('Access denied'));
    });

    test('registerSettingsPage rejects foreign URLs', () async {
      final badRes = await handler.handleMessage('''
      {
        "method": "registerSettingsPage",
        "params": { "id": "s1", "title": "Evil", "url": "https://evil.com/settings" }
      }
      ''');
      expect(badRes['ok'], isFalse);
      expect(badRes['error'], contains('Access denied'));
    });

    test('registerHomeRow adds row to registry when slot enabled', () async {
      const msg = '''
      {
        "method": "registerHomeRow",
        "params": {
          "id": "row1",
          "title": "Plugin Row",
          "items": [
            { "id": "item1", "title": "Item 1" }
          ]
        }
      }
      ''';

      final res = await handler.handleMessage(msg);
      expect(res['ok'], isTrue);
      expect(registry.homeRows, hasLength(1));
      expect(registry.homeRows.first.title, equals('Plugin Row'));
    });

    test('returns error on unknown method or invalid format', () async {
      final badJson = await handler.handleMessage('INVALID_JSON');
      expect(badJson['ok'], isFalse);

      final unknownMethod = await handler.handleMessage('{"method": "unknownMethod"}');
      expect(unknownMethod['ok'], isFalse);
      expect(unknownMethod['error'], contains('Unknown host API method'));
    });

    test('playGame is denied without a games or playback slot', () async {
      final res = await handler.handleMessage('''
      {
        "method": "playGame",
        "params": { "libraryId": "lib", "gameId": "game" }
      }
      ''');
      expect(res['ok'], isFalse);
      expect(res['error'], contains('Access denied'));
    });

    test('playGame rejects bad parameters', () async {
      final games = _gamesHandler(registry, prefs);

      final missing = await games.handleMessage('{"method":"playGame","params":{}}');
      expect(missing['ok'], isFalse);
      expect(missing['error'], contains('Invalid playGame parameters'));

      final empty = await games.handleMessage(
        '{"method":"playGame","params":{"libraryId":"  ","gameId":"game"}}',
      );
      expect(empty['ok'], isFalse);
      expect(empty['error'], contains('Invalid playGame parameters'));

      final tooLong = 'a' * 2049;
      final longId = await games.handleMessage(
        '{"method":"playGame","params":{"libraryId":"$tooLong","gameId":"game"}}',
      );
      expect(longId['ok'], isFalse);
      expect(longId['error'], contains('Invalid playGame parameters'));

      final badTitle = await games.handleMessage(
        '{"method":"playGame","params":{"libraryId":"lib","gameId":"game","title":1}}',
      );
      expect(badTitle['ok'], isFalse);
      expect(badTitle['error'], contains('Invalid playGame parameters'));
    });

    test('playGame returns the callback result', () async {
      String? seenLibrary;
      String? seenGame;
      String? seenTitle;
      final allow = _gamesHandler(
        registry,
        prefs,
        onPlayGame: ({
          required pluginId,
          required libraryId,
          required gameId,
          title,
        }) async {
          seenLibrary = libraryId;
          seenGame = gameId;
          seenTitle = title;
          return gameId == 'ok';
        },
      );

      final yes = await allow.handleMessage(
        '{"method":"playGame","params":{"libraryId":" lib ","gameId":"ok","title":" Mario "}}',
      );
      expect(yes['ok'], isTrue);
      expect(yes['result'], isTrue);
      expect(seenLibrary, 'lib');
      expect(seenGame, 'ok');
      expect(seenTitle, 'Mario');

      final no = await allow.handleMessage(
        '{"method":"playGame","params":{"libraryId":"lib","gameId":"missing"}}',
      );
      expect(no['ok'], isTrue);
      expect(no['result'], isFalse);

      final noCallback = _gamesHandler(registry, prefs);
      final unanswered = await noCallback.handleMessage(
        '{"method":"playGame","params":{"libraryId":"lib","gameId":"ok"}}',
      );
      expect(unanswered['ok'], isTrue);
      expect(unanswered['result'], isFalse);
    });

    test('preamble exposes play as playGame', () {
      final script = HostApiHandler.getBridgeInjectionScript();
      expect(script, contains("play: (p) => MoFinHost.call('playGame', p)"));
      expect(script, contains('playGame'));
    });
  });
}

HostApiHandler _gamesHandler(
  PluginRegistry registry,
  SharedPreferences prefs, {
  PlayGameCallback? onPlayGame,
}) {
  registry.registerManifest(
    const PluginManifest(
      id: 'rom-manager',
      name: 'ROM Manager',
      version: '1.0.0',
      slots: PluginSlots(games: true),
      client: PluginClientInfo(html: 'index.html'),
    ),
  );
  return HostApiHandler(
    pluginId: 'rom-manager',
    registry: registry,
    userContextProvider: () => null,
    clientProvider: () => _MockClient('https://server.test'),
    prefs: prefs,
    onPlayGame: onPlayGame,
  );
}

class _MockClient {
  final String baseUrl;
  final String? accessToken = 'mockToken';
  final dynamic deviceInfo = null;

  _MockClient(this.baseUrl);
}
