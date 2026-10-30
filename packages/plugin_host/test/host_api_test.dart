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

    test('getHostApiVersion returns current version 1', () async {
      final res = await handler.handleMessage('{"method": "getHostApiVersion"}');
      expect(res['ok'], isTrue);
      expect(res['result']['hostApi'], equals(1));
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
  });
}

class _MockClient {
  final String baseUrl;
  final String? accessToken = 'mockToken';
  final dynamic deviceInfo = null;

  _MockClient(this.baseUrl);
}
