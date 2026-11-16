import '../data/viewmodels/live_tv_guide_view_model.dart';
import 'models.dart';

/// Channels that came from the server's Live TV tuner, shown inside the
/// Direct IPTV guide next to the M3U lineup.
const jellyfinLiveSourceId = 'jellyfin-live';

class JellyfinLineup {
  final List<DirectChannel> channels;
  final List<DirectProgram> programs;
  final Map<String, GuideChannel> guides;
  final Set<String> timerProgramIds;

  const JellyfinLineup({
    required this.channels,
    required this.programs,
    required this.guides,
    required this.timerProgramIds,
  });

  static const empty = JellyfinLineup(
    channels: [],
    programs: [],
    guides: {},
    timerProgramIds: {},
  );
}

JellyfinLineup jellyfinLineupFromResponses(
  Map<String, dynamic> channelsResponse,
  Map<String, dynamic> guideResponse,
) {
  return jellyfinLineupFromItems(
    channels: _items(channelsResponse),
    programs: _items(guideResponse),
  );
}

JellyfinLineup jellyfinLineupFromItems({
  required List<Map<String, dynamic>> channels,
  required List<Map<String, dynamic>> programs,
}) {
  final guides = <String, GuideChannel>{};
  final direct = <DirectChannel>[];
  for (final item in channels) {
    final id = item['Id']?.toString().trim() ?? '';
    final name = item['Name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) continue;
    guides[id] = GuideChannel.fromRawItem(item);
    direct.add(
      DirectChannel(
        id: id,
        sourceId: jellyfinLiveSourceId,
        name: name,
        streamUrl: '',
        number: item['ChannelNumber']?.toString(),
        tvgId: id,
        group: 'Jellyfin',
      ),
    );
  }

  final timers = <String>{};
  final shows = <DirectProgram>[];
  for (final item in programs) {
    final id = item['Id']?.toString().trim() ?? '';
    final channelId = item['ChannelId']?.toString().trim() ?? '';
    final start = _time(item['StartDate']);
    final end = _time(item['EndDate']);
    if (id.isEmpty || channelId.isEmpty || start == null || end == null) {
      continue;
    }
    if (!guides.containsKey(channelId)) continue;
    final timer = item['TimerId']?.toString().trim() ?? '';
    if (timer.isNotEmpty) timers.add(id);
    shows.add(
      DirectProgram(
        id: id,
        channelKey: channelId,
        title: item['Name']?.toString() ?? '',
        start: start,
        end: end,
        overview: item['Overview']?.toString(),
        episodeTitle: item['EpisodeTitle']?.toString(),
      ),
    );
  }

  return JellyfinLineup(
    channels: direct,
    programs: shows,
    guides: guides,
    timerProgramIds: timers,
  );
}

List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
  final raw = response['Items'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

DateTime? _time(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}
