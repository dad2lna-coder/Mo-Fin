import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../direct_iptv/guide_tmdb.dart';
import '../../../direct_iptv/guide_tmdb_client.dart';

/// Debounces focus and paints TMDB facts when the match is confident.
///
/// [builder] is called with null while there is no key, no result yet, or
/// no confident match. Callers keep the EPG text in that case. The panel
/// is not focusable; the guide's D-pad order stays where it was.
class GuideTmdbBinder extends StatefulWidget {
  final GuideQuery? query;
  final Widget Function(BuildContext context, GuideTmdbHit? hit) builder;

  const GuideTmdbBinder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  State<GuideTmdbBinder> createState() => _GuideTmdbBinderState();
}

class _GuideTmdbBinderState extends State<GuideTmdbBinder> {
  static const _debounce = Duration(milliseconds: 600);

  Timer? _timer;
  int _token = 0;
  String _key = '';
  GuideTmdbHit? _hit;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant GuideTmdbBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.query;
    final previous = oldWidget.query;
    if (next == null && previous == null) return;
    if (next != null &&
        previous != null &&
        guideTmdbCacheKey(next) == guideTmdbCacheKey(previous) &&
        next.episodeTitle == previous.episodeTitle) {
      return;
    }
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _token++;
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    final query = widget.query;
    final key = query == null ? '' : guideTmdbCacheKey(query);
    if (key != _key) {
      _key = key;
      _hit = query == null
          ? null
          : GuideTmdbLookup.shared.cachedHit(query);
    }
    if (query == null || key.isEmpty) return;
    final token = ++_token;
    unawaited(_schedule(query, key, token));
  }

  Future<void> _schedule(GuideQuery query, String key, int token) async {
    final apiKey = await GuideTmdbLookup.shared.peekKey();
    if (!mounted || token != _token) return;
    if (apiKey.isEmpty) return;
    _timer = Timer(_debounce, () async {
      final hit = await GuideTmdbLookup.shared.lookup(query);
      if (!mounted || token != _token || _key != key) return;
      if (hit == _hit) return;
      setState(() => _hit = hit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: widget.builder(context, _hit),
    );
  }
}
