import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'direct_iptv_client.dart';
import 'direct_iptv_recordings.dart';

/// Local map of station group id to the feed channel id last chosen.
///
/// Moonbase is asked once, on the signed-in Jellyfin session. A missing
/// route, or any failure to reach it, leaves the local map in charge.
const directFeedChoicePath = 'Moonfin/LiveTv/Direct/Feeds';

String directFeedChoiceKey(String? userId) {
  final user = userId?.trim() ?? '';
  if (user.isEmpty) return 'moonfin.direct_iptv.feed_choice';
  return 'moonfin.direct_iptv.feed_choice.$user';
}

/// Null when [body] is not a choice map. An empty object is a real answer.
Map<String, String>? parseDirectFeedChoices(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const {};
  final dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final raw = decoded['choices'] ?? decoded['Choices'] ?? decoded;
  if (raw is! Map) return null;
  final choices = <String, String>{};
  for (final entry in raw.entries) {
    final groupId = entry.key.toString().trim();
    final channelId = entry.value?.toString().trim() ?? '';
    if (groupId.isEmpty || channelId.isEmpty) continue;
    if (groupId == 'choices' || groupId == 'Choices') continue;
    choices[groupId] = channelId;
  }
  return choices;
}

String encodeDirectFeedChoices(Map<String, String> choices) =>
    jsonEncode({'choices': choices});

/// Pulls and pushes the signed-in user's feed map. Null from [pull] means
/// Moonbase could not answer, not that the user has no choices.
abstract class DirectFeedSync {
  Future<Map<String, String>?> pull();
  Future<bool> push(Map<String, String> choices);
}

class MoonbaseDirectFeedSync implements DirectFeedSync {
  MoonbaseDirectFeedSync({
    required this._transport,
    required this._endpoint,
    required this._headers,
  });

  final DirectIptvTransport _transport;
  final Uri _endpoint;
  final Map<String, String> _headers;
  bool _missing = false;

  static Uri endpointFor(String? baseUrl) =>
      recordingEndpoint(baseUrl, directFeedChoicePath);

  @override
  Future<Map<String, String>?> pull() async {
    if (_missing) return null;
    try {
      final result = await _transport.send('GET', _endpoint, {
        ..._headers,
        'Accept': 'application/json',
      }, timeout: const Duration(seconds: 2));
      if (_isMissing(result.statusCode)) {
        _missing = true;
        return null;
      }
      if (result.statusCode < 200 || result.statusCode >= 300) return null;
      return parseDirectFeedChoices(result.body);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> push(Map<String, String> choices) async {
    if (_missing) return false;
    try {
      final result = await _transport.send(
        'PUT',
        _endpoint,
        {
          ..._headers,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: encodeDirectFeedChoices(choices),
        timeout: const Duration(seconds: 2),
      );
      if (_isMissing(result.statusCode)) {
        _missing = true;
        return false;
      }
      return result.statusCode >= 200 && result.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  bool _isMissing(int code) => code == 404 || code == 405 || code == 501;
}

/// Group id to feed channel id. Local storage is per Jellyfin user when
/// the id is known, and the device-wide key otherwise.
class DirectFeedPreference {
  DirectFeedPreference({this._preferences, this._userId, this._sync});

  SharedPreferences? _preferences;
  final String? _userId;
  final DirectFeedSync? _sync;
  Map<String, String> _choices = {};
  Future<void>? _loading;

  String? choiceFor(String groupId) => _choices[groupId];

  Map<String, String> get choices => Map.unmodifiable(_choices);

  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  /// Remembers [channelId] for [groupId]. An automatic failover must not
  /// call this: the saved choice stays what the viewer picked.
  Future<void> save(String groupId, String channelId) async {
    await ensureLoaded();
    final group = groupId.trim();
    final channel = channelId.trim();
    if (group.isEmpty || channel.isEmpty) return;
    if (_choices[group] == channel) return;
    _choices = {..._choices, group: channel};
    await _writeLocal();
    await _sync?.push(_choices);
  }

  Future<void> _load() async {
    _choices = await _readLocal();
    final remote = await _sync?.pull();
    if (remote == null) return;
    final localOnly = <String, String>{};
    for (final entry in _choices.entries) {
      if (!remote.containsKey(entry.key)) localOnly[entry.key] = entry.value;
    }
    _choices = {..._choices, ...remote};
    await _writeLocal();
    if (localOnly.isNotEmpty) {
      await _sync?.push(_choices);
    }
  }

  Future<Map<String, String>> _readLocal() async {
    final prefs = await _store();
    final raw = prefs.getString(directFeedChoiceKey(_userId));
    if (raw == null || raw.isEmpty) return {};
    return parseDirectFeedChoices(raw) ?? {};
  }

  Future<void> _writeLocal() async {
    final prefs = await _store();
    await prefs.setString(
      directFeedChoiceKey(_userId),
      encodeDirectFeedChoices(_choices),
    );
  }

  Future<SharedPreferences> _store() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }
}
