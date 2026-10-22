import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Same hls.js bridge the full web player uses. Browsers will not start an
/// unmuted preview, and they cannot attach the playlist's request headers.
extension type _MoonfinHlsBridge._(JSObject _) implements JSObject {
  external JSBoolean canUseHlsJs(
    web.HTMLVideoElement video,
    JSString url,
    JSBoolean forceHls,
  );

  external JSAny? attach(
    web.HTMLVideoElement video,
    JSString url,
    JSBoolean forceHls,
  );

  external void destroy(JSAny? controller);
}

class DirectIptvPreviewPlayer extends StatefulWidget {
  final String? streamUrl;
  final Map<String, String> headers;

  const DirectIptvPreviewPlayer({
    super.key,
    required this.streamUrl,
    this.headers = const {},
  });

  @override
  State<DirectIptvPreviewPlayer> createState() =>
      _DirectIptvPreviewPlayerState();
}

class _DirectIptvPreviewPlayerState extends State<DirectIptvPreviewPlayer> {
  static final Set<String> _registered = <String>{};
  static final Map<String, _DirectIptvPreviewPlayerState> _owners =
      <String, _DirectIptvPreviewPlayerState>{};
  static int _nextId = 0;

  late final String _viewType;
  late final web.HTMLVideoElement _video;
  JSAny? _hls;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'moonfin-direct-preview-${++_nextId}';
    _owners[_viewType] = this;
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..controls = false
      ..muted = true
      ..preload = 'auto'
      ..loop = false
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.backgroundColor = 'black'
      ..style.pointerEvents = 'none';
    _video.setAttribute('playsinline', '');
    if (_registered.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int _) => (_owners[_viewType] ?? this)._video,
      );
    }
    _applySource();
  }

  @override
  void didUpdateWidget(covariant DirectIptvPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) _applySource();
  }

  _MoonfinHlsBridge? _bridge() {
    if (!web.window.has('MoonfinHlsBridge')) return null;
    final bridge = web.window.getProperty('MoonfinHlsBridge'.toJS);
    return _MoonfinHlsBridge._(bridge as JSObject);
  }

  void _destroyHls() {
    final controller = _hls;
    _hls = null;
    if (controller == null) return;
    try {
      _bridge()?.destroy(controller);
    } catch (_) {}
  }

  void _applySource() {
    if (_disposed) return;
    _destroyHls();
    final url = widget.streamUrl;
    if (url == null || url.isEmpty) {
      try {
        _video.pause();
        _video.removeAttribute('src');
        _video.load();
      } catch (_) {}
      return;
    }
    final forceHls = url.toLowerCase().contains('m3u8');
    final bridge = _bridge();
    var attached = false;
    if (bridge != null) {
      try {
        if (bridge.canUseHlsJs(_video, url.toJS, forceHls.toJS).toDart) {
          _hls = bridge.attach(_video, url.toJS, forceHls.toJS);
          attached = _hls != null;
        }
      } catch (_) {
        _hls = null;
      }
    }
    if (!attached) {
      _video.src = url;
      _video.load();
    }
    _video.muted = true;
    _video.play().toDart.catchError((Object _) => null);
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _video.pause();
      _video.removeAttribute('src');
      _video.load();
    } catch (_) {}
    _destroyHls();
    if (identical(_owners[_viewType], this)) _owners.remove(_viewType);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
