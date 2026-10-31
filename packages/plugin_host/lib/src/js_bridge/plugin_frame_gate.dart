import 'dart:async';
import 'dart:convert';

import 'host_api.dart';
import 'plugin_frame_protocol.dart';

/// Pure-Dart gatekeeper and timeout coordinator for plugin frame bridge communications.
///
/// Handles:
/// - Validation of incoming messages: strict source identity, origin = 'null', and valid nonce.
/// - Load event counting without disabling the bridge on subsequent loads (e.g. hash changes).
/// - 15-second host timeout wrapper returning `{ok: false, error: ...}` envelopes.
class PluginFrameGate {
  final String nonce;
  int _loadCount = 0;

  PluginFrameGate({required this.nonce});

  int get loadCount => _loadCount;

  /// Handles an iframe 'load' event. Returns `true` only on the very first load.
  bool onIFrameLoad() {
    _loadCount++;
    return _loadCount == 1;
  }

  /// Determines whether an incoming message event is valid and extracts its raw payload string.
  ///
  /// Requirements:
  /// - [origin] must be strictly `'null'` (opaque origin of sandboxed iframe).
  /// - [isSourceMatch] must be `true` (event.source strictly matches iframe.contentWindow).
  /// - [envelopeMap] must contain protocol version 1, matching [nonce], and payload <= 256KB.
  ///
  /// Returns extracted payload string if valid, or `null` if the message should be ignored.
  String? validateIncomingMessage({
    required String? origin,
    required bool isSourceMatch,
    required dynamic envelopeMap,
  }) {
    if (!isSourceMatch) {
      return null;
    }
    if (origin != 'null') {
      return null;
    }
    if (envelopeMap is! Map<String, dynamic>) {
      return null;
    }

    return PluginFrameProtocol.validateIncomingEnvelope(
      envelopeMap,
      expectedNonce: nonce,
    );
  }

  /// Parses raw incoming bridge message JSON into a Map, or null if invalid.
  static Map<String, dynamic>? parseMessagePayload(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Extracts the `callbackId` from a raw JSON bridge request string if present.
  static String? extractCallbackId(String rawJson) {
    final parsed = parseMessagePayload(rawJson);
    final id = parsed?['callbackId'];
    return id is String ? id : id?.toString();
  }

  /// Wraps host message dispatch in a 15-second timeout and catches all exceptions.
  ///
  /// Guarantees returning a response map with:
  /// - `ok`: `true` on success, `false` on failure.
  /// - `result`: result on success.
  /// - `error`: error message or `'host_timeout'` on failure.
  /// - `callbackId`: preserved from request if present.
  static Future<Map<String, dynamic>> handleHostMessageWithTimeout(
    HostApiHandler hostApiHandler,
    String rawJson, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    String? callbackId;
    try {
      callbackId = extractCallbackId(rawJson);
    } catch (_) {}

    try {
      final response = await hostApiHandler.handleMessage(rawJson).timeout(timeout);
      return response;
    } on TimeoutException {
      return {
        'ok': false,
        'error': 'host_timeout',
        if (callbackId != null) 'callbackId': callbackId,
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
        if (callbackId != null) 'callbackId': callbackId,
      };
    }
  }
}
