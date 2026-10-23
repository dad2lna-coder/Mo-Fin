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
