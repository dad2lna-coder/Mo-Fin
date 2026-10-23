import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
