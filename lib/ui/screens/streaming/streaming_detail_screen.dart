import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/search_repository.dart';
import '../../../preference/preference_constants.dart';
import '../../../streaming/streaming_launcher.dart';
import '../../../streaming/streaming_service.dart';
import '../../../streaming/tmdb_key_store.dart';
import '../../../streaming/tmdb_streaming_client.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/navigation_layout.dart';

class StreamingDetailScreen extends StatefulWidget {
  const StreamingDetailScreen({
    super.key,
    required this.mediaType,
    required this.tmdbId,
    this.store,
    this.launcher,
  });

  final String mediaType;
  final int tmdbId;
  final TmdbKeyStore? store;
  final StreamingLauncher? launcher;

  @override
  State<StreamingDetailScreen> createState() => _StreamingDetailScreenState();
}

class _StreamingDetailScreenState extends State<StreamingDetailScreen> {
  final _store = TmdbKeyStore();
  StreamingTitle? _title;
  AggregatedItem? _jellyfinMatch;
  bool _loading = true;
  bool _needsKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final providerApiKey = await StreamingProviderKeyStore().read();
    final key = await (widget.store ?? _store).read();
    final client = TmdbStreamingClient.forKey(key);
    if (!client.hasKey) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsKey = true;
      });
      return;
    }
    try {
      final title = await client.details(
        mediaType: widget.mediaType,
        id: widget.tmdbId,
        providerApiKey: providerApiKey,
      );
      AggregatedItem? jMatch;
      if (title != null) {
        jMatch = await _findJellyfinMatch(title, widget.mediaType);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _title = title;
        _jellyfinMatch = jMatch;
        _error = title == null ? 'That title is not available' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = streamingErrorText(error);
      });
    }
  }

  Future<AggregatedItem?> _findJellyfinMatch(StreamingTitle title, String mediaType) async {
    if (!GetIt.instance.isRegistered<SearchRepository>()) return null;
    try {
      final repo = GetIt.instance<SearchRepository>();
      final itemType = mediaType == 'tv' ? 'Series' : 'Movie';
      final name = title.title;
      final results = await repo.search(
        name,
        includeItemTypes: [itemType],
        limit: 5,
      );
      for (final item in results) {
        final itemName = item.rawData['Name']?.toString().toLowerCase();
        if (itemName == name.toLowerCase()) {
          if (title.year != null && item.rawData['ProductionYear'] != null) {
            final pYear = int.tryParse(item.rawData['ProductionYear'].toString());
            if (pYear != null && (pYear - title.year!).abs() > 1) {
              continue;
            }
          }
          return item;
        }
      }
    } catch (_) {}
    return null;
  }

  void _launchTrailer(String key) {
    final url = Uri.parse('https://www.youtube.com/watch?v=$key');
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: NavigationLayout(
        activeRoute: Destinations.streaming,
        showBackButton: true,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_needsKey) {
      return const Center(
        child: Text(
          kStreamingMissingKeyMessage,
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      );
    }
    final title = _title;
    if (title == null) {
      return Center(
        child: Text(
          _error ?? 'That title is not available',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final top = (NavigationLayout.positionNotifier.value ?? NavbarPosition.top) ==
            NavbarPosition.top
        ? 88.0
        : 28.0;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          28,
          top,
          28,
          bottomNavContentPadding(context, 28),
        ),
        children: [
          if (title.backdropUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(title.backdropUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 160,
                  height: 240,
                  child: title.posterUrl == null
                      ? const ColoredBox(color: Color(0xFF10263C))
                      : Image.network(title.posterUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (title.year != null) '${title.year}',
                        if (title.detailLine.isNotEmpty) title.detailLine,
                      ].join(' · '),
                      style: const TextStyle(color: Color(0xFF93C5FD)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title.overview?.trim().isNotEmpty == true
                          ? title.overview!.trim()
                          : 'No overview',
                      style: const TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    if (title.youtubeTrailerKey != null) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Watch Trailer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _launchTrailer(title.youtubeTrailerKey!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (title.cast.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Cast',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: title.cast.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final member = title.cast[index];
                  return SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF10263C),
                          backgroundImage: member.profileUrl != null
                              ? NetworkImage(member.profileUrl!)
                              : null,
                          child: member.profileUrl == null
                              ? const Icon(Icons.person, color: Colors.white38)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          member.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          FocusTraversalGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_jellyfinMatch != null) ...[
                  _JellyfinPlayButton(
                    item: _jellyfinMatch!,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (title.services.isEmpty)
                  const Text(
                    'Not on Netflix, Disney+, Max, or Prime Video',
                    style: TextStyle(color: Colors.white70),
                  )
                else
                  for (var i = 0; i < title.services.length; i++)
                    _WatchButton(
                      service: title.services[i],
                      title: title.title,
                      providerTitleId: title.providerTitleIds[title.services[i]],
                      providerUrl: title.providerUrls[title.services[i]],
                      autofocus: _jellyfinMatch == null && i == 0,
                      onPressed: () {
                        (widget.launcher ?? StreamingLauncher()).open(
                          context,
                          service: title.services[i],
                          title: title.title,
                          providerTitleId: title.providerTitleIds[title.services[i]],
                          providerUrl: title.providerUrls[title.services[i]],
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JellyfinPlayButton extends StatefulWidget {
  const _JellyfinPlayButton({
    required this.item,
    required this.autofocus,
  });

  final AggregatedItem item;
  final bool autofocus;

  @override
  State<_JellyfinPlayButton> createState() => _JellyfinPlayButtonState();
}

class _JellyfinPlayButtonState extends State<_JellyfinPlayButton> {
  final _buttonFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  bool _focused = false;

  void _open() {
    context.push(Destinations.item(widget.item.id, serverId: widget.item.serverId));
  }

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: (_, event) => handleOneShotSelect(event, _open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: AppColorScheme.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? AppColorScheme.accent : AppColorScheme.accent.withValues(alpha: 0.6),
            width: _focused ? 3 : 1.5,
          ),
        ),
        child: TextButton.icon(
          focusNode: _buttonFocus,
          onPressed: _open,
          icon: const Icon(Icons.folder_open, color: Colors.white),
          label: const Text(
            'Open in Jellyfin',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _WatchButton extends StatefulWidget {
  const _WatchButton({
    required this.service,
    required this.title,
    this.providerTitleId,
    this.providerUrl,
    required this.autofocus,
    required this.onPressed,
  });

  final StreamingService service;
  final String title;
  final String? providerTitleId;
  final String? providerUrl;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_WatchButton> createState() => _WatchButtonState();
}

class _WatchButtonState extends State<_WatchButton> {
  final _buttonFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  bool _focused = false;

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.service.watchButtonText(
      providerTitleId: widget.providerTitleId,
      providerUrl: widget.providerUrl,
      title: widget.title,
    );
    final subtitle = widget.service.watchButtonSubtitle(
      providerTitleId: widget.providerTitleId,
      providerUrl: widget.providerUrl,
      title: widget.title,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) => handleOneShotSelect(event, widget.onPressed),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? AppColorScheme.accent : Colors.white24,
              width: _focused ? 3 : 1,
            ),
          ),
          child: TextButton(
            focusNode: _buttonFocus,
            onPressed: widget.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
