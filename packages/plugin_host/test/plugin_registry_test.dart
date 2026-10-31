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
        client: PluginClientInfo(html: 'client/index.html'),
      );

      registry.registerManifest(manifest);
      expect(registry.plugins.containsKey('direct-plugin'), isTrue);
      expect(registry.isPluginEnabled('direct-plugin'), isTrue);
    });

    test('loads plugins from GET /Moonfin/Plugins response with Moonbase format', () {
      final response = {
        'hostApi': 1,
        'capabilities': {'featureA': true},
        'plugins': [
          {
            'id': 'active-plugin',
            'name': 'Active Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': true,
            'requires': ['featureA'],
            'slots': ['homeRow', 'settings'],
            'proxyAccess': 'admin',
            'clientEntryUrl': '/Moonfin/Plugins/active-plugin/files/client/index.html'
          },
          {
            'id': 'dormant-plugin',
            'name': 'Dormant Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': false,
            'dormantReason': 'Missing host requirement',
            'requires': ['seerr'],
            'slots': ['homeRow'],
            'proxyAccess': 'user',
            'clientEntryUrl': '/Moonfin/Plugins/dormant-plugin/files/client/index.html'
          }
        ]
      };

      registry.loadPluginsFromResponse(response, baseUrl: 'https://server.test');

      expect(registry.plugins.containsKey('active-plugin'), isTrue);
      expect(registry.plugins.containsKey('dormant-plugin'), isFalse);
      expect(registry.urlStatus['dormant-plugin'], contains('Dormant'));
    });

    test('trusts server active flag without client-side requires re-checking', () {
      final response = {
        'hostApi': 1,
        'capabilities': {},
        'plugins': [
          {
            'id': 'seerr-plugin',
            'name': 'Seerr Host Plugin',
            'version': '1.0.0',
            'enabled': true,
            'active': true,
            'requires': ['seerr'],
            'slots': ['homeRow'],
            'proxyAccess': 'admin',
            'clientEntryUrl': '/Moonfin/Plugins/seerr-plugin/files/client/index.html'
          }
        ]
      };

      registry.loadPluginsFromResponse(response);

      expect(registry.isPluginEnabled('seerr-plugin'), isTrue);
    });

    test('enabling and disabling plugins filters UI registrations', () {
      const manifest = PluginManifest(
        id: 'ui-plugin',
        name: 'UI Plugin',
        version: '1.0.0',
        slots: PluginSlots(homeRow: true, settings: true),
        client: PluginClientInfo(html: 'client/index.html'),
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

    test('gamesSlotPlugin is the first enabled games plugin and notifies', () {
      var notifications = 0;
      registry.addListener(() => notifications++);

      const other = PluginManifest(
        id: 'other',
        name: 'Other',
        version: '1.0.0',
        slots: PluginSlots(homeRow: true),
        client: PluginClientInfo(html: 'index.html'),
      );
      const first = PluginManifest(
        id: 'rom-a',
        name: 'ROM A',
        version: '1.0.0',
        slots: PluginSlots(games: true),
        client: PluginClientInfo(html: 'a.html'),
      );
      const second = PluginManifest(
        id: 'rom-b',
        name: 'ROM B',
        version: '1.0.0',
        slots: PluginSlots(games: true),
        client: PluginClientInfo(html: 'b.html'),
      );
      registry.registerManifest(other);
      registry.registerManifest(first);
      registry.registerManifest(second);

      expect(registry.gamesSlotPlugin?.id, 'rom-a');
      final before = notifications;
      registry.setPluginEnabled('rom-a', false);
      expect(registry.gamesSlotPlugin?.id, 'rom-b');
      expect(notifications, greaterThan(before));
    });
  });
}
