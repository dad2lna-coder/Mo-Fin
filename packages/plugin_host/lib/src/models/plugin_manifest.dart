import 'dart:convert';

/// Represents plugin slots in Moonbase format.
class PluginSlots {
  final bool homeRow;
  final bool playback;
  final bool settings;
  final bool events;

  const PluginSlots({
    this.homeRow = false,
    this.playback = false,
    this.settings = false,
    this.events = false,
  });

  factory PluginSlots.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return PluginSlots(
        homeRow: json['homeRow'] as bool? ?? false,
        playback: json['playback'] as bool? ?? false,
        settings: json['settings'] as bool? ?? false,
        events: json['events'] as bool? ?? false,
      );
    } else if (json is List<dynamic>) {
      final list = json.map((e) => e.toString()).toList();
      return PluginSlots(
        homeRow: list.contains('homeRow'),
        playback: list.contains('playback'),
        settings: list.contains('settings') || list.contains('settingsPage'),
        events: list.contains('events'),
      );
    }
    return const PluginSlots();
  }

  Map<String, dynamic> toJson() {
    return {
      'homeRow': homeRow,
      'playback': playback,
      'settings': settings,
      'events': events,
    };
  }
}

/// Represents client file entry points in Moonbase format.
class PluginClientInfo {
  final String html;
  final String? js;

  const PluginClientInfo({
    required this.html,
    this.js,
  });

  factory PluginClientInfo.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return PluginClientInfo(
        html: json['html'] as String? ?? 'index.html',
        js: json['js'] as String?,
      );
    } else if (json is String) {
      return PluginClientInfo(html: json);
    }
    return const PluginClientInfo(html: 'index.html');
  }

  Map<String, dynamic> toJson() {
    return {
      'html': html,
      if (js != null) 'js': js,
    };
  }
}

/// Represents a plugin's manifest (`plugin.json`) in Moonbase format.
class PluginManifest {
  /// Unique identifier for the plugin (lowercase letters, digits, hyphens).
  final String id;

  /// Display name of the plugin.
  final String name;

  /// Plugin version string (e.g., "1.0.0").
  final String version;

  /// Optional description.
  final String? description;

  /// Features provided by this plugin.
  final List<String> provides;

  /// Required feature/plugin dependencies.
  final List<String> requires;

  /// Slot registrations (homeRow, playback, settings, events).
  final PluginSlots slots;

  /// Client entry point files.
  final PluginClientInfo client;

  /// Optional server component string or configuration.
  final String? server;

  /// Minimum Host API version required (must be 1).
  final int minHostApi;

  /// Whether the plugin uses host proxy access.
  final bool proxyAccess;

  /// Base URL where the manifest was fetched from.
  final String? baseUrl;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.provides = const [],
    this.requires = const [],
    this.slots = const PluginSlots(),
    required this.client,
    this.server,
    this.minHostApi = 1,
    this.proxyAccess = false,
    this.baseUrl,
  });

  /// Resolves the absolute URL for the plugin's client entry point.
  String get entryUrl {
    final entry = client.html;
    if (entry.startsWith('http://') || entry.startsWith('https://')) {
      return entry;
    }
    if (baseUrl == null || baseUrl!.isEmpty) {
      return entry;
    }
    final uri = Uri.parse(baseUrl!);
    return uri.resolve(entry).toString();
  }

  factory PluginManifest.fromJson(Map<String, dynamic> json, {String? baseUrl}) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Plugin',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String?,
      provides: (json['provides'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      requires: (json['requires'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      slots: PluginSlots.fromJson(json['slots']),
      client: PluginClientInfo.fromJson(json['client'] ?? json['entry'] ?? 'index.html'),
      server: json['server'] as String?,
      minHostApi: (json['minHostApi'] as num?)?.toInt() ?? 1,
      proxyAccess: json['proxyAccess'] as bool? ?? false,
      baseUrl: baseUrl,
    );
  }

  factory PluginManifest.fromRawJson(String rawJson, {String? baseUrl}) {
    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    return PluginManifest.fromJson(map, baseUrl: baseUrl);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      if (description != null) 'description': description,
      'provides': provides,
      'requires': requires,
      'slots': slots.toJson(),
      'client': client.toJson(),
      if (server != null) 'server': server,
      'minHostApi': minHostApi,
      'proxyAccess': proxyAccess,
      if (baseUrl != null) 'baseUrl': baseUrl,
    };
  }

  PluginManifest copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    List<String>? provides,
    List<String>? requires,
    PluginSlots? slots,
    PluginClientInfo? client,
    String? server,
    int? minHostApi,
    bool? proxyAccess,
    String? baseUrl,
  }) {
    return PluginManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      provides: provides ?? this.provides,
      requires: requires ?? this.requires,
      slots: slots ?? this.slots,
      client: client ?? this.client,
      server: server ?? this.server,
      minHostApi: minHostApi ?? this.minHostApi,
      proxyAccess: proxyAccess ?? this.proxyAccess,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}
