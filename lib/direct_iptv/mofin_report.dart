import 'dart:convert';

/// Resolutions a Mo Fin playlist may stamp on a channel. Anything else is
/// ignored so a free-form tag never becomes a badge.
const mofinResolutions = <String>['2160p', '1080p', '720p', '480p', 'SD'];

final _checkedDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? normalizeTvgResolution(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  for (final known in mofinResolutions) {
    if (known.toLowerCase() == lower) return known;
  }
  return null;
}

/// `x-mofin-working` is only `true` or `false`. Other words leave the
/// buttons unhighlighted.
bool? parseMofinWorking(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      return null;
  }
}

String? normalizeMofinChecked(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || !_checkedDate.hasMatch(trimmed)) return null;
  return trimmed;
}

/// `x-mofin-stack`. Zero and junk are not a stack, so a plain channel
/// never grows a badge.
int? parseMofinStack(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final value = int.tryParse(trimmed);
  if (value == null || value < 1) return null;
  return value;
}

/// `x-mofin-members`, a comma-separated list of the channels inside a stack.
List<String> parseMofinMembers(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return const [];
  return [
    for (final part in trimmed.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String mofinToday([DateTime? now]) {
  final day = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

/// The free Mo Fin playlist, whatever host it is served from.
bool isMofinFreeBase(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path.toLowerCase().endsWith('/mofin/free');
}

/// `<base>report`, or null when [baseUrl] is not the Mo Fin free playlist.
Uri? mofinReportUri(String baseUrl) {
  if (!isMofinFreeBase(baseUrl)) return null;
  final trimmed = baseUrl.trim();
  final root = trimmed.endsWith('/') ? trimmed : '$trimmed/';
  return Uri.parse(root).resolve('report');
}

/// `<base>resolution`, or null when [baseUrl] is not the Mo Fin free playlist.
Uri? mofinResolutionUri(String baseUrl) {
  if (!isMofinFreeBase(baseUrl)) return null;
  final trimmed = baseUrl.trim();
  final root = trimmed.endsWith('/') ? trimmed : '$trimmed/';
  return Uri.parse(root).resolve('resolution');
}

/// Decoded picture height to the label Mo Fin stores. Null when the player
/// has not reported a height yet. 1440p is a playback measurement, not a
/// playlist badge, so it is not part of [mofinResolutions].
String? mofinResolutionForHeight(int height) {
  if (height <= 0) return null;
  if (height >= 2160) return '2160p';
  if (height >= 1440) return '1440p';
  if (height >= 1080) return '1080p';
  if (height >= 720) return '720p';
  if (height >= 480) return '480p';
  return 'SD';
}

/// `X-Mofin-Member` from a stream response. Empty and missing are the same.
String? mofinMemberFromHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'x-mofin-member') continue;
    final value = entry.value.trim();
    if (value.isEmpty) return null;
    return value;
  }
  return null;
}

String mofinResolutionBody({
  required String tvgId,
  required String res,
  String? member,
}) {
  final body = <String, String>{'tvg_id': tvgId, 'res': res};
  final who = member?.trim();
  if (who != null && who.isNotEmpty) body['member'] = who;
  return jsonEncode(body);
}
Uri? mofinRemoveUri(String baseUrl) {
  if (!isMofinFreeBase(baseUrl)) return null;
  final trimmed = baseUrl.trim();
  final root = trimmed.endsWith('/') ? trimmed : '$trimmed/';
  return Uri.parse(root).resolve('remove');
}

enum MofinReportStatus { saved, limited, failed }

MofinReportStatus classifyMofinReport(int statusCode, String body) {
  if (statusCode == 429) return MofinReportStatus.limited;
  if (statusCode == 200) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['ok'] == true) {
        return MofinReportStatus.saved;
      }
    } catch (_) {}
  }
  return MofinReportStatus.failed;
}

String mofinReportBody({
  required String tvgId,
  required bool working,
  required String name,
}) {
  return jsonEncode({'tvg_id': tvgId, 'working': working, 'name': name});
}

enum MofinRemoveStatus { removed, forbidden, missing, limited, failed }

MofinRemoveStatus classifyMofinRemove(int statusCode, String body) {
  if (statusCode == 403) return MofinRemoveStatus.forbidden;
  if (statusCode == 404) return MofinRemoveStatus.missing;
  if (statusCode == 429) return MofinRemoveStatus.limited;
  if (statusCode == 200) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['ok'] == true) {
        return MofinRemoveStatus.removed;
      }
    } catch (_) {}
  }
  return MofinRemoveStatus.failed;
}

String mofinRemoveBody({required String tvgId, required String name}) {
  return jsonEncode({'tvg_id': tvgId, 'name': name});
}

/// Token rides as `X-Mofin-Key`. An empty token sends no key header.
Map<String, String> mofinRemoveHeaders(String token) {
  final headers = <String, String>{
    'Accept': '*/*',
    'Content-Type': 'application/json',
  };
  final key = token.trim();
  if (key.isNotEmpty) headers['X-Mofin-Key'] = key;
  return headers;
}
