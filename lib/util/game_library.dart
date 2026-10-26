import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../ui/navigation/destinations.dart';

/// Shared helpers for recognizing and navigating to retro-game (ROM) libraries so every
/// entry point (home tiles, sidebar, top navbar, bottom nav) treats them consistently.
///
/// The Moonbase plugin decides which libraries are game libraries: an admin can select any
/// library, and the plugin exposes that list at /Moonfin/Games/Libraries. The client mirrors
/// it through [GameLibraryRegistry]. Until that list has loaded (offline, or a server without
/// the updated plugin) we fall back to the plugin's own auto-detect, which matches a Mixed
/// Content library by name.
final RegExp _gameLibraryName = RegExp('game|rom|emulat', caseSensitive: false);

/// Caches the game-library ids the Moonbase plugin reports, so routing can tell a game
/// library from a normal one synchronously. Refreshed when the library list loads.
class GameLibraryRegistry {
  final Set<String> _ids = <String>{};
  bool _loaded = false;
  Future<void>? _inFlightRefresh;

  bool get loaded => _loaded;
  bool contains(String id) => _ids.contains(id);

  /// Concurrent callers share a single request instead of each hitting the
  /// server.
  Future<void> refresh() => _inFlightRefresh ??= _refreshNow().whenComplete(
    () => _inFlightRefresh = null,
  );

  /// Populates the registry directly. Tests have no [MediaServerClient] to
  /// refresh from, and both `_ids` and `_loaded` are private.
  @visibleForTesting
  void seed(Iterable<String> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _loaded = true;
  }

  Future<void> _refreshNow() async {
    if (!GetIt.instance.isRegistered<MediaServerClient>()) return;
    final gamesApi = GetIt.instance<MediaServerClient>().gamesApi;
    if (gamesApi == null) return;
    try {
      final libraries = await gamesApi.getLibraries();
      _ids
        ..clear()
        ..addAll(libraries.map((l) => l.id));
      _loaded = true;
    } catch (_) {
      // Keep the previous ids so routing stays stable. The name fallback covers
      // the case where the list never loads.
    }
  }
}

bool isGameLibrary(String id, String? collectionType, String? name) {
  if (GetIt.instance.isRegistered<GameLibraryRegistry>()) {
    final registry = GetIt.instance<GameLibraryRegistry>();
    if (registry.loaded) return registry.contains(id);
  }
  if (name == null || name.isEmpty) return false;
  final ct = (collectionType ?? '').toLowerCase();
  // Mixed Content libraries report an empty/unknown/mixed collection type.
  if (ct.isNotEmpty && ct != 'mixed' && ct != 'unknown') return false;
  return _gameLibraryName.hasMatch(name);
}

/// The route a library tile should open, for every entry point: home tiles, the
/// sidebar, the top toolbar and the mobile bottom nav.
///
/// The game check runs **before** the collection-type switch on purpose. Moonbase
/// lets an admin mark any library as a game library, so one can carry a
/// `books`, `music` or `audiobooks` type and still be a games library. Switching
/// on the type first sent those to the book reader or the music browser and the
/// games browser became unreachable, even though [GameLibraryRegistry] listed
/// the library and the tile already drew a gamepad icon for it.
String libraryRoute(
  String id,
  String? collectionType,
  String name, {
  String? serverId,
}) {
  if (isGameLibrary(id, collectionType, name)) {
    return '${Destinations.gamesLibrary(id)}?title=${Uri.encodeQueryComponent(name)}';
  }
  switch ((collectionType ?? '').toLowerCase()) {
    case 'music':
      return Destinations.musicLibrary(id);
    case 'books':
    case 'audiobooks':
      return Destinations.bookLibrary(
        id,
        collectionType: (collectionType ?? '').toLowerCase(),
      );
    case 'livetv':
      return Destinations.liveTvGuide;
    default:
      return Destinations.library(id, serverId: serverId);
  }
}

const IconData gameLibraryIcon = Icons.sports_esports;

/// A game's art, served by the Moonbase plugin. Null on a server without the games API.
///
/// The plugin fetches the art from libretro and caches it rather than the client going there
/// itself: libretro sends no CORS headers, which a browser will not accept, and one download
/// on the server then serves every client. [kind] is `boxart`, `snap` or `title`. A URL comes
/// back even when the game has no art, so callers still need their error fallback.
String? gameThumbUrl(
  String libraryId,
  String gameId, {
  String kind = 'boxart',
}) {
  final api = GetIt.instance<MediaServerClient>().gamesApi;
  return api?.thumbUrl(libraryId: libraryId, gameId: gameId, kind: kind);
}

String _fileStem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

/// A safe display title for a game. Some ROM folder names carry characters the app font
/// cannot render (they arrive as the replacement char) or control bytes; strip those and,
/// when nothing legible remains, fall back to the filename without its extension.
///
/// No-Intro and GoodTools suffixes ride on the end of the name — `(USA)`, `(Rev 1)`,
/// `[!]`, `[T+Eng]` — and are not part of the title. A trailing `, The` / `, A` / `, An`
/// is the catalog's article-last form and is turned back into "The Name".
String gameDisplayTitle(String title, String fileName) {
  final cleaned = title
      .replaceAll('�', '')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .trim();
  final source = cleaned.isEmpty ? _fileStem(fileName) : cleaned;
  final display = _promoteLeadingArticle(_stripTrailingGroups(source));
  return display.isEmpty ? _fileStem(fileName) : display;
}

/// Folder artwork is a stand-in for a ROM that has no libretro thumbnail. Use the
/// folder's name only when the plugin title is empty or is just the filename —
/// a real plugin title, descriptions, and details stay as the server sent them.
String preferGameFolderTitle({
  required String title,
  required String fileName,
  String? folderTitle,
}) {
  final folder = folderTitle?.trim();
  if (folder == null || folder.isEmpty) return title;
  final raw = title.trim();
  if (raw.isEmpty) return folder;
  final stem = _fileStem(fileName);
  if (raw == fileName || raw == stem) return folder;
  if (gameDisplayTitle(raw, fileName) == gameDisplayTitle('', fileName)) {
    return folder;
  }
  return title;
}

final RegExp _trailingGroup = RegExp(r'\s*(?:\([^)]*\)|\[[^\]]*\])\s*$');
final RegExp _trailingArticle = RegExp(
  r'^(.*),\s*(The|A|An)$',
  caseSensitive: false,
);

String _stripTrailingGroups(String value) {
  var result = value.trim();
  while (true) {
    final next = result.replaceFirst(_trailingGroup, '').trimRight();
    if (next == result) return result.trim();
    result = next;
  }
}

String _promoteLeadingArticle(String value) {
  final match = _trailingArticle.firstMatch(value.trim());
  if (match == null) return value;
  final name = match.group(1)!.trim();
  final article = match.group(2)!;
  if (name.isEmpty) return value;
  final titled = article[0].toUpperCase() + article.substring(1).toLowerCase();
  return '$titled $name';
}

/// A stable, pleasant fallback color for poster/backdrop placeholders when no thumbnail
/// resolves. Derived from [seed] so a given game keeps the same color across sessions.
Color gameFallbackColor(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor();
}
