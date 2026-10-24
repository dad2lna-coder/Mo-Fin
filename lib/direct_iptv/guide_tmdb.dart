/// Title cleanup, match confidence, and the 24-hour guide cache.
///
/// No network and no Flutter. The lookup client and the widget tests sit
/// on top of this so a bad title cannot become a poster for the wrong show.
library;

class GuideQuery {
  final String title;
  final String? episodeTitle;
  final String? overview;
  final int? season;
  final int? episode;
  final int? year;

  const GuideQuery({
    required this.title,
    this.episodeTitle,
    this.overview,
    this.season,
    this.episode,
    this.year,
  });

  /// [season] and [episode] win when the guide already parsed them.
  /// Otherwise a suffix on the title (`S6E19`, `6x19`) is used.
  factory GuideQuery.resolve({
    required String title,
    String? episodeTitle,
    String? overview,
    int? season,
    int? episode,
    String? episodeNum,
  }) {
    final fromNum = parseEpisodeNum(episodeNum);
    final fromTitle = parseSeasonEpisode(title);
    final resolvedSeason = season ?? fromNum?.season ?? fromTitle?.season;
    final resolvedEpisode = episode ?? fromNum?.episode ?? fromTitle?.episode;
    return GuideQuery(
      title: title,
      episodeTitle: _blank(episodeTitle),
      overview: _blank(overview),
      season: resolvedSeason,
      episode: resolvedEpisode,
      year: extractGuideYear(title),
    );
  }

  /// What we send to TMDB: suffixes and broadcast tags removed, case kept.
  String get searchTitle => cleanGuideTitle(title);

  bool get hasEpisode => season != null && episode != null;
}

class SeasonEpisode {
  final int? season;
  final int? episode;

  const SeasonEpisode({this.season, this.episode});

  bool get known => season != null || episode != null;
}

class TmdbCandidate {
  final int id;
  final String mediaType;
  final String title;
  final int? year;

  const TmdbCandidate({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
  });
}

class GuideTmdbHit {
  final int id;
  final String mediaType;
  final String title;
  final int? year;
  final double? rating;
  final List<String> genres;
  final String overview;
  final List<String> cast;
  final String? posterUrl;
  final String? episodeName;
  final String? episodeOverview;
  final String? stillUrl;
  final int? season;
  final int? episode;

  const GuideTmdbHit({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
    this.rating,
    this.genres = const [],
    this.overview = '',
    this.cast = const [],
    this.posterUrl,
    this.episodeName,
    this.episodeOverview,
    this.stillUrl,
    this.season,
    this.episode,
  });

  /// Episode text when we have it, otherwise the show or movie overview.
  String get displayOverview {
    final episodeText = episodeOverview?.trim() ?? '';
    if (episodeText.isNotEmpty) return episodeText;
    return overview;
  }

  /// Episode still when the listing is a known episode, else the poster.
  String? get imageUrl {
    final still = stillUrl;
    if (still != null && still.isNotEmpty) return still;
    final poster = posterUrl;
    if (poster != null && poster.isEmpty) return null;
    return poster;
  }

  String get metaLine {
    final bits = <String>[
      if (year != null) '$year',
      if (rating != null && rating! > 0) rating!.toStringAsFixed(1),
      if (genres.isNotEmpty) genres.take(3).join(', '),
    ];
    return bits.join(' · ');
  }
}

/// A stored lookup, including a confident miss so the same title is not
/// fetched again for [ttl].
class GuideTmdbCache {
  GuideTmdbCache({
    DateTime Function()? now,
    this.ttl = const Duration(hours: 24),
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, _CacheSlot> _slots = {};

  int get length => _slots.length;

  /// Null when nothing is stored or the slot is older than [ttl].
  /// A stored miss is `(hit: null)` and is different from a cache miss,
  /// which is a null return.
  ({GuideTmdbHit? hit})? read(String key) {
    final slot = _slots[key];
    if (slot == null) return null;
    if (_now().difference(slot.at) >= ttl) {
      _slots.remove(key);
      return null;
    }
    return (hit: slot.hit);
  }

  void write(String key, GuideTmdbHit? hit) {
    if (key.isEmpty) return;
    _slots[key] = _CacheSlot(_now(), hit);
  }

  void clear() => _slots.clear();
}

class _CacheSlot {
  final DateTime at;
  final GuideTmdbHit? hit;

  const _CacheSlot(this.at, this.hit);
}

/// Cache identity. Same cleaned title shares one entry. A known episode
/// is its own entry so episode 2 is not served as episode 1.
String guideTmdbCacheKey(GuideQuery query) {
  final title = normalizeGuideTitle(query.title);
  if (title.isEmpty) return '';
  if (query.season == null && query.episode == null) return title;
  return '$title|${query.season ?? ''}|${query.episode ?? ''}';
}

const double guideTitleConfidentScore = 0.88;

/// Broadcast tags and episode suffixes off, punctuation folded, lowercased.
String normalizeGuideTitle(String raw) =>
    cleanGuideTitle(raw).toLowerCase();

/// Same cleanup as [normalizeGuideTitle] but the case of the show name stays
/// so the search query still looks like a title.
String cleanGuideTitle(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  text = text.replaceFirst(
    RegExp(
      r'^(?:new|live|repeat|premiere|encore)\s*:\s*',
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(
    RegExp(
      r'\((?:hd|sd|uhd|hdr|4k|2160p|1080p|720p|480p|hdtv)\)',
      caseSensitive: false,
    ),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'\b(?:hd|sd|uhd|hdr|hdtv)\b', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(
      r'\bS\d{1,2}\s*[:x.]?\s*E\d{1,3}\b',
      caseSensitive: false,
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'\b\d{1,2}\s*x\s*\d{1,3}\b'), ' ');
  text = text.replaceAll(
    RegExp(
      r'\bseason\s+\d{1,2}\s+episode\s+\d{1,3}\b',
      caseSensitive: false,
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), ' ');
  text = text.replaceAll(RegExp(r"['’]"), '');
  text = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// `(1999)` or `(1999)` only. A bare year can be the title itself.
int? extractGuideYear(String raw) {
  final match = RegExp(r'\(((?:19|20)\d{2})\)').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// `S6E19`, `S06 E19`, `6x19`, `Season 6 Episode 19`.
SeasonEpisode? parseSeasonEpisode(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  final seasonEpisode = RegExp(
    r'\bS(\d{1,2})\s*[:x.]?\s*E(\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (seasonEpisode != null) {
    return SeasonEpisode(
      season: int.parse(seasonEpisode.group(1)!),
      episode: int.parse(seasonEpisode.group(2)!),
    );
  }
  final cross = RegExp(r'\b(\d{1,2})\s*x\s*(\d{1,3})\b').firstMatch(text);
  if (cross != null) {
    return SeasonEpisode(
      season: int.parse(cross.group(1)!),
      episode: int.parse(cross.group(2)!),
    );
  }
  final words = RegExp(
    r'\bseason\s+(\d{1,2})\s+episode\s+(\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (words != null) {
    return SeasonEpisode(
      season: int.parse(words.group(1)!),
      episode: int.parse(words.group(2)!),
    );
  }
  return null;
}

/// XMLTV `episode-num`. `xmltv_ns` is zero-based (`5.18.` is season 6
/// episode 19). `onscreen` is `S06E19`.
SeasonEpisode? parseEpisodeNum(String? raw, {String? system}) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  final kind = (system ?? '').toLowerCase();
  if (kind == 'xmltv_ns' || (kind.isEmpty && text.contains('.'))) {
    final parts = text.split('.');
    int? oneBased(String? part) {
      if (part == null) return null;
      final trimmed = part.trim();
      if (trimmed.isEmpty) return null;
      final value = int.tryParse(trimmed);
      if (value == null || value < 0) return null;
      return value + 1;
    }

    final season = parts.isNotEmpty ? oneBased(parts[0]) : null;
    final episode = parts.length > 1 ? oneBased(parts[1]) : null;
    if (season == null && episode == null) return null;
    return SeasonEpisode(season: season, episode: episode);
  }
  return parseSeasonEpisode(text);
}

double titleMatchScore(String query, String candidate) {
  final left = normalizeGuideTitle(query);
  final right = normalizeGuideTitle(candidate);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;
  if (_sameTokens(left, right)) return 1;
  return _dice(left, right);
}

/// True only when the titles are the same show. A spin-off, a sequel, or a
/// different year is not a match.
bool titlesConfidentlyMatch(
  String query,
  String candidate, {
  int? queryYear,
  int? candidateYear,
}) {
  final left = normalizeGuideTitle(query);
  final right = normalizeGuideTitle(candidate);
  if (left.isEmpty || right.isEmpty) return false;
  if (!_yearOk(queryYear, candidateYear)) return false;
  if (left == right || _sameTokens(left, right)) return true;
  final leftTokens = _significant(left);
  final rightTokens = _significant(right);
  if (leftTokens.isEmpty || rightTokens.isEmpty) return false;
  if (leftTokens.first != rightTokens.first) return false;
  if (rightTokens.length > leftTokens.length) return false;
  return titleMatchScore(query, candidate) >= guideTitleConfidentScore;
}

/// TV wins when any TV row is a confident match. Movies are the fallback.
/// A known season and episode never accepts a movie.
TmdbCandidate? pickGuideMatch(GuideQuery query, List<TmdbCandidate> candidates) {
  final needle = query.searchTitle;
  if (needle.isEmpty) return null;
  TmdbCandidate? tv;
  var tvScore = -1.0;
  TmdbCandidate? movie;
  var movieScore = -1.0;
  for (final candidate in candidates) {
    final type = candidate.mediaType;
    if (type != 'tv' && type != 'movie') continue;
    if (query.hasEpisode && type != 'tv') continue;
    if (!titlesConfidentlyMatch(
      needle,
      candidate.title,
      queryYear: query.year,
      candidateYear: candidate.year,
    )) {
      continue;
    }
    final score = titleMatchScore(needle, candidate.title);
    if (type == 'tv' && score > tvScore) {
      tv = candidate;
      tvScore = score;
    } else if (type == 'movie' && score > movieScore) {
      movie = candidate;
      movieScore = score;
    }
  }
  return tv ?? movie;
}

String shortenOverview(String raw, {int max = 280}) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= max) return text;
  final cut = text.lastIndexOf(' ', max);
  final end = cut < 40 ? max : cut;
  return '${text.substring(0, end).trim()}…';
}

bool _yearOk(int? queryYear, int? candidateYear) {
  if (queryYear == null || candidateYear == null) return true;
  return (queryYear - candidateYear).abs() <= 1;
}

bool _sameTokens(String left, String right) {
  final a = _significant(left);
  final b = _significant(right);
  if (a.isEmpty || b.isEmpty || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _significant(String normalized) {
  const drop = {'the', 'a', 'an'};
  final tokens = normalized
      .split(' ')
      .where((token) => token.isNotEmpty && !drop.contains(token))
      .toList();
  if (tokens.isNotEmpty) return tokens;
  return normalized.split(' ').where((token) => token.isNotEmpty).toList();
}

double _dice(String left, String right) {
  if (left.length < 2 || right.length < 2) return 0;
  final counts = <String, int>{};
  for (var i = 0; i < left.length - 1; i++) {
    final pair = left.substring(i, i + 2);
    counts[pair] = (counts[pair] ?? 0) + 1;
  }
  var overlap = 0;
  for (var i = 0; i < right.length - 1; i++) {
    final pair = right.substring(i, i + 2);
    final have = counts[pair] ?? 0;
    if (have > 0) {
      counts[pair] = have - 1;
      overlap++;
    }
  }
  return (2 * overlap) / ((left.length - 1) + (right.length - 1));
}

String? _blank(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

/// `ParentIndexNumber` / `IndexNumber` arrive as ints or numeric strings.
int? readGuideIndex(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
