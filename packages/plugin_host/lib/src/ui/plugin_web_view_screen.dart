import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../plugin_service.dart';
import '../js_bridge/host_api.dart';

/// Screen component rendering a web plugin inside an InAppWebView container.
class PluginWebViewScreen extends StatefulWidget {
  final String title;
  final String entryUrl;
  final String pluginId;
  final PluginService pluginService;

  const PluginWebViewScreen({
    super.key,
    required this.title,
    required this.entryUrl,
    required this.pluginId,
    required this.pluginService,
  });

  @override
  State<PluginWebViewScreen> createState() => _PluginWebViewScreenState();
}

class _PluginWebViewScreenState extends State<PluginWebViewScreen> {
  InAppWebViewController? _webViewController;
  late final HostApiHandler _hostApiHandler;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _hostApiHandler = widget.pluginService.createHostApiHandler(widget.pluginId);
  }

  void _handleJsBridgeMessage(String rawJson) async {
    final response = await _hostApiHandler.handleMessage(rawJson);
    final responseJson = jsonEncode(response);

    if (_webViewController != null) {
      final jsCall = 'if(window.MoFinHost && window.MoFinHost._handleResponse){ window.MoFinHost._handleResponse($responseJson); }';
      await _webViewController!.evaluateJavascript(source: jsCall);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
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
      body: Stack(
        children: [
          if (_errorMessage == null)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.entryUrl)),
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
                final script = HostApiHandler.getBridgeInjectionScript();
                await controller.evaluateJavascript(source: script);
              },
              onReceivedError: (controller, request, error) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Failed to load plugin: ${error.description}';
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
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
