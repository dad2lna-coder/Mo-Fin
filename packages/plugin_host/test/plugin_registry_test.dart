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
      const manifest = PluginManifest(
        id: 'direct-plugin',
        name: 'Direct Plugin',
        version: '1.0.0',
        client: PluginClientInfo(html: 'index.html'),
      );

      registry.registerManifest(manifest);
      expect(registry.plugins.containsKey('direct-plugin'), isTrue);
      expect(registry.isPluginEnabled('direct-plugin'), isTrue);
    });

    test('loads plugins from GET /Moonfin/Plugins response', () {
      final response = {
        'hostApi': 1,
        'capabilities': {'featureA': true, 'featureB': false},
        'plugins': [
          {
            'id': 'active-plugin',
            'name': 'Active Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': true,
            'requires': ['featureA'],
            'slots': {'homeRow': true, 'settings': true},
            'clientEntryUrl': '/Moonfin/Plugins/active-plugin/files/index.html'
          },
          {
            'id': 'dormant-plugin',
            'name': 'Dormant Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': false,
            'dormantReason': 'Missing requirement featureB',
            'requires': ['featureB'],
            'slots': {'homeRow': true},
            'clientEntryUrl': '/Moonfin/Plugins/dormant-plugin/files/index.html'
          }
        ]
      };

      registry.loadPluginsFromResponse(response, baseUrl: 'https://server.test');

      expect(registry.plugins.containsKey('active-plugin'), isTrue);
      expect(registry.plugins.containsKey('dormant-plugin'), isFalse);
      expect(registry.urlStatus['dormant-plugin'], contains('Dormant'));
    });

    test('plugin with inactive requirements stays dormant and fills no slot', () {
      registry.setCapabilities({'req1': false});

      final response = {
        'hostApi': 1,
        'capabilities': {'req1': false},
        'plugins': [
          {
            'id': 'req-plugin',
            'name': 'Required Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': true,
            'requires': ['req1'],
            'slots': {'homeRow': true},
            'clientEntryUrl': '/Moonfin/Plugins/req-plugin/files/index.html'
          }
        ]
      };

      registry.loadPluginsFromResponse(response);

      expect(registry.isPluginEnabled('req-plugin'), isFalse);
      const row = PluginHomeRow(
        id: 'r1',
        pluginId: 'req-plugin',
        title: 'Row 1',
        items: [],
      );
      registry.registerHomeRow(row);
      expect(registry.homeRows, isEmpty);
    });

    test('enabling and disabling plugins filters UI registrations', () {
      const manifest = PluginManifest(
        id: 'ui-plugin',
        name: 'UI Plugin',
        version: '1.0.0',
        slots: PluginSlots(homeRow: true, settings: true),
        client: PluginClientInfo(html: 'index.html'),
      );
      registry.registerManifest(manifest);

      const row = PluginHomeRow(
        id: 'r1',
        pluginId: 'ui-plugin',
        title: 'Row 1',
        items: [],
      );
      const setting = PluginSettingsEntry(
        id: 's1',
        pluginId: 'ui-plugin',
        title: 'Setting 1',
        url: 'setting.html',
      );

      registry.registerHomeRow(row);
      registry.registerSettingsEntry(setting);

      expect(registry.homeRows, hasLength(1));
      expect(registry.settingsEntries, hasLength(1));

      // Disable plugin
      registry.setPluginEnabled('ui-plugin', false);
      expect(registry.homeRows, isEmpty);
      expect(registry.settingsEntries, isEmpty);

      // Enable plugin
      registry.setPluginEnabled('ui-plugin', true);
      expect(registry.homeRows, hasLength(1));
      expect(registry.settingsEntries, hasLength(1));
    });
  });
}
