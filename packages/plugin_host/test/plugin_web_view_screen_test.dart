import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PluginWebViewScreen Entry URL Resolution Tests', () {
    late PluginRegistry registry;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      registry = PluginRegistry();
    });

    test('resolves default clientEntryUrl relative to standard server origin', () {
      final manifest = const PluginManifest(
        id: 'hello-world',
        name: 'Hello World',
        version: '1.0.0',
        clientEntryUrl: 'client/index.html',
        client: PluginClientInfo(html: 'client/index.html'),
      );
      registry.registerManifest(manifest);

      final handler = HostApiHandler(
        pluginId: 'hello-world',
        registry: registry,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://myserver.com'),
        prefs: prefs,
      );

      final rawEntry = manifest.clientEntryUrl ?? manifest.client.html;
      expect(rawEntry, equals('client/index.html'));
      expect(handler.isUrlUnderPluginFilesPath(rawEntry), isTrue);

      final resolved = handler.resolvePluginFileUrl(rawEntry);
      expect(
        resolved,
        equals('https://myserver.com/Moonfin/Plugins/hello-world/files/client/index.html'),
      );
    });

    test('resolves default clientEntryUrl relative to sub-path server origin', () {
      final manifest = const PluginManifest(
        id: 'hello-world',
        name: 'Hello World',
        version: '1.0.0',
        clientEntryUrl: 'client/index.html',
        client: PluginClientInfo(html: 'client/index.html'),
      );
      registry.registerManifest(manifest);

      final handler = HostApiHandler(
        pluginId: 'hello-world',
        registry: registry,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://host/jellyfin'),
        prefs: prefs,
      );

      final rawEntry = manifest.clientEntryUrl ?? manifest.client.html;
      expect(rawEntry, equals('client/index.html'));
      expect(handler.isUrlUnderPluginFilesPath(rawEntry), isTrue);

      final resolved = handler.resolvePluginFileUrl(rawEntry);
      expect(
        resolved,
        equals('https://host/jellyfin/Moonfin/Plugins/hello-world/files/client/index.html'),
      );
    });

    test('rejects path traversal entry URLs', () {
      final handler = HostApiHandler(
        pluginId: 'hello-world',
        registry: registry,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://myserver.com'),
        prefs: prefs,
      );

      expect(
        handler.isUrlUnderPluginFilesPath('../secret.html'),
        isFalse,
      );
      expect(
        handler.isUrlUnderPluginFilesPath('https://myserver.com/Moonfin/Plugins/hello-world/files/../secret.html'),
        isFalse,
      );
    });
  });
}

class _MockClient {
  final String baseUrl;
  final String? accessToken = 'mockToken';

  _MockClient(this.baseUrl);
}
