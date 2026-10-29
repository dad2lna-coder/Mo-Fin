import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';
import '../models/plugin_ui_models.dart';
import '../plugin_registry.dart';

/// User and Server context passed to plugins (never contains access tokens).
class PluginUserContext {
  final String userId;
  final String username;
  final String serverName;

  const PluginUserContext({
    required this.userId,
    required this.username,
    required this.serverName,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'serverName': serverName,
    };
  }
}

typedef UserContextProvider = PluginUserContext? Function();
typedef ClientProvider = dynamic Function();
typedef OpenScreenCallback = void Function(String title, String url, String pluginId);
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
  final ClientProvider? clientProvider;
  final OpenScreenCallback? onOpenScreen;
  final PlayMediaCallback? onPlayMedia;
  final ToastCallback? onShowToast;
  final dynamic prefs;
  final Dio _dio;

  HostApiHandler({
    required this.pluginId,
    required this.registry,
    required this.userContextProvider,
    required this.prefs,
    this.clientProvider,
    this.onOpenScreen,
    this.onPlayMedia,
    this.onShowToast,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// Validates that a target URL is strictly under this plugin's own files path `/Moonfin/Plugins/{pluginId}/files/`.
  bool isUrlUnderPluginFilesPath(String url) {
    if (url.isEmpty) return false;
    final client = clientProvider?.call();
    final baseUrl = client?.baseUrl as String? ?? '';
    final filesPrefix = '/Moonfin/Plugins/$pluginId/files/';

    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (baseUrl.isNotEmpty && !url.startsWith(baseUrl)) {
        return false;
      }
      final uri = Uri.parse(url);
      return uri.path.startsWith(filesPrefix) || uri.path.contains(filesPrefix);
    }

    final cleanPath = url.startsWith('/') ? url : '/$url';
    return cleanPath.startsWith(filesPrefix) || cleanPath.startsWith('/files/');
  }

  /// Resolves relative plugin file URL to full `/Moonfin/Plugins/{pluginId}/files/{path}` URL
  String resolvePluginFileUrl(String path) {
    final client = clientProvider?.call();
    final baseUrl = client?.baseUrl as String? ?? '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final relativePath = path.startsWith('/') ? path.substring(1) : path;
    if (relativePath.startsWith('Moonfin/Plugins/$pluginId/files/')) {
      return baseUrl.isNotEmpty ? '$baseUrl/$relativePath' : '/$relativePath';
    }
    if (relativePath.startsWith('files/')) {
      final sub = relativePath.substring(6);
      return '$baseUrl/Moonfin/Plugins/$pluginId/files/$sub';
    }
    return '$baseUrl/Moonfin/Plugins/$pluginId/files/$relativePath';
  }

  /// Handles an incoming bridge message string from JavaScript.
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
        final map = context.toJson();
        // Security requirement: Ensure token is never returned
        map.remove('token');
        map.remove('accessToken');
        return map;

      case 'openPluginScreen':
        final title = params['title'] as String? ?? 'Plugin';
        final rawUrl = params['url'] as String? ?? '';
        if (rawUrl.isEmpty) throw Exception('Missing url parameter');
        if (!isUrlUnderPluginFilesPath(rawUrl)) {
          throw Exception('Access denied: openPluginScreen URL must be under plugin files path');
        }
        final url = resolvePluginFileUrl(rawUrl);
        onOpenScreen?.call(title, url, pluginId);
        return true;

      case 'registerHomeRow':
        final row = PluginHomeRow.fromJson(params, pluginId);
        registry.registerHomeRow(row);
        return true;

      case 'registerSettingsPage':
        final rawUrl = params['url'] as String? ?? '';
        if (rawUrl.isNotEmpty && !isUrlUnderPluginFilesPath(rawUrl)) {
          throw Exception('Access denied: registerSettingsPage URL must be under plugin files path');
        }
        final entry = PluginSettingsEntry(
          id: params['id'] as String? ?? 'setting-${DateTime.now().millisecondsSinceEpoch}',
          pluginId: pluginId,
          title: params['title'] as String? ?? 'Plugin Settings',
          url: resolvePluginFileUrl(rawUrl),
        );
        registry.registerSettingsEntry(entry);
        return true;

      case 'registerNavItem':
        final rawUrl = params['url'] as String? ?? '';
        if (rawUrl.isNotEmpty && !isUrlUnderPluginFilesPath(rawUrl)) {
          throw Exception('Access denied: registerNavItem URL must be under plugin files path');
        }
        final item = PluginNavItem(
          id: params['id'] as String? ?? 'nav-${DateTime.now().millisecondsSinceEpoch}',
          pluginId: pluginId,
          title: params['title'] as String? ?? 'Plugin',
          icon: params['icon'] as String? ?? 'extension',
          url: resolvePluginFileUrl(rawUrl),
        );
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
      case 'dataGet':
        final key = params['key'] as String? ?? '';
        if (key.isEmpty) throw Exception('Missing data key');
        return await _serverDataGet(key);

      case 'storageSet':
      case 'dataPut':
        final key = params['key'] as String? ?? '';
        if (key.isEmpty) throw Exception('Missing data key');
        final value = params['value'];
        if (value == null) {
          return await _serverDataDelete(key);
        }
        return await _serverDataPut(key, value);

      case 'dataDelete':
        final key = params['key'] as String? ?? '';
        if (key.isEmpty) throw Exception('Missing data key');
        return await _serverDataDelete(key);

      case 'proxy':
        return await _serverProxy(params);

      case 'callPluginRoute':
        final path = params['path'] as String? ?? '';
        final httpMethod = (params['method'] as String? ?? 'GET').toUpperCase();
        final body = params['data'] ?? params['body'];
        return await _serverCallPluginRoute(path, httpMethod, body);

      default:
        throw Exception('Unknown host API method: $method');
    }
  }

  Future<Options> _buildHostAuthOptions() async {
    final client = clientProvider?.call();
    if (client == null) throw Exception('No active media server client');
    final token = client.accessToken as String? ?? '';
    return Options(
      headers: {
        if (token.isNotEmpty)
          'Authorization': buildServerAuthorizationHeader(
            scheme: 'MediaBrowser',
            deviceInfo: client.deviceInfo,
            accessToken: token,
          ),
      },
    );
  }

  String _buildServerUrl(String subPath) {
    final client = clientProvider?.call();
    final baseUrl = client?.baseUrl as String? ?? '';
    if (baseUrl.isEmpty) throw Exception('No active server URL');
    final cleanSub = subPath.startsWith('/') ? subPath.substring(1) : subPath;
    return '$baseUrl/$cleanSub';
  }

  Future<dynamic> _serverDataGet(String key) async {
    final options = await _buildHostAuthOptions();
    final url = _buildServerUrl('Moonfin/Plugins/$pluginId/Data/${Uri.encodeComponent(key)}');
    try {
      final res = await _dio.get(url, options: options);
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<bool> _serverDataPut(String key, dynamic value) async {
    final options = await _buildHostAuthOptions();
    options.headers?['Content-Type'] = 'application/json';
    final url = _buildServerUrl('Moonfin/Plugins/$pluginId/Data/${Uri.encodeComponent(key)}');
    final data = value is String || value is Map || value is List ? value : jsonEncode(value);
    await _dio.put(url, data: data, options: options);
    return true;
  }

  Future<bool> _serverDataDelete(String key) async {
    final options = await _buildHostAuthOptions();
    final url = _buildServerUrl('Moonfin/Plugins/$pluginId/Data/${Uri.encodeComponent(key)}');
    await _dio.delete(url, options: options);
    return true;
  }

  Future<dynamic> _serverProxy(Map<String, dynamic> params) async {
    final options = await _buildHostAuthOptions();
    options.headers?['Content-Type'] = 'application/json';
    final url = _buildServerUrl('Moonfin/Plugins/$pluginId/Proxy');
    final res = await _dio.post(url, data: params, options: options);
    return res.data;
  }

  Future<dynamic> _serverCallPluginRoute(String path, String method, dynamic body) async {
    final options = await _buildHostAuthOptions();
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final url = _buildServerUrl('Moonfin/Plugins/$pluginId/$cleanPath');

    Response res;
    switch (method) {
      case 'POST':
        options.headers?['Content-Type'] = 'application/json';
        res = await _dio.post(url, data: body, options: options);
        break;
      case 'PUT':
        options.headers?['Content-Type'] = 'application/json';
        res = await _dio.put(url, data: body, options: options);
        break;
      case 'DELETE':
        res = await _dio.delete(url, options: options);
        break;
      default:
        res = await _dio.get(url, options: options);
        break;
    }
    return res.data;
  }

  /// Injected JavaScript preamble establishing `window.MoFinHost` JavaScript bridge.
  static String getBridgeInjectionScript() {
    return '''
      (function() {
        if (window.MoFinHost) return;
        window.MoFinHost = {
          _callbackMap: {},
          _callbackIdCounter: 0,
          _eventListeners: [],

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

          onEvent: function(callback) {
            if (typeof callback === 'function') {
              this._eventListeners.push(callback);
            }
          },

          _handleEvent: function(evt) {
            this._eventListeners.forEach(cb => {
              try { cb(evt); } catch(e) { console.error('Error in event listener:', e); }
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
