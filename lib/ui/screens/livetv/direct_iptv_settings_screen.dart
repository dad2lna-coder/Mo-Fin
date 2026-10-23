import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../direct_iptv/direct_iptv_catalog.dart';
import '../../../direct_iptv/models.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../widgets/adaptive/adaptive_dialog.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/settings/preference_tiles.dart';

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
          ? const Center(
              child: Text('No Dispatcharr, Pluto, or M3U sources yet'),
            )
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
  final List<FocusNode> _rows = [];
  int _rowCount = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _rows.isEmpty) return;
      _rows.first.requestFocus();
    });
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
    for (final node in _rows) {
      node.dispose();
    }
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
      id:
          widget.existing?.id ??
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
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (context) => withBackClose(
        context,
        SimpleDialog(
          title: const Text('Remove source?'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(existing.name),
            ),
            _IptvFocusTile(
              autofocus: true,
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(false),
            ),
            _IptvFocusTile(
              title: const Text('Remove'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await GetIt.instance<DirectIptvCatalog>().delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editText({
    required TextEditingController controller,
    required String title,
    String? hint,
    String? helper,
    bool obscure = false,
    TextInputType? keyboardType,
  }) async {
    final next = await showFocusRestoringDialog<String>(
      context: context,
      builder: (ctx) => _IptvTextDialog(
        title: title,
        initial: controller.text,
        hint: hint,
        helper: helper,
        obscure: obscure,
        keyboardType: keyboardType,
      ),
    );
    if (next == null || !mounted) return;
    controller.text = next;
    setState(() => _error = null);
  }

  Future<void> _pickKind() async {
    final next = await showFocusRestoringDialog<DirectIptvKind>(
      context: context,
      builder: (ctx) => withBackClose(
        ctx,
        SimpleDialog(
          title: const Text('Type'),
          children: [
            for (final kind in DirectIptvKind.values)
              _IptvFocusTile(
                autofocus: kind == _kind,
                title: Text(_kindLabel(kind)),
                trailing: kind == _kind ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, kind),
              ),
          ],
        ),
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      _kind = next;
      _error = null;
    });
  }

  String _kindLabel(DirectIptvKind kind) => switch (kind) {
    DirectIptvKind.dispatcharr => 'Dispatcharr',
    DirectIptvKind.m3u => 'M3U playlist',
    DirectIptvKind.pluto => 'Pluto TV',
  };

  String _addressLabel() => switch (_kind) {
    DirectIptvKind.dispatcharr => 'Dispatcharr address',
    DirectIptvKind.pluto => 'Guide address',
    DirectIptvKind.m3u => 'Playlist address',
  };

  String _addressHint() => _kind == DirectIptvKind.pluto
      ? 'https://i.mjh.nz/PlutoTV/us.xml'
      : 'http://host:9191';

  String _m3uHelper() => switch (_kind) {
    DirectIptvKind.dispatcharr =>
      'Blank uses /output/m3u/. A full URL is also accepted.',
    DirectIptvKind.pluto => 'Unused. Pluto channels come from the guide.',
    DirectIptvKind.m3u => 'Blank uses the address above as the playlist.',
  };

  String _epgHelper() => switch (_kind) {
    DirectIptvKind.dispatcharr => 'Blank uses /output/epg/. Some servers use /output/xmltv. Enter - to skip the guide.',
    DirectIptvKind.pluto => 'Blank uses the address above as the XMLTV guide. Channels play from jmp2.uk. Enter - to skip.',
    DirectIptvKind.m3u => 'Optional XMLTV path or URL. Blank skips the guide.',
  };

  String _shownValue(String value, {bool secret = false}) {
    final trimmed = value.trim();
    if (secret) return trimmed.isEmpty ? 'Not set' : 'Set';
    return trimmed.isEmpty ? 'Not set' : trimmed;
  }

  FocusNode _rowNode(int index, String label) {
    if (index == _rows.length) {
      _rows.add(FocusNode(debugLabel: 'iptv-row:$label'));
    }
    return _rows[index];
  }

  void _moveRow(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _rowCount || next >= _rows.length) return;
    _rows[next].requestFocus();
  }

  Widget _row({
    required int index,
    required String label,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return _IptvFocusTile(
      focusNode: _rowNode(index, label),
      autofocus: index == 0,
      captureArrows: true,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      onUp: index == 0 ? null : () => _moveRow(index, -1),
      onDown: index >= _rowCount - 1 ? null : () => _moveRow(index, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remove = widget.existing != null;
    _rowCount = remove ? 15 : 14;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add source' : 'Edit source'),
      ),
      // Every row is built, and Up/Down walks an explicit chain ending at
      // Save. A lazy list never lays out Save, so directional focus stops
      // on the last visible tile.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 32),
        child: Column(
          children: [
            _row(
              index: 0,
              label: 'Name',
              title: const Text('Name'),
              subtitle: Text(_shownValue(_name.text)),
              onTap: () =>
                  unawaited(_editText(controller: _name, title: 'Name')),
            ),
            _row(
              index: 1,
              label: 'Type',
              title: const Text('Type'),
              subtitle: Text(_kindLabel(_kind)),
              onTap: () => unawaited(_pickKind()),
            ),
            _row(
              index: 2,
              label: 'Address',
              title: Text(_addressLabel()),
              subtitle: Text(_shownValue(_baseUrl.text)),
              onTap: () => unawaited(
                _editText(
                  controller: _baseUrl,
                  title: _addressLabel(),
                  hint: _addressHint(),
                  keyboardType: TextInputType.url,
                ),
              ),
            ),
            _row(
              index: 3,
              label: 'Username',
              title: const Text('Username'),
              subtitle: Text(_shownValue(_username.text)),
              onTap: () => unawaited(
                _editText(
                  controller: _username,
                  title: 'Username',
                  helper: 'Optional. Used when no token is set.',
                ),
              ),
            ),
            _row(
              index: 4,
              label: 'Password',
              title: const Text('Password'),
              subtitle: Text(_shownValue(_password.text, secret: true)),
              onTap: () => unawaited(
                _editText(
                  controller: _password,
                  title: 'Password',
                  obscure: true,
                ),
              ),
            ),
            _row(
              index: 5,
              label: 'Token',
              title: const Text('Token'),
              subtitle: Text(_shownValue(_token.text, secret: true)),
              onTap: () => unawaited(
                _editText(
                  controller: _token,
                  title: 'Token',
                  obscure: true,
                  helper:
                      'Optional. Sent as a bearer token instead of a password.',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
              child: Text(
                'The password and token stay on this device with the other preferences. They are not encrypted.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _row(
              index: 6,
              label: 'M3U path',
              title: const Text('M3U path'),
              subtitle: Text(_baseUrlSubtitle(_m3uPath.text, _m3uHelper())),
              onTap: () => unawaited(
                _editText(
                  controller: _m3uPath,
                  title: 'M3U path',
                  helper: _m3uHelper(),
                ),
              ),
            ),
            _row(
              index: 7,
              label: 'EPG path',
              title: const Text('EPG path'),
              subtitle: Text(_baseUrlSubtitle(_epgPath.text, _epgHelper())),
              onTap: () => unawaited(
                _editText(
                  controller: _epgPath,
                  title: 'EPG path',
                  helper: _epgHelper(),
                ),
              ),
            ),
            _row(
              index: 8,
              label: 'Refresh every (minutes)',
              title: const Text('Refresh every (minutes)'),
              subtitle: Text(_shownValue(_refreshMinutes.text)),
              onTap: () => unawaited(
                _editText(
                  controller: _refreshMinutes,
                  title: 'Refresh every (minutes)',
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            _row(
              index: 9,
              label: 'Preferred subtitle language',
              title: const Text('Preferred subtitle language'),
              subtitle: Text(_shownValue(_subtitleLanguage.text)),
              onTap: () => unawaited(
                _editText(
                  controller: _subtitleLanguage,
                  title: 'Preferred subtitle language',
                  hint: 'en',
                ),
              ),
            ),
            _row(
              index: 10,
              label: 'Preferred audio language',
              title: const Text('Preferred audio language'),
              subtitle: Text(_shownValue(_audioLanguage.text)),
              onTap: () => unawaited(
                _editText(
                  controller: _audioLanguage,
                  title: 'Preferred audio language',
                  hint: 'en',
                ),
              ),
            ),
            _row(
              index: 11,
              label: 'Captions on by default',
              title: const Text('Captions on by default'),
              subtitle: const Text(
                'Selects the preferred language on direct channels. Pluto marks its WebVTT rendition off, so the player has to turn it on. CEA-608 is used when that is what the stream carries instead.',
              ),
              trailing: Icon(_captionsOn ? Icons.toggle_on : Icons.toggle_off),
              onTap: () => setState(() => _captionsOn = !_captionsOn),
            ),
            _row(
              index: 12,
              label: 'Enabled',
              title: const Text('Enabled'),
              subtitle: Text(_enabled ? 'On' : 'Off'),
              trailing: Icon(_enabled ? Icons.toggle_on : Icons.toggle_off),
              onTap: () => setState(() => _enabled = !_enabled),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            _row(
              index: 13,
              label: 'Save',
              title: const Text('Save'),
              onTap: () => unawaited(_save()),
            ),
            if (remove)
              _row(
                index: 14,
                label: 'Remove source',
                title: const Text('Remove source'),
                onTap: () => unawaited(_delete()),
              ),
          ],
        ),
      ),
    );
  }

  String _baseUrlSubtitle(String value, String helper) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return helper;
    return '$trimmed\n$helper';
  }
}

/// One D-pad stop. [captureArrows] walks an explicit up/down chain so a row
/// that is below the fold, including Save, is still reachable.
class _IptvFocusTile extends StatefulWidget {
  final bool autofocus;
  final bool captureArrows;
  final FocusNode? focusNode;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _IptvFocusTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onUp,
    this.onDown,
    this.focusNode,
    this.autofocus = false,
    this.captureArrows = false,
  });

  @override
  State<_IptvFocusTile> createState() => _IptvFocusTileState();
}

class _IptvFocusTileState extends State<_IptvFocusTile> {
  int _lastMicros = 0;
  FocusNode? _owned;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_owned ??= FocusNode());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _activate() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - _lastMicros < 250000) return;
    _lastMicros = now;
    onTap();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (widget.captureArrows && (key.isUpKey || key.isDownKey)) {
      if (key.isDownKey) {
        widget.onDown?.call();
      } else {
        widget.onUp?.call();
      }
      return KeyEventResult.handled;
    }
    if (widget.captureArrows && (key.isLeftKey || key.isRightKey)) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key.isSelectKey) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600);
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      descendantsAreFocusable: false,
      onFocusChange: (next) {
        if (!mounted || _focused == next) return;
        setState(() => _focused = next);
        if (next) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 120),
          );
        }
      },
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: focused ? const Color(0xFF1E3A5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onTap == null ? null : _activate,
            canRequestFocus: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: titleStyle,
                          child: widget.title,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle.merge(
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                            child: widget.subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 12),
                    IconTheme.merge(
                      data: const IconThemeData(color: Colors.white, size: 28),
                      child: widget.trailing!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IptvTextDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboardType;

  const _IptvTextDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.helper,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  State<_IptvTextDialog> createState() => _IptvTextDialogState();
}

class _IptvTextDialogState extends State<_IptvTextDialog> {
  late final TextEditingController _controller;
  late final FocusNode _fieldFocus;
  late final FocusNode _cancelFocus;
  late final FocusNode _saveFocus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _cancelFocus = FocusNode(
      debugLabel: 'iptv-dialog:Cancel',
      onKeyEvent: (_, event) =>
          _moveDialog(event, up: _fieldFocus, down: _saveFocus),
    );
    _saveFocus = FocusNode(
      debugLabel: 'iptv-dialog:Save',
      onKeyEvent: (_, event) => _moveDialog(event, up: _cancelFocus),
    );
    // The field's own text shortcuts sit above this node and would swallow
    // arrows for the caret. Handling them here runs first, so down reaches
    // Cancel and then Save. Left/right still fall through to the caret.
    _fieldFocus = FocusNode(
      debugLabel: 'direct-iptv-text',
      onKeyEvent: (_, event) => _moveDialog(event, down: _cancelFocus),
    );
  }

  KeyEventResult _moveDialog(KeyEvent event, {FocusNode? up, FocusNode? down}) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isDownKey && down != null) {
      down.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isUpKey && up != null) {
      up.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key.isDownKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    _cancelFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _fieldFocus,
            autofocus: true,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: widget.hint),
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 8),
            Text(widget.helper!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        adaptiveDialogAction(
          focusNode: _cancelFocus,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        adaptiveDialogAction(
          focusNode: _saveFocus,
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
