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

      handler = HostApiHandler(
        pluginId: 'test.plugin',
        registry: registry,
        userContextProvider: () => const PluginUserContext(
          userId: 'u1',
          username: 'TestUser',
          serverUrl: 'https://server.test/',
          token: 'token123',
        ),
        prefs: prefs,
      );
    });

    test('getHostApiVersion returns current version 1', () async {
      final res = await handler.handleMessage('{"method": "getHostApiVersion"}');
      expect(res['ok'], isTrue);
      expect(res['result']['hostApi'], equals(1));
    });

    test('getUserContext returns user and server info', () async {
      final res = await handler.handleMessage('{"method": "getUserContext"}');
      expect(res['ok'], isTrue);
      expect(res['result']['userId'], equals('u1'));
      expect(res['result']['username'], equals('TestUser'));
      expect(res['result']['serverUrl'], equals('https://server.test/'));
      expect(res['result']['token'], equals('token123'));
    });

    test('registerHomeRow adds row to registry', () async {
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

    test('storageSet and storageGet isolate keys by pluginId', () async {
      await handler.handleMessage('''
      {
        "method": "storageSet",
        "params": { "key": "myKey", "value": "myVal" }
      }
      ''');

      expect(prefs.getString('plugin_test.plugin_myKey'), equals('myVal'));

      final getRes = await handler.handleMessage('''
      {
        "method": "storageGet",
        "params": { "key": "myKey" }
      }
      ''');

      expect(getRes['ok'], isTrue);
      expect(getRes['result'], equals('myVal'));
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
