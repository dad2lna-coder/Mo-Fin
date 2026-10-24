# Channel Server API Specification

This document details the REST API endpoints and M3U playlist attributes that MoFin uses to communicate with a Direct IPTV channel server (e.g. `https://your-server/mofin/free/`).

## Overview & Base URI

A MoFin Direct IPTV source base URI typically points to an endpoint ending with `/mofin/free/` (e.g., `https://your-server/mofin/free/`).

Relative endpoints (`report`, `remove`, `resolution`, `s/stack-<slug>.m3u8`) are resolved against this base URI.

---

## M3U Playlist Attributes

MoFin parses custom `EXTINF` attributes in M3U playlists:

| Attribute | Type | Description |
|---|---|---|
| `tvg-id` | String | Unique channel identifier. |
| `tvg-name` / `tvg-logo` / `group-title` | String | Standard M3U channel metadata and category grouping. |
| `x-mofin-working` | Boolean (`true`/`false`) | Pre-reported channel working state. |
| `x-mofin-checked` | String (`YYYY-MM-DD`) | Date when channel status was last verified. |
| `x-mofin-stack` | Integer | Represents the number of member channels in the stack (integer >= 1). |
| `x-mofin-members` | String | Comma-separated list of member `tvg-id` channels inside a stack (e.g., `channel-101,channel-101-backup`). |
| `x-mofin-rec-url` | String | Recording URL hint for channel recording requests. |

### Playlist Example

In this example, `x-mofin-stack="2"` indicates a stack with 2 member channels, matching the two items listed in `x-mofin-members`.

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="channel-101" tvg-name="Example Channel" group-title="News" x-mofin-working="true" x-mofin-checked="2026-10-23" x-mofin-stack="2" x-mofin-members="channel-101,channel-101-backup" x-mofin-rec-url="https://your-server/mofin/free/rec/channel-101", Example Channel
https://your-server/mofin/free/stream/channel-101.m3u8
```

---

## Stack Playlists (`GET s/stack-<slug>.m3u8`)

Channel stacks can also be requested via stack playlists.

- **URL**: `https://your-server/mofin/free/s/stack-<slug>.m3u8`
- **Method**: `GET`
- **Query Parameters**:
  - `rec=1` *(Optional)*: Requests the recording variant of the stack playlist instead of the live stream variant.

### HTTP Response Header (`X-Mofin-Member`)

When serving or streaming a channel stack, the server identifies the active member stream by sending the HTTP response header:

- **Header**: `X-Mofin-Member: <tvg-id>`
- **Usage**: The app inspects `X-Mofin-Member` from stream load responses to identify which specific underlying stack member is actively playing or serving the stream.

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
  "name": "Example Channel",
  "note": "Optional user comment or error description",
  "member": "channel-101-backup"
}
```

*Fields `name`, `note`, and `member` are optional.*

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
- **Authorization**:
  Requests are authorized using a key token via one of three methods:
  - Header: `X-Mofin-Key: <your-key>`
  - Query Parameter: `?key=<your-key>`
  - Header: `Authorization: Bearer <your-key>`
- **Headers**:
  - `Content-Type: application/json`

#### Request Body

```json
{
  "tvg_id": "channel-101",
  "name": "Example Channel"
}
```

*Field `name` is optional.*

#### Responses

- **200 OK**: Channel successfully removed.
  ```json
  {
    "ok": true
  }
  ```
- **403 Forbidden**: Request is not authorized or key token is missing/invalid.
- **404 Not Found**: Unknown `tvg_id` specified.
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

*Field `member` is optional and included when stream was served by a stack member.*

#### Allowed Resolution Values (`res`)

Must be one of:
- `"2160p"`
- `"1440p"`
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
