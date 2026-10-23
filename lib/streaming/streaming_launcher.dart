import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/platform_detection.dart';
import 'streaming_service.dart';

/// Opens a subscription app. Nothing here plays the title: those streams are
/// DRM-protected and stay inside the service's own app.
class StreamingLauncher {
  StreamingLauncher({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('moonfin/streaming_apps');

  final MethodChannel _channel;

  Future<void> open(
    BuildContext context, {
    required StreamingService service,
    required String title,
  }) async {
    if (PlatformDetection.isAndroid) {
      final installed = await _launchAndroid(service, title);
      if (!installed && context.mounted) {
        _toast(context, "${service.label} isn't installed");
      }
      return;
    }
    final opened = await launchUrl(
      service.webSearchUri(title),
      mode: PlatformDetection.isWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && context.mounted) {
      _toast(context, "Couldn't open ${service.label}");
    }
  }

  Future<bool> _launchAndroid(StreamingService service, String title) async {
    try {
      final result = await _channel.invokeMethod<String>('launch', {
        'packages': service.androidPackages,
        'searchUrl': service.androidSearchUrl(title),
      });
      return result == 'opened';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
