/// TurnIndicator HUD widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Displays the current turn number (with the bot difficulty emoji) and
/// which army is currently active,
/// with a coloured indicator dot matching the army's theme colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/difficulty_picker.dart';
import 'package:harita/presentation/widgets/common/game_names.dart';

/// Shows "Turn: X" and "Active Army: [coloured dot] Name" in the HUD.
///
/// Font size is always >= 16 sp per Requirement 11.1.
/// Colour pairs meet WCAG 4.5:1 contrast per Requirement 11.2.
class TurnIndicator extends ConsumerWidget {
  const TurnIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        final currentTurn = gameState.currentTurn;
        final activeArmyId = gameState.activeArmyId;

        final armyName = armyDisplayName(gameState, activeArmyId, strings);
        final armyDotColor = AppTheme.armyColor(activeArmyId);

        return Container(
          color: AppTheme.kBackground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Turn number + bot difficulty ────────────────────────────
              Tooltip(
                message:
                    '${strings.difficultyLabel}: '
                    '${difficultyName(gameState.difficulty, strings)}',
                child: _TurnChip(label: '${strings.turnLabel} $currentTurn'),
              ),

              // ── Active army indicator ─────────────────────────────────
              const SizedBox(width: 8),
              Flexible(
                child: _ActiveArmyIndicator(
                  label: strings.activeArmyLabel,
                  armyName: armyName,
                  dotColor: armyDotColor,
                  thinkingLabel: gameState.activeArmy.isHuman
                      ? null
                      : strings.aiThinking,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Chip showing the current turn number.
class _TurnChip extends StatelessWidget {
  const _TurnChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.kNeutralLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.army1Primary, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.kTextDark,
        ),
      ),
    );
  }
}

/// Row displaying the active army label + coloured dot + army name.
class _ActiveArmyIndicator extends StatelessWidget {
  const _ActiveArmyIndicator({
    required this.label,
    required this.armyName,
    required this.dotColor,
    this.thinkingLabel,
  });

  final String label;
  final String armyName;
  final Color dotColor;

  /// When non-null the AI is playing: a spinner with this tooltip is shown.
  final String? thinkingLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label text e.g. "Active Army:"
        Flexible(
          child: Text(
            '$label ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.kTextDark,
            ),
          ),
        ),

        // Coloured indicator dot
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withAlpha(180),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),

        // Army name
        Flexible(
          child: Text(
            armyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dotColor,
            ),
          ),
        ),
        if (thinkingLabel != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: thinkingLabel!,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: dotColor,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
