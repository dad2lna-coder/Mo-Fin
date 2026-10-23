import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

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
  bool _loading = true;
  bool _needsKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _title = title;
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (title.services.isEmpty)
            const Text(
              'Not on Netflix, Disney+, Max, or Prime Video',
              style: TextStyle(color: Colors.white70),
            )
          else
            FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < title.services.length; i++)
                    _WatchButton(
                      service: title.services[i],
                      autofocus: i == 0,
                      onPressed: () {
                        (widget.launcher ?? StreamingLauncher()).open(
                          context,
                          service: title.services[i],
                          title: title.title,
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

class _WatchButton extends StatefulWidget {
  const _WatchButton({
    required this.service,
    required this.autofocus,
    required this.onPressed,
  });

  final StreamingService service;
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            child: Text('Watch on ${widget.service.label}'),
          ),
        ),
      ),
    );
  }
}
