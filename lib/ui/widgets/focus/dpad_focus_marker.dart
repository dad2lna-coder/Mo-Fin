import 'package:flutter/material.dart';

/// The painted D-pad marker: a tinted wash, an accent border, a left bar and
/// a slight scale. [focused] is separate from any selected check or radio the
/// child draws.
class DpadFocusFrame extends StatelessWidget {
  const DpadFocusFrame({
    super.key,
    required this.focused,
    required this.child,
    this.borderRadius = 10,
  });

  final bool focused;
  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final dark = scheme.surface.computeLuminance() < 0.45;
    final fill = accent.withValues(alpha: dark ? 0.32 : 0.16);
    return AnimatedScale(
      scale: focused ? 1.025 : 1,
      alignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: focused ? accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        decoration: BoxDecoration(
          color: focused ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Stack(
          children: [
            child,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: ColoredBox(color: focused ? accent : Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints [DpadFocusFrame] when a descendant control has D-pad focus.
class DpadFocusMarker extends StatefulWidget {
  const DpadFocusMarker({
    super.key,
    required this.child,
    this.borderRadius = 10,
  });

  final Widget child;
  final double borderRadius;

  @override
  State<DpadFocusMarker> createState() => DpadFocusMarkerState();
}

class DpadFocusMarkerState extends State<DpadFocusMarker> {
  final FocusNode _scope = FocusNode(
    debugLabel: 'dpad-focus-scope',
    canRequestFocus: false,
    skipTraversal: true,
  );

  bool get focused => _scope.hasFocus;

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _scope,
      canRequestFocus: false,
      skipTraversal: true,
      child: AnimatedBuilder(
        animation: _scope,
        builder: (context, child) => DpadFocusFrame(
          focused: _scope.hasFocus,
          borderRadius: widget.borderRadius,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}
