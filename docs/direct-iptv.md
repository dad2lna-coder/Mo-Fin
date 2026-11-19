# Direct IPTV ("Mo Fin" Source)

MoFin supports direct M3U/M3U8 playlist IPTV streams via its "Mo Fin" live source integration.

## Features

### Custom Channel Groups
- Channels are organized into playlist groups defined by `group-title`.
- Any channels without a group or unclassified channels are automatically sorted into an "Other" category.

### 🙂 / 🙁 Working & Broken Reports
While watching a channel in the live player, users can report channel status back to the server:
- **🙂 (Working)**: Confirms the channel stream is active and functional.
- **🙁 (Broken)**: Reports that the stream is offline or failing.
- Feedback reports are submitted to the channel server's `/report` endpoint along with the channel `tvg-id` and optional `member` / `note` information.

### Resolution Badges & Automatic Reporting
- MoFin evaluates channel video quality and displays resolution badges (`2160p`, `1440p`, `1080p`, `720p`, `480p`, `SD`).
- As streams play, the media engine automatically measures the stream's video height and reports the resolution back to the channel server via `/resolution`.

### 🖕 Channel Removal / Disable
- Channel owners and admins can remove or disable non-working channels using the 🖕 remove button in the live player.
- Sends a request to the channel server's `/remove` endpoint (`{tvg_id, name?}`).
- Authorized requests send key tokens via `X-Mofin-Key: <your-key>`, `?key=<your-key>`, or `Authorization: Bearer <your-key>`. Returns `403` when unauthorized or `404` for unknown channels.

### Channel stacks and feeds
- Redundant streams can be grouped into channel stacks using the `x-mofin-stack` (member count) and `x-mofin-members` M3U attributes.
- Stacks can also be fetched as stack playlists (`s/stack-<slug>.m3u8`).
- When streaming a stack, the channel server sends the HTTP header `X-Mofin-Member: <member-tvg-id>`, and the app reads it to identify which member channel is serving the stream.
- The same station on more than one enabled source is one group. In the player, **Switch feed (n)** in the controls cycles those sources. On a TV remote that button is in the overlay OK or Down opens, and the Menu key lists every feed with the current one checked. Left and Right still change the channel. A short toast shows the source name. The player already running is reused; the previous stream is released first.
- The choice is saved for that station (the group id) and used the next time the channel opens. It syncs for the signed-in Jellyfin user through Moonbase (`PUT /Moonfin/LiveTv/Direct/Feeds`) when that route answers, and stays on the device when it does not.
- If the saved feed fails, or does not start within about 8 seconds, the player tries the next feed for that viewing only and does not replace the saved choice.

### Recording
- Direct IPTV (M3U) recordings are scheduled on the signed-in server at `POST/GET/DELETE /Moonfin/LiveTv/Direct/Recordings`.
- The request uses that user's Jellyfin session. The app does not ask for, store, or send a separate recording key.
- The account needs Live TV management, or to be an administrator. A server that sends `EnableLiveTvRecording` is honored the same way.
- Jellyfin Live TV channels shown in the same guide record through Jellyfin's own timers, with the same session.
- `x-mofin-rec-url` is sent as a recording URL hint. Moonbase does not store the stream URL. Capture uses ffmpeg when it is installed; the job is still scheduled when it is not.
- This needs a Moonbase build that includes the Direct recordings endpoint. Until that plugin is updated, MoFin says the plugin is missing instead of asking for a key.
