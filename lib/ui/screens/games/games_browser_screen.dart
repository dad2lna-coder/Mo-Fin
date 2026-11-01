import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/retro_artwork/retro_artwork_activity_gate.dart';
import '../../../data/services/retro_artwork/retro_artwork_cache.dart';
import '../../../data/services/retro_artwork/retro_artwork_data_source.dart';
import '../../../data/services/retro_artwork/retro_artwork_transport.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/grid_focus_node_mixin.dart';
import '../../../util/game_artwork_cache.dart';
import '../../../util/game_browse_filter.dart';
import '../../../util/game_cores.dart';
import '../../../util/game_launch.dart';
import '../../../util/game_library.dart';
import '../../../util/game_local_data.dart';
import '../../../util/game_storage.dart';
import '../../../util/platform_detection.dart';
import '../../../util/tv_image_cache_stub.dart'
    if (dart.library.io) '../../../util/tv_image_cache_io.dart';
import '../../navigation/destinations.dart';
import '../../navigation/route_lifecycle_observer.dart';
import '../../widgets/game/amiga_system_mark.dart';
import '../../widgets/game/game_card_focus_frame.dart';
import '../../widgets/game/game_poster_card.dart';
import '../../widgets/game/retro_artwork_image.dart';
import '../../widgets/game/retro_artwork_shape.dart';
import '../../widgets/media_card.dart';
import '../settings/downloaded_games_screen.dart';

enum _BrowserTab { all, favorites, recent }

enum _BrowserSort { nameAsc, nameDesc, recent }

/// Native Games browser for Android phone and Fire TV that matches the iOS ROM
/// Manager layout without embedding the plugin WebView.
class GamesBrowserScreen extends StatefulWidget {
  const GamesBrowserScreen({
    super.key,
    required this.libraryId,
    this.title,
  });

  final String libraryId;
  final String? title;

  @override
  State<GamesBrowserScreen> createState() => _GamesBrowserScreenState();
}

class _GamesBrowserScreenState extends State<GamesBrowserScreen>
    with GridFocusNodeMixin<GamesBrowserScreen>, RouteAware {
  final MediaServerClient _client = GetIt.instance<MediaServerClient>();
  final UserPreferences _prefs = GetIt.instance<UserPreferences>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  String? _error;
  List<GameSystem> _systems = const [];
  int _selectedSystemIndex = 0;

  // Games for current system
  bool _loadingGames = false;
  List<GameSummary> _allSystemGames = const [];
  Map<String, GameBrowseTextIndex> _textIndexes = {};

  // Filters & Tabs
  _BrowserTab _currentTab = _BrowserTab.all;
  _BrowserSort _currentSort = _BrowserSort.nameAsc;

  // Focus nodes
  final List<FocusNode> _carouselFocusNodes = [];
  final FocusNode _tabAllFocusNode = FocusNode(debugLabel: 'games_tab_all');
  final FocusNode _tabFavFocusNode = FocusNode(debugLabel: 'games_tab_fav');
  final FocusNode _tabRecentFocusNode = FocusNode(debugLabel: 'games_tab_recent');
  final FocusNode _sortFocusNode = FocusNode(debugLabel: 'games_sort');

  // Side menu state on TV
  bool _sideMenuOpen = false;
  final FocusNode _sideMenuFirstFocus = FocusNode(debugLabel: 'side_menu_first');

  // Cached stats for side menu
  int _cachedBytes = 0;
  int _totalGamesCount = 0;

  // Artwork & route lifecycle
  RetroArtworkActivityGate? _retroArtworkActivityGate;
  RetroArtworkTransport? _retroArtworkTransport;
  RetroArtworkDataSource? _retroArtworkDataSource;
  String? _retroArtworkServerIdentity;
  String? _artworkScope;
  ModalRoute<dynamic>? _observedRoute;
  bool _routeIsCovered = false;

  int _focusedCardIndex = 0;

  @override
  void initState() {
    super.initState();
    GameLocalData.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    GameLocalData.instance.changeNotifier.addListener(_onLocalDataChanged);
    unawaited(_initializeArtwork());
    _loadSystems();
    _refreshStorageStats();
  }

  void _onLocalDataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshStorageStats() async {
    try {
      final list = await GameStorage.list();
      if (!mounted) return;
      setState(() {
        _cachedBytes = list.fold(0, (sum, g) => sum + g.bytes);
      });
    } catch (_) {}
  }

  Future<void> _initializeArtwork() async {
    if (!GetIt.instance.isRegistered<RetroArtworkByteCache>() ||
        !GetIt.instance.isRegistered<RetroArtworkActivityGate>()) {
      return;
    }
    final cache = await GetIt.instance.getAsync<RetroArtworkByteCache>();
    if (!mounted) return;
    final gate = GetIt.instance<RetroArtworkActivityGate>();
    _retroArtworkActivityGate = gate;
    _retroArtworkTransport = RetroArtworkTransport.forServer(
      client: _client,
      cache: cache,
      activityGate: gate,
    );
    _retroArtworkServerIdentity = normalizeRetroArtworkServerIdentity(
      _client.baseUrl,
    );
    final ds = await RetroArtworkDataSourceFactory.create(
      client: _client,
      activityGate: gate,
      transport: _retroArtworkTransport!,
    );
    if (!mounted) {
      ds?.dispose();
      return;
    }
    _retroArtworkDataSource = ds;
    if (_routeIsCovered) _retroArtworkDataSource?.onRouteCovered();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    _routeIsCovered = true;
    _retroArtworkTransport?.cancelAll();
    _retroArtworkDataSource?.onRouteCovered();
  }

  @override
  void didPopNext() {
    _routeIsCovered = false;
    _retroArtworkDataSource?.onRouteReentered();
    _refreshStorageStats();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GameLocalData.instance.changeNotifier.removeListener(_onLocalDataChanged);
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _retroArtworkDataSource?.dispose();
    _retroArtworkTransport?.dispose();
    if (_artworkScope case final scope?) {
      releaseGameArtworkCacheScope(scope);
    }
    for (final node in _carouselFocusNodes) {
      node.dispose();
    }
    _tabAllFocusNode.dispose();
    _tabFavFocusNode.dispose();
    _tabRecentFocusNode.dispose();
    _sortFocusNode.dispose();
    _sideMenuFirstFocus.dispose();
    disposeGridFocusNodes();
    super.dispose();
  }

  Future<void> _loadSystems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final gamesApi = _client.gamesApi;
    if (gamesApi == null) {
      setState(() {
        _loading = false;
        _error = 'Games API is not available.';
      });
      return;
    }

    try {
      final systems = await gamesApi.getSystems(widget.libraryId);
      if (!mounted) return;
      _systems = systems;
      _totalGamesCount = systems.fold(0, (sum, s) => sum + (s.gameCount ?? 0));
      _carouselFocusNodes.clear();
      for (var i = 0; i < systems.length; i++) {
        _carouselFocusNodes.add(FocusNode(debugLabel: 'console_carousel_$i'));
      }
      _loading = false;
      setState(() {});

      if (systems.isNotEmpty) {
        _selectSystem(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load systems: $e';
      });
    }
  }

  void _selectSystem(int index) {
    if (index < 0 || index >= _systems.length) return;
    _selectedSystemIndex = index;
    final system = _systems[index];

    if (_artworkScope case final scope?) {
      releaseGameArtworkCacheScope(scope);
    }
    _artworkScope = gameArtworkScope(widget.libraryId, system.id);
    unawaited(retainGameArtworkCacheScope(_artworkScope!));

    _loadGamesForSystem(system);
  }

  Future<void> _loadGamesForSystem(GameSystem system) async {
    setState(() {
      _loadingGames = true;
    });

    try {
      final gamesApi = _client.gamesApi;
      if (gamesApi == null) return;
      final games = await gamesApi.getGames(widget.libraryId, system: system.id);
      if (!mounted || _systems[_selectedSystemIndex].id != system.id) return;

      final textIndexes = <String, GameBrowseTextIndex>{};
      for (final g in games) {
        textIndexes[g.id] = GameBrowseTextIndex(
          g.title,
          alternateText: g.fileName,
        );
      }

      setState(() {
        _allSystemGames = games;
        _textIndexes = textIndexes;
        _loadingGames = false;
        _focusedCardIndex = 0;
      });

      _retroArtworkDataSource?.refreshSystem(
        libraryId: widget.libraryId,
        systemId: system.id,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGames = false;
      });
    }
  }

  List<GameSummary> _getFilteredAndSortedGames() {
    var games = _allSystemGames;

    // Filter by tab
    if (_currentTab == _BrowserTab.favorites) {
      games = games
          .where((g) => GameLocalData.instance.isFavorite(widget.libraryId, g.id))
          .toList();
    } else if (_currentTab == _BrowserTab.recent) {
      games = games.where((g) {
        return GameLocalData.instance.recentIndex(widget.libraryId, g.id) != null;
      }).toList();
    }

    // Sort games
    if (_currentTab == _BrowserTab.recent) {
      // Ignore name sort on Recent tab: most recent first
      games.sort((a, b) {
        final aIdx = GameLocalData.instance.recentIndex(widget.libraryId, a.id) ?? 9999;
        final bIdx = GameLocalData.instance.recentIndex(widget.libraryId, b.id) ?? 9999;
        return aIdx.compareTo(bIdx);
      });
    } else {
      games = List<GameSummary>.from(games);
      switch (_currentSort) {
        case _BrowserSort.nameAsc:
          games.sort((a, b) {
            final aKey = _textIndexes[a.id]?.sortKey ?? a.title.toLowerCase();
            final bKey = _textIndexes[b.id]?.sortKey ?? b.title.toLowerCase();
            return aKey.compareTo(bKey);
          });
        case _BrowserSort.nameDesc:
          games.sort((a, b) {
            final aKey = _textIndexes[a.id]?.sortKey ?? a.title.toLowerCase();
            final bKey = _textIndexes[b.id]?.sortKey ?? b.title.toLowerCase();
            return bKey.compareTo(aKey);
          });
        case _BrowserSort.recent:
          games.sort((a, b) {
            final aIdx = GameLocalData.instance.recentIndex(widget.libraryId, a.id);
            final bIdx = GameLocalData.instance.recentIndex(widget.libraryId, b.id);
            if (aIdx == null && bIdx == null) {
              final aKey = _textIndexes[a.id]?.sortKey ?? a.title.toLowerCase();
              final bKey = _textIndexes[b.id]?.sortKey ?? b.title.toLowerCase();
              return aKey.compareTo(bKey);
            }
            if (aIdx == null) return 1;
            if (bIdx == null) return -1;
            return aIdx.compareTo(bIdx);
          });
      }
    }

    return games;
  }

  void _openSideMenu() {
    if (PlatformDetection.isTV) {
      setState(() {
        _sideMenuOpen = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sideMenuFirstFocus.requestFocus();
      });
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  void _closeSideMenu() {
    if (_sideMenuOpen) {
      setState(() {
        _sideMenuOpen = false;
      });
      if (_systems.isNotEmpty && _selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      }
    }
  }

  KeyEventResult _handleCarouselKeyEvent(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isLeftKey) {
      if (index == 0) {
        _openSideMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey.isRightKey) {
      if (index == _systems.length - 1) {
        return KeyEventResult.handled; // No wrap
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey.isDownKey) {
      _focusTab(_currentTab);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _focusTab(_BrowserTab tab) {
    switch (tab) {
      case _BrowserTab.all:
        _tabAllFocusNode.requestFocus();
      case _BrowserTab.favorites:
        _tabFavFocusNode.requestFocus();
      case _BrowserTab.recent:
        _tabRecentFocusNode.requestFocus();
    }
  }

  KeyEventResult _handleTabKeyEvent(_BrowserTab tab, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isUpKey) {
      if (_selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isDownKey) {
      final games = _getFilteredAndSortedGames();
      if (games.isNotEmpty) {
        final node = getGridItemFocusNode(0, prefix: 'game_poster');
        node.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isLeftKey) {
      if (tab == _BrowserTab.favorites) {
        _tabAllFocusNode.requestFocus();
        setState(() => _currentTab = _BrowserTab.all);
        return KeyEventResult.handled;
      } else if (tab == _BrowserTab.recent) {
        _tabFavFocusNode.requestFocus();
        setState(() => _currentTab = _BrowserTab.favorites);
        return KeyEventResult.handled;
      } else if (tab == _BrowserTab.all) {
        _openSideMenu();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey.isRightKey) {
      if (tab == _BrowserTab.all) {
        _tabFavFocusNode.requestFocus();
        setState(() => _currentTab = _BrowserTab.favorites);
        return KeyEventResult.handled;
      } else if (tab == _BrowserTab.favorites) {
        _tabRecentFocusNode.requestFocus();
        setState(() => _currentTab = _BrowserTab.recent);
        return KeyEventResult.handled;
      } else if (tab == _BrowserTab.recent) {
        _sortFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey.isSelectKey) {
      setState(() => _currentTab = tab);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSortKeyEvent(KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isUpKey) {
      if (_selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isDownKey) {
      final games = _getFilteredAndSortedGames();
      if (games.isNotEmpty) {
        final node = getGridItemFocusNode(0, prefix: 'game_poster');
        node.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isLeftKey) {
      _tabRecentFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      return KeyEventResult.handled; // swallow at edge
    }

    if (event.logicalKey.isSelectKey) {
      _cycleSort();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _cycleSort() {
    setState(() {
      _currentSort = switch (_currentSort) {
        _BrowserSort.nameAsc => _BrowserSort.nameDesc,
        _BrowserSort.nameDesc => _BrowserSort.recent,
        _BrowserSort.recent => _BrowserSort.nameAsc,
      };
    });
  }

  void _openGameDetail(GameSummary game) {
    context.push(Destinations.gameDetailOf(widget.libraryId, game.id));
  }

  void _toggleFavorite(GameSummary game) {
    unawaited(GameLocalData.instance.toggleFavorite(widget.libraryId, game.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTV = PlatformDetection.isTV;

    return PopScope(
      canPop: !isTV && !_sideMenuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_sideMenuOpen) {
          _closeSideMenu();
        } else {
          context.popOrHome();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColorScheme.background,
        drawer: isTV ? null : _buildSideMenuContent(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadSystems,
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isTV && _sideMenuOpen)
                            SizedBox(
                              width: 280,
                              child: _buildSideMenuContent(),
                            ),
                          Expanded(
                            child: _buildMainContent(),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSideMenuContent() {
    return Focus(
      onKeyEvent: (node, event) {
        if (event.isActionable && (event.logicalKey.isBackKey || event.logicalKey.isRightKey)) {
          _closeSideMenu();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: AppColorScheme.surfaceVariant.withValues(alpha: 0.95),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videogame_asset, size: 28, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  widget.title ?? 'Games',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildStatItem('Total Games', '$_totalGamesCount'),
            const SizedBox(height: 18),
            _buildStatItem('Downloaded Storage', formatBytes(_cachedBytes)),
            const Spacer(),
            Focus(
              focusNode: _sideMenuFirstFocus,
              onKeyEvent: (node, event) {
                if (event.isActionable && event.logicalKey.isSelectKey) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DownloadedGamesScreen(),
                    ),
                  );
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? AppColorScheme.accent : AppColorScheme.surface,
                      foregroundColor: focused ? Colors.black : Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DownloadedGamesScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_for_offline),
                    label: const Text('Downloaded Games'),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    final filteredGames = _getFilteredAndSortedGames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildConsoleCarousel(),
        const SizedBox(height: 14),
        _buildTabsAndSortRow(),
        const SizedBox(height: 12),
        Expanded(
          child: _loadingGames
              ? const Center(child: CircularProgressIndicator())
              : _buildGamesGrid(filteredGames),
        ),
      ],
    );
  }

  Widget _buildConsoleCarousel() {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: _systems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final system = _systems[index];
          final isSelected = index == _selectedSystemIndex;
          final focusNode = _carouselFocusNodes[index];

          return Focus(
            focusNode: focusNode,
            autofocus: PlatformDetection.isTV && index == 0,
            onFocusChange: (focused) {
              if (focused && _selectedSystemIndex != index) {
                _selectSystem(index);
              }
              setState(() {});
            },
            onKeyEvent: (node, event) => _handleCarouselKeyEvent(index, event),
            child: GestureDetector(
              onTap: () {
                _selectSystem(index);
                focusNode.requestFocus();
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;
                  final borders = ThemeRegistry.active.borders;
                  final amiga = isAmigaSystemId(system.id) ||
                      isAmigaSystemId(system.core) ||
                      isAmigaSystemId(system.name);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: (hasFocus || isSelected) ? 220 : 190,
                    decoration: BoxDecoration(
                      color: gameFallbackColor(system.id),
                      borderRadius: borders.cardRadius,
                      border: Border.all(
                        color: hasFocus
                            ? AppColorScheme.accent
                            : isSelected
                                ? Colors.white70
                                : Colors.transparent,
                        width: hasFocus ? 3 : 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _SystemPreviewStrip(
                          system: system,
                          transport: _retroArtworkTransport,
                          activityGate: _retroArtworkActivityGate,
                          libraryId: widget.libraryId,
                          serverIdentity: _retroArtworkServerIdentity,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.86),
                                Colors.black.withValues(alpha: 0.54),
                                Colors.black.withValues(alpha: 0.2),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: amiga
                                    ? const AmigaSystemMark()
                                    : const Icon(
                                        Icons.sports_esports,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gameSystemListName(
                                        id: system.id,
                                        name: system.name,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: (hasFocus || isSelected) ? 15 : 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (system.gameCount != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${system.gameCount} games',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.75),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabsAndSortRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildTabButton(
            label: 'All',
            tab: _BrowserTab.all,
            focusNode: _tabAllFocusNode,
          ),
          const SizedBox(width: 10),
          _buildTabButton(
            label: 'Favorites',
            tab: _BrowserTab.favorites,
            focusNode: _tabFavFocusNode,
          ),
          const SizedBox(width: 10),
          _buildTabButton(
            label: 'Recently Played',
            tab: _BrowserTab.recent,
            focusNode: _tabRecentFocusNode,
          ),
          const Spacer(),
          _buildSortButton(),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required _BrowserTab tab,
    required FocusNode focusNode,
  }) {
    final isSelected = _currentTab == tab;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => _handleTabKeyEvent(tab, event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              setState(() => _currentTab = tab);
              focusNode.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColorScheme.accent.withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasFocus
                      ? AppColorScheme.accent
                      : isSelected
                          ? AppColorScheme.accent
                          : Colors.white24,
                  width: hasFocus ? 2 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected || hasFocus ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortButton() {
    final sortLabel = switch (_currentSort) {
      _BrowserSort.nameAsc => 'Name A–Z',
      _BrowserSort.nameDesc => 'Name Z–A',
      _BrowserSort.recent => 'Recently played',
    };

    return Focus(
      focusNode: _sortFocusNode,
      onKeyEvent: (node, event) => _handleSortKeyEvent(event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              _cycleSort();
              _sortFocusNode.requestFocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasFocus ? AppColorScheme.accent : Colors.white24,
                  width: hasFocus ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    sortLabel,
                    style: TextStyle(
                      color: hasFocus ? Colors.white : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGamesGrid(List<GameSummary> games) {
    if (games.isEmpty) {
      final emptyText = switch (_currentTab) {
        _BrowserTab.all => 'No games found',
        _BrowserTab.favorites => 'No favorites yet',
        _BrowserTab.recent => 'No recently played games',
      };

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const preferredCardWidth = 140.0;
        const spacing = 16.0;
        final availableWidth = constraints.maxWidth - 48; // padding 24 each side
        final crossAxisCount = ((availableWidth + spacing) / (preferredCardWidth + spacing))
            .floor()
            .clamp(2, 20);
        final cardWidth = (availableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final imageHeight = cardWidth * RetroArtworkShape.portraitHeightRatio;
        final cardHeight = imageHeight + 48;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          clipBehavior: Clip.none,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) {
            final game = games[index];
            final cardFocusNode = getGridItemFocusNode(index, prefix: 'game_poster');
            final isFirstRow = index < crossAxisCount;
            final isLastColumn = (index % crossAxisCount) == crossAxisCount - 1;
            final isFirstColumn = (index % crossAxisCount) == 0;
            final isLastItem = index == games.length - 1;

            final reference = _routeIsCovered ? null : _retroArtworkDataSource?.imageFor(game.id);
            final source = reference?.source;
            final artAspect = _retroArtworkDataSource?.snapshot?.aspectRatioFor(game.id);
            final cell = RetroArtworkShape.cellFor(artAspect);
            final containArt = RetroArtworkShape.shouldContain(
              cellAspect: artAspect,
              artAspect: artAspect,
              shapeAspect: cell.aspectRatio,
            );

            return GestureDetector(
              onLongPress: () => _toggleFavorite(game),
              child: GamePosterCard(
                imageUrl: reference?.legacyUrl,
                imageFit: containArt ? BoxFit.contain : BoxFit.cover,
                fillBehind: containArt && source == null,
                artwork: source == null ||
                        _retroArtworkTransport == null ||
                        _retroArtworkActivityGate == null
                    ? null
                    : RetroArtworkImage(
                        source: source,
                        transport: _retroArtworkTransport!,
                        activityGate: _retroArtworkActivityGate!,
                        maxDecodeWidth: cardWidth.toInt() * 2,
                        fit: containArt ? BoxFit.contain : BoxFit.cover,
                        fillBehind: containArt,
                      ),
                title: game.title,
                fileName: game.fileName,
                seed: game.id,
                width: cardWidth,
                imageHeight: imageHeight,
                focusNode: cardFocusNode,
                autoScroll: true,
                onFocus: () {
                  _focusedCardIndex = index;
                },
                onKeyEvent: (_, event) {
                  if (!event.isActionable) return KeyEventResult.ignored;

                  // Long press on remote or menu key toggles favorite
                  if (event.logicalKey == LogicalKeyboardKey.contextMenu) {
                    _toggleFavorite(game);
                    return KeyEventResult.handled;
                  }

                  // Up from top row returns to tabs
                  if (event.logicalKey.isUpKey && isFirstRow) {
                    _focusTab(_currentTab);
                    return KeyEventResult.handled;
                  }

                  // Left edge swallows or moves left
                  if (event.logicalKey.isLeftKey && isFirstColumn) {
                    return KeyEventResult.handled;
                  }

                  // Right edge swallows
                  if (event.logicalKey.isRightKey && (isLastColumn || isLastItem)) {
                    return KeyEventResult.handled;
                  }

                  // Down on bottom row swallows
                  final isBottomRow = index >= games.length - crossAxisCount;
                  if (event.logicalKey.isDownKey && isBottomRow) {
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                onTap: () => _openGameDetail(game),
              ),
            );
          },
        );
      },
    );
  }
}

class _SystemPreviewStrip extends StatelessWidget {
  const _SystemPreviewStrip({
    required this.system,
    required this.transport,
    required this.activityGate,
    required this.libraryId,
    required this.serverIdentity,
  });

  final GameSystem system;
  final RetroArtworkTransport? transport;
  final RetroArtworkActivityGate? activityGate;
  final String? libraryId;
  final String? serverIdentity;

  @override
  Widget build(BuildContext context) {
    final panels = system.previewArtwork?.panels ?? const [];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < 4; index++)
          Expanded(
            child: _SystemPreviewArtwork(
              panel: index < panels.length ? panels[index] : null,
              fallbackSeed: index < panels.length && panels[index].gameId.isNotEmpty
                  ? panels[index].gameId
                  : '${system.id}:$index',
              transport: transport,
              activityGate: activityGate,
              libraryId: libraryId,
              serverIdentity: serverIdentity,
            ),
          ),
      ],
    );
  }
}

class _SystemPreviewArtwork extends StatelessWidget {
  const _SystemPreviewArtwork({
    required this.panel,
    required this.fallbackSeed,
    required this.transport,
    required this.activityGate,
    required this.libraryId,
    required this.serverIdentity,
  });

  final GameSystemPreviewPanel? panel;
  final String fallbackSeed;
  final RetroArtworkTransport? transport;
  final RetroArtworkActivityGate? activityGate;
  final String? libraryId;
  final String? serverIdentity;

  @override
  Widget build(BuildContext context) {
    final descriptor = panel?.artwork;
    if (descriptor == null || !descriptor.isRenderable) return _fallback();

    RetroArtworkSource? source;
    if (transport != null &&
        activityGate != null &&
        libraryId != null &&
        serverIdentity != null &&
        panel!.gameId.isNotEmpty) {
      try {
        source = RetroArtworkSource.fromDescriptor(
          serverIdentity: serverIdentity!,
          libraryId: libraryId!,
          gameId: panel!.gameId,
          role: 'boxart',
          descriptor: descriptor,
        );
      } on FormatException {
        source = null;
      }
    }
    if (source != null) {
      return RetroArtworkImage(
        source: source,
        transport: transport!,
        activityGate: activityGate!,
        maxDecodeWidth: 240,
        fit: BoxFit.cover,
        errorBuilder: (_, _) => _fallback(),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return ColoredBox(
      color: gameFallbackColor(fallbackSeed),
      child: const Center(
        child: Icon(Icons.videogame_asset, color: Colors.white38, size: 20),
      ),
    );
  }
}
