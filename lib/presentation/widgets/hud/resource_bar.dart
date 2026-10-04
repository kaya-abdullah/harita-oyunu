/// ResourceBar HUD widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Displays the Elma (apple currency) balance for both armies side-by-side
/// so players can quickly compare their economic standing at a glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

/// Horizontal bar showing the Elma balance for both armies.
///
/// Army 1 (blue) is on the left; Army 2 (red) is on the right.
/// The active army's side is slightly elevated to draw attention.
/// Font size is always >= 16 sp per Requirement 11.1.
class ResourceBar extends ConsumerWidget {
  const ResourceBar({super.key});

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
        final army1Elma = gameState.army1.elmaBalance;
        final army2Elma = gameState.army2.elmaBalance;
        final isArmy1Active = gameState.activeArmyId.name == 'army1';

        return Container(
          color: AppTheme.kBackground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // ── Army 1 (blue) ────────────────────────────────────────────
              Expanded(
                child: _ArmyElmaChip(
                  elma: army1Elma,
                  label: strings.army1Name,
                  backgroundColor: AppTheme.army1Primary,
                  textColor: AppTheme.kTextLight,
                  isActive: isArmy1Active,
                  balanceLabel: strings.elmaBalanceLabel,
                ),
              ),

              // ── Divider ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'vs',
                  style: AppTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.kTextDark,
                  ),
                ),
              ),

              // ── Army 2 (red) ─────────────────────────────────────────────
              Expanded(
                child: _ArmyElmaChip(
                  elma: army2Elma,
                  label: strings.army2Name,
                  backgroundColor: AppTheme.army2Primary,
                  textColor: AppTheme.kTextLight,
                  isActive: !isArmy1Active,
                  balanceLabel: strings.elmaBalanceLabel,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Internal chip displaying a single army's Elma balance.
class _ArmyElmaChip extends StatelessWidget {
  const _ArmyElmaChip({
    required this.elma,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.isActive,
    required this.balanceLabel,
  });

  final int elma;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final bool isActive;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: backgroundColor.withAlpha(128),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
        border: isActive
            ? Border.all(color: AppTheme.kTextLight, width: 2)
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Apple emoji icon
          Text('🍎', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Army name
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Elma balance
                Text(
                  '$balanceLabel $elma',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
