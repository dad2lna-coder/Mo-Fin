import 'package:flutter/material.dart';

import '../../../streaming/tmdb_key_store.dart';
import '../../widgets/seerr/seerr_text_field.dart';
import '../../widgets/settings/clean_settings_typography.dart';

class StreamingSettingsScreen extends StatefulWidget {
  const StreamingSettingsScreen({super.key, this.store});

  final TmdbKeyStore? store;

  @override
  State<StreamingSettingsScreen> createState() =>
      _StreamingSettingsScreenState();
}

class _StreamingSettingsScreenState extends State<StreamingSettingsScreen> {
  final _controller = TextEditingController();
  late final TmdbKeyStore _store = widget.store ?? TmdbKeyStore();
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _store.read();
    if (!mounted) return;
    _controller.text = key;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _store.write(_controller.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('Streaming')),
        body: _ready
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'TMDB API key',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Used only for Netflix, Disney+, Max, and Prime Video. '
                    'Stored in secure storage, not with the other preferences.',
                  ),
                  const SizedBox(height: 12),
                  SeerrTextField(
                    controller: _controller,
                    hint: 'TMDB API key',
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
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
