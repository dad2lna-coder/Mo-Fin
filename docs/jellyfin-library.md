# Jellyfin Library

MoFin integrates with your Jellyfin media server to provide access to your movies, TV shows, and personal media libraries.

## Administrative Features

### Admin & Permissioned Item Deletion (🖕)

When logged in as a Jellyfin account with administrative privileges (`IsAdministrator`) or with content deletion permission (`EnableContentDeletion`), MoFin displays a deletion button represented by the 🖕 emoji on movie and episode detail screens and video player control overlays.

- **Permissions**: Shown to server administrators and users with explicit content deletion permissions. Non-permissioned users will not see the deletion option.
- **Confirmation Safety**: Selecting the deletion button opens a confirmation dialog asking you to confirm whether you wish to permanently delete the item from your Jellyfin server.
- **Default Focus**: In the confirmation dialog, the **Cancel** button is focused by default. This ensures that accidental presses on a TV D-pad remote will not inadvertently trigger a deletion.

## Connecting to Jellyfin

1. On initial startup, enter your server address (e.g. `https://your-server/`).
2. Log in with your Jellyfin username and password.
3. Access your libraries, continuation rows, and item details.
