import 'dart:convert';
import '../models/plugin_ui_models.dart';
import '../plugin_registry.dart';

/// User and Server context passed to plugins for scoped Jellyfin API calls.
class PluginUserContext {
  final String userId;
  final String username;
  final String serverUrl;
  final String token;

  const PluginUserContext({
    required this.userId,
    required this.username,
    required this.serverUrl,
    required this.token,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'serverUrl': serverUrl,
      'token': token,
    };
  }
}

typedef UserContextProvider = PluginUserContext? Function();
typedef OpenScreenCallback = void Function(String title, String url);
typedef PlayMediaCallback = void Function({
  String? jellyfinItemId,
  String? streamUrl,
  String? title,
});
typedef ToastCallback = void Function(String message);

/// Handles versioned JavaScript bridge API method calls (`hostApi = 1`).
class HostApiHandler {
  static const int currentHostApiVersion = 1;

  final String pluginId;
  final PluginRegistry registry;
  final UserContextProvider userContextProvider;
  final OpenScreenCallback? onOpenScreen;
  final PlayMediaCallback? onPlayMedia;
  final ToastCallback? onShowToast;
  final dynamic prefs;

  HostApiHandler({
    required this.pluginId,
    required this.registry,
    required this.userContextProvider,
    required this.prefs,
    this.onOpenScreen,
    this.onPlayMedia,
    this.onShowToast,
  });

  /// Handles an incoming bridge message string from JavaScript.
  /// Expects JSON payload: `{ "method": "...", "params": {...}, "callbackId": "..." }`.
  Future<Map<String, dynamic>> handleMessage(String rawJson) async {
    Map<String, dynamic> request;
    try {
      request = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (e) {
      return {
        'ok': false,
        'error': 'Invalid JSON format: $e',
      };
    }

    final method = request['method'] as String? ?? '';
    final params = (request['params'] as Map<String, dynamic>?) ?? {};
    final callbackId = request['callbackId'] as String?;

    try {
      final result = await _executeMethod(method, params);
      return {
        'ok': true,
        'result': result,
        if (callbackId != null) 'callbackId': callbackId,
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
        if (callbackId != null) 'callbackId': callbackId,
      };
    }
  }

  Future<dynamic> _executeMethod(String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'getHostApiVersion':
        return {'hostApi': currentHostApiVersion};

      case 'getUserContext':
        final context = userContextProvider();
        if (context == null) {
          throw Exception('No active user context available');
        }
        return context.toJson();

      case 'openPluginScreen':
        final title = params['title'] as String? ?? 'Plugin';
        final url = params['url'] as String? ?? '';
        if (url.isEmpty) throw Exception('Missing url parameter');
        onOpenScreen?.call(title, url);
        return true;

      case 'registerHomeRow':
        final row = PluginHomeRow.fromJson(params, pluginId);
        registry.registerHomeRow(row);
        return true;

      case 'registerSettingsPage':
        final entry = PluginSettingsEntry.fromJson(params, pluginId);
        registry.registerSettingsEntry(entry);
        return true;

      case 'registerNavItem':
        final item = PluginNavItem.fromJson(params, pluginId);
        registry.registerNavItem(item);
        return true;

      case 'playMedia':
        onPlayMedia?.call(
          jellyfinItemId: params['jellyfinItemId'] as String?,
          streamUrl: params['streamUrl'] as String?,
          title: params['title'] as String?,
        );
        return true;

      case 'showToast':
        final message = params['message'] as String? ?? '';
        if (message.isNotEmpty) {
          onShowToast?.call(message);
        }
        return true;

      case 'storageGet':
        final key = params['key'] as String? ?? '';
        if (key.isEmpty) throw Exception('Missing storage key');
        final storageKey = 'plugin_${pluginId}_$key';
        return prefs.getString(storageKey);

      case 'storageSet':
        final key = params['key'] as String? ?? '';
        final value = params['value'] as String?;
        if (key.isEmpty) throw Exception('Missing storage key');
        final storageKey = 'plugin_${pluginId}_$key';
        if (value == null) {
          await prefs.remove(storageKey);
        } else {
          await prefs.setString(storageKey, value);
        }
        return true;

      default:
        throw Exception('Unknown host API method: $method');
    }
  }

  /// Injected JavaScript preamble establishing `window.MoFinHost` JavaScript bridge.
  static String getBridgeInjectionScript() {
    return '''
      (function() {
        if (window.MoFinHost) return;
        window.MoFinHost = {
          _callbackMap: {},
          _callbackIdCounter: 0,

          call: function(method, params) {
            return new Promise((resolve, reject) => {
              const callbackId = 'cb_' + (++this._callbackIdCounter) + '_' + Date.now();
              this._callbackMap[callbackId] = { resolve, reject };

              const payload = JSON.stringify({
                method: method,
                params: params || {},
                callbackId: callbackId
              });

              if (window.MoFinPluginBridge && window.MoFinPluginBridge.postMessage) {
                window.MoFinPluginBridge.postMessage(payload);
              } else if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('MoFinPluginBridge', payload);
              } else {
                delete this._callbackMap[callbackId];
                reject(new Error('MoFinPluginBridge JavaScript interface not available'));
              }
            });
          },

          _handleResponse: function(jsonStr) {
            try {
              const response = typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr;
              const callbackId = response.callbackId;
              if (callbackId && this._callbackMap[callbackId]) {
                const { resolve, reject } = this._callbackMap[callbackId];
                delete this._callbackMap[callbackId];
                if (response.ok) {
                  resolve(response.result);
                } else {
                  reject(new Error(response.error || 'Unknown bridge error'));
                }
              }
            } catch(e) {
              console.error('Error handling MoFinHost response:', e);
            }
          }
        };
      })();
    ''';
  }
}
