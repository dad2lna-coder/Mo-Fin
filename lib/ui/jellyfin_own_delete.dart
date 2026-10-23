import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../auth/jellyfin_item_delete.dart';
import 'widgets/adaptive/adaptive_dialog.dart';
import 'widgets/overlay_sheet.dart';

/// Confirm before a Jellyfin delete. Cancel takes focus so a D-pad OK does
/// not destroy the item.
Future<bool> confirmOwnJellyfinDelete(
  BuildContext context,
  String title,
) async {
  final confirmed = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      backgroundColor: const Color(0xFF171717),
      content: Text(
        jellyfinDeleteConfirmMessage(title),
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        adaptiveDialogAction(
          autofocus: true,
          focusRingColor: AppColorScheme.accent,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, true),
          isDestructive: true,
          backgroundColor: const Color(0xFFB71C1C),
          focusedBackgroundColor: const Color(0xFFD32F2F),
          child: const Text(
            'Delete',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
