import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/playlist_parse.dart';

void main() {
  test('web skips the member probe for anything that is not HLS', () {
    expect(
      shouldProbeMofinMember(
        isWeb: true,
        streamUrl: 'https://example.test/live/channel.ts',
      ),
      isFalse,
    );
    expect(
      shouldProbeMofinMember(
        isWeb: true,
        streamUrl: 'https://example.test/live/channel.m3u8',
      ),
      isTrue,
    );
    expect(
      shouldProbeMofinMember(
        isWeb: false,
        streamUrl: 'https://example.test/live/channel.ts',
      ),
      isTrue,
    );
  });
}
