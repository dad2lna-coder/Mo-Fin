import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:server_core/server_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../plugin_service.dart';
import '../js_bridge/host_api.dart';
import '../models/plugin_manifest.dart';
import 'plugin_host_strings.dart';

/// Screen component rendering a web plugin inside a locked down InAppWebView container.
class PluginWebViewScreen extends StatefulWidget {
  final String title;
  final String pluginId;
  final PluginService pluginService;
  final String? entryUrl;
  final WebViewEnvironment? webViewEnvironment;
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
  InAppWebViewController? _webViewController;
  late final HostApiHandler _hostApiHandler;
  StreamSubscription<PluginEvent>? _eventSubscription;
  bool _isLoading = true;
  String? _errorMessage;
  PluginManifest? _manifest;
  final FocusNode _tvFocusNode = FocusNode(debugLabel: 'PluginWebViewTvFocus');

  @override
  void initState() {
    super.initState();
    _hostApiHandler = widget.pluginService.createHostApiHandler(widget.pluginId);
    _eventSubscription = widget.pluginService.pluginEvents.listen((evt) {
      if (evt.pluginId == widget.pluginId) {
        _handleJsEvent(evt.data);
      }
    });
    _resolveManifest();
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    _tvFocusNode.dispose();
    super.dispose();
  }

  void _handleJsEvent(dynamic eventData) async {
    final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!_hostApiHandler.isUrlUnderPluginFilesPath(currentUrl)) {
      return;
    }
    if (_webViewController != null) {
      final jsonStr = jsonEncode(eventData);
      final jsCall =
          'if(window.MoFinHost && window.MoFinHost._handleEvent){ window.MoFinHost._handleEvent($jsonStr); }';
      await _webViewController!.evaluateJavascript(source: jsCall);
    }
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

  Map<String, String> _buildAuthHeaders() {
    final client = widget.pluginService.clientProvider?.call();
    if (client == null) return {};
    final token = client.accessToken as String? ?? '';
    if (token.isEmpty) return {};
    return {
      'Authorization': buildServerAuthorizationHeader(
        scheme: 'MediaBrowser',
        deviceInfo: client.deviceInfo,
        accessToken: token,
      ),
    };
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

  void _handleJsBridgeMessage(String rawJson) async {
    // Check current main frame URL per message
    final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!_hostApiHandler.isUrlUnderPluginFilesPath(currentUrl)) {
      debugPrint('PluginBridge: Discarded message from unauthorized origin/path: $currentUrl');
      return;
    }

    final response = await _hostApiHandler.handleMessage(rawJson);
    final responseJson = jsonEncode(response);

    if (_webViewController != null) {
      final jsCall =
          'if(window.MoFinHost && window.MoFinHost._handleResponse){ window.MoFinHost._handleResponse($responseJson); }';
      await _webViewController!.evaluateJavascript(source: jsCall);
    }
  }

  bool _isUnsupportedPlatform() {
    if (kIsWeb) return true;
    final target = defaultTargetPlatform;
    return target == TargetPlatform.linux;
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
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _webViewController?.reload();
            },
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
              InAppWebView(
                webViewEnvironment: widget.webViewEnvironment,
                initialUrlRequest: URLRequest(
                  url: WebUri(entryUrl),
                  headers: _buildAuthHeaders(),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'MoFinPluginBridge',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _handleJsBridgeMessage(args[0].toString());
                      }
                    },
                  );
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final requestUrl = navigationAction.request.url?.toString() ?? '';
                  if (_hostApiHandler.isUrlUnderPluginFilesPath(requestUrl)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (requestUrl.startsWith('http://') || requestUrl.startsWith('https://')) {
                    final uri = Uri.tryParse(requestUrl);
                    if (uri != null) {
                      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
                    }
                  }
                  return NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    _isLoading = false;
                  });
                  final currentUrlStr = url?.toString() ?? '';
                  if (_hostApiHandler.isUrlUnderPluginFilesPath(currentUrlStr)) {
                    final script = HostApiHandler.getBridgeInjectionScript();
                    await controller.evaluateJavascript(source: script);
                  }
                },
                onReceivedError: (controller, request, error) {
                  setState(() {
                    _isLoading = false;
                    _errorMessage = widget.strings.loadFailedWithError(error.description);
                  });
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
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _webViewController?.reload();
                        },
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
