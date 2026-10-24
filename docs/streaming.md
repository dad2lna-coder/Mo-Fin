# Streaming Tab

The **Streaming** tab in MoFin integrates TMDB (The Movie Database) "where to watch" data (US region) to discover popular and trending content across popular subscription streaming services.

## Supported Streaming Services

- **Netflix**
- **Disney+**
- **Max** (HBO Max)
- **Prime Video**

## How It Works

1. MoFin queries TMDB for trending and popular media available on configured streaming providers in the US region.
2. Selecting a title shows media details and available streaming providers.
3. Behavior when selecting a provider:
   - **Fire TV / Android TV**: Directly launches the corresponding official native application.
   - **Web**: Opens the streaming service's search page in a new browser tab.
   - **Roku**: Hides the Watch buttons.

## Setup & Configuration

To use the Streaming tab, you must provide your own TMDB API Key (v3 auth):

1. Go to **Settings → Integrations → Streaming** in MoFin.
2. Enter your TMDB API Key (`<your-key>`).
3. Save settings.

Once configured, the Streaming tab will populate with rows for each service.
