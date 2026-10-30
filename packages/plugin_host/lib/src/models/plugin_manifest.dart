import 'dart:convert';

/// Represents plugin slots in Moonbase format.
class PluginSlots {
  final bool homeRow;
  final bool playback;
  final bool settings;
  final bool events;
  final List<String> rawList;

  const PluginSlots({
    this.homeRow = false,
    this.playback = false,
    this.settings = false,
    this.events = false,
    this.rawList = const [],
  });

  factory PluginSlots.fromJson(dynamic json) {
    if (json is List<dynamic>) {
      final list = json.map((e) => e.toString()).toList();
      return PluginSlots(
        homeRow: list.contains('homeRow'),
        playback: list.contains('playback'),
        settings: list.contains('settings') || list.contains('settingsPage'),
        events: list.contains('events'),
        rawList: list,
      );
    } else if (json is Map<String, dynamic>) {
      final homeRow = json['homeRow'] as bool? ?? false;
      final playback = json['playback'] as bool? ?? false;
      final settings =
          (json['settings'] as bool? ?? false) || (json['settingsPage'] as bool? ?? false);
      final events = json['events'] as bool? ?? false;
      final list = <String>[
        if (homeRow) 'homeRow',
        if (playback) 'playback',
        if (settings) 'settings',
        if (events) 'events',
      ];
      return PluginSlots(
        homeRow: homeRow,
        playback: playback,
        settings: settings,
        events: events,
        rawList: list,
      );
    }
    return const PluginSlots();
  }

  dynamic toJson() {
    return rawList.isNotEmpty
        ? rawList
        : [
            if (homeRow) 'homeRow',
            if (playback) 'playback',
            if (settings) 'settings',
            if (events) 'events',
          ];
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

  /// Proxy access level ("admin" | "user", default "admin").
  final String proxyAccess;

  /// Server-provided resolved client entry URL.
  final String? clientEntryUrl;

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
    this.proxyAccess = 'admin',
    this.clientEntryUrl,
    this.baseUrl,
  });

  /// Resolves the absolute URL for the plugin's client entry point.
  String get entryUrl {
    if (clientEntryUrl != null && clientEntryUrl!.isNotEmpty) {
      if (clientEntryUrl!.startsWith('http://') || clientEntryUrl!.startsWith('https://')) {
        return clientEntryUrl!;
      }
      if (baseUrl != null && baseUrl!.isNotEmpty) {
        final uri = Uri.parse(baseUrl!);
        return uri.resolve(clientEntryUrl!).toString();
      }
      return clientEntryUrl!;
    }
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
    final rawProxy = json['proxyAccess'];
    final proxyAccessStr = rawProxy is bool
        ? 'admin'
        : (rawProxy?.toString() ?? 'admin');

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
      proxyAccess: proxyAccessStr,
      clientEntryUrl: json['clientEntryUrl'] as String?,
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
      if (clientEntryUrl != null) 'clientEntryUrl': clientEntryUrl,
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
    String? proxyAccess,
    String? clientEntryUrl,
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
      clientEntryUrl: clientEntryUrl ?? this.clientEntryUrl,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}
