import 'package:flutter/foundation.dart';
import 'plugin_registry.dart';
import 'js_bridge/host_api.dart';

typedef PluginUrlsGetter = List<String> Function();

/// Main entry point for managing the MoFin Plugin Host subsystem.
class PluginService extends ChangeNotifier {
  final PluginRegistry registry;
  final dynamic prefs;
  final UserContextProvider userContextProvider;
  final OpenScreenCallback? onOpenScreen;
  final PlayMediaCallback? onPlayMedia;
  final ToastCallback? onShowToast;
  final PluginUrlsGetter getPluginUrls;

  bool _pluginsEnabled = false;

  PluginService({
    required this.registry,
    required this.prefs,
    required this.userContextProvider,
    required this.getPluginUrls,
    this.onOpenScreen,
    this.onPlayMedia,
    this.onShowToast,
    bool initialPluginsEnabled = false,
  }) : _pluginsEnabled = initialPluginsEnabled;

  bool get pluginsEnabled => _pluginsEnabled;

  void setPluginsEnabled(bool enabled) {
    if (_pluginsEnabled == enabled) return;
    _pluginsEnabled = enabled;
    if (enabled) {
      reloadPlugins();
    } else {
      registry.clear();
    }
    notifyListeners();
  }

  /// Reloads all plugin manifests from configured URLs.
  Future<void> reloadPlugins({ManifestFetcher? fetcher}) async {
    if (!_pluginsEnabled) {
      registry.clear();
      return;
    }
    final urls = getPluginUrls();
    await registry.loadPluginsFromUrls(urls, fetcher: fetcher);
    notifyListeners();
  }

  /// Creates a [HostApiHandler] instance bound to [pluginId].
  HostApiHandler createHostApiHandler(String pluginId) {
    return HostApiHandler(
      pluginId: pluginId,
      registry: registry,
      userContextProvider: userContextProvider,
      prefs: prefs,
      onOpenScreen: onOpenScreen,
      onPlayMedia: onPlayMedia,
      onShowToast: onShowToast,
    );
  }
}
