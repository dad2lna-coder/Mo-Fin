import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/preference_constants.dart';
import '../../../streaming/streaming_service.dart';
import '../../../streaming/tmdb_key_store.dart';
import '../../../streaming/tmdb_streaming_client.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../navigation/destinations.dart';
import '../../navigation/route_lifecycle_observer.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/local_search_field.dart';
import '../../widgets/navigation_layout.dart';
import 'streaming_settings_screen.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key, this.store, this.clientFor});

  final TmdbKeyStore? store;
  final TmdbStreamingClient Function(String apiKey)? clientFor;

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> with RouteAware {
  final _store = TmdbKeyStore();
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'streaming-search');
  Timer? _debounce;
  ModalRoute<dynamic>? _route;
  TmdbStreamingClient? _client;
  StreamingPage? _page;
  bool _loading = true;
  bool _searching = false;
  bool _showSearch = false;

  TmdbKeyStore get store => widget.store ?? _store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) routeLifecycleObserver.unsubscribe(this);
      _route = route;
      routeLifecycleObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (_route != null) routeLifecycleObserver.unsubscribe(this);
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    final key = await store.read();
    final activeServices = await StreamingSubscriptionPreferences.readActiveServices();
    if (!mounted) return;
    final client = widget.clientFor?.call(key) ?? TmdbStreamingClient.forKey(key);
    _client = client;
    if (!client.hasKey) {
      setState(() {
        _loading = false;
        _searching = false;
        _page = const StreamingPage(needsKey: true);
      });
      return;
    }
    setState(() => _loading = true);
    final query = _search.text.trim();
    final isSearchActive = _showSearch && query.isNotEmpty;
    final page = isSearchActive
        ? await client.search(query)
        : await client.loadHome(enabledServices: activeServices);
    if (!mounted || !identical(_client, client)) return;
    setState(() {
      _loading = false;
      _searching = isSearchActive;
      _page = page;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _search.clear();
        _searching = false;
        _load();
      } else {
        _searchFocus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RequestInitialFocus(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: NavigationLayout(
          activeRoute: Destinations.streaming,
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final position =
        NavigationLayout.positionNotifier.value ?? NavbarPosition.top;
    final double topInset = position == NavbarPosition.top ? 28.0 + 56.0 : 28.0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          topInset,
          24,
          bottomNavContentPadding(context, 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Streaming',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Netflix, Disney+, Max, and Prime Video in the US',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_showSearch ? Icons.close : Icons.search, color: Colors.white),
                  tooltip: _showSearch ? 'Close search' : 'Search subscriptions',
                  onPressed: _toggleSearch,
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  tooltip: 'Streaming settings',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StreamingSettingsScreen(store: store),
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_showSearch) ...[
              const SizedBox(height: 12),
              LocalSearchField(
                controller: _search,
                focusNode: _searchFocus,
                hint: 'Search your subscriptions...',
                onChanged: _onSearchChanged,
              ),
            ],
            const SizedBox(height: 16),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final page = _page;
    if (_loading && page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (page == null) return const SizedBox.shrink();
    if (page.needsKey) {
      return Center(
        child: TextButton(
          autofocus: true,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StreamingSettingsScreen(store: store),
              ),
            );
          },
          child: const Text(
            kStreamingMissingKeyMessage,
            style: TextStyle(fontSize: 20),
          ),
        ),
      );
    }
    if (page.error != null) {
      return Center(
        child: Text(streamingErrorText(page.error!), style: const TextStyle(color: Colors.white70)),
      );
    }
    if (_searching) {
      if (page.titles.isEmpty) {
        return const Center(
          child: Text(
            'Nothing on Netflix, Disney+, Max, or Prime Video',
            style: TextStyle(color: Colors.white70),
          ),
        );
      }
      return _posterStrip(page.titles, autofocusFirst: true);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        for (var i = 0; i < page.rows.length; i++)
          _Row(
            row: page.rows[i],
            autofocus: i == 0,
          ),
      ],
    );
  }

  Widget _posterStrip(List<StreamingTitle> titles, {required bool autofocusFirst}) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: titles.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, index) => StreamingPoster(
        title: titles[index],
        autofocus: autofocusFirst && index == 0,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.autofocus});

  final StreamingRow row;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (row.titles.isEmpty)
            const Text(
              'Nothing on this service right now',
              style: TextStyle(color: Colors.white54),
            )
          else
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: row.titles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => StreamingPoster(
                  title: row.titles[index],
                  autofocus: autofocus && index == 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StreamingPoster extends StatefulWidget {
  const StreamingPoster({
    super.key,
    required this.title,
    this.autofocus = false,
  });

  final StreamingTitle title;
  final bool autofocus;

  @override
  State<StreamingPoster> createState() => _StreamingPosterState();
}

class _StreamingPosterState extends State<StreamingPoster> {
  bool _focused = false;

  void _open() {
    context.push(
      Destinations.streamingTitle(widget.title.mediaType, widget.title.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final year = title.year == null ? '' : ' ${title.year}';
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 180),
          );
        }
        setState(() => _focused = focused);
      },
      onKeyEvent: (_, event) => handleOneShotSelect(event, _open),
      child: GestureDetector(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 132,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? AppColorScheme.accent : Colors.transparent,
              width: 3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 168,
                  width: 120,
                  child: _poster(title),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${title.title}$year',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final service in title.services)
                    _Badge(service: service),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(StreamingTitle title) {
    final url = title.posterUrl;
    if (url == null) {
      return const ColoredBox(
        color: Color(0xFF10263C),
        child: Icon(Icons.movie, color: Colors.white38),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF10263C)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.service});

  final StreamingService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Color(service.colorValue),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        service.badge,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
