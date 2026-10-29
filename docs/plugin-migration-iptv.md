# Technical Specification: Direct IPTV Plugin Migration Plan

This document outlines the step-by-step technical migration plan to extract the Direct IPTV ("Mo Fin" Source) feature module from MoFin core into an independent web-based plugin using `packages/plugin_host`.

---

## 1. Goal & Architectural Objectives

Currently, Direct IPTV resides in `lib/direct_iptv/` and is tightly coupled with `lib/ui/screens/livetv/`. Moving Direct IPTV into a web plugin achieves:
- **Core Decoupling**: Upstream Moonfin updates merge cleanly without conflicts in Live TV / Direct IPTV files.
- **Server-Managed Updates**: IPTV playlist processing, EPG rules, and channel reporting can be updated on the user's server without distributing new APKs or web builds.
- **On-Demand Loading**: Users who do not use Direct IPTV avoid loading M3U parsing and guide assets.

---

## 2. Plugin Architecture Overview

The Direct IPTV plugin will consist of:

```
plugins/direct_iptv/
├── plugin.json               # Manifest file
├── index.html                # Entry point (EPG Grid & Channel Browser)
├── css/
│   └── guide.css             # TV D-pad friendly EPG styles
└── js/
    ├── m3u_parser.js         # M3U/M3U8 parser supporting x-mofin-* tags
    ├── epg_manager.js        # EPG fetcher and program grid layout
    ├── stack_resolver.js     # Channel stack and failover manager
    └── mofin_reporter.js     # /report, /remove, and /resolution client
```

### Manifest (`plugin.json`)
```json
{
  "id": "mofin.plugin.iptv",
  "name": "Direct IPTV",
  "version": "1.0.0",
  "minHostApi": 1,
  "entry": "index.html",
  "permissions": [
    "userContext",
    "homeRow",
    "navItem",
    "playback",
    "storage"
  ],
  "hooks": [
    "navItem",
    "homeRow",
    "settingsPage"
  ]
}
```

---

## 3. Host API Hooks & Capabilities Used

The Direct IPTV plugin uses the versioned Host API (`hostApi = 1`):

1. **`getUserContext()`**:
   Reads user credentials and active server base URL (`https://your-server/mofin/free/`) to resolve relative API endpoints (`report`, `remove`, `resolution`, `s/stack-<slug>.m3u8`).
2. **`registerNavItem()`**:
   Registers a "Direct IPTV" sidebar / top navigation menu item opening the plugin's guide UI screen.
3. **`registerHomeRow()`**:
   Registers a "Direct IPTV Favorites" or "Now Airing Channels" dynamic home row.
4. **`playMedia({streamUrl, title})`**:
   Launches channel playback through MoFin's native media engine (`PlaybackLauncher.playStream`).
5. **`storageGet(key)` & `storageSet(key, value)`**:
   Persists cached channel M3U snapshots, group order, and channel favorite toggles in isolated plugin storage.

---

## 4. Step-by-Step Migration Plan

### Step 1: Web-based M3U Parser & EPG Engine
- Port `lib/direct_iptv/playlist_parse.dart` and `models.dart` to JavaScript (`m3u_parser.js`).
- Support extended M3U attributes:
  - `tvg-id`, `tvg-name`, `group-title`, `x-mofin-working`, `x-mofin-checked`, `x-mofin-stack`, `x-mofin-members`, `x-mofin-rec-url`.
- Implement channel group categorization (categorizing unassigned channels into an "Other" group).

### Step 2: D-Pad Friendly EPG Guide UI
- Implement an HTML5/CSS grid (`index.html` + `guide.css`) optimized for TV D-pad remote navigation.
- Implement high-contrast focus highlights and TV remote key handlers (`ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight`, `Enter`, `Back`).
- Implement channel status feedback buttons in the UI:
  - 🙂 **Working** & 🙁 **Broken** status report modal (`POST /report`).
  - 🖕 **Remove / Disable** channel button (`POST /remove` with key authorization token).

### Step 3: Stream Resolution & Channel Failover
- Port `lib/direct_iptv/direct_iptv_playback.dart` failover logic to JS (`stack_resolver.js`).
- When a user selects a stack channel (`x-mofin-stack="2"`):
  - Plugin resolves stack member URLs or requests `s/stack-<slug>.m3u8`.
  - Plugin calls `MoFinHost.call('playMedia', {streamUrl, title})`.
  - If playback fails, plugin intercepts failure and attempts playback of alternative stack member URLs (`x-mofin-members`).

### Step 4: Stream Resolution Auto-Reporting Telemetry
- Expose a bridge event listener in `packages/plugin_host` for native media engine video height reports.
- Upon receiving stream video height, `mofin_reporter.js` submits decoded resolution (`2160p`, `1080p`, `720p`, `480p`, `SD`) back to channel server `/resolution`.

### Step 5: Core Cleanup & Feature Toggle
- After verifying plugin functionality against the host API:
  - Remove `lib/direct_iptv/` folder from core repository.
  - Remove `lib/ui/screens/livetv/direct_iptv_guide_screen.dart` and route references.
  - Retain `packages/plugin_host` integration hook `// MOFIN-PLUGIN-HOOK`.
