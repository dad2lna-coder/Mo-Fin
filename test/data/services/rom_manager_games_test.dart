import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/rom_manager_games.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

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
    client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://server:8096/');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(id: 'd', name: 'TV', appName: 'MoFin', appVersion: '1'),
    );
  });

  RomManagerGames service(_Adapter adapter) =>
      RomManagerGames(dio: Dio()..httpClientAdapter = adapter);

  test('pages the grouped catalog and keeps the MAME title', () async {
    final adapter = _Adapter(
      (_, _) async => _json({
        'ok': true,
        'total': 2,
        'indexing': false,
        'items': [
          {
            'key': 'm:Arcade/1942',
            'title': '1942',
            'system': 'Arcade',
            'coverPath': 'Arcade/1942',
            'versions': 4,
          },
          {
            'key': 'm:Arcade/1943',
            'title': '1943: The Battle of Midway',
            'system': 'Arcade',
            'coverPath': 'Arcade/1943',
            'versions': 2,
            'cheat': 'some',
          },
        ],
      }),
    );

    final page = await service(adapter).page(client: client, system: 'Arcade');

    expect(adapter.calls.single.uri.path, '/Moonfin/Plugins/rom-manager/games');
    final body = adapter.bodies.single as Map;
    expect(body['system'], 'Arcade');
    expect(body['limit'], 60);
    expect(body['offset'], 0);
    expect(page?.total, 2);
    expect(page?.items.map((game) => game.title).toList(), [
      '1942',
      '1943: The Battle of Midway',
    ]);
    final summary = page!.items.first.toSummary('arcade');
    expect(summary.id, 'm:Arcade/1942');
    expect(summary.versionsCount, 4);
    expect(summary.fileName, '1942');
    expect(page.items.last.cheat, 'some');
  });

  test('a missing plugin is null so the file list can be used', () async {
    final adapter = _Adapter((options, _) async {
      return ResponseBody.fromString(
        'nope',
        404,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );
    });

    expect(
      await service(adapter).page(client: client, system: 'Arcade'),
      isNull,
    );
  });

  test(
    'launch keeps the player id and a reason when the ROM cannot start',
    () async {
      final adapter = _Adapter(
        (_, _) async => _json({
          'ok': true,
          'libraryId': 'lib',
          'gameId': 'token',
          'core': 'fbneo',
          'playable': false,
          'reason': 'BIOS is missing for this system.',
        }),
      );

      final launch = await service(adapter)
          .launch(client: client, key: 'm:Arcade/1942', path: 'Arcade/1942');

      expect(
        adapter.calls.single.uri.path,
        '/Moonfin/Plugins/rom-manager/launch',
      );
      expect((adapter.bodies.single as Map)['p'], 'Arcade/1942');
      expect(launch?.gameId, 'token');
      expect(launch?.playable, isFalse);
      expect(launch?.reason, 'BIOS is missing for this system.');
    },
  );

  test('covers decode data URIs and drop anything else', () {
    expect(RomManagerGames.decodeCover('http://x'), isNull);
    final bytes = RomManagerGames.decodeCover(
      'data:image/jpeg;base64,${base64Encode(const [1, 2, 3])}',
    );
    expect(bytes, [1, 2, 3]);
  });
}
