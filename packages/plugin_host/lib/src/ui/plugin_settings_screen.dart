import 'package:flutter/material.dart';
import '../plugin_service.dart';

/// Settings UI screen for configuring plugin URLs and toggling plugins.
class PluginSettingsScreen extends StatefulWidget {
  final PluginService pluginService;
  final ValueChanged<bool> onTogglePluginsEnabled;
  final ValueChanged<List<String>> onUpdatePluginUrls;

  const PluginSettingsScreen({
    super.key,
    required this.pluginService,
    required this.onTogglePluginsEnabled,
    required this.onUpdatePluginUrls,
  });

  @override
  State<PluginSettingsScreen> createState() => _PluginSettingsScreenState();
}

class _PluginSettingsScreenState extends State<PluginSettingsScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _showAddUrlDialog() {
    _urlController.clear();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Plugin Server URL'),
          content: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'https://your-server/plugins/hello/',
              labelText: 'Plugin URL or Manifest Path',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = _urlController.text.trim();
                if (text.isNotEmpty) {
                  final currentUrls = widget.pluginService.getPluginUrls();
                  if (!currentUrls.contains(text)) {
                    final newUrls = [...currentUrls, text];
                    widget.onUpdatePluginUrls(newUrls);
                    widget.pluginService.reloadPlugins();
                  }
                }
                Navigator.of(context).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _removeUrl(String url) {
    final currentUrls = widget.pluginService.getPluginUrls();
    final newUrls = currentUrls.where((u) => u != url).toList();
    widget.onUpdatePluginUrls(newUrls);
    widget.pluginService.reloadPlugins();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pluginService.registry,
      builder: (context, _) {
        final registry = widget.pluginService.registry;
        final isEnabled = widget.pluginService.pluginsEnabled;
        final configuredUrls = widget.pluginService.getPluginUrls();
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
                  'Allows web-based plugins to run from configured Jellyfin/server URLs.',
                ),
                value: isEnabled,
                onChanged: (val) {
                  widget.onTogglePluginsEnabled(val);
                  widget.pluginService.setPluginsEnabled(val);
                },
              ),
              const Divider(),
              if (isEnabled) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Configured Plugin URLs',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ElevatedButton.icon(
                      onPressed: _showAddUrlDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add URL'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (configuredUrls.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'No plugin URLs configured. Click "Add URL" to add a plugin hosted on your server.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: configuredUrls.map((url) {
                        final status = urlStatusMap[url] ?? urlStatusMap['$url/plugin.json'] ?? urlStatusMap['${url}plugin.json'] ?? 'Pending';
                        return ListTile(
                          title: Text(url),
                          subtitle: Text(
                            status,
                            style: TextStyle(
                              color: status.startsWith('Loaded')
                                  ? Colors.green
                                  : (status.startsWith('Failed') || status.startsWith('Incompatible') || status.startsWith('Error')
                                      ? Colors.red
                                      : Colors.orange),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _removeUrl(url),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Installed Plugins (${pluginsMap.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (pluginsMap.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'No plugins currently loaded.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: pluginsMap.values.map((manifest) {
                        final pluginEnabled = registry.isPluginEnabled(manifest.id);
                        return SwitchListTile(
                          title: Text(manifest.name),
                          subtitle: Text(
                            'ID: ${manifest.id} | v${manifest.version} | Hooks: ${manifest.hooks.join(', ')}',
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
