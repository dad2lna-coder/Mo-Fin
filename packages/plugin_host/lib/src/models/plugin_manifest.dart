import 'dart:convert';

/// Represents a plugin's manifest (`plugin.json`).
class PluginManifest {
  /// Unique identifier for the plugin (e.g., "com.example.hello").
  final String id;

  /// Display name of the plugin.
  final String name;

  /// Plugin version string (e.g., "1.0.0").
  final String version;

  /// Minimum Host API version required by this plugin (default: 1).
  final int minHostApi;

  /// Entry point HTML file or full URL (e.g., "index.html").
  final String entry;

  /// Requested permissions (e.g., ["storage", "playback", "userContext"]).
  final List<String> permissions;

  /// Registered hook points (e.g., ["homeRow", "settingsPage", "navItem", "router"]).
  final List<String> hooks;

  /// Base URL where the manifest was fetched from (used to resolve relative entry path).
  final String? baseUrl;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.minHostApi = 1,
    required this.entry,
    this.permissions = const [],
    this.hooks = const [],
    this.baseUrl,
  });

  /// Resolves the absolute URL for the plugin's entry point.
  String get entryUrl {
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
      minHostApi: (json['minHostApi'] as num?)?.toInt() ?? 1,
      entry: json['entry'] as String? ?? 'index.html',
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      hooks: (json['hooks'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
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
      'minHostApi': minHostApi,
      'entry': entry,
      'permissions': permissions,
      'hooks': hooks,
      if (baseUrl != null) 'baseUrl': baseUrl,
    };
  }

  PluginManifest copyWith({
    String? id,
    String? name,
    String? version,
    int? minHostApi,
    String? entry,
    List<String>? permissions,
    List<String>? hooks,
    String? baseUrl,
  }) {
    return PluginManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      minHostApi: minHostApi ?? this.minHostApi,
      entry: entry ?? this.entry,
      permissions: permissions ?? this.permissions,
      hooks: hooks ?? this.hooks,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}
