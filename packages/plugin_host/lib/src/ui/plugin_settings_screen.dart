import 'package:flutter/material.dart';
import '../plugin_service.dart';

/// Settings UI screen for managing client web plugins from the server.
class PluginSettingsScreen extends StatefulWidget {
  final PluginService pluginService;
  final ValueChanged<bool> onTogglePluginsEnabled;

  const PluginSettingsScreen({
    super.key,
    required this.pluginService,
    required this.onTogglePluginsEnabled,
    ValueChanged<List<String>>? onUpdatePluginUrls,
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
            title: const Text('Plugins'),
            actions: [
              if (isEnabled)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload Plugins',
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
                title: const Text('Enable Plugin Host System'),
                subtitle: const Text(
                  'Allows web-based plugins to run from the media server.',
                ),
                value: isEnabled,
                onChanged: (val) {
                  widget.onTogglePluginsEnabled(val);
                  widget.pluginService.setPluginsEnabled(val);
                },
              ),
              const Divider(),
              if (isEnabled) ...[
                Text(
                  'Server Plugins (${pluginsMap.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (pluginsMap.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'No plugins currently active on this server.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: pluginsMap.values.map((manifest) {
                        final pluginEnabled = registry.isPluginEnabled(manifest.id);
                        final status = urlStatusMap[manifest.id] ?? 'Active';
                        return SwitchListTile(
                          title: Text(manifest.name),
                          subtitle: Text(
                            'ID: ${manifest.id} | v${manifest.version} | Status: $status',
                          ),
                          value: pluginEnabled,
                          onChanged: (val) {
                            registry.setPluginEnabled(manifest.id, val);
                          },
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
