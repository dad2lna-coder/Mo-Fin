import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/streaming/streaming_service.dart';

void main() {
  group('StreamingService Deep Links', () {
    test('providerUrl beats id/search for each service', () {
      for (final service in StreamingService.values) {
        const customUrl = 'https://custom.provider.com/watch/12345';
        final androidUri = service.androidTitleUri('fallback_id', providerUrl: customUrl);
        expect(androidUri?.toString(), customUrl);

        final webUri = service.webUri(providerTitleId: 'fallback_id', providerUrl: customUrl, title: 'Test Title');
        expect(webUri.toString(), customUrl);

        final buttonText = service.watchButtonText(providerTitleId: null, providerUrl: customUrl, title: 'Test Title');
        expect(buttonText, 'Play on ${service.label}');

        final subtitle = service.watchButtonSubtitle(providerTitleId: null, providerUrl: customUrl, title: 'Test Title');
        expect(subtitle, isNull);
      }
    });

    test('Netflix deep link URLs and fallbacks', () {
      const service = StreamingService.netflix;
      expect(service.androidPackages, contains('com.netflix.ninja'));
      expect(service.androidPackages, contains('com.netflix.mediaclient'));

      // Direct title link
      final titleUri = service.androidTitleUri('80057281');
      expect(titleUri?.toString(), 'https://www.netflix.com/title/80057281');

      // Web direct title
      final webUri = service.webUri(providerTitleId: '80057281', title: 'Stranger Things');
      expect(webUri.toString(), 'https://www.netflix.com/title/80057281');

      // Fallback search
      final searchUrl = service.androidSearchUrl('Stranger Things');
      expect(searchUrl, 'https://www.netflix.com/search?q=Stranger%20Things');

      // Web fallback search when title ID is absent
      final webSearch = service.webUri(providerTitleId: null, title: 'Stranger Things');
      expect(webSearch.toString(), 'https://www.netflix.com/search?q=Stranger%20Things');

      // Button labels
      expect(
        service.watchButtonText(providerTitleId: '80057281', title: 'Stranger Things'),
        'Play on Netflix',
      );
      expect(
        service.watchButtonText(providerTitleId: null, title: 'Stranger Things'),
        'Search on Netflix',
      );
      expect(
        service.watchButtonSubtitle(providerTitleId: null, title: 'Stranger Things'),
        'Direct title link unavailable - opens search',
      );
    });

    test('Disney+ deep link URLs and fallbacks', () {
      const service = StreamingService.disneyPlus;
      expect(service.androidPackages, ['com.disney.disneyplus']);

      // Direct title link
      final titleUri = service.androidTitleUri('abc-123-disney');
      expect(titleUri?.toString(), 'https://www.disneyplus.com/browse/entity-abc-123-disney');

      // Web direct title
      final webUri = service.webUri(providerTitleId: 'abc-123-disney', title: 'The Mandalorian');
      expect(webUri.toString(), 'https://www.disneyplus.com/browse/entity-abc-123-disney');

      // Disney+ on Android TV has no search intent
      expect(service.androidSearchUrl('The Mandalorian'), isNull);

      // Button labels
      expect(
        service.watchButtonText(providerTitleId: 'abc-123-disney', title: 'The Mandalorian'),
        'Play on Disney+',
      );
      expect(
        service.watchButtonText(providerTitleId: null, title: 'The Mandalorian'),
        'Open Disney+',
      );
      expect(
        service.watchButtonSubtitle(providerTitleId: null, title: 'The Mandalorian'),
        'Direct title link unavailable - opens app home',
      );
    });

    test('Max deep link URLs and fallbacks', () {
      const service = StreamingService.max;
      expect(service.androidPackages, contains('com.wbd.stream'));

      // Direct title link
      final titleUri = service.androidTitleUri('max-title-101');
      expect(titleUri?.toString(), 'https://play.max.com/video/watch/max-title-101');

      // Web direct title
      final webUri = service.webUri(providerTitleId: 'max-title-101', title: 'Succession');
      expect(webUri.toString(), 'https://play.max.com/video/watch/max-title-101');

      // Fallback search
      final searchUrl = service.androidSearchUrl('Succession');
      expect(searchUrl, 'https://play.max.com/search?q=Succession');

      // Button labels
      expect(
        service.watchButtonText(providerTitleId: 'max-title-101', title: 'Succession'),
        'Play on Max',
      );
      expect(
        service.watchButtonText(providerTitleId: null, title: 'Succession'),
        'Search on Max',
      );
    });

    test('Prime Video deep link URLs and fallbacks', () {
      const service = StreamingService.primeVideo;
      expect(service.androidPackages, contains('com.amazon.firebat'));

      // Direct title link
      final titleUri = service.androidTitleUri('amzn1.dv.gti.123');
      expect(titleUri?.toString(), 'https://watch.amazon.com/watch?gti=amzn1.dv.gti.123');

      // Web direct title
      final webUri = service.webUri(providerTitleId: 'amzn1.dv.gti.123', title: 'The Boys');
      expect(webUri.toString(), 'https://www.primevideo.com/detail/amzn1.dv.gti.123');

      // Fallback search
      final searchUrl = service.androidSearchUrl('The Boys');
      expect(searchUrl, 'https://www.amazon.com/gp/video/search/?phrase=The%20Boys');

      // Button labels
      expect(
        service.watchButtonText(providerTitleId: 'amzn1.dv.gti.123', title: 'The Boys'),
        'Play on Prime Video',
      );
      expect(
        service.watchButtonText(providerTitleId: null, title: 'The Boys'),
        'Search on Prime Video',
      );
    });
  });
}
