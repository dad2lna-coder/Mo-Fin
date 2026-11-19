import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/direct_iptv_client.dart';
import 'package:moonfin/direct_iptv/feed_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Call {
  final String method;
  final String? body;

  const _Call(this.method, this.body);
}

class _SyncTransport extends DirectIptvTransport {
  _SyncTransport(this.handler);

  final DirectIptvHttpResult Function(_Call call) handler;
  final calls = <_Call>[];

  @override
  Future<DirectIptvHttpResult> get(
    Uri url,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    return send('GET', url, headers, timeout: timeout);
  }

  @override
  Future<DirectIptvHttpResult> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final call = _Call(method, body?.toString());
    calls.add(call);
    return handler(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a choice survives in local storage for that Jellyfin user', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = DirectFeedPreference(preferences: prefs, userId: 'alice');
    await store.save('tvg:cnn', 'direct:backup:cnn');

    final again = DirectFeedPreference(preferences: prefs, userId: 'alice');
    await again.ensureLoaded();
    expect(again.choiceFor('tvg:cnn'), 'direct:backup:cnn');

    final other = DirectFeedPreference(preferences: prefs, userId: 'bob');
    await other.ensureLoaded();
    expect(other.choiceFor('tvg:cnn'), isNull);
    expect(
      prefs.getString(directFeedChoiceKey('alice')),
      contains('direct:backup:cnn'),
    );
  });

  test(
    'Moonbase wins for keys it has and a missing route stays local',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        directFeedChoiceKey('alice'),
        jsonEncode({
          'choices': {
            'tvg:cnn': 'direct:local:cnn',
            'tvg:hbo': 'direct:local:hbo',
          },
        }),
      );
      final transport = _SyncTransport((call) {
        if (call.method == 'GET') {
          return const DirectIptvHttpResult(
            200,
            '{"choices":{"tvg:cnn":"direct:server:cnn"}}',
          );
        }
        return const DirectIptvHttpResult(200, '{"ok":true}');
      });
      final store = DirectFeedPreference(
        preferences: prefs,
        userId: 'alice',
        sync: MoonbaseDirectFeedSync(
          transport: transport,
          endpoint: MoonbaseDirectFeedSync.endpointFor('http://jellyfin.test'),
          headers: const {'Authorization': 'MediaBrowser Token="t"'},
        ),
      );
      await store.ensureLoaded();
      expect(store.choiceFor('tvg:cnn'), 'direct:server:cnn');
      expect(store.choiceFor('tvg:hbo'), 'direct:local:hbo');
      expect(transport.calls.last.method, 'PUT');

      final missing = _SyncTransport(
        (_) => const DirectIptvHttpResult(404, 'missing'),
      );
      final localOnly = DirectFeedPreference(
        preferences: prefs,
        userId: 'alice',
        sync: MoonbaseDirectFeedSync(
          transport: missing,
          endpoint: MoonbaseDirectFeedSync.endpointFor('http://jellyfin.test'),
          headers: const {'Authorization': 'MediaBrowser Token="t"'},
        ),
      );
      await localOnly.ensureLoaded();
      expect(localOnly.choiceFor('tvg:cnn'), 'direct:server:cnn');
      await localOnly.save('tvg:espn', 'direct:backup:espn');
      expect(localOnly.choiceFor('tvg:espn'), 'direct:backup:espn');
      expect(missing.calls.map((call) => call.method), ['GET']);
    },
  );
}
