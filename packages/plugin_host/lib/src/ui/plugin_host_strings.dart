/// Localized strings provider for Plugin Host UI components with English defaults.
class PluginHostStrings {
  final String pluginsTitle;
  final String reloadPlugins;
  final String enablePluginHost;
  final String enablePluginHostDescription;
  final String Function(int count) serverPluginsCount;
  final String noPluginsActive;
  final String openPlugin;
  final String unsupportedOnDevice;
  final String reload;
  final String retry;
  final String hostDisabled;
  final String Function(String pluginId) pluginNotLoaded;
  final String unauthorizedEntryUrl;
  final String Function(String error) loadFailedWithError;

  const PluginHostStrings({
    this.pluginsTitle = 'Plugins',
    this.reloadPlugins = 'Reload Plugins',
    this.enablePluginHost = 'Enable Plugin Host System',
    this.enablePluginHostDescription =
        'Allows web-based plugins to run from the media server.',
    this.serverPluginsCount = _defaultServerPluginsCount,
    this.noPluginsActive = 'No plugins currently active on this server.',
    this.openPlugin = 'Open Plugin',
    this.unsupportedOnDevice = 'Plugins are not supported on this device.',
    this.reload = 'Reload',
    this.retry = 'Retry',
    this.hostDisabled = 'Plugin Host System is currently disabled.',
    this.pluginNotLoaded = _defaultPluginNotLoaded,
    this.unauthorizedEntryUrl = 'Failed to load plugin: Unauthorized entry URL.',
    this.loadFailedWithError = _defaultLoadFailedWithError,
  });

  static String _defaultServerPluginsCount(int count) =>
      'Server Plugins ($count)';
  static String _defaultPluginNotLoaded(String pluginId) =>
      'Plugin "$pluginId" is not loaded or active.';
  static String _defaultLoadFailedWithError(String error) =>
      'Failed to load plugin: $error';
}
