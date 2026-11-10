# Games on TV (later)

The Games item is in the main nav now. While the plugin host system is supported
on Android TV and Fire TV via WebView (`isPluginHostSupported` returns `true`),
the embedded ROM Manager webview hub is currently bypassed on televisions
(`GamesNav.routeFor` directs TV environments to the native browser screens:
`GamesBrowserScreen` on Fire TV / Android TV and `GameLibraryScreen` on tvOS).
Non-Android TV environments (such as tvOS) and Linux have plugin host support
disabled.

A later step can run the games plugin inside the TV WebView. That pass has to
cover three things the phone hub does not:

1. **WebView focus.** The plugin iframe must take and release D-pad focus
   without trapping the user. Back has to leave the plugin the same way the
   phone hub sends `{type:'hostBack'}` before going Home.
2. **D-pad to arrow keys.** TV remotes do not produce pointer events. Map
   up/down/left/right/select to key events the plugin page already understands,
   and do not let those keys also move a Flutter focus ring behind the WebView.
3. **Gamepad.** A Bluetooth pad should reach the emulator, not the shell.
   The native player already does this; the plugin-on-TV path should reuse
   that routing instead of inventing a second one.

Android and Fire TV use the native `GamesBrowserScreen` which matches the iOS
ROM Manager layout. tvOS stays on `GameLibraryScreen`. The WebView idea stays
deferred.
