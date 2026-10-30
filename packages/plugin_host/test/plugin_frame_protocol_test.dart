import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('PluginFrameProtocol Tests', () {
    const validNonce = 'dGVzdF9ub25jZV8xMjM0NQ==';

    test('accepts valid incoming envelope and returns payload string', () {
      final envelope = {
        'mofin': 1,
        'nonce': validNonce,
        'payload': '{"method":"getUserContext"}',
      };

      final payload = PluginFrameProtocol.validateIncomingEnvelope(
        envelope,
        expectedNonce: validNonce,
      );

      expect(payload, equals('{"method":"getUserContext"}'));
    });

    test('rejects envelope with wrong mofin version', () {
      final envelope = {
        'mofin': 2,
        'nonce': validNonce,
        'payload': '{"method":"getUserContext"}',
      };

      final payload = PluginFrameProtocol.validateIncomingEnvelope(
        envelope,
        expectedNonce: validNonce,
      );

      expect(payload, isNull);
    });

    test('rejects envelope with wrong or missing nonce', () {
      final wrongNonce = {
        'mofin': 1,
        'nonce': 'wrong_nonce',
        'payload': '{"method":"getUserContext"}',
      };
      expect(
        PluginFrameProtocol.validateIncomingEnvelope(
          wrongNonce,
          expectedNonce: validNonce,
        ),
        isNull,
      );

      final missingNonce = {
        'mofin': 1,
        'payload': '{"method":"getUserContext"}',
      };
      expect(
        PluginFrameProtocol.validateIncomingEnvelope(
          missingNonce,
          expectedNonce: validNonce,
        ),
        isNull,
      );
    });

    test('rejects envelope with non-string payload', () {
      final envelope = {
        'mofin': 1,
        'nonce': validNonce,
        'payload': {'method': 'getUserContext'},
      };

      final payload = PluginFrameProtocol.validateIncomingEnvelope(
        envelope,
        expectedNonce: validNonce,
      );

      expect(payload, isNull);
    });

    test('rejects envelope with oversized payload (>256KB)', () {
      final largePayload = 'a' * (256 * 1024 + 1);
      final envelope = {
        'mofin': 1,
        'nonce': validNonce,
        'payload': largePayload,
      };

      final payload = PluginFrameProtocol.validateIncomingEnvelope(
        envelope,
        expectedNonce: validNonce,
      );

      expect(payload, isNull);
    });

    test('builds response envelope with nonce and sanitized data', () {
      final rawData = {
        'userId': 'user123',
        'token': 'secret_token_abc',
        'accessToken': 'secret_access_xyz',
        'Authorization': 'MediaBrowser Token=123',
        'nested': {
          'token': 'hidden_nested_token',
          'server': 'MyServer',
        },
      };

      final envelope = PluginFrameProtocol.buildResponseEnvelope(
        nonce: validNonce,
        responseData: rawData,
      );

      expect(envelope['mofin'], equals(1));
      expect(envelope['nonce'], equals(validNonce));
      expect(envelope['type'], equals('response'));

      final data = envelope['data'] as Map<String, dynamic>;
      expect(data['userId'], equals('user123'));
      expect(data.containsKey('token'), isFalse);
      expect(data.containsKey('accessToken'), isFalse);
      expect(data.containsKey('Authorization'), isFalse);

      final nested = data['nested'] as Map<String, dynamic>;
      expect(nested['server'], equals('MyServer'));
      expect(nested.containsKey('token'), isFalse);

      final jsonStr = jsonEncode(envelope);
      expect(jsonStr.contains('secret_token_abc'), isFalse);
      expect(jsonStr.contains('secret_access_xyz'), isFalse);
      expect(jsonStr.contains('hidden_nested_token'), isFalse);
    });

    test('builds event envelope with nonce and sanitized data', () {
      final eventData = {
        'type': 'plugin:test:update',
        'token': 'evt_token',
        'payload': {'key': 'val'},
      };

      final envelope = PluginFrameProtocol.buildEventEnvelope(
        nonce: validNonce,
        eventData: eventData,
      );

      expect(envelope['mofin'], equals(1));
      expect(envelope['nonce'], equals(validNonce));
      expect(envelope['type'], equals('event'));

      final data = envelope['data'] as Map<String, dynamic>;
      expect(data['type'], equals('plugin:test:update'));
      expect(data.containsKey('token'), isFalse);

      final jsonStr = jsonEncode(envelope);
      expect(jsonStr.contains('evt_token'), isFalse);
    });
  });
}
