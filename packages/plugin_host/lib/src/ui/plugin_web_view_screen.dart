import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../js_bridge/host_api.dart';
import '../models/plugin_manifest.dart';
import '../plugin_service.dart';
import 'plugin_frame_io.dart'
    if (dart.library.js_interop) 'plugin_frame_web.dart';
import 'plugin_host_strings.dart';

/// Screen component rendering a web plugin inside a locked down container.
class PluginWebViewScreen extends StatefulWidget {
  final String title;
  final String pluginId;
  final PluginService pluginService;
  final String? entryUrl;
  final dynamic webViewEnvironment;
  final PluginHostStrings strings;

  const PluginWebViewScreen({
    super.key,
    required this.title,
    required this.pluginId,
    required this.pluginService,
    this.entryUrl,
    this.webViewEnvironment,
    this.strings = const PluginHostStrings(),
  });

  @override
  State<PluginWebViewScreen> createState() => _PluginWebViewScreenState();
}

class _PluginWebViewScreenState extends State<PluginWebViewScreen> {
  late final HostApiHandler _hostApiHandler;
  bool _isLoading = true;
  String? _errorMessage;
  PluginManifest? _manifest;
  int _reloadToken = 0;
  final FocusNode _tvFocusNode = FocusNode(debugLabel: 'PluginWebViewTvFocus');

  @override
  void initState() {
    super.initState();
    _hostApiHandler =
        widget.pluginService.createHostApiHandler(widget.pluginId);
    _resolveManifest();
  }

  @override
  void dispose() {
    _tvFocusNode.dispose();
    super.dispose();
  }

  void _resolveManifest() {
    final registry = widget.pluginService.registry;
    final manifest = registry.plugins[widget.pluginId];

    if (!widget.pluginService.pluginsEnabled) {
      _errorMessage = widget.strings.hostDisabled;
      _isLoading = false;
      return;
    }

    if (manifest == null || !registry.isPluginEnabled(widget.pluginId)) {
      _errorMessage = widget.strings.pluginNotLoaded(widget.pluginId);
      _isLoading = false;
      return;
    }

    _manifest = manifest;

    final candidate = (widget.entryUrl != null && widget.entryUrl!.isNotEmpty)
        ? widget.entryUrl!
        : manifest.entryUrl;

    if (candidate.isEmpty ||
        !_hostApiHandler.isUrlUnderPluginFilesPath(candidate)) {
      _errorMessage = widget.strings.unauthorizedEntryUrl;
      _isLoading = false;
      return;
    }
  }

  String get _resolvedEntryUrl {
    final candidate = (widget.entryUrl != null && widget.entryUrl!.isNotEmpty)
        ? widget.entryUrl!
        : (_manifest?.entryUrl ?? '');
    if (candidate.isNotEmpty &&
        _hostApiHandler.isUrlUnderPluginFilesPath(candidate)) {
      return _hostApiHandler.resolvePluginFileUrl(candidate);
    }
    return '';
  }

  bool _isUnsupportedPlatform() {
    if (kIsWeb) return false;
    final target = defaultTargetPlatform;
    return target == TargetPlatform.linux;
  }

  void _triggerReload() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _reloadToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnsupportedPlatform()) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              widget.strings.unsupportedOnDevice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    final entryUrl = _resolvedEntryUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: widget.strings.reload,
            onPressed: _triggerReload,
          ),
        ],
      ),
      body: Focus(
        focusNode: _tvFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            if (_errorMessage == null && entryUrl.isNotEmpty)
              PluginFrame(
                entryUrl: entryUrl,
                pluginId: widget.pluginId,
                pluginService: widget.pluginService,
                hostApiHandler: _hostApiHandler,
                webViewEnvironment: widget.webViewEnvironment,
                reloadToken: _reloadToken,
                onLoadingChanged: (loading) {
                  if (mounted) setState(() => _isLoading = loading);
                },
                onError: (error) {
                  if (mounted) {
                    setState(() {
                      _errorMessage = error != null
                          ? widget.strings.loadFailedWithError(error)
                          : null;
                    });
                  }
                },
              ),
            if (_isLoading && _errorMessage == null)
              const Center(child: CircularProgressIndicator()),
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _triggerReload,
                        child: Text(widget.strings.retry),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
