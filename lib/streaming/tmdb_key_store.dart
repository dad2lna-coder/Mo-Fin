import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'streaming_service.dart';

/// TMDB key for the Streaming tab. This is not [UserPreferences.tmdbApiKey]:
/// that preference is the plugin's plain value, and this one stays in the
/// platform secure store.
class TmdbKeyStore {
  TmdbKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const storageKey = 'mofin_streaming_tmdb_api_key';

  final FlutterSecureStorage _storage;

  Future<String> read() async {
    try {
      return (await _storage.read(key: storageKey))?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> write(String value) async {
    final trimmed = value.trim();
    try {
      if (trimmed.isEmpty) {
        await _storage.delete(key: storageKey);
        return;
      }
      await _storage.write(key: storageKey, value: trimmed);
    } catch (_) {}
  }
}

class StreamingSubscriptionPreferences {
  static const _prefKey = 'mofin_streaming_active_services';

  static Future<List<StreamingService>> readActiveServices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey);
      if (list == null || list.isEmpty) {
        return kStreamingServices;
      }
      final services = <StreamingService>[];
      for (final name in list) {
        for (final service in kStreamingServices) {
          if (service.name == name) {
            services.add(service);
          }
        }
      }
      return services.isEmpty ? kStreamingServices : services;
    } catch (_) {
      return kStreamingServices;
    }
  }

  static Future<void> writeActiveServices(List<StreamingService> services) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = services.map((s) => s.name).toList();
      await prefs.setStringList(_prefKey, list);
    } catch (_) {}
  }
}
