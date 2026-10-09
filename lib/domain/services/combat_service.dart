/// Combat service for Harita: Kendi İmparatorluğunu Kur.
///
/// Resolves attacks between territories according to the combat resolution
/// rules defined in the design document.
library;

import 'dart:math';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/economy_service.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when an attack is invalid — e.g. territories are not adjacent,
/// the attacking army does not own the source, or the source lacks
/// enough units to mount an attack.
class InvalidAttackException implements Exception {
  const InvalidAttackException(this.message);

  /// Human-readable description of why the attack was rejected.
  final String message;

  @override
  String toString() => 'InvalidAttackException: $message';
}

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Resolves combat between two territories.
abstract class CombatService {
  /// Resolves an attack from [attackingArmyId] launching out of
  /// [sourceTerritoryId] against [targetTerritoryId].
  ///
  /// Returns an updated [GameState] with all unit changes and any ownership
  /// transfer applied atomically.
  ///
  /// Throws [InvalidAttackException] when:
  /// - [attackingArmyId] does not own the source territory.
  /// - Source and target territories are not adjacent.
  /// - The source territory has fewer than 2 units (must keep 1 behind).
  GameState resolveAttack({
    required GameState state,
    required ArmyId attackingArmyId,
    required int sourceTerritoryId,
    required int targetTerritoryId,
  });
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [CombatService].
///
/// Adjacency is verified from the live [GameState.territories] adjacency lists
/// (not from the static [TerritoryGraph] template) so that hot-patch scenarios
/// during tests are straightforward.
class CombatServiceImpl implements CombatService {
  const CombatServiceImpl();

  @override
  GameState resolveAttack({
    required GameState state,
    required ArmyId attackingArmyId,
    required int sourceTerritoryId,
    required int targetTerritoryId,
  }) {
    // ── Look up live territories ──────────────────────────────────────────
    final source = _findTerritory(state, sourceTerritoryId, 'source');
    final target = _findTerritory(state, targetTerritoryId, 'target');

    // ── Validation ────────────────────────────────────────────────────────

    // 1. Attacking army must own the source territory.
    if (source.ownerArmyId != attackingArmyId) {
      throw InvalidAttackException(
        'Army $attackingArmyId does not own source territory '
        '$sourceTerritoryId (owner: ${source.ownerArmyId}).',
      );
    }

    // 2. Source and target must be adjacent.
    if (!source.adjacentIds.contains(targetTerritoryId)) {
      throw InvalidAttackException(
        'Territory $sourceTerritoryId is not adjacent to territory '
        '$targetTerritoryId.',
      );
    }

    // 3. Source must have at least 2 units (1 to attack, 1 to hold source).
    if (source.unitCount < 2) {
      throw InvalidAttackException(
        'Territory $sourceTerritoryId has only ${source.unitCount} unit(s); '
        'at least 2 are required to mount an attack.',
      );
    }

    // ── Friendly move ─────────────────────────────────────────────────────
    // Targeting a territory the attacker already owns moves units instead of
    // fighting: all but 1 unit move, limited by the target's base capacity
    // (Requirement 5.4). Units that do not fit stay at the source.
    if (target.ownerArmyId == attackingArmyId) {
      final movable = source.unitCount - 1;
      final room = target.baseCapacity == null
          ? movable
          : max(0, target.baseCapacity! - target.unitCount);
      final moved = min(movable, room);
      if (moved <= 0) {
        throw InvalidAttackException(
          'Territory $targetTerritoryId is full (capacity '
          '${target.baseCapacity}).',
        );
      }
      return _replace(
        state,
        source.copyWith(unitCount: source.unitCount - moved),
        target.copyWith(unitCount: target.unitCount + moved),
      );
    }

    // ── Combat resolution ─────────────────────────────────────────────────

    // All units except 1 are committed to the attack.
    final attackingUnits = source.unitCount - 1;
    final defendingUnits = target.unitCount;

    Territory updatedSource;
    Territory updatedTarget;

    if (attackingUnits > defendingUnits) {
      // ── Attacker wins ──────────────────────────────────────────────────
      // Attacker loses ceil(defendingUnits × kAttackerWinLossFraction).
      final attackerLosses = (defendingUnits * kAttackerWinLossFraction).ceil();
      final survivingAttackers = attackingUnits - attackerLosses;

      // Determine new unit count for target, capped by base capacity.
      final rawTargetUnits = survivingAttackers;
      final cappedTargetUnits = _applyCapacity(target, rawTargetUnits);

      // Source keeps the 1 unit held back plus any survivors that did not
      // fit into the target's capacity.
      updatedSource = source.copyWith(
        unitCount: 1 + (rawTargetUnits - cappedTargetUnits),
      );

      // Transfer ownership: target now belongs to the attacker.
      // If surviving attackers are somehow 0 (e.g. heavy losses), the
      // territory still transfers but immediately becomes neutral per
      // Property 7 (zero-units rule handled below).
      final newOwner = cappedTargetUnits > 0 ? attackingArmyId : null;

      updatedTarget = target.copyWith(
        unitCount: cappedTargetUnits,
        ownerArmyId: newOwner,
      );
    } else {
      // ── Defender holds ────────────────────────────────────────────────
      // Defender loses ceil(attackingUnits × kDefenderHoldLossFraction).
      final defenderLosses = (attackingUnits * kDefenderHoldLossFraction)
          .ceil();
      final survivingDefenders = defendingUnits - defenderLosses;

      // Attacker loses all attacking units; source keeps the 1 held back.
      updatedSource = source.copyWith(unitCount: 1);

      // A city that holds always keeps at least one soldier and its owner:
      // there is no empty land ("boş toprak alamasın").
      updatedTarget = target.copyWith(unitCount: max(1, survivingDefenders));
    }

    // Conquering a diamond or gold mine pays out.
    return awardMineRewards(
      state,
      _replace(state, updatedSource, updatedTarget),
      attackingArmyId,
    );
  }

  GameState _replace(GameState state, Territory source, Territory target) {
    final updatedTerritories = [
      for (final t in state.territories)
        if (t.id == source.id) source else if (t.id == target.id) target else t,
    ];
    return state.copyWith(territories: updatedTerritories);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Finds a territory by [id] in the live [state]; throws
  /// [InvalidAttackException] if no territory with that id exists.
  Territory _findTerritory(GameState state, int id, String role) {
    for (final t in state.territories) {
      if (t.id == id) return t;
    }
    throw InvalidAttackException('No $role territory found with id $id.');
  }

  /// Caps [units] at the territory's [baseCapacity] if one is set.
  /// For [TerritoryType.normal] territories (no capacity), returns [units]
  /// unchanged.
  int _applyCapacity(Territory territory, int units) {
    if (territory.baseCapacity == null) return units;
    return min(units, territory.baseCapacity!);
  }
}
