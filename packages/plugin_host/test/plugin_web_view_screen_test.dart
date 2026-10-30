import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:plugin_host/plugin_host.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  // Mock implementation for test environments where InAppWebViewPlatform is not instantiated
}

void main() {
  group('PluginWebViewScreen Entry URL Resolution Tests', () {
    late PluginRegistry registry;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      registry = PluginRegistry();
      InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
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

      final resolved = handler.resolvePluginFileUrl(rawEntry);
      expect(handler.isUrlUnderPluginFilesPath(resolved), isTrue);
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

      final resolved = handler.resolvePluginFileUrl(rawEntry);
      expect(handler.isUrlUnderPluginFilesPath(resolved), isTrue);
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

      final resolved = handler.resolvePluginFileUrl('../secret.html');
      expect(handler.isUrlUnderPluginFilesPath(resolved), isFalse);
      expect(
        handler.isUrlUnderPluginFilesPath('https://myserver.com/Moonfin/Plugins/hello-world/files/../secret.html'),
        isFalse,
      );
    });

    test('PluginWebViewScreen LOAD test: resolves plugin entry URL without error for standard server base', () {
      final service = PluginService(
        registry: registry,
        prefs: prefs,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://myserver.com'),
        initialPluginsEnabled: true,
      );

      final manifest = const PluginManifest(
        id: 'hello-world',
        name: 'Hello World',
        version: '1.0.0',
        clientEntryUrl: 'client/index.html',
        client: PluginClientInfo(html: 'client/index.html'),
      );
      registry.registerManifest(manifest);

      final handler = service.createHostApiHandler('hello-world');
      final rawCandidate = manifest.clientEntryUrl ?? 'client.html';
      final resolved = handler.resolvePluginFileUrl(rawCandidate);

      expect(handler.isUrlUnderPluginFilesPath(resolved), isTrue);
      expect(
        resolved,
        equals('https://myserver.com/Moonfin/Plugins/hello-world/files/client/index.html'),
      );
    });

    test('PluginWebViewScreen LOAD test: resolves plugin entry URL without error for sub-path server base', () {
      final service = PluginService(
        registry: registry,
        prefs: prefs,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://host/jellyfin'),
        initialPluginsEnabled: true,
      );

      final manifest = const PluginManifest(
        id: 'hello-world',
        name: 'Hello World',
        version: '1.0.0',
        clientEntryUrl: 'client/index.html',
        client: PluginClientInfo(html: 'client/index.html'),
      );
      registry.registerManifest(manifest);

      final handler = service.createHostApiHandler('hello-world');
      final rawCandidate = manifest.clientEntryUrl ?? 'client.html';
      final resolved = handler.resolvePluginFileUrl(rawCandidate);

      expect(handler.isUrlUnderPluginFilesPath(resolved), isTrue);
      expect(
        resolved,
        equals('https://host/jellyfin/Moonfin/Plugins/hello-world/files/client/index.html'),
      );
    });

    test('PluginWebViewScreen LOAD test: blocks path traversal entryUrl', () {
      final service = PluginService(
        registry: registry,
        prefs: prefs,
        userContextProvider: () => null,
        clientProvider: () => _MockClient('https://myserver.com'),
        initialPluginsEnabled: true,
      );

      final manifest = const PluginManifest(
        id: 'hello-world',
        name: 'Hello World',
        version: '1.0.0',
        clientEntryUrl: '../secret',
        client: PluginClientInfo(html: '../secret'),
      );
      registry.registerManifest(manifest);

      final handler = service.createHostApiHandler('hello-world');
      final rawCandidate = manifest.clientEntryUrl ?? 'client.html';
      final resolved = handler.resolvePluginFileUrl(rawCandidate);

      expect(handler.isUrlUnderPluginFilesPath(resolved), isFalse);
    });
  });
}

class _MockClient {
  final String baseUrl;
  final String? accessToken = 'mockToken';
  final DeviceInfo deviceInfo = const DeviceInfo(
    id: 'dev1',
    name: 'Mock Device',
    appName: 'MoFin',
    appVersion: '1.0.0',
  );

  _MockClient(this.baseUrl);
}
