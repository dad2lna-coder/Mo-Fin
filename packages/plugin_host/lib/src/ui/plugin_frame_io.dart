import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:server_core/server_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../js_bridge/host_api.dart';
import '../plugin_service.dart';

/// Native (IO) implementation of the plugin frame using `flutter_inappwebview`.
class PluginFrame extends StatefulWidget {
  final String entryUrl;
  final String pluginId;
  final PluginService pluginService;
  final HostApiHandler hostApiHandler;
  final WebViewEnvironment? webViewEnvironment;
  final int reloadToken;
  final ValueChanged<bool> onLoadingChanged;
  final ValueChanged<String?> onError;

  const PluginFrame({
    super.key,
    required this.entryUrl,
    required this.pluginId,
    required this.pluginService,
    required this.hostApiHandler,
    this.webViewEnvironment,
    required this.reloadToken,
    required this.onLoadingChanged,
    required this.onError,
  });

  @override
  State<PluginFrame> createState() => _PluginFrameState();
}

class _PluginFrameState extends State<PluginFrame> {
  InAppWebViewController? _webViewController;
  StreamSubscription<PluginEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = widget.pluginService.pluginEvents.listen((evt) {
      if (evt.pluginId == widget.pluginId) {
        _handleJsEvent(evt.data);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PluginFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _webViewController?.reload();
    }
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  void _handleJsEvent(dynamic eventData) async {
    final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!widget.hostApiHandler.isUrlUnderPluginFilesPath(currentUrl)) {
      return;
    }
    if (_webViewController != null) {
      final jsonStr = jsonEncode(eventData);
      final jsCall =
          'if(window.MoFinHost && window.MoFinHost._handleEvent){ window.MoFinHost._handleEvent($jsonStr); }';
      await _webViewController!.evaluateJavascript(source: jsCall);
    }
  }

  void _handleJsBridgeMessage(String rawJson) async {
    final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!widget.hostApiHandler.isUrlUnderPluginFilesPath(currentUrl)) {
      debugPrint(
        'PluginBridge: Discarded message from unauthorized origin/path: $currentUrl',
      );
      return;
    }

    final response = await widget.hostApiHandler.handleMessage(rawJson);
    final responseJson = jsonEncode(response);

    if (_webViewController != null) {
      final jsCall =
          'if(window.MoFinHost && window.MoFinHost._handleResponse){ window.MoFinHost._handleResponse($responseJson); }';
      await _webViewController!.evaluateJavascript(source: jsCall);
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

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      webViewEnvironment: widget.webViewEnvironment,
      initialUrlRequest: URLRequest(
        url: WebUri(widget.entryUrl),
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
        final requestUrl =
            navigationAction.request.url?.toString() ?? '';
        if (widget.hostApiHandler.isUrlUnderPluginFilesPath(requestUrl)) {
          return NavigationActionPolicy.ALLOW;
        }
        if (requestUrl.startsWith('http://') ||
            requestUrl.startsWith('https://')) {
          final uri = Uri.tryParse(requestUrl);
          if (uri != null) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
        }
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStart: (controller, url) {
        widget.onLoadingChanged(true);
        widget.onError(null);
      },
      onLoadStop: (controller, url) async {
        widget.onLoadingChanged(false);
        final currentUrlStr = url?.toString() ?? '';
        if (widget.hostApiHandler.isUrlUnderPluginFilesPath(currentUrlStr)) {
          final script = HostApiHandler.getBridgeInjectionScript();
          await controller.evaluateJavascript(source: script);
        }
      },
      onReceivedError: (controller, request, error) {
        widget.onLoadingChanged(false);
        widget.onError(error.description);
      },
    );
  }
}
