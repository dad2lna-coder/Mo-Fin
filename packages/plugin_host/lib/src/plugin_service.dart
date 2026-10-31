import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';
import 'plugin_registry.dart';
import 'js_bridge/host_api.dart';

/// Event emitted over /Moonfin/Settings/Stream targeting a specific plugin.
class PluginEvent {
  final String pluginId;
  final String eventType;
  final dynamic data;

  const PluginEvent({
    required this.pluginId,
    required this.eventType,
    this.data,
  });
}

/// Main entry point for managing the MoFin Plugin Host subsystem.
class PluginService extends ChangeNotifier {
  final PluginRegistry registry;
  final _eventController = StreamController<PluginEvent>.broadcast();
  final dynamic prefs;
  final UserContextProvider userContextProvider;
  final OpenScreenCallback? onOpenScreen;
  final PlayMediaCallback? onPlayMedia;
  final PlayGameCallback? onPlayGame;
  final ToastCallback? onShowToast;
  final ClientProvider? clientProvider;
  final Dio _dio;

  bool _pluginsEnabled = false;
  int _replySeq = 0;
  final Map<String, Completer<bool>> _replies = {};

  PluginService({
    required this.registry,
    required this.prefs,
    required this.userContextProvider,
    this.clientProvider,
    this.onOpenScreen,
    this.onPlayMedia,
    this.onPlayGame,
    this.onShowToast,
    bool initialPluginsEnabled = false,
    Dio? dio,
  })  : _pluginsEnabled = initialPluginsEnabled,
        _dio = dio ?? Dio();

  bool get pluginsEnabled => _pluginsEnabled;

  Stream<PluginEvent> get pluginEvents => _eventController.stream;

  void dispatchPluginEvent(String pluginId, dynamic eventData) {
    _eventController.add(PluginEvent(
      pluginId: pluginId,
      eventType: eventData is Map ? (eventData['type'] as String? ?? '') : '',
      data: eventData,
    ));
  }

  /// Sends [event] to [pluginId] and waits for `replyHostEvent`.
  ///
  /// A plugin that returns `{handled: true}` from an `onEvent` listener, or
  /// calls `replyHostEvent` itself, completes this with true. Silence within
  /// [timeout] is treated as not handled.
  Future<bool> dispatchAndAwaitHandled(
    String pluginId,
    Map<String, dynamic> event, {
    Duration timeout = const Duration(milliseconds: 300),
  }) async {
    final replyId = 'r${++_replySeq}';
    final completer = Completer<bool>();
    _replies[replyId] = completer;
    dispatchPluginEvent(pluginId, {
      ...event,
      'replyId': replyId,
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return false;
    } finally {
      _replies.remove(replyId);
    }
  }

  void completeHostReply(String replyId, bool handled) {
    final completer = _replies.remove(replyId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(handled);
    }
  }

  void setPluginsEnabled(bool enabled) {
    if (_pluginsEnabled == enabled) return;
    _pluginsEnabled = enabled;
    if (enabled) {
      reloadPlugins();
    } else {
      registry.clear();
    }
    notifyListeners();
  }

  /// Reloads all plugin manifests from GET {server}/Moonfin/Plugins
  Future<void> reloadPlugins({
    Future<Map<String, dynamic>> Function(String url, Map<String, String> headers)? fetcher,
    String? deviceProfile,
  }) async {
    if (!_pluginsEnabled) {
      registry.clear();
      return;
    }

    final client = clientProvider?.call();
    if (client == null) {
      return;
    }

    final baseUrl = client.baseUrl as String? ?? '';
    if (baseUrl.isEmpty) return;

    final token = client.accessToken as String? ?? '';
    final headers = <String, String>{
      if (token.isNotEmpty)
        'Authorization': buildServerAuthorizationHeader(
          scheme: 'MediaBrowser',
          deviceInfo: client.deviceInfo,
          accessToken: token,
        ),
    };

    try {
      final pluginsUrl = '$baseUrl/Moonfin/Plugins';
      Map<String, dynamic> data;
      if (fetcher != null) {
        data = await fetcher(pluginsUrl, headers);
      } else {
        final response = await _dio.get(
          pluginsUrl,
          options: Options(headers: headers),
        );
        if (response.data is Map<String, dynamic>) {
          data = response.data as Map<String, dynamic>;
        } else if (response.data is String) {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        } else {
          data = {};
        }
      }

      registry.loadPluginsFromResponse(
        data,
        baseUrl: baseUrl,
        deviceProfile: deviceProfile,
      );

      // Query Ping for plugins map if available
      try {
        final pingUrl = '$baseUrl/Moonfin/Ping';
        final pingRes = await _dio.get(
          pingUrl,
          options: Options(headers: headers),
        );
        if (pingRes.data is Map<String, dynamic>) {
          final pingData = pingRes.data as Map<String, dynamic>;
          if (pingData['plugins'] is Map<String, dynamic>) {
            registry.setCapabilities(
              registry.capabilities,
              pingPlugins: Map<String, dynamic>.from(pingData['plugins'] as Map),
            );
          }
        }
      } catch (_) {}

    } catch (e) {
      debugPrint('PluginService.reloadPlugins failed: $e');
    }

    notifyListeners();
  }

  /// Creates a [HostApiHandler] instance bound to [pluginId].
  HostApiHandler createHostApiHandler(String pluginId) {
    return HostApiHandler(
      pluginId: pluginId,
      registry: registry,
      userContextProvider: userContextProvider,
      prefs: prefs,
      clientProvider: clientProvider,
      onOpenScreen: onOpenScreen,
      onPlayMedia: onPlayMedia,
      onPlayGame: onPlayGame,
      onHostReply: completeHostReply,
      onShowToast: onShowToast,
    );
  }
}
