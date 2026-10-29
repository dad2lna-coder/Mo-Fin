# Upstream Moonfin Core Architecture & Internal API Specification

## 1. Overview & Baseline Reference

MoFin is a Flutter application forked from Moonfin-Core.

- **Baseline Revision / Commit Hash**: `e61ac43cacfe8a3674dbd7b0c7719b2ce6b95e29`
- **Application Identification**: `moonfin` / `MoFin`
- **Primary Upstream Components**:
  - `lib/`: Flutter UI, viewmodels, routing, preferences, and local data services.
  - `packages/server_core`: Server abstraction interfaces (`MediaServerClient`, `ServerRepository`, `UserRepository`, etc.).
  - `packages/server_jellyfin`: Jellyfin implementation of `server_core`.
  - `packages/server_emby`: Emby implementation of `server_core`.
  - `packages/playback_core`: Abstract playback manager, queue service, and player backend contracts.
  - `packages/playback_jellyfin`: Jellyfin playback integration (reporting, stream resolution, transcode options).
  - `packages/playback_emby`: Emby playback integration.
  - `packages/design`: Shared design tokens, components, and widgets.
  - `packages/preference`: Preference storage primitives (`PreferenceStore`, `Preference`).

---

## 2. Directory & Package Structure

```
.
├── lib/
│   ├── auth/                # Authentication stores, repositories, models, and screens
│   ├── data/                # Database (Drift), offline storage, models, services
│   ├── di/                  # GetIt dependency injection setup and modules
│   ├── direct_iptv/         # MoFin Direct IPTV source integration ("Mo Fin")
│   ├── platform/            # Platform-specific runtime configurations
│   ├── playback/            # App-level playback controllers, handlers, external player policies
│   ├── preference/          # Preference constants and UserPreferences manager
│   ├── streaming/           # TMDB streaming client and launcher
│   ├── syncplay/            # SyncPlay manager and group listening/watching
│   ├── ui/                  # Presentation layer (screens, navigation, widgets, themes)
│   └── util/                # Platform detection, focus management, formatters, helpers
└── packages/
    ├── server_core/         # Abstract server models and API contracts
    ├── server_jellyfin/     # Jellyfin SDK / REST API implementation
    ├── server_emby/         # Emby SDK / REST API implementation
    ├── playback_core/       # Core player state, queue management, media player contracts
    ├── playback_jellyfin/   # Jellyfin media stream resolver and progress reporter
    ├── playback_emby/       # Emby media stream resolver and progress reporter
    ├── design/              # Design system widgets and branding
    └── preference/          # Key-value storage wrapper
```

---

## 3. Dependency Injection & Service Registry

Dependency Injection is configured using `GetIt` (`lib/di/injection.dart`) with `flutter_riverpod` used for localized reactive UI state.

### Key Registered Singletons (`lib/di/injection.dart`)

| Service Interface | Concrete / Locator Class | Primary Purpose |
|---|---|---|
| `DeviceInfo` | `DeviceInfo` (lib/di/injection.dart:366) | App identity, device hardware info, OS version. |
| `PreferenceStore` | `PreferenceStore` (lib/di/injection.dart:376) | Underpins persistent key-value configuration. |
| `UserPreferences` | `UserPreferences` (lib/di/modules/preference_module.dart:10) | Strongly typed preferences manager and listener. |
| `StoragePathService` | `StoragePathService` (lib/di/injection.dart:338) | Resolves application documents and download paths. |
| `OfflineDatabase` | `OfflineDatabase` (lib/di/injection.dart:339) | Drift SQLite database for downloads and offline playback. |
| `OfflineRepository` | `OfflineRepository` (lib/di/injection.dart:340) | CRUD operations for offline items. |
| `OfflineCatalog` | `OfflineCatalog` (lib/di/injection.dart:342) | High-level cache of downloaded media items. |
| `ConnectivityService` | `ConnectivityService` (lib/di/injection.dart:388) | Network connectivity monitor and server reachability state. |
| `SessionRepository` | `SessionRepository` (lib/auth/repositories/session_repository.dart) | Tracks active user session, user IDs, and server IDs. |
| `UserRepository` | `UserRepository` (lib/auth/repositories/user_repository.dart) | Holds current user metadata and administrative flags. |
| `ServerRepository` | `ServerRepository` (lib/auth/repositories/server_repository.dart) | Manages connected media servers list. |
| `MediaServerClientFactory` | `MediaServerClientFactory` (lib/data/services/media_server_client_factory.dart) | Factory producing active `MediaServerClient` instance. |
| `PlaybackManager` | `PlaybackManager` (lib/di/modules/playback_module.dart) | Controls player state, playback queue, and backends. |

---

## 4. Core Domain Models

- **`Server` (`lib/auth/models/server.dart`)**:
  Represents a media server connection entry (`id`, `name`, `url`, `accessToken`, `type`).
- **`User` (`lib/auth/models/user.dart`)**:
  Represents user identity (`id`, `name`, `serverId`, `isAdministrator`, `hasPassword`, `permissions`).
- **`AggregatedItem` (`lib/data/models/aggregated_item.dart`)**:
  MoFin unified media model wrapping server items (`id`, `name`, `type`, `overview`, `posterPath`, `backdropPath`, `mediaSources`, `userData`, `rawData`).
- **`BaseItemDto` (`packages/server_core/lib/src/models/base_item_dto.dart`)**:
  Canonical upstream data transfer object representing Jellyfin/Emby items (movies, series, episodes, audio, channels).
- **`MediaSourceInfo` (`packages/server_core/lib/src/models/media_source_info.dart`)**:
  Describes media streams, transcode URLs, container formats, video/audio tracks, and playback parameters.
- **`HomeSectionConfig` (`lib/preference/home_section_config.dart`)**:
  Configures home screen section rows (`type`, `enabled`, `order`, `customTitle`).

---

## 5. `server_core` Interfaces & Jellyfin API Integration

Upstream decouples media server interactions using `packages/server_core`.

### Core Server Interfaces (`packages/server_core/lib/src/api/`)
- **`MediaServerClient`**: Aggregates items, system, user, library, and media endpoints.
- **`ItemsApi`**: Query items, recommendations, resume items, next up, and library filtering.
- **`UserApi`**: User authentication, credentials, and profile configuration.
- **`SystemApi`**: Server health, capabilities, public configuration, and system info.
- **`AdminPluginsApi`**: Admin endpoint for server-side plugin management (`/Plugins`).

### Key Jellyfin Endpoint Mapping (`packages/server_jellyfin/`)
- Authentication: `POST /Users/AuthenticateByName`
- User Profile: `GET /Users/{UserId}`
- Library Items: `GET /Users/{UserId}/Items`
- Item Details: `GET /Users/{UserId}/Items/{Id}`
- Continuation: `GET /User/{UserId}/Items/Resume` & `GET /Shows/NextUp`
- Stream URL Generation: `/Videos/{Id}/stream.{container}` or `/Audio/{Id}/stream`

---

## 6. Client-to-Moonbase / Plugin Extensions

Upstream Moonfin includes client integration for server-side extensions:

- **`PluginSyncService` (`lib/data/services/plugin_sync_service.dart`)**:
  Syncs client preference settings to/from server plugin profiles (e.g. Moonbase).
- **`AdminPluginsApi` (`packages/server_core/lib/src/api/admin_plugins_api.dart`)**:
  Queries installed Jellyfin server plugins (`GET /Plugins`) and plugin configuration.
- **`AchievementsService` (`lib/data/services/achievements_service.dart`)**:
  Communicates with server-side achievement plugins to fetch user badges and watch milestones.

---

## 7. `playback_core` Lifecycle & Media Engine

Media playback is orchestrated via `packages/playback_core` and `lib/ui/navigation/playback_launcher.dart`.

### Lifecycle Sequence:
1. **Request**: UI or deep link calls `PlaybackLauncher.playItem()` or `PlaybackLauncher.playStream()`.
2. **Resolution**: `PlaybackManager` requests media source information from active `MediaServerClient`.
3. **Queue Initialization**: Items are pushed to `QueueService` in `playback_core`.
4. **Backend Creation**: `Media3PlayerBackend` (Android), `MpvPlayerBackend` (Desktop/Linux/Windows), or native player backend is attached to `PlaybackManager`.
5. **Playback Start**: Player enters buffering/playing state, triggering progress reporting timers (`packages/playback_jellyfin`).
6. **Progress Reporting**: Periodic reports sent to server via `/Sessions/Playing/Progress` and `/Sessions/Playing/Stopped`.

---

## 8. Router & Navigation Structure

Application routing is driven by `GoRouter` in `lib/ui/navigation/app_router.dart` and destination constants in `lib/ui/navigation/destinations.dart`.

### Destination Paths (`lib/ui/navigation/destinations.dart`)

| Destination Path | Screen Class | Description |
|---|---|---|
| `/startup` | `StartupScreen` | Initial authentication & session bootstrap. |
| `/server-select` | `ServerSelectScreen` | Server selection and connection. |
| `/login` | `LoginScreen` | User login. |
| `/` (home) | `HomeScreen` | Main dashboard & content rows. |
| `/search` | `SearchScreen` | Universal search. |
| `/library/:libraryId` | `LibraryBrowseScreen` | Library browser (movies, series, books). |
| `/item/:itemId` | `ItemDetailScreen` | Media item details page. |
| `/video-player` | `VideoPlayerScreen` | Fullscreen video player. |
| `/live-tv` | `LiveTvScreen` | Live TV portal. |
| `/live-tv/guide` | `LiveTvGuideScreen` | Live TV EPG guide. |
| `/live-tv/direct` | `DirectIptvGuideScreen` | MoFin Direct IPTV guide. |
| `/streaming` | `StreamingScreen` | TMDB Streaming service dashboard. |
| `/games` | `GameLibraryScreen` / `GameSystemScreen` | Retro games library. |
| `/settings` | `SettingsSidePanel` | Application settings. |

---

## 9. Home Rows Data Flow

The home screen (`lib/ui/screens/home/home_screen.dart`) renders customizable content rows managed by `RowDataSource` (`lib/data/services/row_data_source.dart`).

- **Section Configuration**: `HomeSectionConfig` (`lib/preference/home_section_config.dart`) defines ordered list of enabled sections (Resume, Next Up, Latest Media, Favorites, Collections, Genres, etc.).
- **Row Builders**:
  - `LibraryRow` (`lib/ui/widgets/library_row.dart`): Horizontal scrolling row of media posters.
  - `ModernRow` (`lib/ui/widgets/modern_row.dart`): Modern TV wide-card focusable row.

---

## 10. Settings & Preferences Subsystem

App settings are accessed via `SettingsSidePanel` (`lib/ui/screens/settings/settings_side_panel.dart`) and driven by `UserPreferences` (`lib/preference/user_preferences.dart`).

- **Scoped Preferences**: User preferences support profile-scoped storage (`${key}_${serverId}_${userId}`), allowing multi-server and multi-user profile isolation.
- **Preference Storage**: Implemented over `shared_preferences` via `PreferenceStore` (`packages/preference`).

---

## 11. Live TV Subsystem

Upstream Live TV support uses `packages/server_core` Live TV API contracts:
- `getLiveTvChannels()`, `getLiveTvGuide()`, `getRecordings()`.
- Rendered in `LiveTvScreen`, `LiveTvGuideScreen`, and `LiveTvPlayerScreen`.
- MoFin adds the Direct IPTV ("Mo Fin") channel source alongside upstream Jellyfin Live TV (`lib/direct_iptv/`).
