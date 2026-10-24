import '../data/viewmodels/live_tv_guide_view_model.dart';
import 'direct_iptv_playback.dart';
import 'models.dart';

/// The existing player and channel strip speak [GuideChannel]. A direct
/// lineup is converted at the moment it is opened, so the server guide
/// model is never asked to load it.
GuideChannel guideChannelFromDirect(
  DirectChannel channel,
  DirectIptvSource source,
) {
  return GuideChannel(
    id: channel.id,
    name: channel.name,
    number: channel.number,
    rawData: playbackRawData(channel: channel, source: source),
  );
}

GuideProgram guideProgramFromDirect(DirectProgram program) {
  final categories = program.categories
      .map((category) => category.toLowerCase())
      .toList();
  bool has(String needle) =>
      categories.any((category) => category.contains(needle));
  return GuideProgram(
    id: program.id,
    channelId: program.channelKey,
    name: program.title,
    startDate: program.start,
    endDate: program.end,
    overview: program.overview,
    episodeTitle: program.episodeTitle,
    isMovie: has('movie') || has('film'),
    isSeries: has('series') || has('episode'),
    isSports: has('sport'),
    isNews: has('news'),
    isKids: has('kids') || has('child'),
    rawData: {
      'Id': program.id,
      'Name': program.title,
      'Overview': program.overview,
      'EpisodeTitle': program.episodeTitle,
      'StartDate': program.start.toIso8601String(),
      'EndDate': program.end.toIso8601String(),
      if (program.seasonNumber != null)
        'ParentIndexNumber': program.seasonNumber,
      if (program.episodeNumber != null) 'IndexNumber': program.episodeNumber,
      'MoonfinDirectSource': true,
    },
  );
}
