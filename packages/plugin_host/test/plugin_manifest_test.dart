import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('PluginManifest Tests', () {
    test('parses valid manifest JSON with defaults', () {
      const json = '''
      {
        "id": "test.plugin",
        "name": "Test Plugin",
        "version": "1.2.0",
        "entry": "index.html"
      }
      ''';

      final manifest = PluginManifest.fromRawJson(json);
      expect(manifest.id, equals('test.plugin'));
      expect(manifest.name, equals('Test Plugin'));
      expect(manifest.version, equals('1.2.0'));
      expect(manifest.minHostApi, equals(1));
      expect(manifest.entry, equals('index.html'));
      expect(manifest.permissions, isEmpty);
      expect(manifest.hooks, isEmpty);
    });

    test('resolves relative entryUrl against baseUrl', () {
      final manifest = PluginManifest(
        id: 'test.plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        entry: 'index.html',
        baseUrl: 'http://localhost:8080/myplugin/plugin.json',
      );

      expect(
        manifest.entryUrl,
        equals('http://localhost:8080/myplugin/index.html'),
      );
    });

    test('keeps absolute entryUrl unchanged', () {
      final manifest = PluginManifest(
        id: 'test.plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        entry: 'https://cdn.example.com/app/index.html',
        baseUrl: 'http://localhost:8080/plugin.json',
      );

      expect(
        manifest.entryUrl,
        equals('https://cdn.example.com/app/index.html'),
      );
    });

    test('serializes to JSON correctly', () {
      final manifest = PluginManifest(
        id: 'test.plugin',
        name: 'Test Plugin',
        version: '1.0.0',
        minHostApi: 1,
        entry: 'entry.html',
        permissions: ['storage', 'playback'],
        hooks: ['homeRow'],
      );

      final map = manifest.toJson();
      expect(map['id'], equals('test.plugin'));
      expect(map['name'], equals('Test Plugin'));
      expect(map['permissions'], contains('storage'));
      expect(map['hooks'], contains('homeRow'));
    });
  });
}
