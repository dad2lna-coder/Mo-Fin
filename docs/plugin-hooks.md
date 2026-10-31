# Plugin Host API Reference & Maintenance Guide

This document describes the MoFin Plugin Host API (`hostApi = 2`), Moonbase manifest specification, server routes, JavaScript bridge communication protocol, security model, and maintenance procedures for upstream merges.

---

## 1. Moonbase Manifest Format (`plugin.json`)

Every MoFin plugin serves a valid `plugin.json` manifest via the Moonbase plugin service at `/Moonfin/Plugins`.

```json
{
  "id": "hello",
  "name": "Hello World Sample Plugin",
  "version": "1.0.0",
  "description": "Sample plugin for MoFin",
  "provides": [
    "hello.homeRow"
  ],
  "requires": [],
  "slots": [
    "homeRow"
  ],
  "client": {
    "html": "client/index.html",
    "js": "client/app.js"
  },
  "minHostApi": 1,
  "proxyAccess": "admin"
}
```

### Manifest Fields
| Field | Type | Required | Description |
|---|---|---|---|
| `id` | String | Yes | Unique plugin identifier using lowercase letters, digits, and hyphens. |
| `name` | String | Yes | Human-readable plugin name. |
| `version` | String | Yes | Plugin version string (semver). |
| `description` | String | No | Optional plugin description. |
| `provides` | Array[String] | No | Feature tags provided by this plugin. |
| `requires` | Array[String] | No | Capability/plugin dependencies required. A plugin whose requirements are not active remains dormant and fills no slot. |
| `slots` | Array[String] or map of booleans | Yes | Enabled UI slots: `homeRow`, `playback`, `settings`, `events`, `games`. |
| `client` | Object | Yes | Entry files: `{ "html": "client/index.html", "js": "client/app.js" }`. |
| `server` | String/Object | No | Server component indicator/configuration. |
| `minHostApi` | Integer | Yes | Minimum Host API version required. `2` is required for `playGame`. |
| `proxyAccess` | String | No | Proxy access level ("admin" \| "user", default "admin"). |

---

## 2. Moonbase Server Routes

MoFin client communicates with the server's Moonbase plugin system via these endpoints:

1. `GET /Moonfin/Plugins`: List installed plugins, client entry URLs, and server capabilities.
2. `GET /Moonfin/Plugins/{id}/files/{path}`: Serves plugin client files with media server authentication.
3. `GET / PUT / DELETE /Moonfin/Plugins/{id}/Data/{key}`: Scoped key-value data storage per plugin on the server.
4. `POST /Moonfin/Plugins/{id}/Proxy`: Server-side proxy endpoint for plugin network requests.
5. `/Moonfin/Plugins/{id}/*`: Plugin-defined server-side routes executed with host authentication.
6. `/Moonfin/Settings/Stream`: Event stream endpoint. Host forwards `plugin:{id}:*` events to matching active plugins.

---

## 3. JavaScript Bridge Protocol & Methods (`hostApi = 2`)

Plugins run in a locked-down WebView and communicate via `window.MoFinHost.call(method, params)`.

```javascript
// Example bridge call
const userContext = await window.MoFinHost.call("getUserContext", {});
```

### Bridge Methods Reference

#### 1. `getHostApiVersion`
Returns current host API version `{ "hostApi": 2 }`.

#### 2. `getUserContext`
Returns active user identity and server name. **Tokens are never exposed.**
- **Parameters**: `{}`
- **Returns**:
  ```json
  {
    "userId": "usr_123",
    "username": "Admin",
    "serverName": "My Media Server"
  }
  ```

#### 3. `dataGet`, `dataPut`, `dataDelete`
Accesses plugin storage on the server (`/Moonfin/Plugins/{id}/Data/{key}`).
- `dataGet`: `{ "key": "prefKey" }` -> returns stored value
- `dataPut`: `{ "key": "prefKey", "value": "val" }` -> stores value on server
- `dataDelete`: `{ "key": "prefKey" }` -> deletes key on server

#### 4. `proxy`
Sends proxy request via `/Moonfin/Plugins/{id}/Proxy`.

#### 5. `callPluginRoute`
Calls the plugin's own server routes under `/Moonfin/Plugins/{id}/...`.
- **Parameters**: `{ "path": "custom/endpoint", "method": "POST", "data": { ... } }`

#### 6. `openPluginScreen`
Opens a plugin screen inside MoFin. Target URL must strictly sit under `/Moonfin/Plugins/{id}/files/`.

#### 7. `registerHomeRow`
Registers a dynamic home row on MoFin's main dashboard.

#### 8. `registerSettingsPage` & `registerNavItem`
Registers settings entry or sidebar navigation item. Target URLs must sit under `/Moonfin/Plugins/{id}/files/`.

#### 9. `playMedia`
Triggers playback through MoFin's player engine. `streamUrl` playback is restricted to server-provided URLs.

#### 10. `playGame` (`hostApi` 2)
Opens MoFin's full-screen emulator. Only a plugin with a `games` or `playback` slot may call it.
`MoFinHost.play(p)` is `MoFinHost.call('playGame', p)`.

- **Parameters**: `{ "libraryId": "...", "gameId": "...", "title": "optional" }`
- `libraryId` and `gameId` are required, non-empty, and at most 2048 characters.
- **Returns**: `true` once the player route is pushed. A missing game is `false` and MoFin shows "Game not found".
- When the player pops, the host sends `{ "type": "gameExited", "gameId": "..." }`.
- The native WebView injects `MoFinHost.play`. On Flutter web the plugin iframe is an opaque sandbox, so that preamble cannot be injected. Web plugins call `MoFinHost.call('playGame', p)` through the server-served `bridge.js`.

#### 11. Back from the Games hub
The host sends `{ "type": "hostBack", "replyId": "..." }`. Reply within 300 ms with
`MoFinHost.call('replyHostEvent', { replyId, handled: true })`, or return `{ handled: true }` from an `onEvent` listener, to keep the hub. Otherwise MoFin goes Home.

#### 12. `showToast`
Displays a toast notification in MoFin.

---

## 4. Security & Isolation Rules

1. **Token Protection**: Access tokens are NEVER passed to plugin JavaScript or returned in bridge responses.
2. **Path Lockdown**: `shouldOverrideUrlLoading` allows navigation ONLY under `/Moonfin/Plugins/{id}/files/` on the server origin.
3. **Message & Bridge Origin Checks**: Bridge messages are verified against current main-frame URL. Foreign pages receive no bridge injection and no response.
4. **Feature Flag Boundary**: When `UserPreferences.pluginsEnabled` is `false` (default), no plugins load, no bridge channels attach, and dynamic UI elements remain hidden.

---

## 5. Web Execution Model (Flutter Web & Safari PWA)

1. **Sandboxed Opaque Origin**: On Flutter Web builds, plugins execute inside a sandboxed `HTMLIFrameElement` (`sandbox="allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox"`). The iframe runs in an opaque origin (`origin: "null"`), so `localStorage`, `sessionStorage`, and cookies are disabled; plugins must use `dataGet`/`dataPut` for persistence.
2. **PostMessage Nonce Bridge**: Every web plugin instance receives a unique 16-byte cryptographically secure random base64url nonce via `location.hash` (`#mofinNonce=<nonce>`). Bridge envelopes must carry `{ mofin: 1, nonce: "<nonce>", payload: "..." }`. Envelopes with invalid nonces, missing fields, or payloads exceeding 256KB are discarded.
3. **Single Entry Page Lifecycle**: The web bridge tracks iframe `load` events. After the initial load event, subsequent in-frame navigations mark the bridge dead and ignore bridge messages until the user taps **Reload** (which generates a fresh nonce and iframe src).
4. **Server Requirements**: The server must serve `/Moonfin/PluginHost/bridge.js`, and the MoFin app origin must be allowed by the HTTP `Content-Security-Policy` `frame-ancestors` directive (same origin as the media server URL or listed in Moonbase's `PluginFrameAncestors` setting).

---

## 6. Upstream Moonfin Merge Checklist

When pulling new releases from upstream `Moonfin-Core`, re-verify integration points marked with `// MOFIN-PLUGIN-HOOK`:

- [ ] **1. Dependency Injection (`lib/di/modules/app_module.dart`)**
- [ ] **2. Navigation Router (`lib/ui/navigation/app_router.dart`)**
- [ ] **3. Settings Panel (`lib/ui/screens/settings/panel/services_screen.dart`)**
- [ ] **4. Home Screen & ViewModel (`lib/ui/screens/home/home_view_model.dart`)**
- [ ] **5. Left Sidebar Navigation (`lib/ui/widgets/left_sidebar.dart`)**
- [ ] **6. Playback Launcher (`lib/ui/navigation/playback_launcher.dart`)**
- [ ] **7. Package Tests (`packages/plugin_host/test/`)**
