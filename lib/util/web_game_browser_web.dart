import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_game_full_page.dart';

String browserUserAgent() => web.window.navigator.userAgent;

int browserMaxTouchPoints() => web.window.navigator.maxTouchPoints;

String browserHref() => web.window.location.href;

void assignBrowserLocation(String url) {
  web.window.location.assign(url);
}

String? readSession(String key) {
  try {
    return web.window.sessionStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeSession(String key, String value) {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {}
}

void removeSession(String key) {
  try {
    web.window.sessionStorage.removeItem(key);
  } catch (_) {}
}

StreamSubscription<web.Event>? _pageShow;

/// Back from the player can restore this document from the back-forward
/// cache. The in-memory app is already on the right screen, so drop the
/// snapshot or the next full load would navigate there again.
void installBrowserGameReturnListener() {
  if (_pageShow != null) return;
  _pageShow = web.EventStreamProviders.pageShowEvent.forTarget(web.window).listen((
    event,
  ) {
    if (!event.isA<web.PageTransitionEvent>()) return;
    if ((event as web.PageTransitionEvent).persisted) {
      removeSession(WebGameReturnSnapshot.storageKey);
    }
  });
}
