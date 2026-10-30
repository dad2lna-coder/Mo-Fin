import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient {
  final String baseUrl;
  final String? accessToken = 'secret_token_12345';
  final dynamic deviceInfo = null;

  _MockClient(this.baseUrl);
}

void main() {
  late PluginRegistry registry;
  late SharedPreferences prefs;
  late PluginService pluginService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    registry = PluginRegistry();

    pluginService = PluginService(
      registry: registry,
      prefs: prefs,
      initialPluginsEnabled: true,
      userContextProvider: () => const PluginUserContext(
        userId: 'u1',
        username: 'TestUser',
        serverName: 'MyServer',
      ),
      clientProvider: () => _MockClient('https://myserver.com'),
    );
  });

  testWidgets('PluginWebViewScreen blocks off-server / unauthorized entryUrl and shows error', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final manifest = const PluginManifest(
      id: 'malicious-plugin',
      name: 'Malicious Plugin',
      version: '1.0.0',
      client: PluginClientInfo(html: 'https://evil.com/phish.html'),
      clientEntryUrl: 'https://evil.com/phish.html',
      baseUrl: 'https://myserver.com',
    );
    registry.registerManifest(manifest);

    await tester.pumpWidget(
      MaterialApp(
        home: PluginWebViewScreen(
          title: 'Malicious Plugin',
          pluginId: 'malicious-plugin',
          pluginService: pluginService,
          entryUrl: 'https://evil.com/phish.html',
        ),
      ),
    );

    expect(find.text('Failed to load plugin: Unauthorized entry URL.'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('PluginWebViewScreen blocks manifest with off-server clientEntryUrl even when no explicit entryUrl passed', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final manifest = const PluginManifest(
      id: 'evil-plugin',
      name: 'Evil Plugin',
      version: '1.0.0',
      client: PluginClientInfo(html: 'index.html'),
      clientEntryUrl: 'https://evil.com/steal.html',
      baseUrl: 'https://myserver.com',
    );
    registry.registerManifest(manifest);

    await tester.pumpWidget(
      MaterialApp(
        home: PluginWebViewScreen(
          title: 'Evil Plugin',
          pluginId: 'evil-plugin',
          pluginService: pluginService,
        ),
      ),
    );

    expect(find.text('Failed to load plugin: Unauthorized entry URL.'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
