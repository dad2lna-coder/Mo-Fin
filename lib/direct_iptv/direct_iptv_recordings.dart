import 'dart:async';
import 'dart:convert';

import 'direct_iptv_client.dart';
import 'models.dart';
import 'playlist_parse.dart';

/// A server-side recording. Nothing is written on the device.
class DirectRecording {
  final String id;
  final String tvgId;
  final String title;
  final DateTime start;
  final DateTime end;
  final String status;

  const DirectRecording({
    required this.id,
    required this.tvgId,
    required this.title,
    required this.start,
    required this.end,
    required this.status,
  });

  /// Red-dot states. Finished and failed jobs stay off the guide.
  bool get marksGuide => status == 'scheduled' || status == 'recording';
}

class DirectIptvRecordingsException implements Exception {
  final String message;

  const DirectIptvRecordingsException(this.message);

  @override
  String toString() => message;
}

const directRecordingsMissingMessage =
    "Recordings aren't available on this source";

/// `POST/GET/DELETE <base>/rec/…` on the IPTV source. A missing route fails
/// with [DirectIptvRecordingsException] instead of throwing from the network.
class DirectIptvRecordings {
  DirectIptvRecordings({DirectIptvTransport? transport})
    : _transport = transport ?? HttpDirectIptvTransport();

  final DirectIptvTransport _transport;

  Future<DirectRecording> schedule({
    required DirectIptvSource source,
    required String tvgId,
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    final payload = jsonEncode({
      'tvg_id': tvgId,
      'title': title,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    });
    final result = await _send(
      'POST',
      _uri(source, 'schedule'),
      source,
      body: payload,
    );
    final parsed = _one(result.body, now: DateTime.now());
    final id =
        _responseId(result.body) ??
        (parsed != null && parsed.id.isNotEmpty
            ? parsed.id
            : '$tvgId@${start.toUtc().toIso8601String()}');
    return DirectRecording(
      id: id,
      tvgId: tvgId,
      title: title,
      start: start,
      end: end,
      status: parsed?.status == 'recording' ? 'recording' : 'scheduled',
    );
  }

  Future<List<DirectRecording>> list(DirectIptvSource source) async {
    final result = await _send('GET', _uri(source, 'list'), source);
    return parseDirectRecordings(result.body);
  }

  Future<void> cancel(DirectIptvSource source, String id) async {
    final encoded = Uri.encodeComponent(id);
    await _send('DELETE', _uri(source, encoded), source);
  }

  Uri _uri(DirectIptvSource source, String path) {
    return resolveSourceUri(source.baseUrl, 'rec/$path');
  }

  Future<DirectIptvHttpResult> _send(
    String method,
    Uri url,
    DirectIptvSource source, {
    String? body,
  }) async {
    final headers = <String, String>{
      ...authHeaders(source),
      if (body != null) 'Content-Type': 'application/json',
    };
    final DirectIptvHttpResult result;
    try {
      result = await _transport.send(method, url, headers, body: body);
    } on DirectIptvRecordingsException {
      rethrow;
    } on TimeoutException {
      throw const DirectIptvRecordingsException(
        'The server took too long to answer',
      );
    } catch (_) {
      throw const DirectIptvRecordingsException('Could not reach the server');
    }
    return _require(result);
  }

  DirectIptvHttpResult _require(DirectIptvHttpResult result) {
    final code = result.statusCode;
    if (code >= 200 && code < 300) return result;
    if (code == 404 || code == 405 || code == 501) {
      throw const DirectIptvRecordingsException(directRecordingsMissingMessage);
    }
    throw DirectIptvRecordingsException('Recording request failed ($code)');
  }

  DirectRecording? _one(String body, {required DateTime now}) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return directRecordingFromJson(
        Map<String, dynamic>.from(decoded),
        now: now,
      );
    } catch (_) {
      return null;
    }
  }

  String? _responseId(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final raw = decoded['id'] ?? decoded['Id'] ?? decoded['recording_id'];
      final id = raw?.toString().trim() ?? '';
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }
}

List<DirectRecording> parseDirectRecordings(String body, {DateTime? now}) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const [];
  final dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw const DirectIptvRecordingsException(directRecordingsMissingMessage);
  }
  final List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map) {
    final nested = decoded['recordings'] ?? decoded['items'] ?? decoded['data'];
    if (nested is List) {
      items = nested;
    } else if (decoded['tvg_id'] != null || decoded['tvgId'] != null) {
      items = [decoded];
    } else {
      throw const DirectIptvRecordingsException(directRecordingsMissingMessage);
    }
  } else {
    throw const DirectIptvRecordingsException(directRecordingsMissingMessage);
  }
  final clock = now ?? DateTime.now();
  final recordings = <DirectRecording>[];
  for (final item in items) {
    if (item is! Map) continue;
    final recording = directRecordingFromJson(
      Map<String, dynamic>.from(item),
      now: clock,
    );
    if (recording == null || recording.tvgId.isEmpty) continue;
    recordings.add(recording);
  }
  return recordings;
}

/// The guide dot for [program] on [channel], if the server still has it
/// scheduled or recording.
DirectRecording? directRecordingFor({
  required Iterable<DirectRecording> recordings,
  required DirectChannel channel,
  required DirectProgram program,
}) {
  final tvg = channel.tvgId?.trim() ?? '';
  if (tvg.isEmpty) return null;
  for (final recording in recordings) {
    if (!recording.marksGuide) continue;
    if (recording.tvgId != tvg) continue;
    if (_sameInstant(recording.start, program.start) &&
        _sameInstant(recording.end, program.end)) {
      return recording;
    }
  }
  return null;
}

const directRecordingMatchSlack = Duration(seconds: 2);

bool _sameInstant(DateTime a, DateTime b) =>
    a.toUtc().difference(b.toUtc()).abs() <= directRecordingMatchSlack;

DirectRecording? directRecordingFromJson(
  Map<String, dynamic> json, {
  DateTime? now,
}) {
  final start = _time(json['start'] ?? json['start_time'] ?? json['StartDate']);
  final end = _time(
    json['end'] ?? json['end_time'] ?? json['stop'] ?? json['EndDate'],
  );
  if (start == null || end == null) return null;
  final tvg = (json['tvg_id'] ?? json['tvgId'] ?? json['channel'] ?? '')
      .toString()
      .trim();
  final rawId = json['id'] ?? json['Id'] ?? json['recording_id'];
  final id = rawId == null || rawId.toString().trim().isEmpty
      ? '$tvg@${start.toUtc().toIso8601String()}'
      : rawId.toString();
  final title = (json['title'] ?? json['name'] ?? json['Name'] ?? '')
      .toString();
  final status = _status(
    json['status'] ?? json['state'],
    start: start,
    end: end,
    now: now ?? DateTime.now(),
  );
  return DirectRecording(
    id: id,
    tvgId: tvg,
    title: title,
    start: start,
    end: end,
    status: status,
  );
}

DateTime? _time(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _status(
  Object? raw, {
  required DateTime start,
  required DateTime end,
  required DateTime now,
}) {
  final value = raw
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  switch (value) {
    case 'scheduled':
    case 'schedule':
    case 'pending':
    case 'queued':
      return 'scheduled';
    case 'recording':
    case 'in_progress':
    case 'inprogress':
    case 'active':
      return 'recording';
    case 'completed':
    case 'complete':
    case 'recorded':
    case 'failed':
    case 'error':
    case 'cancelled':
    case 'canceled':
      return value == 'canceled' ? 'cancelled' : value!;
    case null:
    case '':
      if (now.isBefore(start)) return 'scheduled';
      if (now.isBefore(end)) return 'recording';
      return 'completed';
    default:
      return value;
  }
}
