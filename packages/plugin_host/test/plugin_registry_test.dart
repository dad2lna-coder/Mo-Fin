import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('PluginRegistry Tests', () {
    late PluginRegistry registry;

    setUp(() {
      registry = PluginRegistry();
    });

    test('initial state is empty', () {
      expect(registry.plugins, isEmpty);
      expect(registry.homeRows, isEmpty);
      expect(registry.settingsEntries, isEmpty);
      expect(registry.navItems, isEmpty);
    });

    test('registers manifest directly', () {
      final manifest = PluginManifest(
        id: 'direct.plugin',
        name: 'Direct Plugin',
        version: '1.0.0',
        entry: 'index.html',
      );

      registry.registerManifest(manifest);
      expect(registry.plugins.containsKey('direct.plugin'), isTrue);
      expect(registry.isPluginEnabled('direct.plugin'), isTrue);
    });

    test('loads plugins from valid URLs with mock fetcher', () async {
      const validJson = '''
      {
        "id": "valid.plugin",
        "name": "Valid Plugin",
        "version": "1.0.0",
        "minHostApi": 1,
        "entry": "index.html"
      }
      ''';

      await registry.loadPluginsFromUrls(
        ['http://server/plugin.json'],
        fetcher: (url) async => validJson,
      );

      expect(registry.plugins.containsKey('valid.plugin'), isTrue);
      expect(registry.urlStatus['http://server/plugin.json'], contains('Loaded'));
    });

    test('skips plugin with minHostApi higher than current host version', () async {
      const futureApiJson = '''
      {
        "id": "future.plugin",
        "name": "Future Plugin",
        "version": "2.0.0",
        "minHostApi": 99,
        "entry": "index.html"
      }
      ''';

      await registry.loadPluginsFromUrls(
        ['http://server/future.json'],
        fetcher: (url) async => futureApiJson,
      );

      expect(registry.plugins.containsKey('future.plugin'), isFalse);
      expect(registry.urlStatus['http://server/future.json'], contains('Incompatible'));
    });

    test('gracefully skips invalid JSON or failed HTTP requests without throwing', () async {
      await registry.loadPluginsFromUrls(
        ['http://server/bad.json', 'http://server/error.json'],
        fetcher: (url) async {
          if (url.contains('bad')) return 'NOT_JSON';
          throw Exception('404 Not Found');
        },
      );

      expect(registry.plugins, isEmpty);
      expect(registry.urlStatus['http://server/bad.json'], contains('Failed'));
      expect(registry.urlStatus['http://server/error.json'], contains('Failed'));
    });

    test('enabling and disabling plugins filters UI registrations', () {
      final manifest = PluginManifest(
        id: 'ui.plugin',
        name: 'UI Plugin',
        version: '1.0.0',
        entry: 'index.html',
      );
      registry.registerManifest(manifest);

      const row = PluginHomeRow(
        id: 'r1',
        pluginId: 'ui.plugin',
        title: 'Row 1',
        items: [],
      );
      const setting = PluginSettingsEntry(
        id: 's1',
        pluginId: 'ui.plugin',
        title: 'Setting 1',
        url: 'setting.html',
      );

      registry.registerHomeRow(row);
      registry.registerSettingsEntry(setting);

      expect(registry.homeRows, hasLength(1));
      expect(registry.settingsEntries, hasLength(1));

      // Disable plugin
      registry.setPluginEnabled('ui.plugin', false);
      expect(registry.homeRows, isEmpty);
      expect(registry.settingsEntries, isEmpty);

      // Enable plugin
      registry.setPluginEnabled('ui.plugin', true);
      expect(registry.homeRows, hasLength(1));
      expect(registry.settingsEntries, hasLength(1));
    });
  });
}
