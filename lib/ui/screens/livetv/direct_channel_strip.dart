import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/viewmodels/live_tv_guide_view_model.dart';
import '../../../direct_iptv/direct_iptv_catalog.dart';
import '../../../util/focus/dpad_keys.dart';

/// Channel changer for a direct lineup. The shared carousel asks the server
/// guide for every card, which these channel ids are not part of.
class DirectChannelStrip extends StatefulWidget {
  final List<GuideChannel> channels;
  final String currentChannelId;
  final ValueChanged<String> onChannelSelected;
  final VoidCallback onDismiss;

  const DirectChannelStrip({
    super.key,
    required this.channels,
    required this.currentChannelId,
    required this.onChannelSelected,
    required this.onDismiss,
  });

  @override
  State<DirectChannelStrip> createState() => _DirectChannelStripState();
}

class _DirectChannelStripState extends State<DirectChannelStrip> {
  final FocusNode _focus = FocusNode(debugLabel: 'DirectChannelStrip');
  late int _index;

  @override
  void initState() {
    super.initState();
    final found = widget.channels.indexWhere(
      (channel) => channel.id == widget.currentChannelId,
    );
    _index = found < 0 ? 0 : found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  GuideChannel? get _channel =>
      widget.channels.isEmpty ? null : widget.channels[_index];

  void _step(int delta) {
    if (widget.channels.length < 2) return;
    setState(() {
      _index = (_index + delta) % widget.channels.length;
      if (_index < 0) _index += widget.channels.length;
    });
  }

  String _nowTitle(GuideChannel channel) {
    if (!GetIt.instance.isRegistered<DirectIptvCatalog>()) return '';
    return GetIt.instance<DirectIptvCatalog>()
            .programOnNow(channel.id)
            ?.title ??
        '';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key.isLeftKey) {
        _step(-1);
        return KeyEventResult.handled;
      }
      if (key.isRightKey) {
        _step(1);
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (key.isSelectKey) {
      final channel = _channel;
      if (channel != null) widget.onChannelSelected(channel.id);
      return KeyEventResult.handled;
    }
    if (key.isBackKey || key.isDownKey || key.isUpKey) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    final title = channel == null ? '' : _nowTitle(channel);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              constraints: const BoxConstraints(maxWidth: 720),
              decoration: BoxDecoration(
                color: const Color(0xF0101822),
                borderRadius: AppRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel == null
                        ? ''
                        : [
                            if ((channel.number ?? '').isNotEmpty)
                              channel.number,
                            channel.name,
                          ].join('  '),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Left and right change channel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen channel list for a player that cannot draw the strip over
/// the video, such as the Apple TV host. Pops the chosen channel id.
class DirectChannelListPage extends StatelessWidget {
  final List<GuideChannel> channels;
  final String currentChannelId;

  const DirectChannelListPage({
    super.key,
    required this.channels,
    required this.currentChannelId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Channels')),
      body: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          final number = channel.number ?? '';
          final label = number.isEmpty ? channel.name : '$number  ${channel.name}';
          return ListTile(
            title: Text(label),
            selected: channel.id == currentChannelId,
            onTap: () => Navigator.of(context).pop(channel.id),
          );
        },
      ),
    );
  }
}
