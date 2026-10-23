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

### Channel Stacks & Failover
- Redundant streams can be grouped into channel stacks using the `x-mofin-stack` (member count) and `x-mofin-members` M3U attributes.
- Stacks can also be fetched as stack playlists (`s/stack-<slug>.m3u8`).
- When streaming a stack, the channel server sends the HTTP header `X-Mofin-Member: <member-tvg-id>`, and the app reads it to identify which member channel is serving the stream.
- If a primary stream in a stack fails during playback, MoFin automatically attempts failover playback across alternative member streams.

### Recording
- When recording a channel, MoFin posts the channel `tvg_id` to the server, and the server chooses the appropriate recording source.
- The `x-mofin-rec-url` M3U tag serves as a recording URL hint for the server (or `?rec=1` on stack playlist requests).
