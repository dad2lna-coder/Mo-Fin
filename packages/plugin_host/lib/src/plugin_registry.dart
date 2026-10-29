import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models/plugin_manifest.dart';
import 'models/plugin_ui_models.dart';
import 'js_bridge/host_api.dart';

typedef ManifestFetcher = Future<String> Function(String url);

/// Manages active plugins, manifests, UI registrations, and plugin lifecycle.
class PluginRegistry extends ChangeNotifier {
  final dynamic prefs;

  /// Map of pluginId -> Manifest
  final Map<String, PluginManifest> _plugins = {};

  /// Map of pluginId -> Enabled boolean
  final Map<String, bool> _enabledPlugins = {};

  /// Map of plugin URL -> Loading status message or error
  final Map<String, String> _urlStatus = {};

  /// Dynamic registered UI items
  final List<PluginHomeRow> _homeRows = [];
  final List<PluginSettingsEntry> _settingsEntries = [];
  final List<PluginNavItem> _navItems = [];

  PluginRegistry({this.prefs}) {
    _loadEnabledState();
  }

  Map<String, PluginManifest> get plugins => Map.unmodifiable(_plugins);
  Map<String, bool> get enabledPlugins => Map.unmodifiable(_enabledPlugins);
  Map<String, String> get urlStatus => Map.unmodifiable(_urlStatus);

  List<PluginHomeRow> get homeRows {
    return _homeRows
        .where((r) => isPluginEnabled(r.pluginId))
        .toList();
  }

  List<PluginSettingsEntry> get settingsEntries {
    return _settingsEntries
        .where((s) => isPluginEnabled(s.pluginId))
        .toList();
  }

  List<PluginNavItem> get navItems {
    return _navItems
        .where((n) => isPluginEnabled(n.pluginId))
        .toList();
  }

  void _loadEnabledState() {
    if (prefs == null) return;
    final enabledJson = prefs!.getString('plugin_host_enabled_map');
    if (enabledJson != null && enabledJson.isNotEmpty) {
      try {
        final map = jsonDecode(enabledJson) as Map<String, dynamic>;
        map.forEach((key, val) {
          if (val is bool) {
            _enabledPlugins[key] = val;
          }
        });
      } catch (_) {}
    }
  }

  Future<void> _saveEnabledState() async {
    if (prefs == null) return;
    await prefs!.setString(
      'plugin_host_enabled_map',
      jsonEncode(_enabledPlugins),
    );
  }

  bool isPluginEnabled(String pluginId) {
    return _enabledPlugins[pluginId] ?? true;
  }

  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    _enabledPlugins[pluginId] = enabled;
    await _saveEnabledState();
    notifyListeners();
  }

  void registerHomeRow(PluginHomeRow row) {
    _homeRows.removeWhere((r) => r.id == row.id && r.pluginId == row.pluginId);
    _homeRows.add(row);
    notifyListeners();
  }

  void registerSettingsEntry(PluginSettingsEntry entry) {
    _settingsEntries.removeWhere((s) => s.id == entry.id && s.pluginId == entry.pluginId);
    _settingsEntries.add(entry);
    notifyListeners();
  }

  void registerNavItem(PluginNavItem item) {
    _navItems.removeWhere((n) => n.id == item.id && n.pluginId == item.pluginId);
    _navItems.add(item);
    notifyListeners();
  }

  /// Loads plugin manifests from a list of URLs.
  /// Skips invalid or incompatible plugins without failing app launch.
  Future<void> loadPluginsFromUrls(
    List<String> urls, {
    ManifestFetcher? fetcher,
  }) async {
    _urlStatus.clear();

    for (final rawUrl in urls) {
      final url = rawUrl.trim();
      if (url.isEmpty) continue;

      try {
        final manifestUrl = url.endsWith('plugin.json')
            ? url
            : (url.endsWith('/') ? '${url}plugin.json' : '$url/plugin.json');

        final content = fetcher != null
            ? await fetcher(manifestUrl)
            : await _defaultHttpFetch(manifestUrl);

        final manifest = PluginManifest.fromRawJson(
          content,
          baseUrl: manifestUrl,
        );

        if (manifest.id.isEmpty) {
          _urlStatus[url] = 'Error: Manifest missing plugin id';
          continue;
        }

        if (manifest.minHostApi > HostApiHandler.currentHostApiVersion) {
          _urlStatus[url] =
              'Incompatible: Requires hostApi >= ${manifest.minHostApi} (current: ${HostApiHandler.currentHostApiVersion})';
          continue;
        }

        _plugins[manifest.id] = manifest;
        if (!_enabledPlugins.containsKey(manifest.id)) {
          _enabledPlugins[manifest.id] = true;
        }
        _urlStatus[url] = 'Loaded: ${manifest.name} (v${manifest.version})';
      } catch (e) {
        _urlStatus[url] = 'Failed: ${e.toString()}';
      }
    }

    notifyListeners();
  }

  static Future<String> _defaultHttpFetch(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP status ${response.statusCode}');
    }
    return response.body;
  }

  /// Registers a plugin manifest directly (e.g., from local asset or test).
  void registerManifest(PluginManifest manifest) {
    _plugins[manifest.id] = manifest;
    if (!_enabledPlugins.containsKey(manifest.id)) {
      _enabledPlugins[manifest.id] = true;
    }
    _urlStatus[manifest.entryUrl] = 'Loaded: ${manifest.name}';
    notifyListeners();
  }

  void clear() {
    _plugins.clear();
    _urlStatus.clear();
    _homeRows.clear();
    _settingsEntries.clear();
    _navItems.clear();
    notifyListeners();
  }
}
