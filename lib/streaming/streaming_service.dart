/// The four subscriptions this tab knows about. Provider ids are not stored
/// here: TMDB's `/watch/providers` list is matched by name at runtime.
enum StreamingService {
  netflix,
  disneyPlus,
  max,
  primeVideo,
}

extension StreamingServiceInfo on StreamingService {
  String get label => switch (this) {
        StreamingService.netflix => 'Netflix',
        StreamingService.disneyPlus => 'Disney+',
        StreamingService.max => 'Max',
        StreamingService.primeVideo => 'Prime Video',
      };

  /// Short badge text so four of them still fit under a poster.
  String get badge => switch (this) {
        StreamingService.netflix => 'Netflix',
        StreamingService.disneyPlus => 'Disney+',
        StreamingService.max => 'Max',
        StreamingService.primeVideo => 'Prime',
      };

  int get colorValue => switch (this) {
        StreamingService.netflix => 0xFFE50914,
        StreamingService.disneyPlus => 0xFF113CCF,
        StreamingService.max => 0xFF002BE7,
        StreamingService.primeVideo => 0xFF00A8E1,
      };

  /// Fire TV package first, then the Android package when it differs.
  ///
  /// Netflix on Fire TV is `com.netflix.ninja` (the phone app is
  /// `com.netflix.mediaclient`). Disney+ is `com.disney.disneyplus` on both.
  /// Max on Fire TV is `com.wbd.stream`; older sticks still have
  /// `com.hbo.hbonow`. Prime Video on Fire TV is `com.amazon.firebat`.
  /// `com.amazon.avod` is the older Fire OS package, and
  /// `com.amazon.avod.thirdpartyclient` is the Appstore build.
  List<String> get androidPackages => switch (this) {
        StreamingService.netflix => const [
            'com.netflix.ninja',
            'com.netflix.mediaclient',
          ],
        StreamingService.disneyPlus => const ['com.disney.disneyplus'],
        StreamingService.max => const [
            'com.wbd.stream',
            'com.hbo.hbonow',
          ],
        StreamingService.primeVideo => const [
            'com.amazon.firebat',
            'com.amazon.avod',
            'com.amazon.avod.thirdpartyclient',
          ],
      };

  /// VIEW intent the installed app can open on the title, or null when that
  /// app has no search deep link worth trying. Disney+ on Android TV only
  /// deep links by its own content id, so the launcher just opens the app.
  String? androidSearchUrl(String title) {
    final query = Uri.encodeQueryComponent(title.trim());
    if (query.isEmpty) return null;
    return switch (this) {
      StreamingService.netflix => 'https://www.netflix.com/search?q=$query',
      StreamingService.disneyPlus => null,
      StreamingService.max => 'https://play.max.com/search?q=$query',
      StreamingService.primeVideo =>
        'https://www.amazon.com/gp/video/search/?phrase=$query',
    };
  }

  /// Website search opened in a new tab. These are not played inside Mo-Fin.
  Uri webSearchUri(String title) {
    final query = Uri.encodeQueryComponent(title.trim());
    final url = switch (this) {
      StreamingService.netflix => 'https://www.netflix.com/search?q=$query',
      StreamingService.disneyPlus =>
        'https://www.disneyplus.com/search?q=$query',
      StreamingService.max => 'https://play.max.com/search?q=$query',
      StreamingService.primeVideo =>
        'https://www.amazon.com/gp/video/search/?phrase=$query',
    };
    return Uri.parse(url);
  }
}

/// Exact TMDB `provider_name` values for the four subscriptions. Ad tiers
/// and "Amazon Channel" add-ons share the brand but are different providers,
/// so a substring match would let them in.
StreamingService? streamingServiceForProviderName(String providerName) {
  return switch (providerName.trim().toLowerCase()) {
    'netflix' => StreamingService.netflix,
    'disney plus' || 'disney+' => StreamingService.disneyPlus,
    'max' || 'hbo max' => StreamingService.max,
    'amazon prime video' || 'prime video' => StreamingService.primeVideo,
    _ => null,
  };
}

const List<StreamingService> kStreamingServices = [
  StreamingService.netflix,
  StreamingService.disneyPlus,
  StreamingService.max,
  StreamingService.primeVideo,
];
