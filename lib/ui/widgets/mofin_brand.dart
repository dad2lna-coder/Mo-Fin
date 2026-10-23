import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Crescent mark, or the mark with the MoFin wordmark.
///
/// Dark surfaces get the brighter blue mark and a white wordmark. Light
/// surfaces get the navy mark and a navy wordmark. [onDark] pins a variant
/// when the logo sits on a surface that is not the scaffold, such as the
/// live-TV sidebar.
class MoFinBrand extends StatelessWidget {
  const MoFinBrand({
    super.key,
    this.height,
    this.width,
    this.wordmark = true,
    this.onDark,
    this.fit = BoxFit.contain,
  });

  final double? height;
  final double? width;
  final bool wordmark;
  final bool? onDark;
  final BoxFit fit;

  static bool surfaceIsDark(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return background.computeLuminance() < 0.45;
  }

  static String assetFor({required bool wordmark, required bool dark}) {
    if (wordmark) {
      return dark
          ? 'assets/icons/mofin_lockup_dark.svg'
          : 'assets/icons/mofin_lockup_light.svg';
    }
    return dark
        ? 'assets/icons/mofin_mark_dark.svg'
        : 'assets/icons/mofin_mark_light.svg';
  }

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? surfaceIsDark(context);
    return SvgPicture.asset(
      assetFor(wordmark: wordmark, dark: dark),
      width: width,
      height: height,
      fit: fit,
      semanticsLabel: 'MoFin',
    );
  }
}
