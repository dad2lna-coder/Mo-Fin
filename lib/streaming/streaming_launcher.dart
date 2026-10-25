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
    String? providerTitleId,
  }) async {
    if (PlatformDetection.isAndroid) {
      final installed = await _launchAndroid(
        service,
        title: title,
        providerTitleId: providerTitleId,
      );
      if (!installed && context.mounted) {
        _toast(context, "${service.label} isn't installed");
      }
      return;
    }
    final uri = service.webUri(providerTitleId: providerTitleId, title: title);
    final opened = await launchUrl(
      uri,
      mode: PlatformDetection.isWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && context.mounted) {
      _toast(context, "Couldn't open ${service.label}");
    }
  }

  Future<bool> _launchAndroid(
    StreamingService service, {
    required String title,
    String? providerTitleId,
  }) async {
    try {
      final cleanId = providerTitleId?.trim() ?? '';
      final titleUrl = cleanId.isNotEmpty
          ? service.androidTitleUri(cleanId)?.toString()
          : null;
      final result = await _channel.invokeMethod<String>('launch', {
        'packages': service.androidPackages,
        'titleUrl': titleUrl,
        'searchUrl': service.androidSearchUrl(title),
      });
      return result == 'opened';
    } catch (_) {
      return false;
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
