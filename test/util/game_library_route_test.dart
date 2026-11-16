import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/util/game_library.dart';

void main() {
  group('libraryRoute', () {
    setUp(() => GetIt.instance.reset());
    tearDown(() => GetIt.instance.reset());

    void registerGameLibraries(List<String> ids) {
      GetIt.instance.registerSingleton<GameLibraryRegistry>(
        GameLibraryRegistry()..seed(ids),
      );
    }

    test('a registered game library wins over its collection type', () {
      registerGameLibraries(['lib-games']);

      // Moonbase lets an admin mark any library as a game library, so these
      // types must not short-circuit the games route.
      for (final type in ['books', 'audiobooks', 'music', 'livetv']) {
        expect(
          libraryRoute('lib-games', type, 'Games'),
          startsWith('/games/lib-games'),
          reason: 'collectionType $type stole the games route',
        );
      }
    });

    test('passes the title through for the games browser', () {
      registerGameLibraries(['lib-games']);

      expect(
        libraryRoute('lib-games', null, 'Retro Games'),
        '/games/lib-games?title=Retro+Games',
      );
    });

    test('a library the registry does not list keeps its own route', () {
      registerGameLibraries(['lib-games']);

      expect(libraryRoute('lib-books', 'books', 'Books'),
          '/books/lib-books?collectionType=books');
      expect(libraryRoute('lib-music', 'music', 'Music'), '/music/lib-music');
      expect(libraryRoute('lib-tv', 'livetv', 'Live TV'), '/live-tv/direct');
      expect(
        libraryRoute('lib-movies', 'movies', 'Movies'),
        startsWith('/library/lib-movies'),
      );
    });

    test('falls back to name matching on a mixed library when the registry '
        'never loaded', () {
      // No GameLibraryRegistry registered at all: offline, or a server without
      // the games API.
      expect(
        libraryRoute('lib-roms', null, 'ROMs'),
        startsWith('/games/lib-roms'),
      );
      expect(
        libraryRoute('lib-mixed', 'mixed', 'Emulators'),
        startsWith('/games/lib-mixed'),
      );
      // A typed library must not be guessed at by name alone.
      expect(
        libraryRoute('lib-shows', 'tvshows', 'Game of Thrones'),
        startsWith('/library/lib-shows'),
      );
    });

    test('Retro Games opens the games screen even when the registry omits it',
        () {
      registerGameLibraries(['lib-games']);

      expect(
        libraryRoute('lib-roms', 'homevideos', 'Retro Games'),
        startsWith('/games/lib-roms'),
      );
      expect(
        libraryRoute('lib-roms', null, 'ROMs'),
        startsWith('/games/lib-roms'),
      );
    });

    test('a library named Live TV opens Direct IPTV', () {
      registerGameLibraries(['lib-games']);

      expect(
        libraryRoute('lib-live', 'movies', 'Live Television'),
        '/live-tv/direct',
      );
    });

    test('a stored screen override wins over the automatic match', () {
      registerGameLibraries(['lib-games']);

      expect(
        libraryRoute(
          'lib-games',
          'mixed',
          'Retro Games',
          screenOverrides: const {'lib-games': libraryScreenBrowse},
        ),
        startsWith('/library/lib-games'),
      );
      expect(
        libraryRoute(
          'lib-movies',
          'movies',
          'Movies',
          screenOverrides: const {'lib-movies': libraryScreenDirect},
        ),
        '/live-tv/direct',
      );
      expect(
        libraryRoute(
          'lib-movies',
          'movies',
          'Movies',
          screenOverrides: const {'lib-movies': libraryScreenGames},
        ),
        startsWith('/games/lib-movies'),
      );
    });

    test('the screen map ignores anything that is not a known target', () {
      expect(
        decodeLibraryScreenMap('{"a":"direct","b":"nope","c":1}'),
        {'a': libraryScreenDirect},
      );
      expect(
        decodeLibraryScreenMap(
          encodeLibraryScreenMap({'a': libraryScreenGames, 'b': 'folder'}),
        ),
        {'a': libraryScreenGames},
      );
    });
  });
}
