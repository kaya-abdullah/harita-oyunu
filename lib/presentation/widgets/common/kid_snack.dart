/// Shared, child-friendly feedback SnackBar used across the game HUD.
library;

import 'package:flutter/material.dart';

import 'package:harita/core/theme/app_theme.dart';

/// Shows a short floating SnackBar with an optional [emoji] and [message].
///
/// Any previous SnackBar is cleared first so rapid taps never queue up a
/// long backlog of messages. Silently does nothing when no [ScaffoldMessenger]
/// is available.
void showKidSnack(
  BuildContext context,
  String message, {
  String emoji = '',
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
          if (emoji.isNotEmpty)
            Text('$emoji  ', style: const TextStyle(fontSize: 20)),
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
