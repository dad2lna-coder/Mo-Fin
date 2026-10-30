part of '../settings_side_panel.dart';

class _ServicesScreen extends StatefulWidget {
  const _ServicesScreen();

  @override
  State<_ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<_ServicesScreen> {
  final _servicesScope = FocusScopeNode(
    debugLabel: 'ServicesSettingsScope',
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );

  @override
  void initState() {
    super.initState();
    // A session switch clears the flag before it knows whether it will get far
    // enough to probe again, so ask here rather than trust what login left.
    final achievements = GetIt.instance<AchievementsService>();
    if (!achievements.available &&
        GetIt.instance.isRegistered<MediaServerClient>()) {
      unawaited(
        achievements.refreshAvailability(GetIt.instance<MediaServerClient>()),
      );
    }
  }

  @override
  void dispose() {
    _servicesScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final achievementsService = GetIt.instance<AchievementsService>();
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.integrations)),
        body: FocusScope(
          node: _servicesScope,
          autofocus: true,
          // The plugin probe lands after sign in, so the list waits on it
          // rather than reading the flag once and never hearing the answer.
          child: ListenableBuilder(
            listenable: achievementsService,
            builder: (context, _) => _buildList(l10n, achievementsService),
          ),
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, AchievementsService achievements) {
    final seerrLabel = GetIt.instance<SeerrPreferences>().labelOrDefault(
      l10n.seerr,
    );
    return ListView(
      children: [
        adaptiveListSection(
          children: [
            _TvSettingsListTile(
              autofocus: true,
              leading: Image.asset(
                'assets/icons/seerr.png',
                width: 24,
                height: 24,
              ),
              title: Text(seerrLabel),
              subtitle: Text(l10n.mediaRequestIntegration),
              onTap: () =>
                  context.pushSettingsScreen(const SeerrConfigScreen()),
            ),
            _TvSettingsListTile(
              leading: const Icon(Icons.satellite_alt),
              title: const Text('Direct IPTV'),
              subtitle: const Text(
                'Dispatcharr or an M3U playlist, played without the server tuner',
              ),
              onTap: () => context.pushSettingsScreen(
                const DirectIptvSettingsScreen(),
              ),
            ),
            _TvSettingsListTile(
              leading: const Icon(Icons.subscriptions),
              title: const Text('Streaming'),
              subtitle: const Text('TMDB API key for Netflix, Disney+, Max, and Prime Video'),
              onTap: () => context.pushSettingsScreen(
                const StreamingSettingsScreen(),
              ),
            ),
            // MOFIN-PLUGIN-HOOK: Plugin Host Settings
            if (PlatformDetection.pluginHostSupported)
              _TvSettingsListTile(
                leading: const Icon(Icons.extension),
                title: const Text('Plugins'),
                subtitle: const Text('Web plugin host system and installed plugins'),
                onTap: () => context.pushSettingsScreen(
                  PluginSettingsScreen(
                    pluginService: GetIt.instance<PluginService>(),
                    onTogglePluginsEnabled: (val) async {
                      final prefs = GetIt.instance<UserPreferences>();
                      await prefs.set(UserPreferences.pluginsEnabled, val);
                    },
                    onUpdatePluginUrls: (urls) async {},
                  ),
                ),
              ),
            // MOFIN-PLUGIN-HOOK: Dynamic registered plugin settings entries
            if (PlatformDetection.pluginHostSupported &&
                GetIt.instance<UserPreferences>().get(UserPreferences.pluginsEnabled) &&
                GetIt.instance.isRegistered<PluginRegistry>())
              ...GetIt.instance<PluginRegistry>().settingsEntries.map((entry) {
                return _TvSettingsListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(entry.title),
                  subtitle: Text('Plugin: ${entry.pluginId}'),
                  onTap: () {
                    context.pushSettingsScreen(
                      PluginWebViewScreen(
                        title: entry.title,
                        entryUrl: entry.url,
                        pluginId: entry.pluginId,
                        pluginService: GetIt.instance<PluginService>(),
                        webViewEnvironment: gWebViewEnvironment,
                      ),
                    );
                  },
                );
              }),
            if (achievements.available)
              _TvSettingsListTile(
                leading: const Icon(
                  Icons.military_tech,
                  color: Color(0xFFFFC107),
                ),
                title: Text(l10n.achievementBadges),
                subtitle: Text(l10n.achievementBadgesSubtitle),
                onTap: () => context.pushSettingsScreen(
                  const AchievementsScreen(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
