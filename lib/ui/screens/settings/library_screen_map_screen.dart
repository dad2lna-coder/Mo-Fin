import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/aggregated_library.dart';
import '../../../data/repositories/user_views_repository.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/game_library.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/dpad_focus_marker.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';

/// Which MoFin screen a My Media library opens. Automatic follows the
/// collection type and the known Live TV / ROM names. An override is stored
/// on this device only.
class LibraryScreenMapScreen extends StatefulWidget {
  const LibraryScreenMapScreen({super.key});

  @override
  State<LibraryScreenMapScreen> createState() => _LibraryScreenMapScreenState();
}

class _LibraryScreenMapScreenState extends State<LibraryScreenMapScreen> {
  List<AggregatedLibrary>? _libraries;
  Map<String, String> _overrides = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _overrides = readStoredLibraryScreenOverrides();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!GetIt.instance.isRegistered<UserViewsRepository>()) {
      if (!mounted) return;
      setState(() => _error = 'Sign in to choose library screens');
      return;
    }
    try {
      final libraries = await GetIt.instance<UserViewsRepository>()
          .getUserViews();
      if (!mounted) return;
      setState(() {
        _libraries = libraries;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load libraries');
    }
  }

  Future<void> _pick(AggregatedLibrary library) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(library.name),
        children: [
          for (final option in _choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.value),
              child: Text(
                _overrides[library.id] == option.stored ||
                        (_overrides[library.id] == null && option.stored == null)
                    ? '${option.label}  •'
                    : option.label,
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final next = Map<String, String>.of(_overrides);
    if (chosen.isEmpty) {
      next.remove(library.id);
    } else {
      next[library.id] = chosen;
    }
    if (!GetIt.instance.isRegistered<UserPreferences>()) return;
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.libraryScreenMap,
      encodeLibraryScreenMap(next),
    );
    if (!mounted) return;
    setState(() => _overrides = next);
  }

  String _label(AggregatedLibrary library) {
    final forced = _overrides[library.id];
    if (forced == libraryScreenDirect) return 'Direct IPTV';
    if (forced == libraryScreenGames) return 'ROM Manager';
    if (forced == libraryScreenBrowse) return 'Library';
    return 'Automatic · ${_automatic(library)}';
  }

  String _automatic(AggregatedLibrary library) {
    final route = libraryRoute(
      library.id,
      library.collectionType,
      library.name,
      screenOverrides: const {},
    );
    if (route == Destinations.directIptv) return 'Direct IPTV';
    if (route == Destinations.games || route.startsWith('/games/')) {
      return 'ROM Manager';
    }
    return 'Library';
  }

  @override
  Widget build(BuildContext context) {
    final libraries = _libraries;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, const Text('Library screens')),
        body: libraries == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
              )
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Choose what a My Media tile opens. Live TV and Retro Games '
                      'are picked automatically. The side menu is unchanged.',
                    ),
                  ),
                  if (libraries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No libraries'),
                    ),
                  for (final library in libraries)
                    DpadFocusMarker(
                      child: ListTile(
                        title: Text(library.name),
                        subtitle: Text(_label(library)),
                        onTap: () => unawaited(_pick(library)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

const _choices = <({String? stored, String value, String label})>[
  (stored: null, value: '', label: 'Automatic'),
  (stored: libraryScreenDirect, value: libraryScreenDirect, label: 'Direct IPTV'),
  (stored: libraryScreenGames, value: libraryScreenGames, label: 'ROM Manager'),
  (stored: libraryScreenBrowse, value: libraryScreenBrowse, label: 'Library'),
];
