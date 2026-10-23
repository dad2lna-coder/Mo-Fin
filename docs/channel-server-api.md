# Channel Server API Specification

This document details the REST API endpoints and M3U playlist attributes that MoFin uses to communicate with a Direct IPTV channel server (e.g. `https://your-server/mofin/free/`).

## Overview & Base URI

A MoFin Direct IPTV source base URI typically points to an endpoint ending with `/mofin/free/` (e.g., `https://your-server/mofin/free/`).

Relative endpoints (`report`, `remove`, `resolution`) are resolved against this base URI.

---

## M3U Playlist Attributes

MoFin parses custom `EXTINF` attributes in M3U playlists:

| Attribute | Type | Description |
|---|---|---|
| `tvg-id` | String | Unique channel identifier. |
| `tvg-name` / `tvg-logo` / `group-title` | String | Standard M3U channel metadata and category grouping. |
| `x-mofin-working` | Boolean (`true`/`false`) | Pre-reported channel working state. |
| `x-mofin-checked` | String (`YYYY-MM-DD`) | Date when channel status was last verified. |
| `x-mofin-stack` | Integer | ID representing a channel stack grouping (> 0). |
| `x-mofin-members` | String | Comma-separated list of member `tvg-id` channels inside a stack (e.g., `ch1,ch2,ch3`). |
| `x-mofin-rec-url` | String | Alternative URL to use when requesting a channel recording. |

### Playlist Example

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="channel-101" tvg-name="Example Channel" group-title="News" x-mofin-working="true" x-mofin-checked="2026-10-23" x-mofin-stack="5" x-mofin-members="channel-101,channel-101-backup" x-mofin-rec-url="https://your-server/mofin/free/rec/channel-101", Example Channel
https://your-server/mofin/free/stream/channel-101.m3u8
```

---

## HTTP Stream Headers

### `X-Mofin-Member`

When playing a channel within a channel stack (`x-mofin-stack`), the media player inspects response headers from stream requests.

- **Header**: `X-Mofin-Member: <member-tvg-id>`
- **Usage**: Indicates which underlying stack member served the stream.

---

## API Endpoints

### 1. Report Status (`POST /report`)

Submits a user status report (🙂 working / 🙁 broken) for a channel.

- **URL**: `https://your-server/mofin/free/report`
- **Method**: `POST`
- **Headers**:
  - `Content-Type: application/json`

#### Request Body

```json
{
  "tvg_id": "channel-101",
  "working": true,
  "name": "Example Channel"
}
```

#### Responses

- **200 OK**: Report saved successfully.
  ```json
  {
    "ok": true
  }
  ```
- **429 Too Many Requests**: Rate limit exceeded.
- **400 / 500**: Operation failed.

---

### 2. Remove Channel (`POST /remove`)

Requests removal or disabling of a non-working channel (triggered by the 🖕 removal button).

- **URL**: `https://your-server/mofin/free/remove`
- **Method**: `POST`
- **Headers**:
  - `Content-Type: application/json`
  - `X-Mofin-Key: <your-key>` *(Optional key token configured in playlist source)*

#### Request Body

```json
{
  "tvg_id": "channel-101",
  "name": "Example Channel"
}
```

#### Responses

- **200 OK**: Channel successfully removed.
  ```json
  {
    "ok": true
  }
  ```
- **403 Forbidden**: Invalid token or network forbidden.
- **404 Not Found**: Channel specified by `tvg_id` not found.
- **429 Too Many Requests**: Rate limit exceeded.

---

### 3. Report Resolution (`POST /resolution`)

Automatically reports decoded video resolution height during playback.

- **URL**: `https://your-server/mofin/free/resolution`
- **Method**: `POST`
- **Headers**:
  - `Content-Type: application/json`

#### Request Body

```json
{
  "tvg_id": "channel-101",
  "res": "1080p",
  "member": "channel-101-backup"
}
```

*(Note: `member` field is included when stream was resolved from a stack via `X-Mofin-Member` header).*

#### Allowed Resolution Values

- `"2160p"`
- `"1080p"`
- `"720p"`
- `"480p"`
- `"SD"`

#### Responses

- **200 OK**: Resolution updated.
  ```json
  {
    "ok": true
  }
  ```
