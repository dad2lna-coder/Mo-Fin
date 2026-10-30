import 'package:flutter/material.dart';
import '../plugin_service.dart';
import 'plugin_host_strings.dart';
import 'plugin_web_view_screen.dart';

/// Settings UI screen for managing client web plugins from the server.
class PluginSettingsScreen extends StatefulWidget {
  final PluginService pluginService;
  final ValueChanged<bool> onTogglePluginsEnabled;
  final dynamic webViewEnvironment;
  final PluginHostStrings strings;

  const PluginSettingsScreen({
    super.key,
    required this.pluginService,
    required this.onTogglePluginsEnabled,
    this.webViewEnvironment,
    this.strings = const PluginHostStrings(),
  });

  @override
  State<PluginSettingsScreen> createState() => _PluginSettingsScreenState();
}

class _PluginSettingsScreenState extends State<PluginSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pluginService.registry,
      builder: (context, _) {
        final registry = widget.pluginService.registry;
        final isEnabled = widget.pluginService.pluginsEnabled;
        final pluginsMap = registry.plugins;
        final urlStatusMap = registry.urlStatus;

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.strings.pluginsTitle),
            actions: [
              if (isEnabled)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: widget.strings.reloadPlugins,
                  onPressed: () {
                    widget.pluginService.reloadPlugins();
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              SwitchListTile(
                title: Text(widget.strings.enablePluginHost),
                subtitle: Text(widget.strings.enablePluginHostDescription),
                value: isEnabled,
                onChanged: (val) {
                  widget.onTogglePluginsEnabled(val);
                  widget.pluginService.setPluginsEnabled(val);
                },
              ),
              const Divider(),
              if (isEnabled) ...[
                Text(
                  widget.strings.serverPluginsCount(pluginsMap.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (pluginsMap.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      widget.strings.noPluginsActive,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: pluginsMap.values.map((manifest) {
                        final pluginEnabled =
                            registry.isPluginEnabled(manifest.id);
                        final rawStatus =
                            urlStatusMap[manifest.id] ?? 'Active';
                        final statusDisplay = rawStatus == 'Active'
                            ? widget.strings.statusActive
                            : rawStatus;
                        return ListTile(
                          title: Text(manifest.name),
                          subtitle: Text(
                            widget.strings.pluginSubtitleDetails(
                              manifest.id,
                              manifest.version,
                              statusDisplay,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pluginEnabled)
                                IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  tooltip: widget.strings.openPlugin,
                                  onPressed: () {
                                    final hostApi = widget.pluginService
                                        .createHostApiHandler(manifest.id);
                                    final rawEntry =
                                        manifest.clientEntryUrl ?? 'client.html';
                                    final resolvedEntry =
                                        hostApi.resolvePluginFileUrl(rawEntry);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PluginWebViewScreen(
                                          title: manifest.name,
                                          pluginId: manifest.id,
                                          pluginService: widget.pluginService,
                                          entryUrl: resolvedEntry,
                                          webViewEnvironment:
                                              widget.webViewEnvironment,
                                          strings: widget.strings,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              Switch(
                                value: pluginEnabled,
                                onChanged: (val) {
                                  registry.setPluginEnabled(manifest.id, val);
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
