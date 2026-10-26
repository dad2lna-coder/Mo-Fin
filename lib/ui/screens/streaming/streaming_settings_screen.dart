import 'package:flutter/material.dart';

import '../../../streaming/streaming_service.dart';
import '../../../streaming/tmdb_key_store.dart';
import '../../widgets/seerr/seerr_text_field.dart';
import '../../widgets/settings/clean_settings_typography.dart';

class StreamingSettingsScreen extends StatefulWidget {
  const StreamingSettingsScreen({super.key, this.store, this.providerStore});

  final TmdbKeyStore? store;
  final StreamingProviderKeyStore? providerStore;

  @override
  State<StreamingSettingsScreen> createState() =>
      _StreamingSettingsScreenState();
}

class _StreamingSettingsScreenState extends State<StreamingSettingsScreen> {
  final _tmdbController = TextEditingController();
  final _providerController = TextEditingController();
  late final TmdbKeyStore _store = widget.store ?? TmdbKeyStore();
  late final StreamingProviderKeyStore _providerStore =
      widget.providerStore ?? StreamingProviderKeyStore();

  bool _ready = false;
  bool _saving = false;
  List<StreamingService> _activeServices = kStreamingServices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _store.read();
    final providerKey = await _providerStore.read();
    final active = await StreamingSubscriptionPreferences.readActiveServices();
    if (!mounted) return;
    _tmdbController.text = key;
    _providerController.text = providerKey;
    setState(() {
      _activeServices = active;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _tmdbController.dispose();
    _providerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _store.write(_tmdbController.text);
    await _providerStore.write(_providerController.text);
    await StreamingSubscriptionPreferences.writeActiveServices(_activeServices);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toggleService(StreamingService service, bool enabled) {
    setState(() {
      final updated = List<StreamingService>.from(_activeServices);
      if (enabled) {
        if (!updated.contains(service)) updated.add(service);
      } else {
        updated.remove(service);
      }
      _activeServices = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('Streaming Settings')),
        body: _ready
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'TMDB API key',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Required for catalog metadata (trending, popular, top-rated). Stored securely.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  SeerrTextField(
                    controller: _tmdbController,
                    hint: 'TMDB API key',
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Streaming Provider Lookup Key (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Optional Watchmode / Streaming Availability key for direct title deep links. Stored securely.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  SeerrTextField(
                    controller: _providerController,
                    hint: 'Watchmode / Provider API Key (Optional)',
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'My Subscriptions',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select which services to show on your streaming home screen (Hulu is excluded).',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  for (final service in kStreamingServices)
                    SwitchListTile(
                      title: Text(service.label),
                      value: _activeServices.contains(service),
                      onChanged: (enabled) => _toggleService(service, enabled),
                    ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      autofocus: true,
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
