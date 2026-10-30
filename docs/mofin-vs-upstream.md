# MoFin vs. Upstream Moonfin-Core Changes & Plugin Migration Assessment

This document lists every file added or modified in MoFin relative to the upstream Moonfin-Core repository baseline (`commit e61ac43cacfe8a3674dbd7b0c7719b2ce6b95e29`), grouped by feature module. Each feature includes an evaluation of the effort and feasibility of migrating it into a web-based plugin using the MoFin Plugin Host API (`packages/plugin_host`).

---

## 1. Direct IPTV Module ("Mo Fin" Source)

### Added / Modified Files & Line Ranges
- `lib/direct_iptv/direct_iptv_client.dart` (Lines 1-285): Direct IPTV M3U/M3U8 client and HTTP fetcher.
- `lib/direct_iptv/direct_iptv_catalog.dart` (Lines 1-320): Category grouping, playlist indexing, and channel filtering.
- `lib/direct_iptv/direct_iptv_playback.dart` (Lines 1-190): Direct stream resolver, failover logic across stack members, and HTTP header inspection (`X-Mofin-Member`).
- `lib/direct_iptv/direct_iptv_recordings.dart` (Lines 1-140): Recording request poster and recording playlist hint builder.
- `lib/direct_iptv/direct_iptv_resolver.dart` (Lines 1-160): Channel URL resolver.
- `lib/direct_iptv/direct_guide.dart` (Lines 1-250): EPG data structures and channel mapping.
- `lib/direct_iptv/guide_tmdb.dart` (Lines 1-180): TMDB metadata enhancer for live channels.
- `lib/direct_iptv/guide_tmdb_client.dart` (Lines 1-120): TMDB client for EPG art and summaries.
- `lib/direct_iptv/models.dart` (Lines 1-150): M3U channel, stack, and recording data models.
- `lib/direct_iptv/mofin_report.dart` (Lines 1-130): `/report`, `/remove`, and `/resolution` API client.
- `lib/direct_iptv/playlist_parse.dart` (Lines 1-210): Extended M3U tag parser (`x-mofin-*`, `group-title`, `tvg-id`).
- `lib/direct_iptv/snapshot_store.dart`, `snapshot_store_io.dart`, `snapshot_store_stub.dart` (Lines 1-180 combined): Local snapshot disk store.
- `lib/ui/screens/livetv/direct_iptv_guide_screen.dart` (Lines 1-310): Direct IPTV grid UI screen.
- `lib/ui/screens/livetv/live_tv_screen.dart` (Lines 45-120): Added Direct IPTV tab navigation button.
- `docs/direct-iptv.md` (Lines 1-52): Documentation for Direct IPTV source.
- `docs/channel-server-api.md` (Lines 1-140): Direct IPTV channel server API spec.

### Plugin Migration Difficulty: **Medium**
- **Rationale**: Direct IPTV requires fetching M3U playlists, parsing channel stacks, and sending feedback reports (`/report`, `/remove`, `/resolution`). A web plugin running in WebView can easily parse M3U, display a custom channel guide screen, store cached channels via plugin storage (`storageSet`), and launch playback of stream URLs via `playMedia({streamUrl: ...})`. Automatic stream resolution telemetry from native playback requires bridge progress hooks.

---

## 2. TMDB Streaming Integration Module

### Added / Modified Files & Line Ranges
- `lib/streaming/streaming_service.dart` (Lines 1-210): Queries TMDB for trending content across Netflix, Disney+, Max, Prime Video.
- `lib/streaming/tmdb_streaming_client.dart` (Lines 1-180): TMDB REST API HTTP client.
- `lib/streaming/tmdb_key_store.dart` (Lines 1-85): TMDB API key storage and configuration.
- `lib/streaming/streaming_launcher.dart` (Lines 1-110): Native app deeplink launcher (Fire TV / Android TV) and web browser redirect.
- `lib/ui/screens/streaming/streaming_screen.dart` (Lines 1-290): Streaming dashboard UI showing provider rows.
- `lib/ui/screens/streaming/streaming_detail_screen.dart` (Lines 1-260): Streaming title detail and provider selector screen.
- `docs/streaming.md` (Lines 1-38): Documentation for TMDB Streaming integration.

### Plugin Migration Difficulty: **Easy**
- **Rationale**: TMDB API queries and UI presentation are pure web technology (HTML/JS/CSS). The plugin host API provides `registerHomeRow` / `registerSettingsPage` and `openPluginScreen`. Deep launching external native apps (or opening external web links) can be routed through a host bridge method.

---

## 3. Retro Gaming & Emulators Module

### Added / Modified Files & Line Ranges
- `lib/ui/screens/games/game_library_screen.dart` (Lines 1-340): Retro game systems & titles browser.
- `lib/ui/screens/games/game_system_screen.dart` (Lines 1-280): System-specific game grid view.
- `lib/ui/screens/games/game_detail_screen.dart` (Lines 1-310): Game detail view, artwork viewer, launch options.
- `lib/ui/screens/playback/game_emulator_screen.dart` (Lines 1-420): EmulatorJS web view runner.
- `lib/ui/screens/playback/native_game_player_screen.dart` (Lines 1-380): Native libretro player integration.
- `lib/util/game_cores.dart` (Lines 1-260): Supported libretro core definitions (NES, SNES, Genesis, Commodore Amiga PUAE, etc.).
- `lib/util/game_storage.dart` (Lines 1-150): ROM unpacking, extraction, and save-state storage.
- `lib/data/services/retro_artwork/` (Lines 1-380 across 4 files): Retro game artwork fetchers.

### Plugin Migration Difficulty: **Hard**
- **Rationale**: While EmulatorJS is web-based, native libretro execution (`native_game_player_screen.dart`), C++ ABI bindings, and native ROM file extraction (`game_storage.dart`) rely on compiled native C/Dart code. The EmulatorJS frontend can be hosted as a web plugin, but native libretro execution must remain in the app shell.

---

## 4. Seerr Integration Module (Jellyseerr / Overseerr)

### Added / Modified Files & Line Ranges
- `lib/ui/screens/seerr/seerr_discover_screen.dart` (Lines 1-320): Seerr discover dashboard.
- `lib/ui/screens/seerr/seerr_requests_screen.dart` (Lines 1-240): Seerr request and issue management screen.
- `lib/ui/screens/seerr/seerr_browse_screen.dart` (Lines 1-210): Seerr category filter browser.
- `lib/ui/screens/seerr/seerr_collection_screen.dart` (Lines 1-190): Seerr collection detail view.
- `lib/ui/screens/seerr/seerr_person_screen.dart` (Lines 1-180): Seerr person detail view.
- `lib/data/services/seerr/` (Lines 1-450 across 6 files): Seerr API client, authentication, notifications, and row builders.
- `lib/ui/widgets/seerr/` (Lines 1-350 across 5 files): Seerr action buttons and availability badges.

### Plugin Migration Difficulty: **Easy**
- **Rationale**: Seerr is a REST client interacting with Overseerr / Jellyseerr servers. A web plugin can fetch requests via standard HTTP, show availability badges, and register dynamic home rows using `registerHomeRow`.

---

## 5. Deep Link Handling Module

### Added / Modified Files & Line Ranges
- `lib/data/services/deep_link_service.dart` (Lines 1-160): Handles `moonfin://` scheme deep link parsing.
- `lib/ui/navigation/deep_link_navigator.dart` (Lines 1-120): Routes deep links to item details, player, or Live TV channels.

### Plugin Migration Difficulty: **Medium**
- **Rationale**: Deep link registration with OS manifest files is native. However, plugins can register custom URI route handlers with the host router via `openPluginScreen` or bridge intent handlers.

---

## 6. Admin & Permissioned Deletion Module

### Added / Modified Files & Line Ranges
- `lib/auth/jellyfin_item_delete.dart` (Lines 1-110): Administrative / permissioned item deletion logic.
- `lib/ui/jellyfin_own_delete.dart` (Lines 1-140): UI 🖕 deletion confirmation dialog with safe focus default on Cancel.
- `docs/jellyfin-library.md` (Lines 1-28): Documentation for administrative item deletion.

### Plugin Migration Difficulty: **Easy**
- **Rationale**: Jellyfin item deletion is a standard REST call (`DELETE /Items/{Id}`). A plugin with user credentials (`getUserContext()`) can perform deletion API requests.

---

## 7. Setup Wizard & Web Diagnostics Module

### Added / Modified Files & Line Ranges
- `lib/ui/screens/setup/setup_wizard_screen.dart` (Lines 1-310): First-run setup wizard.
- `lib/ui/screens/setup/setup_wizard_gate.dart` (Lines 1-85): Setup wizard completion condition gate.
- `lib/ui/screens/web_diagnostics_screen.dart` (Lines 1-220): Web diagnostics screen for connection debugging.

### Plugin Migration Difficulty: **Medium**
- **Rationale**: Web diagnostics and setup wizard interact with core authentication and network overrides. Parts can be pluginized, but first-run setup wizard gate requires core app integration.

---

## 8. Visual Branding & Navigation Module

### Added / Modified Files & Line Ranges
- `lib/ui/widgets/mofin_brand.dart` (Lines 1-150): MoFin visual identity marks and SVG lockups.
- `docs/branding-and-navigation.md` (Lines 1-32): Documentation for branding and D-pad focus rules.
- `assets/icons/` & `assets/images/`: Visual assets for MoFin branding.

### Plugin Migration Difficulty: **Hard**
- **Rationale**: Core app branding and high-contrast D-pad focus highlights are integral to the native Flutter UI design system (`packages/design`). Plugins render inside web views or dynamic rows, whereas host branding belongs to the host shell.
