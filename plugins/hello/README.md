# Hello World Sample Plugin

This directory contains a sample web plugin demonstrating the MoFin Plugin Host API (`hostApi = 1`).

## Files
- `plugin.json`: Plugin manifest specifying ID, name, entry URL, permissions, and hooks.
- `index.html`: Entry HTML page containing JavaScript bridge invocations (`window.MoFinHost.call`).

## How to Host and Run

### 1. Host locally or on your server
You can serve the `plugins/hello/` folder with any web server (Caddy, Nginx, Python http.server, or directly on your Jellyfin server).

#### Quick Test using Python HTTP Server:
```bash
cd plugins/hello
python3 -m http.server 8080
```

This serves the plugin manifest at: `http://localhost:8080/plugin.json` (or `http://<your-ip>:8080/`).

### 2. Configure in MoFin
1. Open MoFin.
2. Go to **Settings → Integrations → Plugins**.
3. Toggle **Enable Plugin Host System** to ON.
4. Click **Add URL** and enter:
   `http://<your-ip>:8080/`
5. Click **Add**.
6. The plugin status will show **Loaded: Hello World Sample Plugin (v1.0.0)**.

### 3. Verify Functionality
- **Home Row**: Return to MoFin's Home screen. A new row titled **Hello World Picks** will appear with test video streams.
- **Settings Page**: In **Settings → Integrations**, selecting **Hello Plugin Preferences** opens the plugin WebView screen.
- **JavaScript Bridge Calls**: Click the buttons inside the webview to test `getUserContext`, storage, toasts, and direct stream playback.
