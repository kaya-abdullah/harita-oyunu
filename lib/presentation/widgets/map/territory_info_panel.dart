/// City information panel for Harita: Kendi İmparatorluğunu Kur.
///
/// Shows the selected city: owner, soldiers, mines, forest, and its
/// neighbours — with an attack button for each neighbour the player can
/// send soldiers to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/services/combat_service.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/game_names.dart';

// ─── TerritoryInfoPanel ───────────────────────────────────────────────────────

/// Card with the selected city, or a hint when nothing is selected.
class TerritoryInfoPanel extends ConsumerWidget {
  const TerritoryInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedTerritoryProvider);
    final state = ref.watch(gameProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        final humanPlays =
            state.activeArmy.isHuman && state.phase == GamePhase.playing;
        if (selectedId == null || selectedId >= state.territories.length) {
          return _Hint(
            text: humanPlays ? strings.hintAttack : strings.hintSelectTerritory,
          );
        }
        return _CityCard(
          state: state,
          cityId: selectedId,
          strings: strings,
          humanPlays: humanPlays,
          onAttack: (target) => ref
              .read(gameProvider.notifier)
              .dispatchTroops(selectedId, target),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded, color: AppTheme.army1Primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: AppTheme.kTextDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _CityCard ────────────────────────────────────────────────────────────────

class _CityCard extends StatelessWidget {
  const _CityCard({
    required this.state,
    required this.cityId,
    required this.strings,
    required this.humanPlays,
    required this.onAttack,
  });

  final GameState state;
  final int cityId;
  final AppStrings strings;
  final bool humanPlays;
  final void Function(int targetId) onAttack;

  @override
  Widget build(BuildContext context) {
    final graph = TerritoryGraph.bundled();
    final lang = strings.languageCode;
    final city = state.territories[cityId];
    final owner = city.ownerArmyId;
    final headerColor = owner == null
        ? AppTheme.kNeutralLight
        : AppTheme.armyColor(owner);
    final onHeader = owner == null ? AppTheme.kTextDark : AppTheme.kTextLight;
    final me = state.activeArmyId;
    final mine = humanPlays && owner == me;
    final strength = mine ? attackStrength(state.activeArmy, city) : null;

    return Card(
      key: const Key('city_card'),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.location_city_rounded, color: onHeader),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    graph.cityName(cityId, lang),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: onHeader,
                    ),
                  ),
                ),
                Text(
                  '${city.unitCount}',
                  key: const Key('city_units'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: onHeader,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: strings.territoryOwnerLabel,
                  value: owner == null
                      ? strings.territoryOwnerNeutral
                      : armyDisplayName(state, owner, strings),
                ),
                _Line(
                  label: strings.territoryUnitsLabel,
                  value: '${city.unitCount}',
                ),
                if (strength != null)
                  _Line(label: strings.strengthLabel, value: '$strength'),
                if (city.hasDiamondMine)
                  _Badge(
                    icon: Icons.diamond_rounded,
                    color: AppTheme.kDiamond,
                    text: '${strings.diamondMineLabel} +$kDiamondMineReward',
                  ),
                if (city.hasGoldMine)
                  _Badge(
                    icon: Icons.paid_rounded,
                    color: AppTheme.kGold,
                    text: '${strings.goldMineLabel} +$kGoldMineReward',
                  ),
                if (city.hasForest)
                  _Badge(
                    icon: Icons.forest_rounded,
                    color: AppTheme.kAccentGreen,
                    text: strings.forestLabel,
                  ),
                const SizedBox(height: 6),
                Text(
                  strings.territoryAdjacentLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.kTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final adj in city.adjacentIds)
                      _NeighbourChip(
                        name: graph.cityName(adj, lang),
                        units: state.territories[adj].unitCount,
                        owner: state.territories[adj].ownerArmyId,
                        canAttack: mine && city.unitCount >= 2,
                        attackLabel: strings.btnAttack,
                        onAttack: () => onAttack(adj),
                        key: Key('neighbour_$adj'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 15, color: AppTheme.kTextDark),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeighbourChip extends StatelessWidget {
  const _NeighbourChip({
    super.key,
    required this.name,
    required this.units,
    required this.owner,
    required this.canAttack,
    required this.attackLabel,
    required this.onAttack,
  });

  final String name;
  final int units;
  final ArmyId? owner;
  final bool canAttack;
  final String attackLabel;
  final VoidCallback onAttack;

  @override
  Widget build(BuildContext context) {
    final color = owner == null
        ? const Color(0xFF8D8D8D)
        : AppTheme.armyColor(owner!);
    return Material(
      color: color.withAlpha(36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canAttack ? onAttack : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 6, backgroundColor: color),
              const SizedBox(width: 4),
              Text(
                '$name $units',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.kTextDark,
                ),
              ),
              if (canAttack) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: color,
                  semanticLabel: attackLabel,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
