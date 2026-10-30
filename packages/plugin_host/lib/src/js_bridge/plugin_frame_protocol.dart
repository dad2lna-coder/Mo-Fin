import 'dart:convert';

/// Pure-Dart protocol handler for web iframe postMessage bridge communication.
///
/// Validates incoming envelopes and builds outgoing response/event envelopes
/// using a per-instance cryptographically secure nonce.
class PluginFrameProtocol {
  static const int mofinProtocolVersion = 1;
  static const int maxPayloadSizeBytes = 256 * 1024; // 256KB

  /// Validates an incoming postMessage envelope map against [expectedNonce].
  ///
  /// Returns the extracted payload string if valid, or null if invalid.
  static String? validateIncomingEnvelope(
    Map<String, dynamic> envelope, {
    required String expectedNonce,
  }) {
    if (expectedNonce.isEmpty) {
      return null;
    }

    final mofin = envelope['mofin'];
    if (mofin != mofinProtocolVersion) {
      return null;
    }

    final nonce = envelope['nonce'];
    if (nonce is! String || nonce != expectedNonce) {
      return null;
    }

    final payload = envelope['payload'];
    if (payload is! String) {
      return null;
    }

    if (utf8.encode(payload).length > maxPayloadSizeBytes) {
      return null;
    }

    return payload;
  }

  /// Recursively strips sensitive keys ('token', 'accessToken', 'Authorization') from a data structure.
  static dynamic sanitizeData(dynamic data) {
    if (data is Map) {
      final sanitized = <String, dynamic>{};
      data.forEach((key, value) {
        final keyStr = key.toString();
        final lowerKey = keyStr.toLowerCase();
        if (lowerKey == 'token' ||
            lowerKey == 'accesstoken' ||
            lowerKey == 'authorization') {
          return;
        }
        sanitized[keyStr] = sanitizeData(value);
      });
      return sanitized;
    } else if (data is List) {
      return data.map((e) => sanitizeData(e)).toList();
    }
    return data;
  }

  /// Builds an outgoing response envelope map.
  static Map<String, dynamic> buildResponseEnvelope({
    required String nonce,
    required dynamic responseData,
  }) {
    return {
      'mofin': mofinProtocolVersion,
      'nonce': nonce,
      'type': 'response',
      'data': sanitizeData(responseData),
    };
  }

  /// Builds an outgoing event envelope map.
  static Map<String, dynamic> buildEventEnvelope({
    required String nonce,
    required dynamic eventData,
  }) {
    return {
      'mofin': mofinProtocolVersion,
      'nonce': nonce,
      'type': 'event',
      'data': sanitizeData(eventData),
    };
  }
}
