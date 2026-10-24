import 'mofin_report.dart';

/// A direct IPTV account. Dispatcharr is the first kind; a raw M3U uses the
/// same shape so another proxy can be added without a new playback path.
/// Pluto builds its lineup from an XMLTV guide instead of an M3U.
enum DirectIptvKind { dispatcharr, m3u, pluto }

class DirectIptvSource {
  final String id;
  final String name;
  final DirectIptvKind kind;
  final String baseUrl;
  final String username;
  final String password;
  final String token;

  /// Empty means "the base URL is the playlist" for a raw M3U, and the
  /// Dispatcharr default otherwise.
  final String m3uPath;
  final String epgPath;
  final int refreshMinutes;
  final String preferredSubtitleLanguage;
  final String preferredAudioLanguage;
  final bool captionsOnByDefault;
  final bool enabled;

  const DirectIptvSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.username = '',
    this.password = '',
    this.token = '',
    this.m3uPath = '',
    this.epgPath = '',
    this.refreshMinutes = 30,
    this.preferredSubtitleLanguage = '',
    this.preferredAudioLanguage = '',
    this.captionsOnByDefault = true,
    this.enabled = true,
  });

  static const dispatcharrM3uPath = '/output/m3u/';
  static const dispatcharrEpgPath = '/output/epg/';

  String get effectiveM3uPath {
    if (kind == DirectIptvKind.pluto) return '';
    final path = m3uPath.trim();
    if (path.isNotEmpty) return path;
    return kind == DirectIptvKind.dispatcharr ? dispatcharrM3uPath : '';
  }

  String get effectiveEpgPath {
    final path = epgPath.trim();
    if (path == '-' || path.toLowerCase() == 'none') return '';
    if (path.isNotEmpty) return path;
    return kind == DirectIptvKind.dispatcharr ? dispatcharrEpgPath : '';
  }

  /// A Pluto source with a blank guide path plays the XML at [baseUrl].
  /// `-` still means there is no guide.
  bool get usesBaseAsGuide {
    if (kind != DirectIptvKind.pluto) return false;
    final path = epgPath.trim();
    if (path == '-' || path.toLowerCase() == 'none') return false;
    return path.isEmpty;
  }

  Duration get refreshInterval =>
      Duration(minutes: refreshMinutes < 1 ? 30 : refreshMinutes);

  DirectIptvSource copyWith({
    String? name,
    DirectIptvKind? kind,
    String? baseUrl,
    String? username,
    String? password,
    String? token,
    String? m3uPath,
    String? epgPath,
    int? refreshMinutes,
    String? preferredSubtitleLanguage,
    String? preferredAudioLanguage,
    bool? captionsOnByDefault,
    bool? enabled,
  }) {
    return DirectIptvSource(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      token: token ?? this.token,
      m3uPath: m3uPath ?? this.m3uPath,
      epgPath: epgPath ?? this.epgPath,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      preferredSubtitleLanguage:
          preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      preferredAudioLanguage:
          preferredAudioLanguage ?? this.preferredAudioLanguage,
      captionsOnByDefault: captionsOnByDefault ?? this.captionsOnByDefault,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    'token': token,
    'm3uPath': m3uPath,
    'epgPath': epgPath,
    'refreshMinutes': refreshMinutes,
    'preferredSubtitleLanguage': preferredSubtitleLanguage,
    'preferredAudioLanguage': preferredAudioLanguage,
    'captionsOnByDefault': captionsOnByDefault,
    'enabled': enabled,
  };

  factory DirectIptvSource.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString();
    return DirectIptvSource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Dispatcharr',
      kind: DirectIptvKind.values.firstWhere(
        (kind) => kind.name == kindName,
        orElse: () => DirectIptvKind.dispatcharr,
      ),
      baseUrl: json['baseUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      m3uPath: json['m3uPath']?.toString() ?? '',
      epgPath: json['epgPath']?.toString() ?? '',
      refreshMinutes: _asInt(json['refreshMinutes']) ?? 30,
      preferredSubtitleLanguage:
          json['preferredSubtitleLanguage']?.toString() ?? '',
      preferredAudioLanguage: json['preferredAudioLanguage']?.toString() ?? '',
      captionsOnByDefault: json['captionsOnByDefault'] != false,
      enabled: json['enabled'] != false,
    );
  }
}

class DirectSubtitle {
  final String url;
  final String title;
  final String? language;
  final String codec;

  const DirectSubtitle({
    required this.url,
    this.title = 'Captions',
    this.language,
    this.codec = 'vtt',
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    if (language != null) 'language': language,
    'codec': codec,
  };

  factory DirectSubtitle.fromJson(Map<String, dynamic> json) => DirectSubtitle(
    url: json['url']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Captions',
    language: json['language']?.toString(),
    codec: json['codec']?.toString() ?? 'vtt',
  );
}

class DirectChannel {
  final String id;
  final String sourceId;
  final String name;
  final String? number;
  final String? tvgId;
  final String? logoUrl;
  final String? group;
  final String streamUrl;
  final List<DirectSubtitle> subtitles;

  /// `tvg-resolution` when it is one of 2160p, 1080p, 720p, 480p, or SD.
  final String? resolution;

  /// Last Mo Fin report for this channel, from `x-mofin-working` or a tap.
  final bool? mofinWorking;

  /// `x-mofin-checked`, `YYYY-MM-DD`, when the playlist or a tap provided one.
  final String? mofinChecked;

  /// `x-mofin-stack`. Kept in memory for the guide badge. Not written into
  /// the lineup snapshot.
  final int? stackSize;

  /// `x-mofin-members`. Same rule as [stackSize]: not catalog storage.
  final List<String> stackMembers;

  /// `x-mofin-rec-url`. Recording still posts [tvgId]; the server chooses
  /// the source. Not catalog storage.
  final String? mofinRecUrl;

  const DirectChannel({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.streamUrl,
    this.number,
    this.tvgId,
    this.logoUrl,
    this.group,
    this.subtitles = const [],
    this.resolution,
    this.mofinWorking,
    this.mofinChecked,
    this.stackSize,
    this.stackMembers = const [],
    this.mofinRecUrl,
  });

  DirectChannel withMofinReport({
    required bool working,
    required String checked,
  }) {
    return DirectChannel(
      id: id,
      sourceId: sourceId,
      name: name,
      streamUrl: streamUrl,
      number: number,
      tvgId: tvgId,
      logoUrl: logoUrl,
      group: group,
      subtitles: subtitles,
      resolution: resolution,
      mofinWorking: working,
      mofinChecked: checked,
      stackSize: stackSize,
      stackMembers: stackMembers,
      mofinRecUrl: mofinRecUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'streamUrl': streamUrl,
    if (number != null) 'number': number,
    if (tvgId != null) 'tvgId': tvgId,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (group != null) 'group': group,
    'subtitles': subtitles.map((track) => track.toJson()).toList(),
    if (resolution != null) 'resolution': resolution,
    if (mofinWorking != null) 'mofinWorking': mofinWorking,
    if (mofinChecked != null) 'mofinChecked': mofinChecked,
  };

  factory DirectChannel.fromJson(Map<String, dynamic> json) => DirectChannel(
    id: json['id']?.toString() ?? '',
    sourceId: json['sourceId']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    streamUrl: json['streamUrl']?.toString() ?? '',
    number: json['number']?.toString(),
    tvgId: json['tvgId']?.toString(),
    logoUrl: json['logoUrl']?.toString(),
    group: json['group']?.toString(),
    subtitles: (json['subtitles'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => DirectSubtitle.fromJson(Map<String, dynamic>.from(entry)),
        )
        .where((track) => track.url.isNotEmpty)
        .toList(),
    resolution: normalizeTvgResolution(json['resolution']?.toString()),
    mofinWorking: json['mofinWorking'] is bool
        ? json['mofinWorking'] as bool
        : parseMofinWorking(json['mofinWorking']?.toString()),
    mofinChecked: normalizeMofinChecked(json['mofinChecked']?.toString()),
  );
}

class DirectProgram {
  final String id;
  final String channelKey;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? overview;
  final String? episodeTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final List<String> categories;

  const DirectProgram({
    required this.id,
    required this.channelKey,
    required this.title,
    required this.start,
    required this.end,
    this.overview,
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.categories = const [],
  });

  bool airsAt(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelKey': channelKey,
    'title': title,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    if (overview != null) 'overview': overview,
    if (episodeTitle != null) 'episodeTitle': episodeTitle,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
    'categories': categories,
  };

  factory DirectProgram.fromJson(Map<String, dynamic> json) {
    return DirectProgram(
      id: json['id']?.toString() ?? '',
      channelKey: json['channelKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      start: DateTime.parse(json['start'].toString()).toLocal(),
      end: DateTime.parse(json['end'].toString()).toLocal(),
      overview: json['overview']?.toString(),
      episodeTitle: json['episodeTitle']?.toString(),
      seasonNumber: _asInt(json['seasonNumber']),
      episodeNumber: _asInt(json['episodeNumber']),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(),
    );
  }
}

class DirectIptvSnapshot {
  final String sourceId;
  final DateTime fetchedAt;
  final List<DirectChannel> channels;
  final List<DirectProgram> programs;

  const DirectIptvSnapshot({
    required this.sourceId,
    required this.fetchedAt,
    required this.channels,
    required this.programs,
  });

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'channels': channels.map((channel) => channel.toJson()).toList(),
    'programs': programs.map((program) => program.toJson()).toList(),
  };

  factory DirectIptvSnapshot.fromJson(Map<String, dynamic> json) {
    return DirectIptvSnapshot(
      sourceId: json['sourceId']?.toString() ?? '',
      fetchedAt: DateTime.parse(json['fetchedAt'].toString()).toLocal(),
      channels: (json['channels'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (entry) => DirectChannel.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
      programs: (json['programs'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (entry) => DirectProgram.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
    );
  }
}

class DirectIptvException implements Exception {
  final String message;

  const DirectIptvException(this.message);

  @override
  String toString() => message;
}

/// 403 or 429. Automatic refresh waits out the source interval. A manual
/// refresh may try once.
class DirectIptvRejected extends DirectIptvException {
  final int statusCode;

  const DirectIptvRejected(this.statusCode, String message) : super(message);
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
