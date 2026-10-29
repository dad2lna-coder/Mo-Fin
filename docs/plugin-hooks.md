# Plugin Host API Reference & Maintenance Guide

This document describes the MoFin Plugin Host API (`hostApi = 1`), manifest specification, JavaScript bridge communication protocol, security model, and maintenance procedures for upstream merges.

---

## 1. Manifest Format (`plugin.json`)

Every MoFin plugin must serve a valid `plugin.json` manifest at its root URL.

```json
{
  "id": "com.example.myplugin",
  "name": "My Custom Feature Plugin",
  "version": "1.0.0",
  "minHostApi": 1,
  "entry": "index.html",
  "permissions": [
    "userContext",
    "homeRow",
    "settingsPage",
    "playback",
    "storage"
  ],
  "hooks": [
    "homeRow",
    "settingsPage",
    "navItem"
  ]
}
```

### Manifest Fields
| Field | Type | Required | Description |
|---|---|---|---|
| `id` | String | Yes | Unique reverse-domain plugin identifier. |
| `name` | String | Yes | Human-readable plugin name. |
| `version` | String | Yes | Plugin version string (semver). |
| `minHostApi` | Integer | Yes | Minimum Host API version required (current host version = 1). |
| `entry` | String | Yes | Relative path or full URL to entry point HTML. |
| `permissions` | Array[String] | No | Capabilities required by plugin. |
| `hooks` | Array[String] | No | Hook points utilized by plugin. |

---

## 2. JavaScript Bridge Communication Protocol (`hostApi = 1`)

Plugins communicate with MoFin host via `window.MoFinHost.call(method, params)`.

```javascript
// Example bridge call in JS
const userContext = await window.MoFinHost.call("getUserContext", {});
```

### Protocol Format
Incoming message to host (`MoFinPluginBridge`):
```json
{
  "method": "registerHomeRow",
  "params": {
    "id": "my_row",
    "title": "Custom Row",
    "items": []
  },
  "callbackId": "cb_1_1710000000"
}
```

Response from host to `window.MoFinHost._handleResponse(response)`:
```json
{
  "ok": true,
  "result": true,
  "callbackId": "cb_1_1710000000"
}
```

---

## 3. Host API Methods Reference

### 1. `getUserContext`
Returns active user identity and server credentials scoped strictly to the user's active media server.
- **Parameters**: `{}`
- **Returns**:
  ```json
  {
    "userId": "usr_123",
    "username": "Admin",
    "serverUrl": "https://your-server/",
    "token": "secret_token"
  }
  ```

### 2. `openPluginScreen`
Opens a plugin screen inside MoFin.
- **Parameters**: `{ "title": "My Screen", "url": "https://your-server/plugins/myplugin/screen.html" }`
- **Returns**: `true`

### 3. `registerHomeRow`
Registers a dynamic home row on MoFin's main dashboard.
- **Parameters**:
  ```json
  {
    "id": "my_custom_row",
    "title": "Custom Plugin Row",
    "items": [
      {
        "id": "item_1",
        "title": "Video Title",
        "subtitle": "Video Subtitle",
        "imageUrl": "https://your-server/poster.jpg",
        "streamUrl": "https://your-server/stream.m3u8"
      }
    ]
  }
  ```
- **Returns**: `true`

### 4. `registerSettingsPage`
Registers an entry under **Settings → Integrations**.
- **Parameters**: `{ "id": "my_settings", "title": "Plugin Settings", "url": "https://your-server/plugins/myplugin/settings.html" }`
- **Returns**: `true`

### 5. `registerNavItem`
Registers a sidebar / navigation item.
- **Parameters**: `{ "id": "my_nav", "title": "My Plugin", "icon": "extension", "url": "https://your-server/plugins/myplugin/index.html" }`
- **Returns**: `true`

### 6. `playMedia`
Triggers media playback through MoFin's player engine.
- **Parameters**: `{ "jellyfinItemId": "item_id" }` OR `{ "streamUrl": "https://your-server/stream.m3u8", "title": "Title" }`
- **Returns**: `true`

### 7. `showToast`
Displays a toast notification in MoFin.
- **Parameters**: `{ "message": "Notification message" }`
- **Returns**: `true`

### 8. `storageGet` & `storageSet`
Reads or writes isolated plugin storage (`plugin_<pluginId>_<key>`).
- **`storageGet` Parameters**: `{ "key": "myPref" }`
- **`storageSet` Parameters**: `{ "key": "myPref", "value": "myValue" }`

---

## 4. Security & Isolation Rules

1. **Auth Token Scoping**: User credentials and access tokens returned by `getUserContext` belong exclusively to the active logged-in server.
2. **Storage Key Isolation**: Storage keys are automatically prefixed with `plugin_<pluginId>_`, preventing plugins from tampering with other plugins or core app preferences.
3. **Graceful Skipping**: If a plugin fails to load or manifest parsing throws an error, MoFin skips the URL without breaking application startup or crash reporting.
4. **Feature Flag Boundary**: When `UserPreferences.pluginsEnabled` is `false` (default), no plugin manifests are fetched, no bridge channels are injected, and no dynamic rows or setting links are shown.

---

## 5. Upstream Moonfin Merge Checklist

When pulling new releases from upstream `Moonfin-Core`, use this checklist to re-verify integration points marked with `// MOFIN-PLUGIN-HOOK`:

- [ ] **1. Dependency Injection (`lib/di/modules/app_module.dart`)**
  - Verify `PluginRegistry` and `PluginService` registrations under `registerAppModule()`.
- [ ] **2. Preferences (`lib/preference/user_preferences.dart`)**
  - Verify `pluginsEnabled` and `pluginUrls` preference fields.
- [ ] **3. Navigation Router (`lib/ui/navigation/app_router.dart`)**
  - Verify `/plugin-screen` GoRoute definition.
- [ ] **4. Settings Panel (`lib/ui/screens/settings/panel/services_screen.dart`)**
  - Verify `Plugins` settings tile and registered plugin settings entries loop.
- [ ] **5. Home Screen & ViewModel (`lib/ui/screens/home/home_view_model.dart`)**
  - Verify `_getRegisteredPluginHomeRows()` retriever and injection into `_rows`.
- [ ] **6. Left Sidebar Navigation (`lib/ui/widgets/left_sidebar.dart`)**
  - Verify registered plugin nav items loop in `_buildContent()`.
- [ ] **7. Playback Launcher (`lib/ui/navigation/playback_launcher.dart`)**
  - Verify `PlaybackLauncher.playItem` and `PlaybackLauncher.playStream` helper methods.
- [ ] **8. Package Tests (`packages/plugin_host/test/`)**
  - Run `flutter test packages/plugin_host` to confirm host package tests pass.
