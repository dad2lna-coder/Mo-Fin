import 'package:flutter/foundation.dart';

/// Evaluates whether the current device platform supports the web plugin host system.
///
/// Returns `false` for Linux and non-Android TV environments (such as tvOS).
/// Android TV / Fire TV are supported via WebView.
bool isPluginHostSupported({bool isTv = false}) {
  if (defaultTargetPlatform == TargetPlatform.linux) return false;
  if (isTv && defaultTargetPlatform != TargetPlatform.android) return false;
  return true;
}
