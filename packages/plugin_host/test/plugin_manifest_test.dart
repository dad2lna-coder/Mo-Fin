import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('PluginManifest Tests', () {
    test('parses valid manifest JSON in Moonbase format with defaults', () {
      const json = '''
      {
        "id": "test-plugin",
        "name": "Test Plugin",
        "version": "1.2.0",
        "description": "A test plugin",
        "provides": ["test.homeRow"],
        "requires": [],
        "slots": ["homeRow"],
        "client": { "html": "client/index.html", "js": "client/app.js" },
        "minHostApi": 1,
        "proxyAccess": "admin",
        "clientEntryUrl": "/Moonfin/Plugins/test-plugin/files/client/index.html"
      }
      ''';

      final manifest = PluginManifest.fromRawJson(json);
      expect(manifest.id, equals('test-plugin'));
      expect(manifest.name, equals('Test Plugin'));
      expect(manifest.version, equals('1.2.0'));
      expect(manifest.description, equals('A test plugin'));
      expect(manifest.provides, contains('test.homeRow'));
      expect(manifest.requires, isEmpty);
      expect(manifest.slots.homeRow, isTrue);
      expect(manifest.client.html, equals('client/index.html'));
      expect(manifest.client.js, equals('client/app.js'));
      expect(manifest.minHostApi, equals(1));
      expect(manifest.proxyAccess, equals('admin'));
      expect(manifest.clientEntryUrl, equals('/Moonfin/Plugins/test-plugin/files/client/index.html'));
    });

    test('parses proxyAccess string levels correctly', () {
      final m1 = PluginManifest.fromJson({'id': 'a', 'proxyAccess': 'admin'});
      expect(m1.proxyAccess, equals('admin'));

      final m2 = PluginManifest.fromJson({'id': 'b', 'proxyAccess': 'user'});
      expect(m2.proxyAccess, equals('user'));

      final m3 = PluginManifest.fromJson({'id': 'c', 'proxyAccess': true});
      expect(m3.proxyAccess, equals('admin'));

      final m4 = PluginManifest.fromJson({'id': 'd'});
      expect(m4.proxyAccess, equals('admin'));
    });

    test('resolves relative entryUrl against baseUrl', () {
      const manifest = PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        client: PluginClientInfo(html: 'client/index.html'),
        clientEntryUrl: '/Moonfin/Plugins/test-plugin/files/client/index.html',
        baseUrl: 'http://localhost:8080',
      );

      expect(
        manifest.entryUrl,
        equals('http://localhost:8080/Moonfin/Plugins/test-plugin/files/client/index.html'),
      );
    });

    test('keeps absolute entryUrl unchanged', () {
      const manifest = PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        client: PluginClientInfo(html: 'https://cdn.example.com/app/index.html'),
        clientEntryUrl: 'https://cdn.example.com/app/index.html',
        baseUrl: 'http://localhost:8080',
      );

      expect(
        manifest.entryUrl,
        equals('https://cdn.example.com/app/index.html'),
      );
    });

    test('serializes to JSON correctly', () {
      const manifest = PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        provides: ['homeRow', 'settings'],
        slots: PluginSlots(homeRow: true, settings: true),
        client: PluginClientInfo(html: 'client/index.html'),
        minHostApi: 1,
        proxyAccess: 'admin',
      );

      final map = manifest.toJson();
      expect(map['id'], equals('test-plugin'));
      expect(map['name'], equals('Test Plugin'));
      expect(map['provides'], contains('homeRow'));
      expect(map['slots'], contains('homeRow'));
      expect(map['proxyAccess'], equals('admin'));
    });
    test('games slot round-trips through list and map forms', () {
      final fromList = PluginSlots.fromJson(['games', 'playback']);
      expect(fromList.games, isTrue);
      expect(fromList.playback, isTrue);
      expect(fromList.toJson(), ['games', 'playback']);
      expect(PluginSlots.fromJson(fromList.toJson()).games, isTrue);

      final fromMap = PluginSlots.fromJson({
        'games': true,
        'homeRow': false,
      });
      expect(fromMap.games, isTrue);
      expect(fromMap.homeRow, isFalse);
      expect(fromMap.toJson(), {
        'homeRow': false,
        'playback': false,
        'settings': false,
        'events': false,
        'games': true,
      });

      final manifest = PluginManifest(
        id: 'rom-manager',
        name: 'ROM Manager',
        version: '1.0.0',
        slots: fromList,
        client: const PluginClientInfo(html: 'index.html'),
      );
      final decoded = PluginManifest.fromJson(manifest.toJson());
      expect(decoded.slots.games, isTrue);
      expect(decoded.slots.playback, isTrue);
    });
  });
}
