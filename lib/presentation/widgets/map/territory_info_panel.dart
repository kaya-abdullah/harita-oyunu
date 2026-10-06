/// Territory info panel widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Displays information about the currently selected territory:
/// owner, unit count, and adjacent territory names.
///
/// Requirements: 3.3, 11.1, 11.2, 11.3
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

// ─── TerritoryInfoPanel ───────────────────────────────────────────────────────

/// A card panel that displays contextual information for the territory
/// currently selected in [selectedTerritoryProvider].
///
/// When no territory is selected the panel shows a subtle prompt inviting
/// the player to tap the map (Req 3.3).
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────┐
/// │  🗺  Territory Name                  │
/// ├──────────────────────────────────────┤
/// │  Owner:    Army 1 / Neutral          │
/// │  Units:    12                        │
/// │  Adjacent: A, B, C…                  │
/// └──────────────────────────────────────┘
/// ```
class TerritoryInfoPanel extends ConsumerWidget {
  const TerritoryInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedTerritoryProvider);
    final gameState = ref.watch(gameProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const _LoadingPanel(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);

        // ── Nothing selected ────────────────────────────────────────────────
        final isPlayerTurn =
            gameState.activeArmyId == ArmyId.army1 &&
            gameState.phase == GamePhase.playing;
        final hint = isPlayerTurn
            ? '${strings.hintSelectTerritory}\n${strings.hintAttack}'
            : strings.hintSelectTerritory;

        if (selectedId == null) {
          return _NoSelectionPanel(hint: hint);
        }

        // ── Look up the territory ────────────────────────────────────────────
        final territories = gameState.territories;
        final Territory? territory = selectedId < territories.length
            ? territories[selectedId]
            : null;

        if (territory == null) {
          return _NoSelectionPanel(hint: hint);
        }

        final canAttackFrom =
            isPlayerTurn && territory.ownerArmyId == ArmyId.army1;

        // ── Resolve owner label ───────────────────────────────────────────
        final String ownerLabel = _ownerLabel(territory.ownerArmyId, strings);

        // ── Resolve adjacent territory names ──────────────────────────────
        final adjacent = territory.adjacentIds
            .where((adjId) => adjId < territories.length)
            .map((adjId) {
              final adjTerritory = territories[adjId];
              return _AdjacentEntry(
                id: adjId,
                name:
                    '${_direction(territory.id, adjId)} '
                    '${localeService.translate(adjTerritory.name, locale)}',
                units: adjTerritory.unitCount,
                owner: adjTerritory.ownerArmyId,
                canAttack:
                    canAttackFrom && adjTerritory.ownerArmyId != ArmyId.army1,
              );
            })
            .toList();

        // ── Resolve the panel title (territory name) ──────────────────────
        final territoryName = localeService.translate(territory.name, locale);

        return _InfoCard(
          territoryName: territoryName,
          ownerLabel: strings.territoryOwnerLabel,
          ownerValue: ownerLabel,
          unitsLabel: strings.territoryUnitsLabel,
          unitCount: territory.unitCount,
          adjacentLabel: strings.territoryAdjacentLabel,
          adjacent: adjacent,
          ownerArmyId: territory.ownerArmyId,
          attackLabel: strings.btnAttack,
          onAttack: (targetId) => _attack(ref, territory.id, targetId),
          deployLabel: canAttackFrom && gameState.army1.totalUnitPool > 0
              ? strings.btnDeploy(count: '${gameState.army1.totalUnitPool}')
              : null,
          reserveText: territory.ownerArmyId == ArmyId.army1
              ? (strings.reserveLabel, '${gameState.army1.totalUnitPool}')
              : null,
          mineText: territory.hasDiamondMine
              ? (strings.diamondMineLabel, '+$kDiamondMineReward')
              : territory.hasGoldMine
              ? (strings.goldMineLabel, '+$kGoldMineReward')
              : null,
          mineIsGold: !territory.hasDiamondMine && territory.hasGoldMine,
          terrainText: (
            strings.terrainLabel,
            strings.terrainName(
              TerritoryGraph.bundled().terrainOf(territory.id).name,
            ),
          ),
          terrain: TerritoryGraph.bundled().terrainOf(territory.id),
          onDeploy: () => ref
              .read(gameProvider.notifier)
              .deployReinforcements(territory.id),
        );
      },
    );
  }

  /// Arrow pointing from tile [from] to its neighbour [to] on the grid, so
  /// neighbouring squares of the same country can be told apart.
  String _direction(int from, int to) {
    final graph = TerritoryGraph.bundled();
    final a = graph.positionOf(from);
    final b = graph.positionOf(to);
    if (graph.isSeaLink(from, to)) return '≈';
    if (b.row < a.row) return '↑';
    if (b.row > a.row) return '↓';
    if (b.col < a.col) return '←';
    return '→';
  }

  /// Declares an attack from [sourceId] into [targetId]. The notifier emits
  /// a [GameFeedback] that the game screen turns into sound + a message.
  void _attack(WidgetRef ref, int sourceId, int targetId) {
    ref.read(gameProvider.notifier).declareAttack(sourceId, targetId);
  }

  /// Converts an optional [ArmyId] to the localised owner label.
  String _ownerLabel(ArmyId? ownerArmyId, AppStrings strings) {
    if (ownerArmyId == null) return strings.territoryOwnerNeutral;
    return strings.armyName(ownerArmyId.index);
  }
}

// ─── _InfoCard ────────────────────────────────────────────────────────────────

/// The populated card shown when a territory is selected.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.territoryName,
    required this.ownerLabel,
    required this.ownerValue,
    required this.unitsLabel,
    required this.unitCount,
    required this.adjacentLabel,
    required this.adjacent,
    required this.ownerArmyId,
    required this.attackLabel,
    required this.onAttack,
    required this.deployLabel,
    required this.onDeploy,
    required this.reserveText,
    required this.mineText,
    required this.mineIsGold,
    required this.terrainText,
    required this.terrain,
  });

  final String territoryName;
  final String ownerLabel;
  final String ownerValue;
  final String unitsLabel;
  final int unitCount;
  final String adjacentLabel;
  final List<_AdjacentEntry> adjacent;
  final ArmyId? ownerArmyId;
  final String attackLabel;
  final void Function(int targetId) onAttack;

  /// Label of the deploy button, or `null` to hide it.
  final String? deployLabel;
  final VoidCallback onDeploy;

  /// (label, value) of the reserve-soldier row, or `null` to hide it.
  final (String, String)? reserveText;

  /// (label, value) of the diamond- or gold-mine row, or `null` to hide it.
  final (String, String)? mineText;

  /// Whether [mineText] describes a gold mine (else a diamond mine).
  final bool mineIsGold;

  /// (label, value) of the terrain row (forest, desert, …).
  final (String, String) terrainText;

  /// The tile's terrain (picks the row's icon).
  final Terrain terrain;

  @override
  Widget build(BuildContext context) {
    final Color headerColor = _headerColor(ownerArmyId);
    final Color onHeaderColor = ownerArmyId != null
        ? AppTheme.kTextLight
        : AppTheme.kTextDark;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  color: onHeaderColor,
                  size: 24,
                  semanticLabel: 'Territory',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    territoryName,
                    style: AppTheme.headingStyle.copyWith(
                      color: onHeaderColor,
                      fontSize: 20,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Owner row
                _InfoRow(
                  icon: Icons.flag_outlined,
                  iconColor: _ownerIconColor(ownerArmyId),
                  label: ownerLabel,
                  value: ownerValue,
                ),
                const SizedBox(height: 10),

                // Unit count row
                _InfoRow(
                  icon: Icons.people_outline,
                  iconColor: AppTheme.army1Primary,
                  label: unitsLabel,
                  value: unitCount.toString(),
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: switch (terrain) {
                    Terrain.rainforest ||
                    Terrain.woodland => Icons.forest_rounded,
                    Terrain.savanna => Icons.grass_rounded,
                    Terrain.steppe => Icons.landscape_rounded,
                    Terrain.desert => Icons.wb_sunny_rounded,
                  },
                  iconColor: switch (terrain) {
                    Terrain.rainforest => const Color(0xFF1B5E20),
                    Terrain.woodland => const Color(0xFF558B2F),
                    Terrain.savanna => const Color(0xFF9E9D24),
                    Terrain.steppe => const Color(0xFF8D6E63),
                    Terrain.desert => const Color(0xFFE65100),
                  },
                  label: terrainText.$1,
                  value: terrainText.$2,
                ),
                if (mineText != null) ...[
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: mineIsGold
                        ? Icons.paid_rounded
                        : Icons.diamond_rounded,
                    iconColor: mineIsGold ? AppTheme.kGold : AppTheme.kDiamond,
                    label: mineText!.$1,
                    value: mineText!.$2,
                  ),
                ],
                if (reserveText != null) ...[
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.groups_outlined,
                    iconColor: AppTheme.kAccentGreen,
                    label: reserveText!.$1,
                    value: reserveText!.$2,
                  ),
                ],
                if (deployLabel != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: onDeploy,
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    label: Text(
                      deployLabel!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.kAccentGreen,
                      foregroundColor: AppTheme.kTextLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // Adjacent territories row
                _AdjacentRow(
                  label: adjacentLabel,
                  entries: adjacent,
                  attackLabel: attackLabel,
                  onAttack: onAttack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _headerColor(ArmyId? owner) =>
      owner == null ? AppTheme.kNeutralLight : AppTheme.armyColor(owner);

  Color _ownerIconColor(ArmyId? owner) => owner == null
      ? const Color(0xFF757575) // neutral grey
      : AppTheme.armyColor(owner);
}

// ─── _InfoRow ─────────────────────────────────────────────────────────────────

/// A single labelled row with an icon, label text, and value text.
///
/// All text is >= 16 sp (Req 11.1) and uses high-contrast colours (Req 11.2).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon label alongside text (Req 11.3)
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
            style: AppTheme.bodyStyle.copyWith(
              fontSize: 16,
              color: AppTheme.kTextDark,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── _AdjacentRow ─────────────────────────────────────────────────────────────

/// Displays the adjacent territories label and a wrapping list of names.
class _AdjacentRow extends StatelessWidget {
  const _AdjacentRow({
    required this.label,
    required this.entries,
    required this.attackLabel,
    required this.onAttack,
  });

  final String label;
  final List<_AdjacentEntry> entries;
  final String attackLabel;
  final void Function(int targetId) onAttack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.device_hub_outlined,
              color: AppTheme.kAccentPurple,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.kTextDark,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: entries
              .map(
                (e) => e.canAttack
                    ? _AttackChip(
                        entry: e,
                        attackLabel: attackLabel,
                        onPressed: () => onAttack(e.id),
                      )
                    : Chip(
                        label: Text(
                          '${e.name} (${e.units})',
                          style: AppTheme.bodyStyle.copyWith(
                            fontSize: 16,
                            color: AppTheme.kTextDark,
                          ),
                        ),
                        backgroundColor: AppTheme.kNeutralLight,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                      ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ─── _NoSelectionPanel ────────────────────────────────────────────────────────

/// Placeholder shown when no territory has been selected yet.
class _NoSelectionPanel extends StatelessWidget {
  const _NoSelectionPanel({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            const Icon(
              Icons.touch_app_outlined,
              color: AppTheme.kAccentPurple,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hint,
                style: AppTheme.bodyStyle.copyWith(
                  fontSize: 16,
                  color: AppTheme.kTextDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _LoadingPanel ────────────────────────────────────────────────────────────

/// Minimal placeholder shown while the locale service is loading.
class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

// ─── _AdjacentEntry / _AttackChip ─────────────────────────────────────────────

/// View data for one neighbouring territory.
class _AdjacentEntry {
  const _AdjacentEntry({
    required this.id,
    required this.name,
    required this.units,
    required this.owner,
    required this.canAttack,
  });

  final int id;
  final String name;
  final int units;
  final ArmyId? owner;
  final bool canAttack;
}

/// Neighbour chip with a big "Attack" button (icon + text, Req 11.3).
class _AttackChip extends StatelessWidget {
  const _AttackChip({
    required this.entry,
    required this.attackLabel,
    required this.onPressed,
  });

  final _AdjacentEntry entry;
  final String attackLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final owner = entry.owner;
    final color = owner == null
        ? AppTheme.kTextDark
        : AppTheme.armyColor(owner);
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.gps_fixed_rounded, size: 20),
      label: Text(
        '$attackLabel: ${entry.name} (${entry.units})',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.kSurface,
        foregroundColor: color,
        side: BorderSide(color: color, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
