import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import 'direct_iptv_client.dart';
import 'models.dart';

/// Session header for Moonbase. The value is the signed-in access token,
/// never a key the user typed.
Map<String, String> recordingSessionHeaders(MediaServerClient client) {
  final token = client.accessToken?.trim() ?? '';
  if (token.isEmpty) return const {};
  return {
    'Authorization': buildServerAuthorizationHeader(
      scheme: client.serverType == ServerType.emby ? 'Emby' : 'MediaBrowser',
      deviceInfo: client.deviceInfo,
      accessToken: token,
    ),
  };
}

Uri recordingEndpoint(String? baseUrl, String path) {
  final base = (baseUrl ?? 'http://moonbase.local')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  final root = base.endsWith('/') ? base : '$base/';
  return Uri.parse(root).resolve(path);
}

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
    'Recordings need the Moonbase plugin on this server';

const directRecordingsForbiddenMessage =
    "Live TV recording isn't allowed for this account";

/// `POST/GET/DELETE /Moonfin/LiveTv/Direct/Recordings` on the signed-in
/// Jellyfin server. The session token already on the client is the only
/// credential. A playlist token or API key is never sent.
class DirectIptvRecordings {
  DirectIptvRecordings({
    DirectIptvTransport? transport,
    MediaServerClient? client,
    String? baseUrl,
    Map<String, String>? sessionHeaders,
  }) : _transport = transport,
       _client = client,
       _baseUrl = baseUrl,
       _sessionHeaders = sessionHeaders;

  final DirectIptvTransport? _transport;
  final MediaServerClient? _client;
  final String? _baseUrl;
  final Map<String, String>? _sessionHeaders;

  static const recordingsPath = 'Moonfin/LiveTv/Direct/Recordings';

  Future<DirectRecording> schedule({
    required String tvgId,
    required String title,
    required DateTime start,
    required DateTime end,
    String? streamUrl,
    String? recUrl,
  }) async {
    final payload = jsonEncode({
      'tvgId': tvgId,
      'title': title,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      if (streamUrl != null && streamUrl.trim().isNotEmpty)
        'streamUrl': streamUrl.trim(),
      if (recUrl != null && recUrl.trim().isNotEmpty) 'recUrl': recUrl.trim(),
    });
    final result = await _send('POST', recordingsPath, body: payload);
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

  Future<List<DirectRecording>> list() async {
    final result = await _send('GET', recordingsPath);
    return parseDirectRecordings(result.body);
  }

  Future<void> cancel(String id) async {
    final encoded = Uri.encodeComponent(id);
    await _send('DELETE', '$recordingsPath/$encoded');
  }

  Future<DirectIptvHttpResult> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final client = _client ?? (_baseUrl == null ? _registeredClient() : null);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?_sessionHeaders,
      if (client != null) ...recordingSessionHeaders(client),
    };
    final url = recordingEndpoint(_baseUrl ?? client?.baseUrl, path);
    final DirectIptvHttpResult result;
    try {
      final transport = _transport;
      if (transport != null) {
        result = await transport.send(method, url, headers, body: body);
      } else {
        result = await _dioSend(method, url, headers, body: body);
      }
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

  MediaServerClient? _registeredClient() {
    if (!GetIt.instance.isRegistered<MediaServerClient>()) return null;
    return GetIt.instance<MediaServerClient>();
  }

  Future<DirectIptvHttpResult> _dioSend(
    String method,
    Uri url,
    Map<String, String> headers, {
    String? body,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
        validateStatus: (_) => true,
      ),
    );
    configureServerDio(dio);
    try {
      final response = await dio
          .requestUri<String>(
            url,
            data: body,
            options: Options(method: method, responseType: ResponseType.plain),
          )
          .timeout(const Duration(seconds: 30));
      return DirectIptvHttpResult(
        response.statusCode ?? 0,
        response.data ?? '',
      );
    } finally {
      dio.close();
    }
  }

  DirectIptvHttpResult _require(DirectIptvHttpResult result) {
    final code = result.statusCode;
    if (code >= 200 && code < 300) return result;
    if (code == 401 || code == 403) {
      throw const DirectIptvRecordingsException(
        directRecordingsForbiddenMessage,
      );
    }
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
