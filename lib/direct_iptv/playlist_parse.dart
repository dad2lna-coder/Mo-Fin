import 'dart:convert';

import 'models.dart';

/// Reads an M3U playlist. Attribute names are matched without case, and the
/// channel name is the text after the comma that is not inside quotes.
List<ParsedM3uChannel> parseM3u(String body) {
  final text = body.startsWith('\uFEFF') ? body.substring(1) : body;
  final lines = text.split(RegExp(r'\r\n|\n|\r'));
  final channels = <ParsedM3uChannel>[];
  Map<String, String>? attributes;
  String? name;
  final pendingSubtitles = <DirectSubtitle>[];

  void reset() {
    attributes = null;
    name = null;
    pendingSubtitles.clear();
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      reset();
      final payload = line.substring('#EXTINF:'.length);
      final comma = _commaOutsideQuotes(payload);
      final header = comma < 0 ? payload : payload.substring(0, comma);
      name = comma < 0 ? '' : payload.substring(comma + 1).trim();
      attributes = _attributes(header);
      final parsedAttributes = attributes!;
      final titled = parsedAttributes['tvg-name'];
      if ((name == null || name!.isEmpty) && titled != null) name = titled;
      pendingSubtitles.addAll(_subtitlesFromAttributes(parsedAttributes));
      continue;
    }
    if (line.startsWith('#EXTVLCOPT:')) {
      final option = line.substring('#EXTVLCOPT:'.length);
      final separator = option.indexOf('=');
      if (separator > 0 &&
          option.substring(0, separator).trim().toLowerCase() == 'sub-file') {
        final url = option.substring(separator + 1).trim();
        if (url.isNotEmpty) {
          pendingSubtitles.add(
            DirectSubtitle(url: url, title: 'Captions', codec: codecForUrl(url)),
          );
        }
      }
      continue;
    }
    if (line.toUpperCase().startsWith('#EXTSUB:')) {
      final url = line.substring('#EXTSUB:'.length).trim();
      if (url.isNotEmpty) {
        pendingSubtitles.add(
          DirectSubtitle(url: url, title: 'Captions', codec: codecForUrl(url)),
        );
      }
      continue;
    }
    if (line.startsWith('#')) continue;
    final parsedAttributes = attributes;
    if (parsedAttributes == null) continue;
    channels.add(
      ParsedM3uChannel(
        name: (name == null || name!.isEmpty) ? line : name!,
        streamUrl: line,
        tvgId: _blankToNull(parsedAttributes['tvg-id']),
        tvgName: _blankToNull(parsedAttributes['tvg-name']),
        logoUrl: _blankToNull(parsedAttributes['tvg-logo']),
        number: _blankToNull(
          parsedAttributes['tvg-chno'] ?? parsedAttributes['tvg-ch'],
        ),
        group: _blankToNull(parsedAttributes['group-title']),
        subtitles: List<DirectSubtitle>.of(pendingSubtitles),
      ),
    );
    reset();
  }
  return channels;
}

class ParsedM3uChannel {
  final String name;
  final String streamUrl;
  final String? tvgId;
  final String? tvgName;
  final String? logoUrl;
  final String? number;
  final String? group;
  final List<DirectSubtitle> subtitles;

  const ParsedM3uChannel({
    required this.name,
    required this.streamUrl,
    this.tvgId,
    this.tvgName,
    this.logoUrl,
    this.number,
    this.group,
    this.subtitles = const [],
  });
}

/// XMLTV. Programmes are matched to channels by the `channel` attribute,
/// which Dispatcharr copies from `tvg-id`. Every programme is returned.
/// A windowed read goes through [XmltvScan] so a large guide is not kept
/// as one string.
List<ParsedXmltvProgramme> parseXmltv(String body) {
  final scan = XmltvScan();
  const size = 4096;
  for (var i = 0; i < body.length; i += size) {
    final end = i + size < body.length ? i + size : body.length;
    scan.add(body.substring(i, end));
  }
  scan.close();
  return scan.programmes;
}

class ParsedXmltvProgramme {
  final String channelId;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? overview;
  final String? episodeTitle;
  final List<String> categories;

  const ParsedXmltvProgramme({
    required this.channelId,
    required this.title,
    required this.start,
    required this.end,
    this.overview,
    this.episodeTitle,
    this.categories = const [],
  });
}

class ParsedXmltvChannel {
  final String id;
  final String name;
  final String? iconUrl;

  const ParsedXmltvChannel({
    required this.id,
    required this.name,
    this.iconUrl,
  });
}

/// How far either side of "now" a streamed guide keeps. The full file is
/// never stored.
const xmltvWindowPast = Duration(hours: 6);
const xmltvWindowFuture = Duration(hours: 12);

/// Incremental XMLTV reader. Complete `<channel>` and `<programme>` elements
/// are taken as they arrive. One element is capped so a broken file cannot
/// grow without bound. [now] null keeps every programme; a value keeps those
/// that overlap the window around it.
class XmltvScan {
  XmltvScan({this.now, this.maxElementBytes = 2 * 1024 * 1024});

  final DateTime? now;
  final int maxElementBytes;
  final channels = <ParsedXmltvChannel>[];
  final programmes = <ParsedXmltvProgramme>[];

  final StringBuffer _pending = StringBuffer();
  final StringBuffer _skip = StringBuffer();
  bool _skipping = false;
  String _skipClose = '';
  bool _strippedBom = false;

  void add(String chunk) {
    var text = chunk;
    if (!_strippedBom) {
      _strippedBom = true;
      if (text.startsWith('\uFEFF')) text = text.substring(1);
    }
    if (_skipping) {
      _skip.write(text);
      final buffered = _skip.toString();
      final end = buffered.toLowerCase().indexOf(_skipClose);
      if (end < 0) {
        if (buffered.length > _skipClose.length) {
          _skip
            ..clear()
            ..write(buffered.substring(buffered.length - _skipClose.length + 1));
        }
        return;
      }
      _skipping = false;
      final rest = buffered.substring(end + _skipClose.length);
      _skip.clear();
      _pending.write(rest);
    } else {
      _pending.write(text);
    }
    _drain();
  }

  void close() {
    _pending.clear();
    _skip.clear();
  }

  void _drain() {
    var text = _pending.toString();
    while (true) {
      final lower = text.toLowerCase();
      final channelAt = lower.indexOf('<channel');
      final programmeAt = lower.indexOf('<programme');
      if (channelAt < 0 && programmeAt < 0) {
        if (text.length > 64) text = text.substring(text.length - 64);
        break;
      }
      final start = channelAt < 0
          ? programmeAt
          : programmeAt < 0
          ? channelAt
          : (channelAt < programmeAt ? channelAt : programmeAt);
      if (start > 0) text = text.substring(start);
      final isChannel = text.toLowerCase().startsWith('<channel');
      final close = isChannel ? '</channel>' : '</programme>';
      final end = text.toLowerCase().indexOf(close);
      if (end < 0) {
        if (text.length > maxElementBytes) {
          _skipping = true;
          _skipClose = close;
          final tail = close.length - 1;
          _skip
            ..clear()
            ..write(text.substring(text.length - tail));
          text = '';
        }
        break;
      }
      final element = text.substring(0, end + close.length);
      _consume(element, isChannel);
      text = text.substring(end + close.length);
    }
    _pending
      ..clear()
      ..write(text);
  }

  void _consume(String element, bool isChannel) {
    final openEnd = element.indexOf('>');
    if (openEnd < 0) return;
    final open = element.substring(0, openEnd);
    final close = isChannel ? '</channel>' : '</programme>';
    final inner = element.substring(openEnd + 1, element.length - close.length);
    final attrs = _attributes(open);
    if (isChannel) {
      final id = attrs['id'];
      if (id == null || id.isEmpty) return;
      final name = _firstTag(inner, 'display-name') ?? id;
      channels.add(
        ParsedXmltvChannel(id: id, name: name, iconUrl: _iconSrc(inner)),
      );
      return;
    }
    final channel = attrs['channel'];
    final start = parseXmltvTime(attrs['start']);
    final stop = parseXmltvTime(attrs['stop']);
    if (channel == null || channel.isEmpty || start == null || stop == null) {
      return;
    }
    if (!stop.isAfter(start)) return;
    if (!_inWindow(start, stop)) return;
    final title = _firstTag(inner, 'title') ?? '';
    if (title.isEmpty) return;
    programmes.add(
      ParsedXmltvProgramme(
        channelId: channel,
        title: title,
        start: start,
        end: stop,
        overview: _firstTag(inner, 'desc'),
        episodeTitle: _firstTag(inner, 'sub-title'),
        categories: _allTags(inner, 'category'),
      ),
    );
  }

  bool _inWindow(DateTime start, DateTime end) {
    final moment = now;
    if (moment == null) return true;
    final from = moment.subtract(xmltvWindowPast);
    final to = moment.add(xmltvWindowFuture);
    return end.isAfter(from) && start.isBefore(to);
  }
}

/// `https://jmp2.uk/plu-<id>.m3u8`. A channel id that already starts with
/// `plu-` is not prefixed twice.
String plutoStreamUrl(String channelId) {
  var id = channelId.trim();
  if (id.toLowerCase().startsWith('plu-')) id = id.substring(4);
  if (id.isEmpty) id = channelId.trim();
  return 'https://jmp2.uk/plu-$id.m3u8';
}

/// `20261021120000 +0000` and the same form with a colon in the offset.
DateTime? parseXmltvTime(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-])(\d{2}):?(\d{2}))?',
  ).firstMatch(text);
  if (match == null) return DateTime.tryParse(text)?.toLocal();
  final wall = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  final sign = match.group(7);
  if (sign == null) return wall.toLocal();
  final offset = Duration(
    hours: int.parse(match.group(8)!),
    minutes: int.parse(match.group(9)!),
  );
  final instant = sign == '-' ? wall.add(offset) : wall.subtract(offset);
  return instant.toLocal();
}

/// Subtitle renditions declared on an HLS master. [master] must be the
/// playlist URL after redirects. Resolving `subtitle/en.m3u8` against the
/// pre-redirect `https://jmp2.uk/plu-<id>.m3u8` points at a 404.
List<DirectSubtitle> hlsSubtitleTracks(String playlist, Uri master) {
  final tracks = <DirectSubtitle>[];
  for (final raw in playlist.split(RegExp(r'\r\n|\n|\r'))) {
    final line = raw.trim();
    if (!line.toUpperCase().startsWith('#EXT-X-MEDIA:')) continue;
    final attrs = _attributes(line.substring('#EXT-X-MEDIA:'.length));
    if ((attrs['type'] ?? '').toUpperCase() != 'SUBTITLES') continue;
    final uri = attrs['uri'];
    if (uri == null || uri.isEmpty) continue;
    final absolute = master.resolve(uri).toString();
    final language = _blankToNull(attrs['language']);
    tracks.add(
      DirectSubtitle(
        url: absolute,
        title: _blankToNull(attrs['name']) ?? 'Captions',
        language: language,
        codec: codecForUrl(absolute),
      ),
    );
  }
  return tracks;
}

/// Joins a Dispatcharr base with a path, or returns [path] when it is already
/// absolute. An empty path means [base] itself is the document.
Uri resolveSourceUri(String base, String path) {
  final trimmedPath = path.trim();
  final trimmedBase = base.trim();
  if (trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://')) {
    return Uri.parse(trimmedPath);
  }
  if (trimmedPath.isEmpty) return Uri.parse(trimmedBase);
  final root = trimmedBase.endsWith('/') ? trimmedBase : '$trimmedBase/';
  final relative = trimmedPath.startsWith('/')
      ? trimmedPath.substring(1)
      : trimmedPath;
  return Uri.parse(root).resolve(relative);
}

String codecForUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith('.ass') || path.endsWith('.ssa')) return 'ass';
  if (path.endsWith('.srt')) return 'srt';
  if (path.endsWith('.vtt') || path.endsWith('.webvtt')) return 'vtt';
  return 'vtt';
}

bool looksLikeHls(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.m3u');
}

DirectIptvSnapshot assembleSnapshot({
  required DirectIptvSource source,
  required String m3u,
  required String? epg,
  List<ParsedXmltvProgramme>? programmes,
  List<ParsedXmltvChannel>? xmlChannels,
  required DateTime fetchedAt,
}) {
  final parsedProgrammes = programmes ??
      (epg == null || epg.trim().isEmpty
          ? const <ParsedXmltvProgramme>[]
          : parseXmltv(epg));
  if (source.kind == DirectIptvKind.pluto) {
    var guideChannels = xmlChannels;
    var guideProgrammes = parsedProgrammes;
    if ((guideChannels == null || guideChannels.isEmpty) &&
        epg != null &&
        epg.trim().isNotEmpty &&
        programmes == null) {
      final scan = XmltvScan();
      scan.add(epg);
      scan.close();
      guideChannels = scan.channels;
      guideProgrammes = scan.programmes;
    }
    return _snapshotFromXmlChannels(
      source: source,
      xmlChannels: guideChannels ?? const [],
      programmes: guideProgrammes,
      fetchedAt: fetchedAt,
    );
  }
  if (xmlChannels != null && xmlChannels.isNotEmpty && m3u.trim().isEmpty) {
    return _snapshotFromXmlChannels(
      source: source,
      xmlChannels: xmlChannels,
      programmes: parsedProgrammes,
      fetchedAt: fetchedAt,
    );
  }
  final parsed = parseM3u(m3u);
  final channels = <DirectChannel>[];
  final seen = <String>{};
  for (var i = 0; i < parsed.length; i++) {
    final entry = parsed[i];
    final tvgId = entry.tvgId;
    final baseId = 'direct:${source.id}:${tvgId ?? 'n$i'}';
    var id = baseId;
    var duplicate = 2;
    while (!seen.add(id)) {
      id = '$baseId~$duplicate';
      duplicate++;
    }
    channels.add(
      DirectChannel(
        id: id,
        sourceId: source.id,
        name: entry.name,
        streamUrl: _absoluteUrl(source, entry.streamUrl) ?? entry.streamUrl,
        number: entry.number,
        tvgId: tvgId,
        logoUrl: _absoluteUrl(source, entry.logoUrl),
        group: entry.group,
        subtitles: [
          for (final track in entry.subtitles)
            DirectSubtitle(
              url: _absoluteUrl(source, track.url) ?? track.url,
              title: track.title,
              language: track.language,
              codec: track.codec,
            ),
        ],
      ),
    );
  }

  final byTvgId = <String, String>{};
  for (final channel in channels) {
    final tvgId = channel.tvgId;
    if (tvgId != null && tvgId.isNotEmpty && !byTvgId.containsKey(tvgId)) {
      byTvgId[tvgId] = channel.id;
    }
  }

  final programs = <DirectProgram>[];
  for (final programme in parsedProgrammes) {
    final channelId = byTvgId[programme.channelId];
    if (channelId == null) continue;
    programs.add(
      DirectProgram(
        id: '$channelId|${programme.start.toUtc().toIso8601String()}',
        channelKey: channelId,
        title: programme.title,
        start: programme.start,
        end: programme.end,
        overview: programme.overview,
        episodeTitle: programme.episodeTitle,
        categories: programme.categories,
      ),
    );
  }

  return DirectIptvSnapshot(
    sourceId: source.id,
    fetchedAt: fetchedAt,
    channels: channels,
    programs: programs,
  );
}

DirectIptvSnapshot _snapshotFromXmlChannels({
  required DirectIptvSource source,
  required List<ParsedXmltvChannel> xmlChannels,
  required List<ParsedXmltvProgramme> programmes,
  required DateTime fetchedAt,
}) {
  final channels = <DirectChannel>[];
  final seen = <String>{};
  for (var i = 0; i < xmlChannels.length; i++) {
    final entry = xmlChannels[i];
    final baseId = 'direct:${source.id}:${entry.id}';
    var id = baseId;
    var duplicate = 2;
    while (!seen.add(id)) {
      id = '$baseId~$duplicate';
      duplicate++;
    }
    channels.add(
      DirectChannel(
        id: id,
        sourceId: source.id,
        name: entry.name,
        streamUrl: plutoStreamUrl(entry.id),
        tvgId: entry.id,
        logoUrl: _absoluteUrl(source, entry.iconUrl),
      ),
    );
  }
  final byTvgId = <String, String>{};
  for (final channel in channels) {
    final tvgId = channel.tvgId;
    if (tvgId != null && tvgId.isNotEmpty && !byTvgId.containsKey(tvgId)) {
      byTvgId[tvgId] = channel.id;
    }
  }
  final programs = <DirectProgram>[];
  for (final programme in programmes) {
    final channelId = byTvgId[programme.channelId];
    if (channelId == null) continue;
    programs.add(
      DirectProgram(
        id: '$channelId|${programme.start.toUtc().toIso8601String()}',
        channelKey: channelId,
        title: programme.title,
        start: programme.start,
        end: programme.end,
        overview: programme.overview,
        episodeTitle: programme.episodeTitle,
        categories: programme.categories,
      ),
    );
  }
  return DirectIptvSnapshot(
    sourceId: source.id,
    fetchedAt: fetchedAt,
    channels: channels,
    programs: programs,
  );
}

/// Arguments are plain maps and strings so a caller can run this inside an
/// isolate. The catalog does not: an XMLTV guide is streamed instead.
DirectIptvSnapshot assembleSnapshotIsolate(Map<String, dynamic> args) {
  return assembleSnapshot(
    source: DirectIptvSource.fromJson(
      Map<String, dynamic>.from(args['source'] as Map),
    ),
    m3u: args['m3u'] as String,
    epg: args['epg'] as String?,
    fetchedAt: DateTime.parse(args['fetchedAt'] as String),
  );
}

String? _absoluteUrl(DirectIptvSource source, String? url) {
  final trimmed = url?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = source.baseUrl.trim();
  if (base.isEmpty) return trimmed;
  return resolveSourceUri(base, trimmed).toString();
}

Map<String, String> authHeaders(DirectIptvSource source) {
  final headers = <String, String>{
    'User-Agent': 'Moonfin',
    'Accept': '*/*',
  };
  final token = source.token.trim();
  if (token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
    return headers;
  }
  final username = source.username.trim();
  if (username.isNotEmpty) {
    final encoded = base64Encode(utf8.encode('$username:${source.password}'));
    headers['Authorization'] = 'Basic $encoded';
  }
  return headers;
}

/// Playback headers for [streamUri]. Authorization is kept only when that
/// host is [credentialHost] or a subdomain of it. A missing host drops the
/// credential rather than sending it to whoever answers the URL.
Map<String, String> headersForPlayback({
  required Map<String, String> headers,
  required Uri streamUri,
  String? credentialHost,
}) {
  final host = credentialHost?.trim() ?? '';
  if (host.isNotEmpty && _hostMatches(streamUri.host, host)) return headers;
  final copy = <String, String>{};
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'authorization') return;
    copy[key] = value;
  });
  return copy;
}

bool _hostMatches(String host, String allowed) {
  final left = host.toLowerCase();
  final right = allowed.toLowerCase();
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.endsWith('.$right');
}

List<DirectSubtitle> _subtitlesFromAttributes(Map<String, String> attributes) {
  const keys = ['tvg-cc-url', 'tvg-subtitle', 'subtitle-url', 'sub-url'];
  final tracks = <DirectSubtitle>[];
  for (final key in keys) {
    final url = attributes[key];
    if (url == null || url.isEmpty) continue;
    final language = _blankToNull(
      attributes['tvg-cc-lang'] ?? attributes['tvg-language'],
    );
    tracks.add(
      DirectSubtitle(
        url: url,
        title: 'Captions',
        language: language,
        codec: codecForUrl(url),
      ),
    );
  }
  return tracks;
}

int _commaOutsideQuotes(String value) {
  var quoted = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '"') quoted = !quoted;
    if (char == ',' && !quoted) return i;
  }
  return -1;
}

Map<String, String> _attributes(String header) {
  final result = <String, String>{};
  final pattern = RegExp(
    r'''([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|([^",\s]+))''',
  );
  for (final match in pattern.allMatches(header)) {
    final raw = match.group(2) ?? match.group(3) ?? '';
    result[match.group(1)!.toLowerCase()] = _decodeXml(raw);
  }
  return result;
}

String? _iconSrc(String inner) {
  final match = RegExp(
    '<icon\\b([^>]*)/?>',
    caseSensitive: false,
  ).firstMatch(inner);
  if (match == null) return null;
  return _blankToNull(_attributes(match.group(1) ?? '')['src']);
}

String? _firstTag(String inner, String tag) {
  final match = RegExp(
    '<$tag\\b[^>]*>(.*?)</$tag>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(inner);
  final text = match?.group(1);
  if (text == null) return null;
  final decoded = _decodeXml(text.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
  return decoded.isEmpty ? null : decoded;
}

List<String> _allTags(String inner, String tag) {
  return RegExp(
    '<$tag\\b[^>]*>(.*?)</$tag>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(inner).map((match) {
    return _decodeXml(
      (match.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
    ).trim();
  }).where((text) => text.isNotEmpty).toList();
}

String _decodeXml(String value) {
  final amp = '&' 'amp;';
  final lt = '&' 'lt;';
  final gt = '&' 'gt;';
  final quot = '&' 'quot;';
  final apos = '&' 'apos;';
  final num = '&' '#39;';
  return value
      .replaceAll(amp, '&')
      .replaceAll(lt, '<')
      .replaceAll(gt, '>')
      .replaceAll(quot, '"')
      .replaceAll(apos, "'")
      .replaceAll(num, "'");
}

String? _blankToNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
