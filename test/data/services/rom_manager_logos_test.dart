import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/rom_manager_logos.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

/// A 1x1 transparent PNG, the smallest thing the plugin could legitimately
/// answer with.
const String _pngDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class _LogoAdapter implements HttpClientAdapter {
  _LogoAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options, Object? body)
  respond;

  final List<RequestOptions> calls = [];
  final List<Object?> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    bodies.add(body);
    return respond(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late _MockClient client;

  setUp(() {
    RomManagerLogoService.resetSessionCache();
    client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://server:8096/');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(
      () => client.deviceInfo,
    ).thenReturn(const DeviceInfo(id: 'd', name: 'TV', appName: 'MoFin', appVersion: '1'));
  });

  RomManagerLogoService serviceWith(_LogoAdapter adapter) =>
      RomManagerLogoService(dio: Dio()..httpClientAdapter = adapter);

  test('keeps data URIs and caches them per console name', () async {
    final adapter = _LogoAdapter(
      (_, _) async => _json({
        'ok': true,
        'kind': 'consoles',
        'logos': {'Nintendo Entertainment System': _pngDataUri},
      }),
    );
    final service = serviceWith(adapter);

    final changed = await service.fetchConsoles(client, [
      'Nintendo Entertainment System',
    ]);

    expect(changed, isTrue);
    expect(service.logoFor('Nintendo Entertainment System'), _pngDataUri);
    expect(service.logoFor('Super Nintendo'), isNull);

    // The request went to the plugin's logos route with the documented body.
    expect(adapter.calls, hasLength(1));
    final call = adapter.calls.single;
    expect(call.method, 'POST');
    expect(
      call.uri.toString(),
      'http://server:8096/Moonfin/Plugins/rom-manager/logos',
    );
    expect(call.headers['Authorization'], contains('MediaBrowser'));
    expect(call.headers['Authorization'], contains('token'));
    final body = adapter.bodies.single! as Map<String, dynamic>;
    expect(body['kind'], 'consoles');
    expect(body['names'], ['Nintendo Entertainment System']);
  });

  test('refuses anything that is not an image data URI', () async {
    final adapter = _LogoAdapter(
      (_, _) async => _json({
        'ok': true,
        'kind': 'consoles',
        'logos': {
          'NES': 'http://example.test/nes.png',
          'SNES': 'data:text/plain;base64,aGk=',
          'GBA': 'data:image/png;base64,@@@@',
          'GB': _pngDataUri,
        },
      }),
    );
    final service = serviceWith(adapter);

    final changed = await service.fetchConsoles(client, [
      'NES',
      'SNES',
      'GBA',
      'GB',
    ]);

    expect(changed, isTrue);
    expect(service.logoFor('NES'), isNull);
    expect(service.logoFor('SNES'), isNull);
    expect(service.logoFor('GB'), _pngDataUri);
    expect(RomManagerLogoService.isLogoDataUri('http://x/y.png'), isFalse);
    expect(
      RomManagerLogoService.decodeDataUri('data:image/png;base64,@@@@'),
      isNull,
    );
  });

  test('does not ask twice for a console in one session', () async {
    final adapter = _LogoAdapter(
      (_, _) async => _json({'ok': true, 'kind': 'consoles', 'logos': {}}),
    );
    final service = serviceWith(adapter);

    await service.fetchConsoles(client, ['NES']);
    final again = await service.fetchConsoles(client, ['NES']);

    expect(again, isFalse);
    expect(adapter.calls, hasLength(1));
  });

  test('batches past the route name limit', () async {
    final adapter = _LogoAdapter(
      (_, _) async => _json({'ok': true, 'kind': 'consoles', 'logos': {}}),
    );
    final service = serviceWith(adapter);

    await service.fetchConsoles(client, [
      for (var i = 0; i < RomManagerLogoService.maxNamesPerRequest + 3; i++)
        'Console $i',
    ]);

    expect(adapter.calls, hasLength(2));
    expect((adapter.bodies.first! as Map)['names'], hasLength(500));
    expect((adapter.bodies.last! as Map)['names'], hasLength(3));
  });

  test('a slow server times out to no logos instead of holding the screen', () async {
    final adapter = _LogoAdapter((_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _json({
        'ok': true,
        'kind': 'consoles',
        'logos': {'NES': _pngDataUri},
      });
    });
    final service = RomManagerLogoService(
      dio: Dio()..httpClientAdapter = adapter,
      timeout: const Duration(milliseconds: 30),
    );

    final changed = await service.fetchConsoles(client, ['NES']);

    expect(changed, isFalse);
    expect(service.logoFor('NES'), isNull);
  });

  test('a missing route is not an error', () async {
    final adapter = _LogoAdapter((_, _) async => _json({}, status: 404));
    final service = serviceWith(adapter);

    expect(await service.fetchConsoles(client, ['NES']), isFalse);
  });

  test('an empty server address asks for nothing', () async {
    when(() => client.baseUrl).thenReturn('   ');
    final adapter = _LogoAdapter((_, _) async => _json({}));
    final service = serviceWith(adapter);

    expect(await service.fetchConsoles(client, ['NES']), isFalse);
    expect(adapter.calls, isEmpty);
  });
}
