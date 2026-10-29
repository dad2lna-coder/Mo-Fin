import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('PluginManifest Tests', () {
    test('parses valid manifest JSON with defaults', () {
      const json = '''
      {
        "id": "test-plugin",
        "name": "Test Plugin",
        "version": "1.2.0",
        "description": "A test plugin",
        "provides": ["homeRow"],
        "requires": [],
        "slots": { "homeRow": true, "playback": false, "settings": false, "events": false },
        "client": { "html": "index.html", "js": "index.js" },
        "minHostApi": 1,
        "proxyAccess": false
      }
      ''';

      final manifest = PluginManifest.fromRawJson(json);
      expect(manifest.id, equals('test-plugin'));
      expect(manifest.name, equals('Test Plugin'));
      expect(manifest.version, equals('1.2.0'));
      expect(manifest.description, equals('A test plugin'));
      expect(manifest.provides, contains('homeRow'));
      expect(manifest.requires, isEmpty);
      expect(manifest.slots.homeRow, isTrue);
      expect(manifest.client.html, equals('index.html'));
      expect(manifest.client.js, equals('index.js'));
      expect(manifest.minHostApi, equals(1));
      expect(manifest.proxyAccess, isFalse);
    });

    test('resolves relative entryUrl against baseUrl', () {
      const manifest = PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        client: PluginClientInfo(html: 'index.html'),
        baseUrl: 'http://localhost:8080/Moonfin/Plugins/test-plugin/files/plugin.json',
      );

      expect(
        manifest.entryUrl,
        equals('http://localhost:8080/Moonfin/Plugins/test-plugin/files/index.html'),
      );
    });

    test('keeps absolute entryUrl unchanged', () {
      const manifest = PluginManifest(
        id: 'test-plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        client: PluginClientInfo(html: 'https://cdn.example.com/app/index.html'),
        baseUrl: 'http://localhost:8080/plugin.json',
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
        client: PluginClientInfo(html: 'entry.html'),
        minHostApi: 1,
      );

      final map = manifest.toJson();
      expect(map['id'], equals('test-plugin'));
      expect(map['name'], equals('Test Plugin'));
      expect(map['provides'], contains('homeRow'));
      expect(map['slots']['homeRow'], isTrue);
      expect(map['client']['html'], equals('entry.html'));
    });
  });
}
