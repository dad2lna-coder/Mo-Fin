import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'game_storage.dart';

/// Manages local favorites and recently played games stored under the durable
/// games directory. Keyed by "$libraryId:$gameId".
class GameLocalData {
  GameLocalData._();

  static final GameLocalData instance = GameLocalData._();

  static const int maxRecents = 50;
  static const String _fileName = 'userdata.json';

  final Set<String> _favorites = <String>{};
  final List<String> _recents = <String>[];
  bool _loaded = false;
  Completer<void>? _loadCompleter;

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static String itemKey(String libraryId, String gameId) =>
      '$libraryId:$gameId';

  Future<File> _getFile() async {
    final systemDir = await GameStorage.systemDir();
    // System dir is `<durableRoot>/games/system`. Parent is `<durableRoot>/games`.
    final gamesDir = systemDir.parent;
    return File('${gamesDir.path}/$_fileName');
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    final completer = Completer<void>();
    _loadCompleter = completer;

    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          if (data['favorites'] is List) {
            _favorites.clear();
            for (final f in data['favorites'] as List) {
              if (f is String) _favorites.add(f);
            }
          }
          if (data['recents'] is List) {
            _recents.clear();
            for (final r in data['recents'] as List) {
              if (r is String) _recents.add(r);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[GameLocalData] Error loading userdata: $e');
    } finally {
      _loaded = true;
      completer.complete();
      _loadCompleter = null;
    }
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final data = {
        'favorites': _favorites.toList(),
        'recents': _recents,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[GameLocalData] Error saving userdata: $e');
    }
  }

  bool isFavorite(String libraryId, String gameId) {
    return _favorites.contains(itemKey(libraryId, gameId));
  }

  Future<bool> toggleFavorite(String libraryId, String gameId) async {
    await ensureLoaded();
    final key = itemKey(libraryId, gameId);
    final isFav = _favorites.contains(key);
    if (isFav) {
      _favorites.remove(key);
    } else {
      _favorites.add(key);
    }
    await _save();
    changeNotifier.value++;
    return !isFav;
  }

  List<String> getRecents() {
    return List<String>.unmodifiable(_recents);
  }

  int? recentIndex(String libraryId, String gameId) {
    final idx = _recents.indexOf(itemKey(libraryId, gameId));
    return idx >= 0 ? idx : null;
  }

  Future<void> recordRecent(String libraryId, String gameId) async {
    await ensureLoaded();
    final key = itemKey(libraryId, gameId);
    _recents.remove(key);
    _recents.insert(0, key);
    if (_recents.length > maxRecents) {
      _recents.removeRange(maxRecents, _recents.length);
    }
    await _save();
    changeNotifier.value++;
  }

  @visibleForTesting
  void resetForTest({Set<String>? favorites, List<String>? recents}) {
    _favorites.clear();
    if (favorites != null) _favorites.addAll(favorites);
    _recents.clear();
    if (recents != null) _recents.addAll(recents);
    _loaded = true;
    _loadCompleter = null;
    changeNotifier.value++;
  }
}
