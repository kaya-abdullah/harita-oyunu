/// Shared feedback SnackBar used across the game HUD.
library;

import 'package:flutter/material.dart';

import 'package:harita/core/theme/app_theme.dart';

/// Shows a short floating SnackBar with an optional [icon] and [message].
///
/// Any previous SnackBar is cleared first so rapid taps never queue up a
/// long backlog of messages. Silently does nothing when no [ScaffoldMessenger]
/// is available.
void showGameSnack(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? color,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: color,
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppTheme.kTextLight, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 16, color: AppTheme.kTextLight),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ),
  );
}
