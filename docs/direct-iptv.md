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
- Feedback reports are submitted to the channel server's `/report` endpoint along with the channel `tvg-id`.

### Resolution Badges & Automatic Reporting
- MoFin evaluates channel video quality and displays resolution badges (`2160p`, `1080p`, `720p`, `480p`, `SD`).
- As streams play, the media engine automatically measures the stream's video height and reports the resolution back to the channel server via `/resolution`.

### 🖕 Channel Removal / Disable
- Channel owners and admins can remove or disable non-working channels using the 🖕 remove button in the live player.
- Sends a request to the channel server's `/remove` endpoint.
- Server authorized requests send an optional key header `X-Mofin-Key: <your-key>`.

### Channel Stacks & Automatic Failover
- Redundant streams can be grouped into channel stacks using the `x-mofin-stack` and `x-mofin-members` M3U attributes.
- If a primary stream in a stack fails during playback, MoFin automatically attempts failover playback across member channel streams.
- The player reports the specific active member via the HTTP header `X-Mofin-Member`.

### Recording Choice
- Channels with recording capability can supply an alternative recording URL using the `x-mofin-rec-url` M3U tag.
- When scheduling or initiating a recording, MoFin uses `x-mofin-rec-url` if provided.
