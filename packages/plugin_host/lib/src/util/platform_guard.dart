import 'package:flutter/foundation.dart';

/// Evaluates whether the current device platform supports the web plugin host system.
///
/// Returns `false` for Web, Linux, and TV environments (Android TV / tvOS).
bool isPluginHostSupported({bool isTv = false}) {
  if (kIsWeb) return false;
  if (defaultTargetPlatform == TargetPlatform.linux) return false;
  if (isTv) return false;
  return true;
}
