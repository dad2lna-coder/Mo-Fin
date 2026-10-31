import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

class _FakePreferences {
  final Map<String, dynamic> _storage = {};
  dynamic get(String key) => _storage[key];
  Future<bool> setString(String key, String value) async {
    _storage[key] = value;
    return true;
  }
}

class _SlowHostApiHandler extends HostApiHandler {
  final Duration delay;
  final bool shouldThrow;

  _SlowHostApiHandler({
    required super.pluginId,
    required super.registry,
    required super.userContextProvider,
    required super.prefs,
    required this.delay,
    this.shouldThrow = false,
  });

  @override
  Future<Map<String, dynamic>> handleMessage(String rawJson) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (shouldThrow) {
      throw Exception('Simulated host internal failure');
    }
    return await super.handleMessage(rawJson);
  }
}

void main() {
  group('PluginFrameGate Load Counting & State Tests', () {
    test('onIFrameLoad returns true only on first load and tracks count on subsequent loads', () {
      final gate = PluginFrameGate(nonce: 'test-nonce-123');

      expect(gate.loadCount, 0);

      // Load 1 (initial page load)
      expect(gate.onIFrameLoad(), isTrue);
      expect(gate.loadCount, 1);

      // Load 2 (e.g. Safari hash change #1)
      expect(gate.onIFrameLoad(), isFalse);
      expect(gate.loadCount, 2);

      // Load 3
      expect(gate.onIFrameLoad(), isFalse);
      expect(gate.loadCount, 3);

      // Load 4
      expect(gate.onIFrameLoad(), isFalse);
      expect(gate.loadCount, 4);

      // Load 5 (e.g. multiple hash changes)
      expect(gate.onIFrameLoad(), isFalse);
      expect(gate.loadCount, 5);
    });

    test('valid nonce + correct source is accepted after 1, 2, and 5 load events', () {
      final gate = PluginFrameGate(nonce: 'valid-nonce-abc');

      final envelope = {
        'mofin': 1,
        'nonce': 'valid-nonce-abc',
        'payload': jsonEncode({'method': 'getHostApiVersion', 'callbackId': 'cb_1'}),
      };

      // 1 load event
      gate.onIFrameLoad();
      final res1 = gate.validateIncomingMessage(
        origin: 'null',
        isSourceMatch: true,
        envelopeMap: envelope,
      );
      expect(res1, isNotNull);
      expect(jsonDecode(res1!)['method'], 'getHostApiVersion');

      // 2 load events
      gate.onIFrameLoad();
      final res2 = gate.validateIncomingMessage(
        origin: 'null',
        isSourceMatch: true,
        envelopeMap: envelope,
      );
      expect(res2, isNotNull);

      // 5 load events total
      gate.onIFrameLoad();
      gate.onIFrameLoad();
      gate.onIFrameLoad();
      expect(gate.loadCount, 5);
      final res5 = gate.validateIncomingMessage(
        origin: 'null',
        isSourceMatch: true,
        envelopeMap: envelope,
      );
      expect(res5, isNotNull);
    });

    test('rejection on wrong or missing nonce returns null without throwing', () {
      final gate = PluginFrameGate(nonce: 'expected-nonce');

      // Wrong nonce
      final wrongNonceEnv = {
        'mofin': 1,
        'nonce': 'wrong-nonce',
        'payload': '{"method":"getHostApiVersion"}',
      };
      expect(
        gate.validateIncomingMessage(
          origin: 'null',
          isSourceMatch: true,
          envelopeMap: wrongNonceEnv,
        ),
        isNull,
      );

      // Missing nonce
      final missingNonceEnv = {
        'mofin': 1,
        'payload': '{"method":"getHostApiVersion"}',
      };
      expect(
        gate.validateIncomingMessage(
          origin: 'null',
          isSourceMatch: true,
          envelopeMap: missingNonceEnv,
        ),
        isNull,
      );
    });

    test('rejection on non-matching source or non-null origin returns null', () {
      final gate = PluginFrameGate(nonce: 'test-nonce');
      final validEnv = {
        'mofin': 1,
        'nonce': 'test-nonce',
        'payload': '{"method":"getHostApiVersion"}',
      };

      // Non-matching source
      expect(
        gate.validateIncomingMessage(
          origin: 'null',
          isSourceMatch: false,
          envelopeMap: validEnv,
        ),
        isNull,
      );

      // Non-null origin
      expect(
        gate.validateIncomingMessage(
          origin: 'https://attacker.example.com',
          isSourceMatch: true,
          envelopeMap: validEnv,
        ),
        isNull,
      );
    });
  });

  group('PluginFrameGate Host Message Timeout & Exception Tests', () {
    late PluginRegistry registry;
    late _FakePreferences prefs;

    setUp(() {
      registry = PluginRegistry();
      prefs = _FakePreferences();
    });

    test('handles non-string callbackId gracefully without throwing', () async {
      final handler = HostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        prefs: prefs,
      );

      final requestJson = jsonEncode({
        'method': 'getHostApiVersion',
        'callbackId': 12345,
      });

      final response = await PluginFrameGate.handleHostMessageWithTimeout(
        handler,
        requestJson,
        timeout: const Duration(milliseconds: 500),
      );

      expect(response['ok'], isTrue);
      expect(response['result'], {
        'hostApi': HostApiHandler.currentHostApiVersion,
      });
      expect(response['callbackId'], '12345');
    });

    test('returns successful response within timeout', () async {
      final handler = HostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        prefs: prefs,
      );

      final requestJson = jsonEncode({
        'method': 'getHostApiVersion',
        'callbackId': 'cb_success_123',
      });

      final response = await PluginFrameGate.handleHostMessageWithTimeout(
        handler,
        requestJson,
        timeout: const Duration(milliseconds: 500),
      );

      expect(response['ok'], isTrue);
      expect(response['result'], {
        'hostApi': HostApiHandler.currentHostApiVersion,
      });
      expect(response['callbackId'], 'cb_success_123');
    });

    test('returns ok:false with error host_timeout and callbackId on timeout', () async {
      final handler = _SlowHostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        prefs: prefs,
        delay: const Duration(milliseconds: 200),
      );

      final requestJson = jsonEncode({
        'method': 'getHostApiVersion',
        'callbackId': 'cb_timeout_456',
      });

      final response = await PluginFrameGate.handleHostMessageWithTimeout(
        handler,
        requestJson,
        timeout: const Duration(milliseconds: 50),
      );

      expect(response['ok'], isFalse);
      expect(response['error'], 'host_timeout');
      expect(response['callbackId'], 'cb_timeout_456');
    });

    test('returns ok:false with error message and callbackId on exception', () async {
      final handler = _SlowHostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        prefs: prefs,
        delay: Duration.zero,
        shouldThrow: true,
      );

      final requestJson = jsonEncode({
        'method': 'getHostApiVersion',
        'callbackId': 'cb_error_789',
      });

      final response = await PluginFrameGate.handleHostMessageWithTimeout(
        handler,
        requestJson,
        timeout: const Duration(milliseconds: 500),
      );

      expect(response['ok'], isFalse);
      expect(response['error'], contains('Simulated host internal failure'));
      expect(response['callbackId'], 'cb_error_789');
    });

    test('preserves null callbackId when request does not contain callbackId', () async {
      final handler = _SlowHostApiHandler(
        pluginId: 'test-plugin',
        registry: registry,
        userContextProvider: () => null,
        prefs: prefs,
        delay: const Duration(milliseconds: 200),
      );

      final requestJson = jsonEncode({
        'method': 'getHostApiVersion',
      });

      final response = await PluginFrameGate.handleHostMessageWithTimeout(
        handler,
        requestJson,
        timeout: const Duration(milliseconds: 50),
      );

      expect(response['ok'], isFalse);
      expect(response['error'], 'host_timeout');
      expect(response.containsKey('callbackId'), isFalse);
    });
  });
}
