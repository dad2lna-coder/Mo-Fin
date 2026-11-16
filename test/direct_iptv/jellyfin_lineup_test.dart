import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/direct_iptv/jellyfin_lineup.dart';

void main() {
  test('Jellyfin channels and programs join the direct guide', () {
    final lineup = jellyfinLineupFromResponses(
      {
        'Items': [
          {'Id': 'ch-1', 'Name': 'News', 'ChannelNumber': '7'},
          {'Id': '', 'Name': 'Blank'},
        ],
      },
      {
        'Items': [
          {
            'Id': 'p-1',
            'ChannelId': 'ch-1',
            'Name': 'Nightly',
            'StartDate': '2026-10-22T20:00:00Z',
            'EndDate': '2026-10-22T21:00:00Z',
            'TimerId': 'timer-1',
          },
          {
            'Id': 'p-2',
            'ChannelId': 'missing',
            'Name': 'Skip',
            'StartDate': '2026-10-22T20:00:00Z',
            'EndDate': '2026-10-22T21:00:00Z',
          },
        ],
      },
    );

    expect(lineup.channels, hasLength(1));
    expect(lineup.channels.single.sourceId, jellyfinLiveSourceId);
    expect(lineup.channels.single.group, 'Jellyfin');
    expect(lineup.channels.single.streamUrl, isEmpty);
    expect(lineup.guides['ch-1']?.name, 'News');
    expect(lineup.guides['ch-1']?.rawData['Id'], 'ch-1');
    expect(lineup.programs, hasLength(1));
    expect(lineup.programs.single.channelKey, 'ch-1');
    expect(lineup.timerProgramIds, {'p-1'});
  });
}
