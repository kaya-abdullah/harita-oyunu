/// ResourceBar HUD widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Shows the player's diamond (Elmas) balance and, for every army in the
/// game, a colour chip with the number of tiles it owns. The army whose turn
/// it is gets a highlighted border; eliminated armies are greyed out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

/// Horizontal bar with the diamond balance and per-army tile counts.
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
        final tiles = <ArmyId, int>{};
        for (final t in gameState.territories) {
          final owner = t.ownerArmyId;
          if (owner != null) tiles[owner] = (tiles[owner] ?? 0) + 1;
        }

        return Container(
          color: AppTheme.kBackground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _DiamondChip(
                key: const Key('diamond_balance'),
                label: strings.diamondBalanceLabel,
                diamonds: gameState.army1.diamondBalance,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final army in gameState.armies)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _ArmyChip(
                            key: Key('army_chip_${army.id.name}'),
                            name: army.id == ArmyId.army1
                                ? strings.youLabel
                                : strings.armyName(army.id.index),
                            tiles: tiles[army.id] ?? 0,
                            color: AppTheme.armyColor(army.id),
                            isActive: army.id == gameState.activeArmyId,
                            tilesLabel: strings.tilesLabel,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The player's diamond balance.
class _DiamondChip extends StatelessWidget {
  const _DiamondChip({super.key, required this.label, required this.diamonds});

  final String label;
  final int diamonds;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label $diamonds',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.kDiamond,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.diamond_rounded,
              color: AppTheme.kTextLight,
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              '$diamonds',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.kTextLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One army: colour, short name and tile count.
class _ArmyChip extends StatelessWidget {
  const _ArmyChip({
    super.key,
    required this.name,
    required this.tiles,
    required this.color,
    required this.isActive,
    required this.tilesLabel,
  });

  final String name;
  final int tiles;
  final Color color;
  final bool isActive;
  final String tilesLabel;

  @override
  Widget build(BuildContext context) {
    final alive = tiles > 0;
    final bg = alive ? color : AppTheme.kNeutralLight;
    final fg = alive ? AppTheme.kTextLight : AppTheme.kTextDark.withAlpha(120);
    return Tooltip(
      message: '$name: $tiles $tilesLabel',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppTheme.kWarning : Colors.transparent,
            width: 3,
          ),
        ),
        child: Text(
          '${name.split(' ').first} $tiles',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: fg,
            decoration: alive ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}
