import 'dart:async';

import 'package:clock/clock.dart';
import 'package:custom_tv_text_field/custom_tv_text_field.dart';
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
import '../../../data/services/rom_manager_games.dart';
import '../../../data/services/rom_manager_logos.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/clock_format.dart';
import '../../../util/disk_free_space.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/grid_focus_node_mixin.dart';
import '../../../util/game_artwork_cache.dart';
import '../../../util/game_browse_filter.dart';
import '../../../util/game_cores.dart';
import '../../../util/game_launch.dart';
import '../../../util/game_library.dart';
import '../../../util/game_local_data.dart';
import '../../../util/game_storage.dart';
import '../../../util/tv_image_cache_stub.dart'
    if (dart.library.io) '../../../util/tv_image_cache_io.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../navigation/route_lifecycle_observer.dart';
import '../../widgets/game/amiga_system_mark.dart';
import '../../widgets/game/game_alpha_picker_bar.dart';
import '../../widgets/game/game_poster_card.dart';
import '../../widgets/game/retro_artwork_image.dart';
import '../../widgets/game/retro_artwork_shape.dart';
import '../../widgets/local_search_field.dart';
import '../../widgets/mofin_brand.dart';
import '../settings/achievements_screen.dart';
import '../settings/downloaded_games_screen.dart';
import '../settings/settings_side_panel.dart';

enum _BrowserTab { all, favorites, recent }

enum _BrowserSort { nameAsc, nameDesc, recent }

/// Rows in the TV sidebar: the mockup's rail, in reading order, so the d-pad
/// walks down it the way the screen is read.
enum _GamesNavItem {
  home,
  library,
  favorites,
  recent,
  collections,
  platforms,
  achievements,
  settings,
}

extension on _GamesNavItem {
  String get label => switch (this) {
    _GamesNavItem.home => 'Home',
    _GamesNavItem.library => 'Library',
    _GamesNavItem.favorites => 'Favorites',
    _GamesNavItem.recent => 'Recently Played',
    _GamesNavItem.collections => 'Collections',
    _GamesNavItem.platforms => 'Platforms',
    _GamesNavItem.achievements => 'Achievements',
    _GamesNavItem.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    _GamesNavItem.home => Icons.home_rounded,
    _GamesNavItem.library => Icons.videogame_asset_rounded,
    _GamesNavItem.favorites => Icons.favorite_rounded,
    _GamesNavItem.recent => Icons.history_rounded,
    _GamesNavItem.collections => Icons.collections_bookmark_rounded,
    _GamesNavItem.platforms => Icons.devices_other_rounded,
    _GamesNavItem.achievements => Icons.emoji_events_rounded,
    _GamesNavItem.settings => Icons.settings_rounded,
  };
}

/// Deep navy to black, as in the TV mockup, rather than the theme background so
/// the console art and the neon focus rings stay legible over it.
const Color _kGamesBackdropTop = Color(0xFF0A1526);
const Color _kGamesBackdropBottom = Color(0xFF03060D);
const Color _kGamesPanelLight = Color(0xFF122139);
const Color _kGamesPanelDark = Color(0xFF0A1220);

/// Native Games browser for Android phone and Fire TV that matches the iOS ROM
/// Manager layout without embedding the plugin WebView.
///
/// On a TV this is the Games destination: [GamesNav] sends televisions here
/// instead of to the ROM Manager hub, whose webview a remote cannot drive. The
/// layout follows the 10-foot mockup - a rail down the left, a search and clock
/// top bar, a "Browse by Console" carousel of glossy console cards, one pill
/// group for the tabs, sort and filter, and the box-art grid underneath. Every
/// step of that chain is focusable and ordered, and Back walks up out of it
/// instead of dead-ending.
class GamesBrowserScreen extends StatefulWidget {
  const GamesBrowserScreen({
    super.key,
    required this.libraryId,
    this.title,
    this.logoService,
    this.romGames,
  });

  final String libraryId;
  final String? title;

  /// Console-logo transport. Tests inject one; null means the real plugin
  /// route, which is skipped entirely when it can't be reached.
  final RomManagerLogoService? logoService;

  /// Grouped catalog the phone Games page uses. Null in tests, which keep
  /// reading the Moonbase file list. Production passes [RomManagerGames].
  final RomManagerGames? romGames;

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

  // Games for the selected console. One page is loaded up front; more follow
  // as the grid scrolls, so a large console is not parsed in one shot.
  static const int _gamesPageSize = 100;
  static const int _gamesPrefetchTail = 18;
  static const double _gamesScrollTailPx = 720;

  bool _loadingGames = false;
  bool _loadingMoreGames = false;
  List<GameSummary> _allSystemGames = const [];
  Map<String, GameBrowseTextIndex> _textIndexes = {};
  Map<String, RomManagerGame> _romById = {};
  Map<String, Uint8List> _covers = {};
  bool _romCatalog = false;
  bool _romCatalogDisabled = false;
  String? _gamesError;
  int _gamesEpoch = 0;
  int _gamesTotal = 0;
  bool _gamesComplete = true;
  String? _loadedSystemId;
  final ScrollController _contentScrollController = ScrollController();

  // Filters and tabs
  _BrowserTab _currentTab = _BrowserTab.all;
  _BrowserSort _currentSort = _BrowserSort.nameAsc;
  String _letterFilter = '';
  bool _letterFilterVisible = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'games_search');
  final GlobalKey<CustomTVTextFieldState> _searchTvKey = GlobalKey();

  // Focus nodes
  final List<FocusNode> _carouselFocusNodes = [];
  final FocusNode _carouselPrevFocus = FocusNode(
    debugLabel: 'games_carousel_prev',
  );
  final FocusNode _carouselNextFocus = FocusNode(
    debugLabel: 'games_carousel_next',
  );
  final FocusNode _tabAllFocusNode = FocusNode(debugLabel: 'games_tab_all');
  final FocusNode _tabFavFocusNode = FocusNode(debugLabel: 'games_tab_fav');
  final FocusNode _tabRecentFocusNode = FocusNode(
    debugLabel: 'games_tab_recent',
  );
  final FocusNode _sortFocusNode = FocusNode(debugLabel: 'games_sort');
  final FocusNode _filterFocusNode = FocusNode(debugLabel: 'games_filter');
  final FocusNode _downloadedGamesFocus = FocusNode(
    debugLabel: 'games_downloaded',
  );
  final Map<_GamesNavItem, FocusNode> _navFocusNodes = {
    for (final item in _GamesNavItem.values)
      item: FocusNode(debugLabel: 'games_nav_${item.name}'),
  };
  final ScrollController _carouselController = ScrollController();
  final Map<String, FocusNode> _letterFocusNodes = {
    for (final letter in GameAlphaPickerBar.letters)
      letter: FocusNode(
        debugLabel: 'games_alpha_${letter.isEmpty ? 'all' : letter}',
      ),
  };

  /// On a TV the rail is a narrow strip of icons until it is opened, which is
  /// where the nav rows and the stat cards live. Left from the first console
  /// card opens it, so those stay reachable without spending a fifth of the
  /// screen on them.
  bool _sideMenuOpen = false;

  /// On a TV the sidebar stays expanded so the Total Games and Storage cards
  /// from the design are visible without opening it. Phones keep the rail.
  late bool _sidebarPinned = PlatformDetection.isTV;

  // Sidebar stats
  int _cachedBytes = 0;
  int? _freeBytes;

  // Console logos (ROM Manager plugin route), cached per session
  RomManagerLogoService? _logoService;

  // Clock
  String _clockLabel = '';
  Timer? _clockTimer;

  // Artwork and route lifecycle
  RetroArtworkActivityGate? _retroArtworkActivityGate;
  RetroArtworkTransport? _retroArtworkTransport;
  RetroArtworkDataSource? _retroArtworkDataSource;
  String? _retroArtworkServerIdentity;
  String? _artworkScope;
  ModalRoute<dynamic>? _observedRoute;
  bool _routeIsCovered = false;

  @override
  void initState() {
    super.initState();
    _contentScrollController.addListener(_onContentScroll);
    _logoService = widget.logoService ?? RomManagerLogoService();
    GameLocalData.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    GameLocalData.instance.changeNotifier.addListener(_onLocalDataChanged);
    unawaited(_initializeArtwork());
    _loadSystems();
    _refreshStorageStats();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _updateClock();
    });
  }

  void _updateClock() {
    // `clock.now()` so a golden test can pin the time of day instead of
    // recording whatever minute the suite happened to run in.
    final label = formatClockTime(
      clock.now(),
      use24Hour: _prefs.get(UserPreferences.use24HourClock),
    );
    if (mounted && label != _clockLabel) setState(() => _clockLabel = label);
  }

  void _onLocalDataChanged() {
    if (mounted) setState(() {});
  }

  /// Downloaded game bytes, plus the device's free space where the platform
  /// reports it. Both numbers are labelled for what they measure.
  Future<void> _refreshStorageStats() async {
    try {
      final list = await GameStorage.list();
      final bytes = list.fold<int>(0, (sum, g) => sum + g.bytes);
      int? free;
      try {
        final cacheRoot = await GameStorage.romsRoot();
        free = await availableDiskSpaceBytes(cacheRoot.path);
      } catch (_) {
        free = null;
      }
      if (!mounted) return;
      setState(() {
        _cachedBytes = bytes;
        _freeBytes = free;
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
    setState(() {});
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
    _clockTimer?.cancel();
    GameLocalData.instance.changeNotifier.removeListener(_onLocalDataChanged);
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _retroArtworkDataSource?.dispose();
    _retroArtworkTransport?.dispose();
    if (_artworkScope case final scope?) {
      releaseGameArtworkCacheScope(scope);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _contentScrollController.removeListener(_onContentScroll);
    _contentScrollController.dispose();
    _carouselController.dispose();
    for (final node in _carouselFocusNodes) {
      node.dispose();
    }
    _carouselPrevFocus.dispose();
    _carouselNextFocus.dispose();
    _tabAllFocusNode.dispose();
    _tabFavFocusNode.dispose();
    _tabRecentFocusNode.dispose();
    _sortFocusNode.dispose();
    _filterFocusNode.dispose();
    _downloadedGamesFocus.dispose();
    for (final node in _navFocusNodes.values) {
      node.dispose();
    }
    for (final node in _letterFocusNodes.values) {
      node.dispose();
    }
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
      for (final node in _carouselFocusNodes) {
        node.dispose();
      }
      _carouselFocusNodes.clear();
      for (var i = 0; i < systems.length; i++) {
        _carouselFocusNodes.add(FocusNode(debugLabel: 'console_carousel_$i'));
      }
      setState(() {
        _systems = systems;
        _loading = false;
      });
      unawaited(_ensureConsoleLogos());

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

  /// The name the ROM Manager plugin files a console logo under. The plugin
  /// folds names when matching, so the label the carousel shows is the one to
  /// ask for.
  String _logoNameFor(GameSystem system) =>
      gameSystemListName(id: system.id, name: system.name);

  /// Asks for any console logo this session has not asked about yet. A failure
  /// leaves the map empty and the badges fall back to styled names, which is
  /// the only thing a missing plugin does here.
  Future<void> _ensureConsoleLogos() async {
    final service = _logoService;
    if (service == null || _systems.isEmpty) return;
    try {
      final changed = await service.fetchConsoles(
        _client,
        _systems.map(_logoNameFor),
      );
      if (changed && mounted) setState(() {});
    } catch (_) {
      // No logos: the styled fallback is already on screen.
    }
  }

  String? _logoForSystem(GameSystem system) {
    try {
      return _logoService?.logoFor(_logoNameFor(system));
    } catch (_) {
      return null;
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

  @override
  void trackGridItemFocus(int index, bool hasFocus) {
    super.trackGridItemFocus(index, hasFocus);
    if (!hasFocus) return;
    if (index >= _allSystemGames.length - _gamesPrefetchTail) {
      _maybeLoadNextGamesPage();
    }
  }

  void _onContentScroll() {
    if (!_contentScrollController.hasClients) return;
    final position = _contentScrollController.position;
    if (!position.hasContentDimensions) return;
    if (position.maxScrollExtent - position.pixels <= _gamesScrollTailPx) {
      _maybeLoadNextGamesPage();
    }
  }

  bool get _needsFullCatalog {
    if (_currentTab != _BrowserTab.all) return true;
    if (_currentSort != _BrowserSort.nameAsc) return true;
    if (_letterFilter.isNotEmpty) return true;
    if (gameBrowseQueryWords(_searchController.text).isNotEmpty) return true;
    return false;
  }

  void _scheduleCatalogDrain() {
    if (!_needsFullCatalog ||
        _gamesComplete ||
        _loadingGames ||
        _loadingMoreGames) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeLoadNextGamesPage();
    });
  }

  void _scheduleViewportFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _gamesComplete || _loadingGames || _loadingMoreGames) {
        return;
      }
      if (!_contentScrollController.hasClients) return;
      final position = _contentScrollController.position;
      if (!position.hasContentDimensions) return;
      // The first page did not fill the screen, so fetch another rather than
      // waiting for a scroll that cannot happen.
      if (position.maxScrollExtent <= position.viewportDimension + 1) {
        _maybeLoadNextGamesPage();
      }
    });
  }

  Future<void> _loadGamesForSystem(GameSystem system) async {
    final epoch = ++_gamesEpoch;
    setState(() {
      _loadingGames = true;
      _loadingMoreGames = false;
      _allSystemGames = const [];
      _textIndexes = {};
      _romById = {};
      _covers = {};
      _romCatalog = false;
      _romCatalogDisabled = false;
      _gamesError = null;
      _gamesTotal = 0;
      _gamesComplete = false;
      _loadedSystemId = system.id;
    });
    cleanupGridFocusNodes(0);
    await _fetchGamesPage(system, 0, epoch);
  }

  void _maybeLoadNextGamesPage() {
    if (_loadingGames || _loadingMoreGames || _gamesComplete) return;
    final systemId = _loadedSystemId;
    if (systemId == null) return;
    GameSystem? system;
    for (final candidate in _systems) {
      if (candidate.id == systemId) {
        system = candidate;
        break;
      }
    }
    if (system == null) return;
    if (_gamesTotal > 0 && _allSystemGames.length >= _gamesTotal) {
      _gamesComplete = true;
      return;
    }
    _loadingMoreGames = true;
    unawaited(_fetchGamesPage(system, _allSystemGames.length, _gamesEpoch));
  }

  Future<void> _fetchGamesPage(GameSystem system, int offset, int epoch) async {
    final gamesApi = _client.gamesApi;
    if (gamesApi == null && widget.romGames == null) {
      if (mounted && epoch == _gamesEpoch) {
        setState(() {
          _loadingGames = false;
          _loadingMoreGames = false;
          _gamesComplete = true;
          _gamesError = 'Games API is not available.';
        });
      }
      return;
    }

    try {
      final loaded = await _loadGamePage(system, offset);
      if (!mounted || epoch != _gamesEpoch) return;
      if (_systems[_selectedSystemIndex].id != system.id) return;

      if (loaded.roms != null) {
        _romCatalog = true;
        for (final game in loaded.roms!) {
          _romById[game.key] = game;
        }
        if (loaded.roms!.isNotEmpty) unawaited(_loadCovers(loaded.roms!));
      } else if (offset == 0) {
        _romCatalog = false;
        _romCatalogDisabled = loaded.disableRomCatalog;
      }

      final page = loaded.page;
      final merged = offset == 0
          ? page.items
          : <GameSummary>[..._allSystemGames, ...page.items];
      final indexes = offset == 0
          ? <String, GameBrowseTextIndex>{}
          : Map<String, GameBrowseTextIndex>.of(_textIndexes);
      for (final game in page.items) {
        indexes[game.id] = GameBrowseTextIndex(
          game.title,
          alternateText: game.fileName,
        );
      }
      final complete = page.items.isEmpty || merged.length >= page.total;
      setState(() {
        _allSystemGames = merged;
        _textIndexes = indexes;
        _gamesTotal = page.total;
        _gamesComplete = complete;
        _gamesError = loaded.error;
        _loadingGames = false;
        _loadingMoreGames = false;
        _loadedSystemId = system.id;
      });
      cleanupGridFocusNodes(merged.length);
      if (!_romCatalog) {
        unawaited(_refreshArtworkPage(system.id, page.offset, page.limit));
      }
      if (!complete) {
        _scheduleViewportFill();
      }
    } catch (_) {
      // A failed later page leaves the rows already on screen and stops
      // asking. A failed first page used to look like a library of 0 games.
      if (!mounted || epoch != _gamesEpoch) return;
      setState(() {
        _loadingGames = false;
        _loadingMoreGames = false;
        _gamesComplete = true;
        if (offset == 0) {
          _gamesError = 'Could not load ${system.name}.';
        }
      });
    }
  }

  /// The phone's grouped catalog when ROM Manager answers, otherwise one
  /// window of the Moonbase file list. Does not touch widget state; the caller
  /// applies [_LoadedGamePage.roms] only if this load is still current.
  Future<_LoadedGamePage> _loadGamePage(GameSystem system, int offset) async {
    final rom = widget.romGames;
    if (rom != null && !_romCatalogDisabled) {
      final grouped = await rom.page(
        client: _client,
        system: system.name,
        offset: offset,
        sort: 'title',
      );
      if (grouped != null &&
          offset == 0 &&
          grouped.indexing &&
          grouped.items.isEmpty) {
        return _LoadedGamePage(
          page: GamePage(
            items: const [],
            total: 0,
            offset: 0,
            limit: RomManagerGames.pageSize,
          ),
          roms: const [],
          error: grouped.message ?? 'Library is being indexed.',
        );
      }
      final indexMiss =
          grouped != null &&
          offset == 0 &&
          grouped.items.isEmpty &&
          grouped.total == 0 &&
          !grouped.indexing &&
          system.gameCount > 0;
      if (grouped != null && !indexMiss) {
        return _LoadedGamePage(
          page: GamePage(
            items: [
              for (final game in grouped.items) game.toSummary(system.core),
            ],
            total: grouped.total,
            offset: offset,
            limit: RomManagerGames.pageSize,
          ),
          roms: grouped.items,
        );
      }
      // A later page must not switch to the file list mid-catalog. The rows
      // already on screen stay, and the grid stops requesting more.
      if (offset > 0) {
        throw StateError('ROM catalog page failed');
      }
      return _LoadedGamePage(
        page: await _moonbasePage(system, offset),
        disableRomCatalog: true,
      );
    }

    return _LoadedGamePage(page: await _moonbasePage(system, offset));
  }

  Future<GamePage> _moonbasePage(GameSystem system, int offset) {
    final gamesApi = _client.gamesApi;
    if (gamesApi == null) {
      throw StateError('Games API is not available.');
    }
    return gamesApi.getGamesPage(
      widget.libraryId,
      system: system.id,
      offset: offset,
      limit: _gamesPageSize,
    );
  }

  Future<void> _loadCovers(List<RomManagerGame> games) async {
    final rom = widget.romGames;
    if (rom == null) return;
    final epoch = _gamesEpoch;
    try {
      final covers = await rom.covers(_client, [
        for (final game in games) game.path,
      ]);
      if (!mounted || epoch != _gamesEpoch || covers.isEmpty) return;
      setState(() {
        for (final game in games) {
          final bytes = covers[game.path];
          if (bytes != null) _covers[game.key] = bytes;
        }
      });
    } catch (_) {
      // Posters keep the color fallback.
    }
  }

  Future<void> _refreshArtworkPage(
    String systemId,
    int offset,
    int limit,
  ) async {
    final source = _retroArtworkDataSource;
    if (source == null) return;
    try {
      await source.refreshSystem(
        libraryId: widget.libraryId,
        systemId: systemId,
        offset: offset,
        limit: limit,
      );
    } catch (_) {
      // Art for this page stays missing; the grid itself does not reset.
    }
  }

  List<GameSummary> _getFilteredAndSortedGames() {
    var games = _allSystemGames;
    final queryWords = gameBrowseQueryWords(_searchController.text);

    // Filter by tab
    if (_currentTab == _BrowserTab.favorites) {
      games = games
          .where(
            (g) => GameLocalData.instance.isFavorite(widget.libraryId, g.id),
          )
          .toList();
    } else if (_currentTab == _BrowserTab.recent) {
      games = games.where((g) {
        return GameLocalData.instance.recentIndex(widget.libraryId, g.id) !=
            null;
      }).toList();
    }

    // Search and the alphabetical picker
    if (queryWords.isNotEmpty || _letterFilter.isNotEmpty) {
      games = games.where((g) {
        final index = _textIndexes[g.id];
        if (index == null) {
          return gameTitleMatchesBrowseFilters(
            g.title,
            alternateText: g.fileName,
            query: _searchController.text,
            letter: _letterFilter,
          );
        }
        return index.matches(queryWords: queryWords, letter: _letterFilter);
      }).toList();
    }

    // Sort games
    if (_currentTab == _BrowserTab.recent) {
      // Recent ignores the name sort: most recently played first.
      games.sort((a, b) {
        final aIdx =
            GameLocalData.instance.recentIndex(widget.libraryId, a.id) ?? 9999;
        final bIdx =
            GameLocalData.instance.recentIndex(widget.libraryId, b.id) ?? 9999;
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
            final aIdx = GameLocalData.instance.recentIndex(
              widget.libraryId,
              a.id,
            );
            final bIdx = GameLocalData.instance.recentIndex(
              widget.libraryId,
              b.id,
            );
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

  bool get _sidebarVisible => _sideMenuOpen || _sidebarPinned;

  int get _totalGamesCount =>
      _systems.fold<int>(0, (sum, system) => sum + system.gameCount);

  void _openSideMenu() {
    if (!PlatformDetection.isTV) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    if (_sideMenuOpen) return;
    setState(() {
      _sideMenuOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navFocusNodes[_GamesNavItem.library]?.requestFocus();
    });
  }

  void _closeSideMenu({bool restoreFocus = true}) {
    if (!PlatformDetection.isTV) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (!_sideMenuOpen && !_sidebarPinned) return;
    setState(() {
      _sideMenuOpen = false;
      _sidebarPinned = false;
    });
    if (!restoreFocus) return;
    if (_systems.isNotEmpty &&
        _selectedSystemIndex < _carouselFocusNodes.length) {
      _carouselFocusNodes[_selectedSystemIndex].requestFocus();
    }
  }

  void _dispatchNavItem(_GamesNavItem item) {
    switch (item) {
      case _GamesNavItem.home:
        _closeSideMenu(restoreFocus: false);
        context.navigateTopLevel(Destinations.home);
      case _GamesNavItem.library:
      case _GamesNavItem.platforms:
        _closeSideMenu();
      case _GamesNavItem.favorites:
        _closeSideMenu();
        setState(() => _currentTab = _BrowserTab.favorites);
        _tabFavFocusNode.requestFocus();
      case _GamesNavItem.recent:
        _closeSideMenu();
        setState(() => _currentTab = _BrowserTab.recent);
        _tabRecentFocusNode.requestFocus();
      case _GamesNavItem.collections:
        _closeSideMenu(restoreFocus: false);
        context.push(Destinations.allFavorites);
      case _GamesNavItem.achievements:
      case _GamesNavItem.settings:
        _closeSideMenu(restoreFocus: false);
        unawaited(
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => item == _GamesNavItem.achievements
                      ? const AchievementsScreen()
                      : const SettingsSidePanel(),
                ),
              )
              .then((_) {
                if (!mounted) return;
                _navFocusNodes[item]?.requestFocus();
                _refreshStorageStats();
              }),
        );
    }
  }

  KeyEventResult _handleNavKeyEvent(_GamesNavItem item, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final items = _GamesNavItem.values;
    final index = items.indexOf(item);

    if (event.logicalKey.isDownKey) {
      final next = index + 1;
      if (next < items.length) {
        _navFocusNodes[items[next]]?.requestFocus();
      } else {
        _downloadedGamesFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isUpKey) {
      if (index > 0) {
        _navFocusNodes[items[index - 1]]?.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isBackKey) {
      // The rail is the last stop before leaving Games: grid → tabs → carousel
      // → rail → out. Right closes it without leaving for anyone who only
      // wants the menu put away.
      _exitGames();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      _closeSideMenu();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isSelectKey || isActivateKey(event)) {
      _dispatchNavItem(item);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSideMenuKeyEvent(KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    if (event.logicalKey.isBackKey) {
      _exitGames();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Leaves the Games destination. The rail has already been collapsed by the
  /// time this runs, so no animation is left half-done.
  void _exitGames() {
    _closeSideMenu(restoreFocus: false);
    context.popOrHome();
  }

  KeyEventResult _handleCarouselKeyEvent(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isLeftKey) {
      if (index == 0) {
        _openSideMenu();
      } else {
        _focusCarouselItem(index - 1);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      if (index >= _systems.length - 1) {
        _carouselNextFocus.requestFocus();
      } else {
        _focusCarouselItem(index + 1);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isDownKey) {
      _focusTab(_currentTab);
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isUpKey) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isBackKey) {
      _openSideMenu();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isSelectKey) {
      _selectSystem(index);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCarouselArrowKeyEvent(
    KeyEvent event, {
    required bool isNext,
  }) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isSelectKey || isActivateKey(event)) {
      _scrollCarousel(isNext ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isLeftKey) {
      if (isNext) {
        // The arrows bracket the row rather than chaining, so Left from the
        // trailing arrow lands on the last console and Right from the leading
        // one lands on the first, with no pass through an empty middle.
        if (_systems.isNotEmpty) {
          _focusCarouselItem(_systems.length - 1);
        }
      } else {
        _openSideMenu();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      if (!isNext && _systems.isNotEmpty) {
        _focusCarouselItem(0);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isDownKey) {
      _focusTab(_currentTab);
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isUpKey) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isBackKey) {
      _openSideMenu();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Moves focus along the console row and scrolls the row so the newly
  /// focused card is fully on screen.
  void _focusCarouselItem(int index) {
    if (index < 0 || index >= _carouselFocusNodes.length) return;
    _carouselFocusNodes[index].requestFocus();
    _revealCarouselItem(index);
  }

  void _scrollCarousel(int direction) {
    if (!_carouselController.hasClients) return;
    final position = _carouselController.position;
    final target = (position.pixels + direction * 400).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _carouselController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
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

  void _focusFirstGridItem() {
    final games = _getFilteredAndSortedGames();
    if (games.isEmpty) return;
    getGridItemFocusNode(0, prefix: 'game_poster').requestFocus();
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
      _focusFirstGridItem();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isLeftKey) {
      if (tab == _BrowserTab.favorites) {
        setState(() => _currentTab = _BrowserTab.all);
        _tabAllFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (tab == _BrowserTab.recent) {
        setState(() => _currentTab = _BrowserTab.favorites);
        _tabFavFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (tab == _BrowserTab.all) {
        _openSideMenu();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey.isRightKey) {
      if (tab == _BrowserTab.all) {
        setState(() => _currentTab = _BrowserTab.favorites);
        _tabFavFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (tab == _BrowserTab.favorites) {
        setState(() => _currentTab = _BrowserTab.recent);
        _tabRecentFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (tab == _BrowserTab.recent) {
        _sortFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey.isBackKey) {
      if (_selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      }
      return KeyEventResult.handled;
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
      _focusFirstGridItem();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isLeftKey) {
      _tabRecentFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      _filterFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isBackKey) {
      _tabRecentFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isSelectKey) {
      _cycleSort();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleFilterKeyEvent(KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isLeftKey || event.logicalKey.isBackKey) {
      _sortFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isUpKey) {
      if (_selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isDownKey) {
      _focusFirstGridItem();
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isRightKey) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey.isSelectKey) {
      setState(() => _letterFilterVisible = !_letterFilterVisible);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSearchKeyEvent(KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    if (event.logicalKey.isDownKey) {
      if (_selectedSystemIndex < _carouselFocusNodes.length) {
        _carouselFocusNodes[_selectedSystemIndex].requestFocus();
      } else {
        _focusTab(_currentTab);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isBackKey) {
      _openSideMenu();
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

  String get _sortLabel => switch (_currentSort) {
    _BrowserSort.nameAsc => 'Name A–Z',
    _BrowserSort.nameDesc => 'Name Z–A',
    _BrowserSort.recent => 'Recently played',
  };

  void _openGameDetail(GameSummary game) {
    final rom = _romById[game.id];
    if (rom == null) {
      context.push(Destinations.gameDetailOf(widget.libraryId, game.id));
      return;
    }
    unawaited(_openRomGame(rom));
  }

  Future<void> _openRomGame(RomManagerGame game) async {
    final rom = widget.romGames;
    if (rom == null) return;
    final resolved = await rom.launch(
      client: _client,
      key: game.key,
      path: game.path,
    );
    if (!mounted) return;
    final libraryId = resolved?.libraryId;
    final gameId = resolved?.gameId;
    if (libraryId == null ||
        libraryId.isEmpty ||
        gameId == null ||
        gameId.isEmpty) {
      _showGameMessage(resolved?.reason ?? 'Could not open this game.');
      return;
    }
    context.push(Destinations.gameDetailOf(libraryId, gameId));
  }

  void _toggleFavorite(GameSummary game) {
    unawaited(GameLocalData.instance.toggleFavorite(widget.libraryId, game.id));
  }

  /// Resolves the core for this game the same way the rest of the app does, so
  /// a console without an installable core shows the friendly message instead
  /// of failing to boot.
  Future<void> _playGame(GameSummary game) async {
    final romGame = _romById[game.id];
    if (romGame != null) {
      await _playRomGame(romGame, game);
      return;
    }
    final gamesApi = _client.gamesApi;
    if (gamesApi == null) return;
    try {
      final detail = await gamesApi.getGame(widget.libraryId, game.id);
      if (!mounted || detail == null) return;
      final launched = launchGame(
        context,
        widget.libraryId,
        detail,
        hardwareRenderingEnabled: _prefs.get(
          UserPreferences.useHardwareRendering,
        ),
      );
      if (launched) {
        await GameLocalData.instance.recordRecent(widget.libraryId, game.id);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showGameMessage(
        gamePlaybackBlockedMessage(game.core) ??
            AppLocalizations.of(context).gamePlaybackUnsupported,
      );
    }
  }

  Future<void> _playRomGame(RomManagerGame game, GameSummary summary) async {
    final rom = widget.romGames;
    final gamesApi = _client.gamesApi;
    if (rom == null || gamesApi == null) return;
    try {
      final resolved = await rom.launch(
        client: _client,
        key: game.key,
        path: game.path,
      );
      if (!mounted) return;
      if (resolved == null || resolved.playable != true) {
        _showGameMessage(resolved?.reason ?? 'This game cannot be played.');
        return;
      }
      final libraryId = resolved.libraryId;
      final gameId = resolved.gameId;
      if (libraryId == null || gameId == null) {
        _showGameMessage(resolved.reason ?? 'This game cannot be played.');
        return;
      }
      final detail = await gamesApi.getGame(libraryId, gameId);
      if (!mounted || detail == null) return;
      final launched = launchGame(
        context,
        libraryId,
        detail,
        name: game.title,
        hardwareRenderingEnabled: _prefs.get(
          UserPreferences.useHardwareRendering,
        ),
      );
      if (launched) {
        await GameLocalData.instance.recordRecent(widget.libraryId, summary.id);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showGameMessage(
        gamePlaybackBlockedMessage(summary.core) ??
            AppLocalizations.of(context).gamePlaybackUnsupported,
      );
    }
  }

  void _showGameMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
        backgroundColor: _kGamesBackdropBottom,
        drawer: isTV ? null : _GamesSidebar(open: true, screen: this),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kGamesBackdropTop, _kGamesBackdropBottom],
            ),
          ),
          child: SafeArea(
            child: _loading
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
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isTV)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: _sidebarVisible ? 288 : 76,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: _sidebarVisible ? 288 : 76,
                              maxWidth: _sidebarVisible ? 288 : 76,
                              child: _GamesSidebar(
                                open: _sidebarVisible,
                                screen: this,
                              ),
                            ),
                          ),
                        ),
                      Expanded(child: _buildMainContent()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    _scheduleCatalogDrain();
    final filteredGames = _getFilteredAndSortedGames();
    final isTV = PlatformDetection.isTV;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            controller: _contentScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBrowseHeading(),
                const SizedBox(height: 10),
                _buildConsoleCarousel(),
                const SizedBox(height: 20),
                _buildSectionHeader(_headerGameCount(filteredGames)),
                const SizedBox(height: 12),
                _buildTabsAndSortRow(),
                if (_letterFilterVisible) ...[
                  const SizedBox(height: 10),
                  GameAlphaPickerBar(
                    selected: _letterFilter,
                    onChanged: (letter) =>
                        setState(() => _letterFilter = letter),
                    letterFocusNodes: _letterFocusNodes,
                    onNavigateUp: () => _filterFocusNode.requestFocus(),
                  ),
                ],
                const SizedBox(height: 14),
                _loadingGames
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _gamesError != null && filteredGames.isEmpty
                    ? _buildGamesError()
                    : _buildGamesGrid(filteredGames),
                SizedBox(height: isTV ? 32 : 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final isTV = PlatformDetection.isTV;
    return Padding(
      padding: EdgeInsets.fromLTRB(isTV ? 28 : 16, 16, isTV ? 28 : 16, 4),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: LocalSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                tvFieldKey: _searchTvKey,
                hint: 'Search games, platforms, genres...',
                onChanged: (_) => setState(() {}),
                onTvKeyEvent: (node, event) => _handleSearchKeyEvent(event),
              ),
            ),
          ),
          const Spacer(),
          Text(
            _clockLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: isTV ? 20 : 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildBrowseHeading() {
    final isTV = PlatformDetection.isTV;
    return Padding(
      padding: EdgeInsets.fromLTRB(isTV ? 28 : 16, 8, isTV ? 28 : 16, 0),
      child: Text(
        'Browse by Console',
        style: TextStyle(
          color: Colors.white,
          fontSize: isTV ? 24 : 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildConsoleCarousel() {
    final isTV = PlatformDetection.isTV;
    if (_systems.isEmpty) {
      return const SizedBox(height: 200);
    }
    final cardHeight = isTV ? 208.0 : 176.0;

    return SizedBox(
      height: cardHeight + 20,
      child: Row(
        children: [
          const SizedBox(width: 12),
          _buildCarouselArrow(isNext: false),
          Expanded(
            child: ListView.separated(
              controller: _carouselController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _systems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final system = _systems[index];
                final focusNode = _carouselFocusNodes[index];
                return _ConsoleCard(
                  system: system,
                  displayName: _logoNameFor(system),
                  logo: _logoForSystem(system),
                  height: cardHeight,
                  isSelected: index == _selectedSystemIndex,
                  focusNode: focusNode,
                  autofocus: PlatformDetection.isTV && index == 0,
                  transport: _retroArtworkTransport,
                  activityGate: _retroArtworkActivityGate,
                  libraryId: widget.libraryId,
                  serverIdentity: _retroArtworkServerIdentity,
                  onSelect: () => _selectSystem(index),
                  onFocusChange: (focused) {
                    if (!focused) return;
                    if (_selectedSystemIndex != index) _selectSystem(index);
                    setState(() {});
                    _revealCarouselItem(index);
                  },
                  onKeyEvent: (event) => _handleCarouselKeyEvent(index, event),
                );
              },
            ),
          ),
          _buildCarouselArrow(isNext: true),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  void _revealCarouselItem(int index) {
    if (!_carouselController.hasClients) return;
    final position = _carouselController.position;
    const itemExtent = 196.0 + 14.0;
    final target = (index * itemExtent - 24).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((position.pixels - target).abs() < 8) return;
    _carouselController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildCarouselArrow({required bool isNext}) {
    final isTV = PlatformDetection.isTV;
    final focusNode = isNext ? _carouselNextFocus : _carouselPrevFocus;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTV ? 4 : 2),
      child: _RoundFocusButton(
        focusNode: focusNode,
        size: isTV ? 52 : 40,
        icon: isNext ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
        debugLabel: isNext ? 'games-carousel-next' : 'games-carousel-prev',
        onTap: () => _scrollCarousel(isNext ? 1 : -1),
        onKeyEvent: (event) =>
            _handleCarouselArrowKeyEvent(event, isNext: isNext),
      ),
    );
  }

  int _headerGameCount(List<GameSummary> filtered) {
    final unfiltered =
        _currentTab == _BrowserTab.all &&
        _letterFilter.isEmpty &&
        gameBrowseQueryWords(_searchController.text).isEmpty;
    if (unfiltered && _gamesTotal > 0) return _gamesTotal;
    return filtered.length;
  }

  Widget _buildSectionHeader(int visibleCount) {
    final isTV = PlatformDetection.isTV;
    final system = _systems[_selectedSystemIndex];
    final name = _logoNameFor(system);
    final logo = _logoForSystem(system);
    final amiga =
        isAmigaSystemId(system.id) ||
        isAmigaSystemId(system.core) ||
        isAmigaSystemId(system.name);

    return Padding(
      padding: EdgeInsets.fromLTRB(isTV ? 28 : 16, 0, isTV ? 28 : 16, 0),
      child: Row(
        children: [
          Container(
            width: isTV ? 44 : 34,
            height: isTV ? 44 : 34,
            padding: EdgeInsets.all(isTV ? 8 : 6),
            decoration: BoxDecoration(
              color: _kGamesPanelLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: amiga
                ? const AmigaSystemMark()
                : logo != null
                ? ConsoleLogo(dataUri: logo, height: isTV ? 28 : 22)
                : Icon(
                    Icons.sports_esports_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: isTV ? 22 : 18,
                  ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isTV ? 24 : 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '| $visibleCount Games',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: isTV ? 15 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsAndSortRow() {
    final isTV = PlatformDetection.isTV;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTV ? 28 : 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildTabButton(
            label: 'All Games',
            tab: _BrowserTab.all,
            focusNode: _tabAllFocusNode,
            debugLabel: 'games-tab-all',
          ),
          _buildTabButton(
            label: 'Favorites',
            tab: _BrowserTab.favorites,
            focusNode: _tabFavFocusNode,
            debugLabel: 'games-tab-favorites',
          ),
          _buildTabButton(
            label: 'Recently Played',
            tab: _BrowserTab.recent,
            focusNode: _tabRecentFocusNode,
            debugLabel: 'games-tab-recent',
          ),
          _buildSortButton(),
          _buildFilterButton(),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required _BrowserTab tab,
    required FocusNode focusNode,
    required String debugLabel,
  }) {
    final isSelected = _currentTab == tab;
    final isTV = PlatformDetection.isTV;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Focus(
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
              child: AnimatedContainer(
                key: ValueKey(debugLabel),
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(
                  horizontal: isTV ? 20 : 14,
                  vertical: isTV ? 10 : 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColorScheme.accent.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: hasFocus
                        ? AppColorScheme.accent
                        : isSelected
                        ? AppColorScheme.accent.withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.14),
                    width: hasFocus ? 2 : 1.2,
                  ),
                  boxShadow: (isSelected || hasFocus)
                      ? [
                          BoxShadow(
                            color: AppColorScheme.accent.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected || hasFocus
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.72),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: isTV ? 15 : 13,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSortButton() {
    final isTV = PlatformDetection.isTV;

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
            child: AnimatedContainer(
              key: const ValueKey('games-sort'),
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(
                horizontal: isTV ? 16 : 12,
                vertical: isTV ? 10 : 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hasFocus
                      ? AppColorScheme.accent
                      : Colors.white.withValues(alpha: 0.14),
                  width: hasFocus ? 2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: isTV ? 18 : 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Sort:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: isTV ? 14 : 12.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _sortLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: hasFocus ? 1 : 0.8),
                      fontSize: isTV ? 14 : 12.5,
                      fontWeight: FontWeight.w600,
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

  Widget _buildFilterButton() {
    final isTV = PlatformDetection.isTV;
    final active = _letterFilterVisible || _letterFilter.isNotEmpty;

    return Focus(
      focusNode: _filterFocusNode,
      onKeyEvent: (node, event) => _handleFilterKeyEvent(event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              setState(() => _letterFilterVisible = !_letterFilterVisible);
              _filterFocusNode.requestFocus();
            },
            child: AnimatedContainer(
              key: const ValueKey('games-filter'),
              duration: const Duration(milliseconds: 140),
              width: isTV ? 44 : 38,
              height: isTV ? 44 : 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColorScheme.accent.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: hasFocus
                      ? AppColorScheme.accent
                      : active
                      ? AppColorScheme.accent.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.14),
                  width: hasFocus ? 2 : 1.2,
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: isTV ? 20 : 17,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDownloadedGamesButton() {
    return Focus(
      focusNode: _downloadedGamesFocus,
      onKeyEvent: (node, event) {
        if (!event.isActionable) return KeyEventResult.ignored;
        if (event.logicalKey.isBackKey || event.logicalKey.isRightKey) {
          _closeSideMenu();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isUpKey) {
          _navFocusNodes[_GamesNavItem.settings]?.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isSelectKey || isActivateKey(event)) {
          _openDownloadedGames();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: _openDownloadedGames,
            child: AnimatedContainer(
              key: const ValueKey('games-sidebar-downloaded'),
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: hasFocus
                    ? AppColorScheme.accent
                    : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: hasFocus
                      ? AppColorScheme.accent
                      : Colors.white.withValues(alpha: 0.12),
                  width: hasFocus ? 2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_for_offline_rounded,
                    size: 18,
                    color: hasFocus ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Downloaded Games',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasFocus ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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

  void _openDownloadedGames() {
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const DownloadedGamesScreen(),
            ),
          )
          .then((_) {
            if (!mounted) return;
            _refreshStorageStats();
            _downloadedGamesFocus.requestFocus();
          }),
    );
  }

  Widget _buildGamesError() {
    final system = _systems[_selectedSystemIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _gamesError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadGamesForSystem(system),
              child: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesGrid(List<GameSummary> games) {
    if (games.isEmpty) {
      final emptyText = _searchController.text.trim().isNotEmpty
          ? 'No games match your search'
          : switch (_currentTab) {
              _BrowserTab.all => 'No games found',
              _BrowserTab.favorites => 'No favorites yet',
              _BrowserTab.recent => 'No recently played games',
            };

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    final isTV = PlatformDetection.isTV;

    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredCardWidth = isTV ? 152.0 : 140.0;
        const spacing = 16.0;
        final sidePadding = isTV ? 28.0 : 16.0;
        final availableWidth = constraints.maxWidth - sidePadding * 2;
        final crossAxisCount =
            ((availableWidth + spacing) / (preferredCardWidth + spacing))
                .floor()
                .clamp(2, 20);
        final cardWidth =
            (availableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final imageHeight = cardWidth * RetroArtworkShape.portraitHeightRatio;
        final cardHeight = imageHeight + 52;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 24),
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
            final cardFocusNode = getGridItemFocusNode(
              index,
              prefix: 'game_poster',
            );
            final isFirstRow = index < crossAxisCount;
            final isLastColumn = (index % crossAxisCount) == crossAxisCount - 1;
            final isFirstColumn = (index % crossAxisCount) == 0;
            final isLastItem = index == games.length - 1;
            final isBottomRow = index >= games.length - crossAxisCount;

            final reference = _routeIsCovered
                ? null
                : _retroArtworkDataSource?.imageFor(game.id);
            final cover = _covers[game.id];
            final source = cover == null ? reference?.source : null;
            final artAspect = _retroArtworkDataSource?.snapshot?.aspectRatioFor(
              game.id,
            );
            final cell = RetroArtworkShape.cellFor(artAspect);
            final containArt = RetroArtworkShape.shouldContain(
              cellAspect: artAspect,
              artAspect: artAspect,
              shapeAspect: cell.aspectRatio,
            );

            return GestureDetector(
              onLongPress: () => _toggleFavorite(game),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GamePosterCard(
                    imageUrl: cover == null ? reference?.legacyUrl : null,
                    imageFit: containArt ? BoxFit.contain : BoxFit.cover,
                    fillBehind: containArt && source == null && cover == null,
                    artwork: cover != null
                        ? Image.memory(
                            cover,
                            fit: containArt ? BoxFit.contain : BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : source == null ||
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
                    onKeyEvent: (_, event) {
                      if (!event.isActionable) return KeyEventResult.ignored;

                      if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                          event.logicalKey.isContextMenuKey) {
                        _toggleFavorite(game);
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey ==
                          LogicalKeyboardKey.mediaPlayPause) {
                        unawaited(_playGame(game));
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey.isBackKey) {
                        _focusTab(_currentTab);
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey.isUpKey && isFirstRow) {
                        _focusTab(_currentTab);
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey.isLeftKey && isFirstColumn) {
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey.isRightKey &&
                          (isLastColumn || isLastItem)) {
                        return KeyEventResult.handled;
                      }

                      if (event.logicalKey.isDownKey && isBottomRow) {
                        return KeyEventResult.handled;
                      }

                      return KeyEventResult.ignored;
                    },
                    onTap: () => _openGameDetail(game),
                  ),
                  Positioned(left: 6, top: 6, child: _GameBadges(game: game)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LoadedGamePage {
  const _LoadedGamePage({
    required this.page,
    this.roms,
    this.disableRomCatalog = false,
    this.error,
  });

  final GamePage page;
  final List<RomManagerGame>? roms;
  final bool disableRomCatalog;
  final String? error;
}

/// The "2 Versions" / "Cheat" / "Hack" chips over a box art. The server does
/// not send these today, so the widget collapses to nothing unless a response
/// carries the fields.
class _GameBadges extends StatelessWidget {
  const _GameBadges({required this.game});

  final GameSummary game;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (game.hasMultipleVersions)
        _badge('${game.versionsCount} Versions', const Color(0xFF2E7BFF)),
      if (game.isCheat) _badge('Cheat', const Color(0xFFB7791F)),
      if (game.isHack) _badge('Hack', const Color(0xFF805AD5)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// A round, focusable chevron used either side of the console carousel.
class _RoundFocusButton extends StatelessWidget {
  const _RoundFocusButton({
    required this.focusNode,
    required this.size,
    required this.icon,
    required this.onTap,
    required this.onKeyEvent,
    required this.debugLabel,
  });

  final FocusNode focusNode;
  final double size;
  final IconData icon;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final String debugLabel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Semantics(
            button: true,
            label: debugLabel,
            child: GestureDetector(
              onTap: () {
                onTap();
                focusNode.requestFocus();
              },
              child: AnimatedContainer(
                key: ValueKey(debugLabel),
                duration: const Duration(milliseconds: 140),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasFocus
                      ? AppColorScheme.accent.withValues(alpha: 0.3)
                      : _kGamesPanelLight,
                  border: Border.all(
                    color: hasFocus
                        ? AppColorScheme.accent
                        : Colors.white.withValues(alpha: 0.12),
                    width: hasFocus ? 2 : 1.2,
                  ),
                  boxShadow: hasFocus
                      ? [
                          BoxShadow(
                            color: AppColorScheme.accent.withValues(alpha: 0.4),
                            blurRadius: 18,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withValues(alpha: hasFocus ? 1 : 0.7),
                  size: size * 0.55,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A tall, glossy console tile: the console logo over a fan of box art from its
/// own library, tilted back until it is selected or focused, when it stands
/// upright inside a blue glow.
class _ConsoleCard extends StatefulWidget {
  const _ConsoleCard({
    required this.system,
    required this.displayName,
    required this.logo,
    required this.height,
    required this.isSelected,
    required this.focusNode,
    required this.autofocus,
    required this.transport,
    required this.activityGate,
    required this.libraryId,
    required this.serverIdentity,
    required this.onSelect,
    required this.onFocusChange,
    required this.onKeyEvent,
  });

  final GameSystem system;
  final String displayName;
  final String? logo;
  final double height;
  final bool isSelected;
  final FocusNode focusNode;
  final bool autofocus;
  final RetroArtworkTransport? transport;
  final RetroArtworkActivityGate? activityGate;
  final String? libraryId;
  final String? serverIdentity;
  final VoidCallback onSelect;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  @override
  State<_ConsoleCard> createState() => _ConsoleCardState();
}

class _ConsoleCardState extends State<_ConsoleCard> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _hasFocus;
    final amiga =
        isAmigaSystemId(widget.system.id) ||
        isAmigaSystemId(widget.system.core) ||
        isAmigaSystemId(widget.system.name);
    final borders = ThemeRegistry.active.borders;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (_hasFocus != focused) setState(() => _hasFocus = focused);
        widget.onFocusChange(focused);
      },
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: GestureDetector(
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onSelect();
        },
        child: AnimatedContainer(
          key: ValueKey('console-card-${widget.system.id}'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: active ? 196 : 176,
          height: widget.height,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateZ(active ? 0 : -0.012),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: borders.cardRadius,
            border: Border.all(
              color: active
                  ? AppColorScheme.accent
                  : Colors.white.withValues(alpha: 0.1),
              width: active ? 2.5 : 1.2,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColorScheme.accent.withValues(alpha: 0.45),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kGamesPanelLight,
                gameFallbackColor(widget.system.id).withValues(alpha: 0.55),
                _kGamesPanelDark,
              ],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ConsoleFan(
                system: widget.system,
                transport: widget.transport,
                activityGate: widget.activityGate,
                libraryId: widget.libraryId,
                serverIdentity: widget.serverIdentity,
              ),
              // Glossy sheen plus a scrim so the logo and label stay readable.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0, 0.3, 0.7, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 40,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: amiga
                            ? const SizedBox(
                                width: 88,
                                child: AmigaSystemMark(),
                              )
                            : widget.logo != null
                            ? ConsoleLogo(
                                dataUri: widget.logo!,
                                height: 34,
                                fit: BoxFit.contain,
                              )
                            : Icon(
                                Icons.sports_esports_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                                size: 26,
                              ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: active ? 16 : 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.system.gameCount} Games',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three overlapping box-art covers, fanned like a hand of cards, behind the
/// console logo.
class _ConsoleFan extends StatelessWidget {
  const _ConsoleFan({
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

  static const int _count = 3;

  @override
  Widget build(BuildContext context) {
    final panels = system.previewArtwork?.panels ?? const [];

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth * 0.46).clamp(56.0, 96.0);
            final cardHeight = cardWidth * 1.25;
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                for (var i = 0; i < _count; i++)
                  Positioned(
                    top: 0,
                    left:
                        constraints.maxWidth / 2 -
                        cardWidth / 2 +
                        (i - 1) * cardWidth * 0.42,
                    child: Transform.rotate(
                      angle: (i - 1) * 0.14,
                      child: Opacity(
                        opacity: i == 1 ? 1 : 0.85,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: _SystemPreviewArtwork(
                              panel: i < panels.length ? panels[i] : null,
                              fallbackSeed:
                                  i < panels.length &&
                                      panels[i].gameId.isNotEmpty
                                  ? panels[i].gameId
                                  : '${system.id}:$i',
                              transport: transport,
                              activityGate: activityGate,
                              libraryId: libraryId,
                              serverIdentity: serverIdentity,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
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
      child: Center(
        child: Icon(
          Icons.videogame_asset_rounded,
          color: Colors.white.withValues(alpha: 0.35),
          size: 20,
        ),
      ),
    );
  }
}

/// The left rail. On a TV it collapses to a strip of icons and expands over the
/// content when opened; on a phone it fills the drawer. The nav rows only exist
/// on the TV rail, whose destination is this screen rather than the hub.
class _GamesSidebar extends StatelessWidget {
  const _GamesSidebar({required this.open, required this.screen});

  final bool open;
  final _GamesBrowserScreenState screen;

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformDetection.isTV;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kGamesPanelLight.withValues(alpha: 0.96),
            _kGamesPanelDark.withValues(alpha: 0.98),
          ],
        ),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => screen._handleSideMenuKeyEvent(event),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: open ? 16 : 10,
              vertical: 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 18),
                if (isTV)
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final item in _GamesNavItem.values)
                          _buildNavRow(item, isTV: true),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (open) ...[
                  _buildTotalGamesCard(),
                  const SizedBox(height: 12),
                  _buildStorageCard(context),
                  const SizedBox(height: 12),
                  screen._buildDownloadedGamesButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (!open) {
      return Column(
        children: [
          SizedBox(
            height: 34,
            child: FittedBox(child: MoFinBrand(onDark: true, height: 26)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Flexible(child: MoFinBrand(onDark: true, height: 26))]),
        const SizedBox(height: 6),
        Text(
          'EMULATION',
          style: TextStyle(
            color: AppColorScheme.accent.withValues(alpha: 0.9),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }

  Widget _buildNavRow(_GamesNavItem item, {required bool isTV}) {
    final selected = item == _GamesNavItem.library;
    final focusNode = screen._navFocusNodes[item];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) => screen._handleNavKeyEvent(item, event),
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            return Semantics(
              button: true,
              selected: selected,
              child: GestureDetector(
                onTap: () {
                  focusNode?.requestFocus();
                  screen._dispatchNavItem(item);
                },
                child: AnimatedContainer(
                  key: ValueKey('games-sidebar-row-${item.name}'),
                  duration: const Duration(milliseconds: 140),
                  padding: EdgeInsets.symmetric(
                    horizontal: open ? 12 : 0,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected
                        ? AppColorScheme.accent.withValues(alpha: 0.22)
                        : hasFocus
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: hasFocus
                          ? AppColorScheme.accent
                          : selected
                          ? AppColorScheme.accent.withValues(alpha: 0.55)
                          : Colors.transparent,
                      width: hasFocus ? 2 : 1.2,
                    ),
                    boxShadow: hasFocus
                        ? [
                            BoxShadow(
                              color: AppColorScheme.accent.withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: open
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: selected || hasFocus
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                      ),
                      if (open) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected || hasFocus
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTotalGamesCard() {
    return _StatCard(
      key: const ValueKey('games-sidebar-total-games'),
      label: 'Total Games',
      value: '${screen._totalGamesCount}',
      icon: Icons.videogame_asset_rounded,
    );
  }

  Widget _buildStorageCard(BuildContext context) {
    final cached = screen._cachedBytes;
    final free = screen._freeBytes;
    final caption = free != null
        ? '${formatBytes(free)} free space on this device'
        : 'Downloaded game files';
    final fraction = free != null && (cached + free) > 0
        ? (cached / (cached + free)).clamp(0.0, 1.0)
        : 0.0;

    return _StatCard(
      key: const ValueKey('games-sidebar-storage'),
      label: 'Downloaded Storage',
      value: formatBytes(cached),
      icon: Icons.storage_rounded,
      caption: caption,
      progress: fraction,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.progress,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: AppColorScheme.accent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColorScheme.accent,
                ),
              ),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              maxLines: 2,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
