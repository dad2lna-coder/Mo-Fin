/// Data model for dynamic plugin home rows.
class PluginHomeRow {
  final String id;
  final String pluginId;
  final String title;
  final List<PluginMediaItem> items;

  const PluginHomeRow({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.items,
  });

  factory PluginHomeRow.fromJson(Map<String, dynamic> json, String pluginId) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PluginHomeRow(
      id: json['id'] as String? ?? 'row-${DateTime.now().millisecondsSinceEpoch}',
      pluginId: pluginId,
      title: json['title'] as String? ?? 'Plugin Row',
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((i) => PluginMediaItem.fromJson(i))
          .toList(),
    );
  }
}

/// Dynamic item within a plugin home row.
class PluginMediaItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? jellyfinItemId;
  final String? streamUrl;
  final String? actionUrl;

  const PluginMediaItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.jellyfinItemId,
    this.streamUrl,
    this.actionUrl,
  });

  factory PluginMediaItem.fromJson(Map<String, dynamic> json) {
    return PluginMediaItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
      jellyfinItemId: json['jellyfinItemId'] as String?,
      streamUrl: json['streamUrl'] as String?,
      actionUrl: json['actionUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (jellyfinItemId != null) 'jellyfinItemId': jellyfinItemId,
      if (streamUrl != null) 'streamUrl': streamUrl,
      if (actionUrl != null) 'actionUrl': actionUrl,
    };
  }
}

/// Data model for registered plugin settings entries.
class PluginSettingsEntry {
  final String id;
  final String pluginId;
  final String title;
  final String url;

  const PluginSettingsEntry({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.url,
  });

  factory PluginSettingsEntry.fromJson(Map<String, dynamic> json, String pluginId) {
    return PluginSettingsEntry(
      id: json['id'] as String? ?? 'setting-${DateTime.now().millisecondsSinceEpoch}',
      pluginId: pluginId,
      title: json['title'] as String? ?? 'Plugin Settings',
      url: json['url'] as String? ?? '',
    );
  }
}

/// Data model for registered plugin navigation menu items.
class PluginNavItem {
  final String id;
  final String pluginId;
  final String title;
  final String icon;
  final String url;

  const PluginNavItem({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.icon,
    required this.url,
  });

  factory PluginNavItem.fromJson(Map<String, dynamic> json, String pluginId) {
    return PluginNavItem(
      id: json['id'] as String? ?? 'nav-${DateTime.now().millisecondsSinceEpoch}',
      pluginId: pluginId,
      title: json['title'] as String? ?? 'Plugin',
      icon: json['icon'] as String? ?? 'extension',
      url: json['url'] as String? ?? '',
    );
  }
}
