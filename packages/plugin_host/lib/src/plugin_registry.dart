import 'package:flutter/foundation.dart';
import 'models/plugin_manifest.dart';
import 'models/plugin_ui_models.dart';
import 'js_bridge/host_api.dart';

/// Manages active plugins, manifests, UI registrations, and plugin lifecycle.
class PluginRegistry extends ChangeNotifier {
  final dynamic prefs;

  /// Map of pluginId -> Manifest
  final Map<String, PluginManifest> _plugins = {};

  /// Map of pluginId -> Enabled boolean
  final Map<String, bool> _enabledPlugins = {};

  /// Map of pluginId -> Loading status message or dormant status
  final Map<String, String> _urlStatus = {};

  /// Profile slot overrides: pluginId -> profile -> slotName -> enabled
  final Map<String, Map<String, Map<String, bool>>> _profileSlotOverrides = {};

  /// Server capabilities and active ping plugins
  Map<String, dynamic> _capabilities = {};
  Map<String, dynamic> _pingPlugins = {};

  /// Active device profile ('global', 'desktop', 'mobile', 'tv')
  String _deviceProfile = 'global';

  /// Dynamic registered UI items
  final List<PluginHomeRow> _homeRows = [];
  final List<PluginSettingsEntry> _settingsEntries = [];
  final List<PluginNavItem> _navItems = [];

  PluginRegistry({this.prefs});

  Map<String, PluginManifest> get plugins => Map.unmodifiable(_plugins);
  Map<String, bool> get enabledPlugins => Map.unmodifiable(_enabledPlugins);
  Map<String, String> get urlStatus => Map.unmodifiable(_urlStatus);
  Map<String, dynamic> get capabilities => Map.unmodifiable(_capabilities);
  Map<String, dynamic> get pingPlugins => Map.unmodifiable(_pingPlugins);
  String get deviceProfile => _deviceProfile;

  List<PluginHomeRow> get homeRows {
    return _homeRows
        .where((r) => isPluginEnabled(r.pluginId) && isSlotEnabled(r.pluginId, 'homeRow'))
        .toList();
  }

  List<PluginSettingsEntry> get settingsEntries {
    return _settingsEntries
        .where((s) => isPluginEnabled(s.pluginId) && isSlotEnabled(s.pluginId, 'settings'))
        .toList();
  }

  List<PluginNavItem> get navItems {
    return _navItems
        .where((n) => isPluginEnabled(n.pluginId) && isSlotEnabled(n.pluginId, 'navItem'))
        .toList();
  }

  /// The first enabled plugin registered for the games slot, or null.
  /// Listeners are notified whenever that answer can change.
  PluginManifest? get gamesSlotPlugin {
    for (final manifest in _plugins.values) {
      if (!isPluginEnabled(manifest.id)) continue;
      if (!manifest.slots.games) continue;
      if (!isSlotEnabled(manifest.id, 'games')) continue;
      return manifest;
    }
    return null;
  }

  bool isPluginEnabled(String pluginId) {
    if (!(_enabledPlugins[pluginId] ?? true)) return false;
    final manifest = _plugins[pluginId];
    return manifest != null;
  }

  bool isSlotEnabledForProfile(String pluginId, String slotName, String profile) {
    if (!isPluginEnabled(pluginId)) return false;
    final manifest = _plugins[pluginId];
    if (manifest == null) return false;

    final override = _profileSlotOverrides[pluginId]?[profile]?[slotName];
    if (override != null) return override;

    switch (slotName) {
      case 'homeRow':
        return manifest.slots.homeRow;
      case 'settings':
      case 'settingsPage':
        return manifest.slots.settings;
      case 'playback':
        return manifest.slots.playback;
      case 'events':
        return manifest.slots.events;
      case 'games':
        return manifest.slots.games;
      default:
        return true;
    }
  }

  bool isSlotEnabled(String pluginId, String slotName) {
    return isSlotEnabledForProfile(pluginId, slotName, _deviceProfile);
  }

  void setSlotEnabledForProfile({
    required String pluginId,
    required String profile,
    required String slot,
    required bool enabled,
  }) {
    _profileSlotOverrides.putIfAbsent(pluginId, () => {})
        .putIfAbsent(profile, () => {})[slot] = enabled;
    notifyListeners();
  }

  void setCapabilities(Map<String, dynamic> caps, {Map<String, dynamic>? pingPlugins}) {
    _capabilities = Map.from(caps);
    if (pingPlugins != null) {
      _pingPlugins = Map.from(pingPlugins);
    }
    notifyListeners();
  }

  void setDeviceProfile(String profile) {
    _deviceProfile = profile;
    notifyListeners();
  }

  void registerHomeRow(PluginHomeRow row) {
    if (!isPluginEnabled(row.pluginId) || !isSlotEnabled(row.pluginId, 'homeRow')) return;
    _homeRows.removeWhere((r) => r.id == row.id && r.pluginId == row.pluginId);
    _homeRows.add(row);
    notifyListeners();
  }

  void registerSettingsEntry(PluginSettingsEntry entry) {
    if (!isPluginEnabled(entry.pluginId) || !isSlotEnabled(entry.pluginId, 'settings')) return;
    _settingsEntries.removeWhere((s) => s.id == entry.id && s.pluginId == entry.pluginId);
    _settingsEntries.add(entry);
    notifyListeners();
  }

  void registerNavItem(PluginNavItem item) {
    if (!isPluginEnabled(item.pluginId)) return;
    _navItems.removeWhere((n) => n.id == item.id && n.pluginId == item.pluginId);
    _navItems.add(item);
    notifyListeners();
  }

  /// Process plugin payload returned from GET /Moonfin/Plugins
  void loadPluginsFromResponse(
    Map<String, dynamic> response, {
    String? baseUrl,
    String? deviceProfile,
  }) {
    _plugins.clear();
    _urlStatus.clear();
    _homeRows.clear();
    _settingsEntries.clear();
    _navItems.clear();

    if (deviceProfile != null) {
      _deviceProfile = deviceProfile;
    }

    if (response['capabilities'] is Map<String, dynamic>) {
      _capabilities = Map<String, dynamic>.from(response['capabilities'] as Map);
    }

    final rawPlugins = response['plugins'] as List<dynamic>? ?? [];
    for (final item in rawPlugins) {
      if (item is! Map<String, dynamic>) continue;

      final manifest = PluginManifest.fromJson(item, baseUrl: baseUrl);
      final id = manifest.id;
      if (id.isEmpty) continue;

      final enabled = item['enabled'] as bool? ?? true;
      final active = item['active'] as bool? ?? true;
      final dormantReason = item['dormantReason'] as String?;

      if (!enabled) {
        _urlStatus[id] = 'Disabled';
        continue;
      }

      if (!active) {
        final reason = dormantReason ?? 'Dormant';
        _urlStatus[id] = 'Dormant: $reason';
        continue;
      }

      if (manifest.minHostApi > HostApiHandler.currentHostApiVersion) {
        _urlStatus[id] =
            'Incompatible: Requires hostApi >= ${manifest.minHostApi} (current: ${HostApiHandler.currentHostApiVersion})';
        continue;
      }

      _plugins[id] = manifest;
      _enabledPlugins[id] = true;
      _urlStatus[id] = 'Loaded: ${manifest.name} (v${manifest.version})';
    }

    notifyListeners();
  }

  /// Registers a plugin manifest directly (e.g. tests or local mock).
  void registerManifest(PluginManifest manifest) {
    _plugins[manifest.id] = manifest;
    _enabledPlugins[manifest.id] = true;
    _urlStatus[manifest.id] = 'Loaded: ${manifest.name}';
    notifyListeners();
  }

  void setPluginEnabled(String pluginId, bool enabled) {
    _enabledPlugins[pluginId] = enabled;
    notifyListeners();
  }

  void clear() {
    _plugins.clear();
    _urlStatus.clear();
    _homeRows.clear();
    _settingsEntries.clear();
    _navItems.clear();
    _capabilities.clear();
    _pingPlugins.clear();
    _profileSlotOverrides.clear();
    notifyListeners();
  }
}
