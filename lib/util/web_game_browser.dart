import 'package:flutter/foundation.dart';

import 'web_game_browser_stub.dart'
    if (dart.library.js_interop) 'web_game_browser_web.dart'
    as browser;
import 'web_game_full_page.dart';

export 'web_game_browser_stub.dart'
    if (dart.library.js_interop) 'web_game_browser_web.dart';

void rememberWebGameReturn(WebGameReturnSnapshot snapshot) {
  if (!kIsWeb) return;
  browser.writeSession(WebGameReturnSnapshot.storageKey, snapshot.encode());
}

/// Route to open after a full-page game, or null. Clears the snapshot.
String? consumeWebGameReturnRoute() {
  if (!kIsWeb) return null;
  final raw = browser.readSession(WebGameReturnSnapshot.storageKey);
  browser.removeSession(WebGameReturnSnapshot.storageKey);
  return WebGameReturnSnapshot.decode(raw)?.restoreRoute;
}
