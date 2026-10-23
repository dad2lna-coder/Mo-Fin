# Changelog

All notable changes to MoFin will be documented in this file.

## [Unreleased] - 2026-10-23

### Documentation & Cleanup

#### General & README
- Rewrote `README.md` specifically for MoFin (fork of Moonfin).
- Outlined platform targets: Fire TV / Android TV (`Mo-Fin.apk`), Web (`Mo-Fin-web.zip` served under `/mofin/`), and Roku (`Mo-Fin-roku.zip`).
- Added installation instructions for `.apk`, web deployments, and `.zip` side-loading from the `latest` GitHub release.
- Clarified credits to Moonfin and GPL license.

#### Jellyfin Library
- Documented Jellyfin integration and item deletion (🖕 emoji) feature available to administrators and users with content deletion permissions (`EnableContentDeletion`).
- Documented deletion confirmation dialog behavior with default focus on **Cancel**.

#### Direct IPTV ("Mo Fin" Source)
- Documented channel grouping, including automatic "Other" grouping for unclassified channels.
- Documented 🙂 (working) / 🙁 (broken) user status reports.
- Documented resolution badge display (`2160p`, `1440p`, `1080p`, `720p`, `480p`, `SD`) and automatic stream height reporting.
- Documented 🖕 channel removal/disabling and key authorization methods (`X-Mofin-Key`, `?key=`, `Authorization: Bearer`).
- Documented channel stacks failover mechanism, stack playlists (`s/stack-<slug>.m3u8`), and HTTP response header `X-Mofin-Member`.
- Documented recording behavior where posts send `tvg_id` to server with `x-mofin-rec-url` acting as a hint.

#### Streaming Tab
- Documented integration with TMDB "where to watch" service for Netflix, Disney+, Max, and Prime Video (US region).
- Documented platform launching behavior: native app launching on Fire TV / Android TV, search in new browser tab on Web, and hiding Watch buttons on Roku.
- Documented TMDB API Key configuration under Settings → Integrations → Streaming.

#### Branding & Navigation
- Documented MoFin custom branding assets and screensaver.
- Documented D-pad remote focus highlight behavior.

#### Developer & Server Specifications
- Created `docs/channel-server-api.md` covering channel server REST endpoints (`/report`, `/remove`, `/resolution`), Stack Playlists (`s/stack-<slug>.m3u8`), M3U playlist attributes (`x-mofin-working`, `x-mofin-checked`, `x-mofin-stack` member count, `x-mofin-members`, `x-mofin-rec-url`), and response header `X-Mofin-Member`.
- Updated endpoint bodies, status responses (`403` unauthorized, `404` unknown channel), and auth options.
- Updated `roku/README.md` and `CONTRIBUTING.md`.
- Sanitized all documentation examples to use generic placeholders (`https://your-server/mofin/free/`, `<your-key>`, `<roku-ip>`).
