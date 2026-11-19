import 'jellyfin_lineup.dart';
import 'models.dart';

/// How long a saved feed may fail to start, or sit buffering, before the
/// player tries the next feed. That hop is not written back as the choice.
const directFeedStallTimeout = Duration(seconds: 8);

/// Lower-case, trimmed, one space. Empty stays empty.
String normalizeDirectFeedKey(String? raw) {
  final trimmed = raw?.trim().toLowerCase() ?? '';
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

/// One playable stream inside a station group.
class DirectChannelFeed {
  final String groupId;
  final DirectChannel channel;
  final DirectIptvSource source;

  const DirectChannelFeed({
    required this.groupId,
    required this.channel,
    required this.source,
  });

  String get channelId => channel.id;
  String get sourceId => source.id;
  String get sourceName => source.name;
}

/// The same station on every enabled Direct IPTV source.
class DirectFeedGroup {
  final String id;
  final List<DirectChannelFeed> feeds;

  const DirectFeedGroup({required this.id, required this.feeds});
}

class DirectFeedIndex {
  final Map<String, DirectFeedGroup> byId;
  final Map<String, String> groupByChannelId;

  const DirectFeedIndex({required this.byId, required this.groupByChannelId});

  static const empty = DirectFeedIndex(byId: {}, groupByChannelId: {});

  DirectFeedGroup? groupForChannel(String channelId) {
    final groupId = groupByChannelId[channelId];
    if (groupId == null) return null;
    return byId[groupId];
  }
}

/// Stations that share a tvg-id, or the same name when the id differs, are
/// one group. The id prefers the first tvg-id in alphabetical order so the
/// preference key does not depend on which source was opened.
///
/// Disabled sources, the Jellyfin tuner, and rows with no stream URL are
/// not feeds. A source contributes one feed, the first matching row.
DirectFeedIndex buildDirectFeedIndex({
  required Iterable<DirectIptvSource> sources,
  required DirectIptvSnapshot? Function(String sourceId) snapshotFor,
}) {
  final nodes = <_FeedNode>[];
  final byTvg = <String, _FeedNode>{};
  final byName = <String, _FeedNode>{};

  for (final source in sources) {
    if (!source.enabled || source.id == jellyfinLiveSourceId) continue;
    final channels =
        snapshotFor(source.id)?.channels ?? const <DirectChannel>[];
    for (final channel in channels) {
      if (channel.streamUrl.trim().isEmpty) continue;
      final node = _FeedNode(channel, source);
      nodes.add(node);
      final tvg = normalizeDirectFeedKey(channel.tvgId);
      final name = normalizeDirectFeedKey(channel.name);
      if (tvg.isNotEmpty) {
        final prior = byTvg[tvg];
        if (prior == null) {
          byTvg[tvg] = node;
        } else {
          _union(prior, node);
        }
      }
      if (name.isNotEmpty) {
        final prior = byName[name];
        if (prior == null) {
          byName[name] = node;
        } else {
          _union(prior, node);
        }
      }
    }
  }

  final grouped = <_FeedNode, List<_FeedNode>>{};
  for (final node in nodes) {
    grouped.putIfAbsent(_find(node), () => []).add(node);
  }

  final byId = <String, DirectFeedGroup>{};
  final groupByChannelId = <String, String>{};
  for (final members in grouped.values) {
    final id = _groupId(members);
    final seenSources = <String>{};
    final feeds = <DirectChannelFeed>[];
    for (final node in members) {
      if (!seenSources.add(node.source.id)) continue;
      final feed = DirectChannelFeed(
        groupId: id,
        channel: node.channel,
        source: node.source,
      );
      feeds.add(feed);
      groupByChannelId[node.channel.id] = id;
    }
    // Channels dropped as a duplicate source still need to find the group,
    // so a later row of the same station opens the same feed list.
    for (final node in members) {
      groupByChannelId.putIfAbsent(node.channel.id, () => id);
    }
    byId[id] = DirectFeedGroup(id: id, feeds: feeds);
  }

  return DirectFeedIndex(byId: byId, groupByChannelId: groupByChannelId);
}

/// Next index, wrapping both ways. An unknown [current] (-1) lands on the
/// first feed when moving forward and the last feed when moving back.
int cycleDirectFeedIndex({
  required int current,
  required int count,
  required int delta,
}) {
  if (count <= 1) return 0;
  if (current < 0) return delta < 0 ? count - 1 : 0;
  final next = (current % count + delta) % count;
  return next < 0 ? next + count : next;
}

/// The saved channel when it is still one of [feeds]. Anything else means
/// the row that was opened, and the stored choice is left alone.
String? savedFeedChannelId({
  required String? saved,
  required Iterable<DirectChannelFeed> feeds,
}) {
  final id = saved?.trim() ?? '';
  if (id.isEmpty) return null;
  for (final feed in feeds) {
    if (feed.channelId == id) return id;
  }
  return null;
}

class _FeedNode {
  _FeedNode? parent;
  final DirectChannel channel;
  final DirectIptvSource source;

  _FeedNode(this.channel, this.source);
}

_FeedNode _find(_FeedNode node) {
  var root = node;
  while (root.parent != null) {
    root = root.parent!;
  }
  var cursor = node;
  while (cursor.parent != null) {
    final next = cursor.parent!;
    cursor.parent = root;
    cursor = next;
  }
  return root;
}

void _union(_FeedNode a, _FeedNode b) {
  final left = _find(a);
  final right = _find(b);
  if (left != right) right.parent = left;
}

String _groupId(List<_FeedNode> members) {
  final tvgs = <String>{
    for (final node in members)
      if (normalizeDirectFeedKey(node.channel.tvgId).isNotEmpty)
        normalizeDirectFeedKey(node.channel.tvgId),
  }.toList()..sort();
  if (tvgs.isNotEmpty) return 'tvg:${tvgs.first}';
  final names = <String>{
    for (final node in members)
      if (normalizeDirectFeedKey(node.channel.name).isNotEmpty)
        normalizeDirectFeedKey(node.channel.name),
  }.toList()..sort();
  if (names.isNotEmpty) return 'name:${names.first}';
  return 'id:${members.first.channel.id}';
}
