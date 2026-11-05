import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_core/server_core.dart';

void main() {
  MoonbaseGamesApi createApi() => MoonbaseGamesApi(
    Dio(),
    () => 'http://redstar.example:8101',
    () => 'test-token',
    ServerType.jellyfin,
  );

  for (final core in ['mame', 'arcade']) {
    test('$core player URL preserves the original encoded ZIP filename', () {
      final player = Uri.parse(
        createApi().playerUrl(
          libraryId: 'Retro Games',
          gameId: 'opaque-token',
          core: core,
          romFileName: 'Atari Tetris (set 1).zip',
        ),
      );

      final rom = Uri.parse(player.queryParameters['rom']!);
      expect(rom.pathSegments.last, 'Atari Tetris (set 1).zip');
      expect(
        Uri.decodeComponent(rom.path),
        endsWith('/opaque-token/Atari Tetris (set 1).zip'),
      );
      expect(rom.queryParameters['ApiKey'], 'test-token');
    });
  }

  test('non-arcade player URL retains the legacy token-only route', () {
    final player = Uri.parse(
      createApi().playerUrl(
        libraryId: 'Retro Games',
        gameId: 'opaque-token',
        core: 'snes',
        romFileName: 'Example Game.zip',
      ),
    );

    final rom = Uri.parse(player.queryParameters['rom']!);
    expect(rom.pathSegments.last, 'opaque-token');
    expect(rom.path, isNot(contains('Example Game.zip')));
  });

  test('player URL uses the supplied core-specific save namespace', () {
    final player = Uri.parse(
      createApi().playerUrl(
        libraryId: 'Retro Games',
        gameId: 'opaque-token',
        core: 'arcade',
        includeSaveUrl: true,
        saveId: 'ejs-arcade-opaque-token',
      ),
    );

    final save = Uri.parse(player.queryParameters['save']!);
    expect(save.path, endsWith('/Saves/ejs-arcade-opaque-token'));
    expect(save.queryParameters['kind'], 'state');
    expect(save.queryParameters['ApiKey'], 'test-token');
  });

  test(
    'artwork protocol models tolerate omitted and malformed optional fields',
    () {
      final system = GameSystem.fromJson({
        'id': 'nes',
        'gameCount': 'not-a-number',
        'previewArtwork': {
          'selectionGeneration': 'inventory-7',
          'panels': [
            {
              'gameId': 'zelda',
              'artwork': {
                'state': 'thumbnailReady',
                'url': 42,
                'revision': 'rev-1',
                'retryAfterSeconds': 'not-a-number',
                'refreshAfterSeconds': {},
              },
            },
            {'gameId': 'empty', 'artwork': 'not-an-object'},
          ],
        },
      });

      expect(system.previewArtwork?.selectionGeneration, 'inventory-7');
      expect(system.gameCount, 0);
      expect(system.previewArtwork?.panels, hasLength(2));
      expect(system.previewArtwork?.panels.first.artwork.isRenderable, isFalse);
      expect(
        system.previewArtwork?.panels.first.artwork.retryAfterSeconds,
        isNull,
      );
      expect(
        system.previewArtwork?.panels.first.artwork.refreshAfterSeconds,
        isNull,
      );
      expect(system.previewArtwork?.panels.last.artwork.state, isEmpty);

      final manifest = GameArtworkManifest.fromJson({
        'generation': 'artwork-7',
        'entries': [
          {
            'gameId': 'zelda',
            'artwork': {
              'boxart': {'state': 'thumbnailReady', 'url': '/art/box'},
              'snap': {'state': 'missing'},
              'title': 'malformed',
            },
          },
        ],
      });
      final capabilities = GameArtworkCapabilities.fromJson({
        'protocolVersion': 2,
        'manifest': true,
        'versionedAssets': true,
        'priorityHints': true,
        'systemPreviews': true,
      });
      final priority = GameArtworkPriorityRequest(
        systemId: 'nes',
        knownGeneration: 'artwork-7',
        items: const [
          GameArtworkPriorityItem(gameId: 'zelda', roles: ['boxart', 'snap']),
        ],
      );

      expect(manifest.entries.single.artwork.keys, ['boxart', 'snap']);
      expect(manifest.entries.single.artwork['boxart']?.isRenderable, isTrue);
      expect(capabilities.supportsManifest, isTrue);
      expect(capabilities.supportsVersionedAssets, isTrue);
      expect(capabilities.supportsPriorityHints, isTrue);
      expect(capabilities.supportsSystemPreviews, isTrue);
      expect(priority.toJson(), {
        'systemId': 'nes',
        'knownGeneration': 'artwork-7',
        'items': [
          {
            'gameId': 'zelda',
            'roles': ['boxart', 'snap'],
          },
        ],
      });
      expect(GameArtworkCapabilities.fromJson({}).supportsManifest, isFalse);
      expect(
        GameArtworkCapabilities.fromJson({
          'protocolVersion': 'two',
        }).supportsManifest,
        isFalse,
      );
    },
  );

  test('protocol 3 descriptors carry artwork dimensions', () {
    final descriptor = GameArtworkDescriptor.fromJson({
      'state': 'thumbnailReady',
      'url': '/art/box',
      'width': 512,
      'height': 374,
    });
    final protocol3 = GameArtworkCapabilities.fromJson({
      'protocolVersion': 3,
      'manifest': true,
      'dimensions': true,
    });

    expect(descriptor.aspectRatio, closeTo(1.369, 0.001));
    expect(
      GameArtworkDescriptor.fromJson({'state': 'pending'}).aspectRatio,
      isNull,
    );
    expect(
      GameArtworkDescriptor.fromJson({'state': 'x', 'width': 512, 'height': 0})
          .aspectRatio,
      isNull,
    );
    expect(protocol3.supportsDimensions, isTrue);
    expect(protocol3.supportsManifest, isTrue);
    expect(
      GameArtworkCapabilities.fromJson({
        'protocolVersion': 2,
        'dimensions': true,
      }).supportsDimensions,
      isFalse,
    );
  });

  test('versioned artwork URLs retain the authenticated server origin', () {
    final artwork = Uri.parse(
      createApi().artworkUrl('/Moonfin/Games/retro/Artwork/zelda/boxart/rev-1'),
    );

    expect(artwork.host, 'redstar.example');
    expect(artwork.path, '/Moonfin/Games/retro/Artwork/zelda/boxart/rev-1');
    expect(artwork.queryParameters['ApiKey'], 'test-token');
  });

  test(
    'cancelArtworkRequests cancels active manifest and priority calls',
    () async {
      final adapter = _BlockingArtworkAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final api = MoonbaseGamesApi(
        dio,
        () => 'http://redstar.example:8101',
        () => 'test-token',
        ServerType.jellyfin,
      );
      final manifest = api.getArtworkManifest('library', systemId: 'nes');
      final priority = api.submitArtworkPriority(
        'library',
        const GameArtworkPriorityRequest(
          systemId: 'nes',
          knownGeneration: 'generation-1',
          items: <GameArtworkPriorityItem>[],
        ),
      );
      final manifestExpectation = expectLater(
        manifest,
        throwsA(isA<DioException>()),
      );
      final priorityExpectation = expectLater(
        priority,
        throwsA(isA<DioException>()),
      );
      await adapter.bothStarted.future;

      api.cancelArtworkRequests();

      await manifestExpectation;
      await priorityExpectation;
      await adapter.allCancelled.future;
      expect(adapter.active, 0);
    },
  );

  test('artwork cancellation is isolated to its adapter owner', () async {
    final adapter = _BlockingArtworkAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = MoonbaseGamesApi(
      dio,
      () => 'http://redstar.example:8101',
      () => 'test-token',
      ServerType.jellyfin,
    );
    final manifestOwner = Object();
    final priorityOwner = Object();
    final manifest = api.getArtworkManifest(
      'library',
      systemId: 'nes',
      cancellationOwner: manifestOwner,
    );
    final priority = api.submitArtworkPriority(
      'library',
      const GameArtworkPriorityRequest(
        systemId: 'nes',
        knownGeneration: 'generation-1',
        items: <GameArtworkPriorityItem>[],
      ),
      cancellationOwner: priorityOwner,
    );
    final manifestExpectation = expectLater(
      manifest,
      throwsA(isA<DioException>()),
    );
    final priorityExpectation = expectLater(
      priority,
      throwsA(isA<DioException>()),
    );
    await adapter.bothStarted.future;

    api.cancelArtworkRequests(cancellationOwner: manifestOwner);
    await manifestExpectation;
    expect(adapter.active, 1);

    api.cancelArtworkRequests(cancellationOwner: priorityOwner);
    await priorityExpectation;
    await adapter.allCancelled.future;
    expect(adapter.active, 0);
  });

  test('getGamesPage reads the page envelope and still slices a bare array', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/Moonfin/Games/retro/Games');
          expect(options.queryParameters['system'], 'Arcade');
          expect(options.queryParameters['offset'], 100);
          expect(options.queryParameters['limit'], 100);
          expect(options.queryParameters.containsKey('generation'), isFalse);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'items': [
                  {
                    'id': 'a',
                    'title': 'Asteroids',
                    'system': 'Arcade',
                    'core': 'mame',
                    'fileName': 'asteroid.zip',
                  },
                ],
                'total': 6670,
                'offset': 100,
                'limit': 100,
              },
            ),
          );
        },
      ),
    );
    final api = MoonbaseGamesApi(
      dio,
      () => 'http://redstar.example:8101',
      () => 'test-token',
      ServerType.jellyfin,
    );

    final page = await api.getGamesPage(
      'retro',
      system: 'Arcade',
      offset: 100,
      limit: 100,
    );
    expect(page.total, 6670);
    expect(page.offset, 100);
    expect(page.limit, 100);
    expect(page.items.single.title, 'Asteroids');

    final legacy = GamePage.fromResponse(
      [
        {'id': 'z', 'title': 'Zelda', 'system': 'nes', 'core': 'fceumm', 'fileName': 'zelda.nes'},
        {'id': 'm', 'title': 'Mario', 'system': 'nes', 'core': 'fceumm', 'fileName': 'mario.nes'},
        {'id': 'k', 'title': 'Kid', 'system': 'nes', 'core': 'fceumm', 'fileName': 'kid.nes'},
      ],
      offset: 1,
      limit: 1,
    );
    expect(legacy.total, 3);
    expect(legacy.items.single.id, 'm');

    final manifest = GameArtworkManifest.fromJson({
      'generation': 'g1',
      'entries': [
        {'gameId': 'a', 'artwork': {}},
      ],
      'total': 6670,
      'offset': 100,
      'limit': 100,
    });
    expect(manifest.total, 6670);
    expect(manifest.offset, 100);
    expect(manifest.entries.single.gameId, 'a');
    expect(GameArtworkManifest.fromJson({'generation': 'g', 'entries': []}).total, isNull);
  });
}

class _BlockingArtworkAdapter implements HttpClientAdapter {
  final Completer<void> bothStarted = Completer<void>();
  final Completer<void> allCancelled = Completer<void>();
  int active = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    active++;
    if (active == 2 && !bothStarted.isCompleted) bothStarted.complete();
    try {
      await cancelFuture;
    } finally {
      active--;
      if (active == 0 && !allCancelled.isCompleted) allCancelled.complete();
    }
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }

  @override
  void close({bool force = false}) {}
}
