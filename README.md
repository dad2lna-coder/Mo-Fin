# MoFin

MoFin is a custom media client for Fire TV / Android TV, Web, and Roku, forked from Moonfin. It combines a Jellyfin media library with direct IPTV playback, streaming service integration, and a TV-friendly interface with high-contrast D-pad navigation.

## Platforms Supported

- **Fire TV / Android TV**: Native Android APK (`Mo-Fin.apk`)
- **Web**: Web application bundle (`Mo-Fin-web.zip`, served under `/mofin/`)
- **Roku**: Side-loadable SceneGraph channel (`Mo-Fin-roku.zip`)

## Installation

Download the latest releases from the [`latest` release page](https://github.com/dad2lna-coder/Mo-Fin/releases/tag/latest):

- **Fire TV / Android TV**: Download `Mo-Fin.apk` and side-load or install on your Fire TV or Android TV device.
- **Web**: Download `Mo-Fin-web.zip` and deploy or serve under the `/mofin/` path on your server (e.g., `https://your-server/mofin/`).
- **Roku**: Download `Mo-Fin-roku.zip` and side-load via Roku Developer Mode (`http://<roku-ip>`). See [roku/README.md](roku/README.md) for full steps.

## Key Features

### Jellyfin Library
- Connect to your Jellyfin server to stream movies, TV series, and media.
- **Admin & Permissioned Deletion (🖕)**: Administrators and users with delete permission can delete movies and episodes directly from the detail screen or player overlay.
- Safe deletion flow with confirmation dialog where **Cancel** is focused by default to prevent accidental deletion.

### Direct IPTV ("Mo Fin" Source)
- **Organized Groups**: Channels grouped into custom categories plus an automatic "Other" group for unclassified channels.
- **🙂 / 🙁 Feedback Reports**: Send channel working/broken status reports back to the IPTV server.
- **Resolution Badges & Auto-Reporting**: Displays resolution badges (2160p, 1440p, 1080p, 720p, 480p, SD) and automatically reports detected video height back to the channel server.
- **🖕 Channel Disable / Removal**: Turn off or remove non-working/unwanted channels with key authorization (`X-Mofin-Key`, `?key=`, or `Authorization: Bearer`).
- **Channel Stacks & Failover**: Group redundant stream sources into channel stacks with automatic failover across member channels.
- **Recording Choice**: Select or hint custom recording URLs (`x-mofin-rec-url`) or post channel requests for channel recording.

### Streaming Tab
- Browse popular media on **Netflix**, **Disney+**, **Max**, and **Prime Video** via TMDB "where to watch" data (US region).
- Directly opens the native streaming application on supported TV devices (Fire TV / Android TV), opens search in a new browser tab on Web, and hides Watch buttons on Roku.
- Requires your own TMDB API key, configured in **Settings → Integrations → Streaming**.

### Custom Branding & Navigation
- MoFin visual branding across login, screensaver, and navigation elements.
- Enhanced high-contrast D-pad focus highlights for TV remote control navigation.

## Documentation

For detailed guides and API specifications, see the [`docs/`](docs/) directory:

- [Jellyfin Library Guide](docs/jellyfin-library.md)
- [Direct IPTV Guide](docs/direct-iptv.md)
- [Streaming Tab Guide](docs/streaming.md)
- [Branding and Navigation Guide](docs/branding-and-navigation.md)
- [Channel Server API Specification](docs/channel-server-api.md)

## Credits

MoFin is a fork of [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core) and builds upon the work of the original Moonfin contributors and the Jellyfin project.

## License

MoFin is free software released under the GNU General Public License v2 (or later). See [LICENSE](LICENSE) for details.
