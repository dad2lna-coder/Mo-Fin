import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

void main() {
  test('a reported rendition keeps the id the player can select', () {
    const groupKey = '0:subtitle:en';
    final id = textRenditionId(groupKey, 1);
    final tracks = NativeTextRendition.listFromWire([
      {
        'id': id,
        'label': 'English',
        'language': 'en',
        'mimeType': 'text/vtt',
        'groupId': groupKey,
        'trackIndex': 1,
        'selected': false,
      },
      {'label': 'missing id'},
      'not a track',
    ]);

    expect(tracks, hasLength(1));
    expect(tracks.single.id, id);
    expect(tracks.single.mimeType, 'text/vtt');
    final parsed = parseTextRenditionId(tracks.single.id);
    expect(parsed?.groupKey, groupKey);
    expect(parsed?.trackIndex, 1);
  });

  test('english matches eng and en-us, and a miss does not invent a track', () {
    final tracks = [
      const NativeTextRendition(id: 'es', label: 'Spanish', language: 'es'),
      const NativeTextRendition(id: 'en', label: 'English', language: 'en-US'),
    ];
    expect(chooseNativeTextRendition(tracks, 'en')?.id, 'en');
    expect(chooseNativeTextRendition(tracks, '')?.id, 'en');
    expect(
      chooseNativeTextRendition(
        const [
          NativeTextRendition(id: 'eng', label: 'English', language: 'eng'),
        ],
        'en',
      )?.id,
      'eng',
    );
    expect(
      chooseNativeTextRendition(
        const [NativeTextRendition(id: 'fr', label: 'French', language: 'fr')],
        'en',
      ),
      isNull,
    );
  });
}
