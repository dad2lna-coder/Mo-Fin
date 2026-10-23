# Changelog

All notable changes to MoFin will be documented in this file.

## [Unreleased] - 2026-10-23

### Documentation & Cleanup

#### General & README
- Rewrote `README.md` specifically for MoFin (fork of Moonfin).
- Outlined platform targets: Fire TV / Android TV, Web, and Roku.
- Added installation instructions for `.apk`, web deployments, and `.zip` side-loading from the `latest` GitHub release.
- Clarified credits to Moonfin and GPL license.

#### Jellyfin Library
- Documented Jellyfin integration and admin-only 🖕 item deletion feature.
- Documented deletion confirmation dialog behavior with default focus on **Cancel**.

#### Direct IPTV ("Mo Fin" Source)
- Documented channel grouping, including automatic "Other" grouping for unclassified channels.
- Documented 🙂 (working) / 🙁 (broken) user reporting features.
- Documented resolution badge display and automatic stream height reporting.
- Documented 🖕 channel removal/disabling and optional `X-Mofin-Key` header authentication.
- Documented channel stacks failover mechanism and stream header `X-Mofin-Member`.
- Documented recording URL selection (`x-mofin-rec-url`).

#### Streaming Tab
- Documented integration with TMDB "where to watch" service for Netflix, Disney+, Max, and Prime Video.
- Documented native app launching on supported TV systems.
- Documented TMDB API Key configuration under Settings → Integrations → Streaming.

#### Branding & Navigation
- Documented MoFin custom branding assets and screensaver.
- Documented D-pad remote focus highlight behavior.

#### Developer & Server Specifications
- Created `docs/channel-server-api.md` covering channel server REST endpoints (`/report`, `/remove`, `/resolution`), M3U playlist attributes (`x-mofin-working`, `x-mofin-checked`, `x-mofin-stack`, `x-mofin-members`, `x-mofin-rec-url`), and response headers (`X-Mofin-Member`).
- Sanitized all documentation examples to use generic placeholders (`https://your-server/mofin/free/`, `<your-key>`, `<roku-ip>`).
