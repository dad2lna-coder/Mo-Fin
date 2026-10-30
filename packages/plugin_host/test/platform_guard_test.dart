import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_host/plugin_host.dart';

void main() {
  group('platform_guard Tests', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('isPluginHostSupported returns false when isTv is true', () {
      expect(isPluginHostSupported(isTv: true), isFalse);
    });

    test('isPluginHostSupported returns false on Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(isPluginHostSupported(isTv: false), isFalse);
    });

    test('isPluginHostSupported returns true on Android when not TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isPluginHostSupported(isTv: false), isTrue);
    });

    test('isPluginHostSupported returns true on iOS when not TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isPluginHostSupported(isTv: false), isTrue);
    });

    test('isPluginHostSupported returns true on macOS when not TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(isPluginHostSupported(isTv: false), isTrue);
    });

    test('isPluginHostSupported returns true on Windows when not TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(isPluginHostSupported(isTv: false), isTrue);
    });
  });
}
