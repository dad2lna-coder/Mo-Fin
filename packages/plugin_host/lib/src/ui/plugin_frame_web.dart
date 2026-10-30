import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../js_bridge/host_api.dart';
import '../js_bridge/plugin_frame_protocol.dart';
import '../plugin_service.dart';

int _nextViewTypeCounter = 0;

/// Web implementation of the plugin frame using a sandboxed `HTMLIFrameElement`.
class PluginFrame extends StatefulWidget {
  final String entryUrl;
  final String pluginId;
  final PluginService pluginService;
  final HostApiHandler hostApiHandler;
  final dynamic webViewEnvironment;
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
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _messageEventListener;
  JSFunction? _loadEventListener;
  StreamSubscription<PluginEvent>? _eventSubscription;

  late String _nonce;
  int _loadCount = 0;
  bool _isBridgeDead = false;

  @override
  void initState() {
    super.initState();
    _generateNonce();
    final count = ++_nextViewTypeCounter;
    _viewType = 'mofin-plugin-frame-${widget.pluginId}-$count';

    _eventSubscription = widget.pluginService.pluginEvents.listen((evt) {
      if (evt.pluginId == widget.pluginId) {
        _handleJsEvent(evt.data);
      }
    });

    _messageEventListener = ((web.MessageEvent event) {
      _handleMessageEvent(event);
    }).toJS;
    web.window.addEventListener('message', _messageEventListener);

    _registerViewFactory();
  }

  void _generateNonce() {
    final random = math.Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    _nonce = base64Url.encode(bytes);
  }

  void _registerViewFactory() {
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _buildIFrame(),
    );
  }

  web.HTMLIFrameElement _buildIFrame() {
    _loadCount = 0;
    _isBridgeDead = false;

    final iframe = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..setAttribute(
        'sandbox',
        'allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox',
      )
      ..setAttribute('referrerpolicy', 'no-referrer');

    final fullUrl = widget.hostApiHandler.resolvePluginFileUrl(widget.entryUrl);
    iframe.src = '$fullUrl#mofinNonce=$_nonce';

    _loadEventListener = ((web.Event _) {
      _loadCount++;
      if (_loadCount == 1) {
        widget.onLoadingChanged(false);
      } else if (_loadCount > 1) {
        // Subsequent navigation in sandboxed iframe marks bridge dead
        _isBridgeDead = true;
      }
    }).toJS;

    iframe.addEventListener('load', _loadEventListener);
    _iframe = iframe;
    return iframe;
  }

  @override
  void didUpdateWidget(covariant PluginFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _reloadIFrame();
    }
  }

  void _reloadIFrame() {
    _generateNonce();
    _loadCount = 0;
    _isBridgeDead = false;
    widget.onLoadingChanged(true);
    widget.onError(null);

    final iframe = _iframe;
    if (iframe != null) {
      final fullUrl =
          widget.hostApiHandler.resolvePluginFileUrl(widget.entryUrl);
      iframe.src = '$fullUrl#mofinNonce=$_nonce';
    }
  }

  void _handleMessageEvent(web.MessageEvent event) async {
    if (_isBridgeDead) return;

    final iframe = _iframe;
    if (iframe == null) return;

    final contentWindow = iframe.contentWindow;
    if (contentWindow == null) return;

    // Check message source is iframe.contentWindow and origin is 'null' (opaque origin)
    if (event.source != contentWindow) return;
    if (event.origin != 'null') return;

    final dataAny = event.data;
    if (dataAny == null) return;

    Map<String, dynamic> envelopeMap;
    try {
      final dartified = dataAny.dartify();
      if (dartified is Map) {
        envelopeMap = Map<String, dynamic>.from(dartified);
      } else if (dartified is String) {
        final decoded = jsonDecode(dartified);
        if (decoded is Map) {
          envelopeMap = Map<String, dynamic>.from(decoded);
        } else {
          return;
        }
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    final payloadStr = PluginFrameProtocol.validateIncomingEnvelope(
      envelopeMap,
      expectedNonce: _nonce,
    );
    if (payloadStr == null) return;

    final responseMap = await widget.hostApiHandler.handleMessage(payloadStr);
    final responseEnvelope = PluginFrameProtocol.buildResponseEnvelope(
      nonce: _nonce,
      responseData: responseMap,
    );

    try {
      contentWindow.postMessage(responseEnvelope.jsify(), '*'.toJS);
    } catch (e) {
      debugPrint('PluginFrameWeb: Failed to post response to iframe: $e');
    }
  }

  void _handleJsEvent(dynamic eventData) {
    if (_isBridgeDead) return;

    final iframe = _iframe;
    if (iframe == null) return;

    final contentWindow = iframe.contentWindow;
    if (contentWindow == null) return;

    final eventEnvelope = PluginFrameProtocol.buildEventEnvelope(
      nonce: _nonce,
      eventData: eventData,
    );

    try {
      contentWindow.postMessage(eventEnvelope.jsify(), '*'.toJS);
    } catch (e) {
      debugPrint('PluginFrameWeb: Failed to post event to iframe: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    if (_messageEventListener != null) {
      web.window.removeEventListener('message', _messageEventListener);
    }
    if (_iframe != null && _loadEventListener != null) {
      _iframe!.removeEventListener('load', _loadEventListener);
    }
    _iframe = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
