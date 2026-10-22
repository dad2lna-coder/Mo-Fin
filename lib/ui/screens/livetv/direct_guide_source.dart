import '../../../direct_iptv/models.dart';

/// Last Direct IPTV source the guide was left on. Not part of the catalog.
const directIptvLastSourceKey = 'moonfin.direct_iptv.last_source';

/// Saved source, then the enabled M3U named "Mo Fin", then the first enabled
/// source. A saved id that is missing or disabled does not count.
String? chooseDefaultDirectSource({
  required Iterable<DirectIptvSource> sources,
  String? savedId,
}) {
  final enabled = [
    for (final source in sources)
      if (source.enabled) source,
  ];
  final saved = savedId?.trim();
  if (saved != null && saved.isNotEmpty) {
    for (final source in enabled) {
      if (source.id == saved) return source.id;
    }
  }
  for (final source in enabled) {
    if (source.kind == DirectIptvKind.m3u && source.name == 'Mo Fin') {
      return source.id;
    }
  }
  if (enabled.isEmpty) return null;
  return enabled.first.id;
}
