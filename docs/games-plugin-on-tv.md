# Games on TV (later)

The Games item is in the main nav now. On Fire TV and tvOS it opens the native
game library. Plugins stay off on TV (`isPluginHostSupported` returns false),
so ROM Manager is not embedded there yet.

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
