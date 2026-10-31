import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_host/plugin_host.dart';

import '../../../util/webview_environment.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';

/// Full-screen ROM Manager. No title bar; MoFin's own navigation chrome stays
/// so the bottom bar (or the toolbar, on web) is still there. The plugin frame
/// is pushed under the player rather than replaced, so iOS Safari keeps the
/// iframe alive while a game is running.
class GamesHubScreen extends StatefulWidget {
  const GamesHubScreen({
    super.key,
    @visibleForTesting this.useNavigationChrome = true,
  });

  /// Widget tests skip [NavigationLayout], which needs the signed-in shell.
  final bool useNavigationChrome;

  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen> {
  bool _handlingBack = false;

  PluginService? get _service => GetIt.instance.isRegistered<PluginService>()
      ? GetIt.instance<PluginService>()
      : null;

  PluginManifest? get _plugin {
    final service = _service;
    if (service == null || !service.pluginsEnabled) return null;
    return service.registry.gamesSlotPlugin;
  }

  @override
  void initState() {
    super.initState();
    _service?.registry.addListener(_onRegistry);
  }

  @override
  void dispose() {
    _service?.registry.removeListener(_onRegistry);
    super.dispose();
  }

  void _onRegistry() {
    if (mounted) setState(() {});
  }

  Future<void> _onBack() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      final plugin = _plugin;
      final service = _service;
      if (plugin != null && service != null) {
        final handled = await service.dispatchAndAwaitHandled(
          plugin.id,
          const {'type': 'hostBack'},
        );
        if (handled || !mounted) return;
      }
      if (!mounted) return;
      context.go(Destinations.home);
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugin = _plugin;
    final body = plugin == null || _service == null
        ? const _GamesEmpty()
        : PluginWebViewScreen(
            chromeless: true,
            title: plugin.name,
            pluginId: plugin.id,
            pluginService: _service!,
            entryUrl: plugin.entryUrl,
            webViewEnvironment: gWebViewEnvironment,
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onBack());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: widget.useNavigationChrome
            ? NavigationLayout(
                activeRoute: Destinations.games,
                child: body,
              )
            : body,
      ),
    );
  }
}

class _GamesEmpty extends StatelessWidget {
  const _GamesEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Install ROM Manager to see games here',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }
}
