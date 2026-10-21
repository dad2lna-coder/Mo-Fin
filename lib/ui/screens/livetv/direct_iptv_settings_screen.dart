import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../direct_iptv/direct_iptv_catalog.dart';
import '../../../direct_iptv/models.dart';

/// Dispatcharr and raw M3U accounts. Credentials stay in on-device preferences.
class DirectIptvSettingsScreen extends StatefulWidget {
  /// When set, the editor for that source opens immediately.
  final String? editSourceId;

  /// Opens a blank editor on top of the list. Used by the empty guide.
  final bool createOnOpen;

  const DirectIptvSettingsScreen({
    super.key,
    this.editSourceId,
    this.createOnOpen = false,
  });

  @override
  State<DirectIptvSettingsScreen> createState() =>
      _DirectIptvSettingsScreenState();
}

class _DirectIptvSettingsScreenState extends State<DirectIptvSettingsScreen> {
  late final DirectIptvCatalog _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = GetIt.instance<DirectIptvCatalog>();
    _catalog.addListener(_onCatalog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openRequested());
    });
  }

  Future<void> _openRequested() async {
    if (widget.createOnOpen) {
      await _catalog.ensureLoaded();
      if (!mounted) return;
      await _edit(null);
      return;
    }
    final id = widget.editSourceId;
    if (id == null) return;
    await _catalog.ensureLoaded();
    if (!mounted) return;
    final source = _catalog.sourceById(id);
    if (source == null) return;
    await _edit(source);
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  void _onCatalog() {
    if (mounted) setState(() {});
  }

  Future<void> _edit(DirectIptvSource? source) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _DirectIptvEditor(existing: source)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _catalog.sources;
    return Scaffold(
      appBar: AppBar(title: const Text('Direct IPTV')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_edit(null)),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: !_catalog.loaded
          ? const Center(child: CircularProgressIndicator())
          : sources.isEmpty
          ? const Center(child: Text('No Dispatcharr, Pluto, or M3U sources yet'))
          : ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                final count = _catalog.snapshotFor(source.id)?.channels.length;
                final error = _catalog.errorFor(source.id);
                final subtitle = [
                  source.kind == DirectIptvKind.dispatcharr
                      ? 'Dispatcharr'
                      : source.kind == DirectIptvKind.pluto
                      ? 'Pluto TV'
                      : 'M3U playlist',
                  if (!source.enabled) 'Off',
                  if (count != null) '$count channels',
                  ?error,
                ].join(' · ');
                return ListTile(
                  title: Text(source.name),
                  subtitle: Text(subtitle),
                  trailing: _catalog.isRefreshing(source.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Refresh',
                          onPressed: source.enabled
                              ? () => unawaited(
                                  _catalog.refresh(source.id, force: true),
                                )
                              : null,
                          icon: const Icon(Icons.refresh),
                        ),
                  onTap: () => unawaited(_edit(source)),
                );
              },
            ),
    );
  }
}

class _DirectIptvEditor extends StatefulWidget {
  final DirectIptvSource? existing;

  const _DirectIptvEditor({required this.existing});

  @override
  State<_DirectIptvEditor> createState() => _DirectIptvEditorState();
}

class _DirectIptvEditorState extends State<_DirectIptvEditor> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _token;
  late final TextEditingController _m3uPath;
  late final TextEditingController _epgPath;
  late final TextEditingController _refreshMinutes;
  late final TextEditingController _subtitleLanguage;
  late final TextEditingController _audioLanguage;
  late DirectIptvKind _kind;
  late bool _enabled;
  late bool _captionsOn;
  String? _error;

  @override
  void initState() {
    super.initState();
    final source = widget.existing;
    _name = TextEditingController(text: source?.name ?? 'Dispatcharr');
    _baseUrl = TextEditingController(text: source?.baseUrl ?? '');
    _username = TextEditingController(text: source?.username ?? '');
    _password = TextEditingController(text: source?.password ?? '');
    _token = TextEditingController(text: source?.token ?? '');
    _m3uPath = TextEditingController(text: source?.m3uPath ?? '');
    _epgPath = TextEditingController(text: source?.epgPath ?? '');
    _refreshMinutes = TextEditingController(
      text: '${source?.refreshMinutes ?? 30}',
    );
    _subtitleLanguage = TextEditingController(
      text: source?.preferredSubtitleLanguage ?? '',
    );
    _audioLanguage = TextEditingController(
      text: source?.preferredAudioLanguage ?? '',
    );
    _kind = source?.kind ?? DirectIptvKind.dispatcharr;
    _enabled = source?.enabled ?? true;
    _captionsOn = source?.captionsOnByDefault ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    _m3uPath.dispose();
    _epgPath.dispose();
    _refreshMinutes.dispose();
    _subtitleLanguage.dispose();
    _audioLanguage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final base = _baseUrl.text.trim();
    final uri = Uri.tryParse(base);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = 'Enter an http or https address');
      return;
    }
    final minutes = int.tryParse(_refreshMinutes.text.trim()) ?? 30;
    final source = DirectIptvSource(
      id: widget.existing?.id ??
          'src${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
      name: _name.text.trim().isEmpty ? 'Direct IPTV' : _name.text.trim(),
      kind: _kind,
      baseUrl: base,
      username: _username.text,
      password: _password.text,
      token: _token.text.trim(),
      m3uPath: _m3uPath.text.trim(),
      epgPath: _epgPath.text.trim(),
      refreshMinutes: minutes < 1 ? 30 : minutes,
      preferredSubtitleLanguage: _subtitleLanguage.text.trim(),
      preferredAudioLanguage: _audioLanguage.text.trim(),
      captionsOnByDefault: _captionsOn,
      enabled: _enabled,
    );
    await GetIt.instance<DirectIptvCatalog>().upsert(source);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove source?'),
        content: Text(existing.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await GetIt.instance<DirectIptvCatalog>().delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add source' : 'Edit source'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DirectIptvKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(
                value: DirectIptvKind.dispatcharr,
                child: Text('Dispatcharr'),
              ),
              DropdownMenuItem(
                value: DirectIptvKind.m3u,
                child: Text('M3U playlist'),
              ),
              DropdownMenuItem(
                value: DirectIptvKind.pluto,
                child: Text('Pluto TV'),
              ),
            ],
            onChanged: (kind) {
              if (kind != null) setState(() => _kind = kind);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: _kind == DirectIptvKind.dispatcharr
                  ? 'Dispatcharr address'
                  : _kind == DirectIptvKind.pluto
                  ? 'Guide address'
                  : 'Playlist address',
              hintText: _kind == DirectIptvKind.pluto
                  ? 'https://i.mjh.nz/PlutoTV/us.xml'
                  : 'http://host:9191',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText: 'Optional. Used when no token is set.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token',
              helperText: 'Optional. Sent as a bearer token instead of a password.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The password and token stay on this device with the other preferences. They are not encrypted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _m3uPath,
            decoration: InputDecoration(
              labelText: 'M3U path',
              helperText: _kind == DirectIptvKind.dispatcharr
                  ? 'Blank uses /output/m3u/. A full URL is also accepted.'
                  : _kind == DirectIptvKind.pluto
                  ? 'Unused. Pluto channels come from the guide.'
                  : 'Blank uses the address above as the playlist.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _epgPath,
            decoration: InputDecoration(
              labelText: 'EPG path',
              helperText: _kind == DirectIptvKind.dispatcharr
                  ? 'Blank uses /output/epg/. Some servers use /output/xmltv. Enter - to skip the guide.'
                  : _kind == DirectIptvKind.pluto
                  ? 'Blank uses the address above as the XMLTV guide. Channels play from jmp2.uk. Enter - to skip.'
                  : 'Optional XMLTV path or URL. Blank skips the guide.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _refreshMinutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Refresh every (minutes)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subtitleLanguage,
            decoration: const InputDecoration(
              labelText: 'Preferred subtitle language',
              hintText: 'en',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _audioLanguage,
            decoration: const InputDecoration(
              labelText: 'Preferred audio language',
              hintText: 'en',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Captions on by default'),
            subtitle: const Text(
              'Selects the preferred language on direct channels. Pluto marks its WebVTT rendition off, so the player has to turn it on. CEA-608 is used when that is what the stream carries instead.',
            ),
            value: _captionsOn,
            onChanged: (value) => setState(() => _captionsOn = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          FilledButton(onPressed: () => unawaited(_save()), child: const Text('Save')),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(_delete()),
              child: const Text('Remove source'),
            ),
          ],
        ],
      ),
    );
  }
}
