/// Combat service for Harita: Kendi İmparatorluğunu Kur.
///
/// Resolves attacks between neighbouring cities (with tanks and forests)
/// and bomber raids.
library;

import 'dart:math';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/economy_service.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when an attack is invalid — e.g. the cities are not neighbours,
/// the attacking army does not own the source, or the source lacks
/// soldiers to send.
class InvalidAttackException implements Exception {
  const InvalidAttackException(this.message);

  /// Human-readable description of why the attack was rejected.
  final String message;

  @override
  String toString() => 'InvalidAttackException: $message';
}

// ─── Strength helpers ────────────────────────────────────────────────────────

/// Attack strength of [army] sending all but one soldier out of [source]:
/// the soldiers plus [kTankPower] when a tank is ready to join.
int attackStrength(Army army, Territory source) =>
    max(0, source.unitCount - 1) + (army.tanksReady > 0 ? kTankPower : 0);

/// Defence strength of [target]: its soldiers, [kForestDefenseBonus] more
/// in a forest.
int defenceStrength(Territory target) => target.hasForest
    ? (target.unitCount * (1 + kForestDefenseBonus)).ceil()
    : target.unitCount;

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Resolves combat between cities.
abstract class CombatService {
  /// Sends all but one soldier from [sourceTerritoryId] into the neighbouring
  /// [targetTerritoryId]. A ready tank joins (each tank once per turn).
  ///
  /// - Into an own city: the soldiers just move.
  /// - Into any other city: the stronger side wins (see [attackStrength],
  ///   [defenceStrength]) and keeps what is left after the other side's
  ///   strength is taken off. The winner takes or keeps the city; a failed
  ///   attack also loses the tank.
  ///
  /// Throws [InvalidAttackException] when [attackingArmyId] does not own the
  /// source, the cities are not neighbours, or fewer than 2 soldiers are in
  /// the source.
  GameState resolveAttack({
    required GameState state,
    required ArmyId attackingArmyId,
    required int sourceTerritoryId,
    required int targetTerritoryId,
  });

  /// One bomber of [armyId] bombs [targetTerritoryId] (any city that is not
  /// its own), destroying [kBomberDamage] soldiers. A city left without
  /// soldiers becomes neutral.
  ///
  /// Throws [InvalidAttackException] when no bomber is ready this turn or
  /// the target is the army's own city.
  GameState bomberRaid({
    required GameState state,
    required ArmyId armyId,
    required int targetTerritoryId,
  });
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [CombatService].
class CombatServiceImpl implements CombatService {
  const CombatServiceImpl();

  @override
  GameState resolveAttack({
    required GameState state,
    required ArmyId attackingArmyId,
    required int sourceTerritoryId,
    required int targetTerritoryId,
  }) {
    final source = _find(state, sourceTerritoryId, 'source');
    final target = _find(state, targetTerritoryId, 'target');

    if (source.ownerArmyId != attackingArmyId) {
      throw InvalidAttackException(
        'Army $attackingArmyId does not own source city $sourceTerritoryId.',
      );
    }
    if (!source.adjacentIds.contains(targetTerritoryId)) {
      throw InvalidAttackException(
        'City $sourceTerritoryId is not next to city $targetTerritoryId.',
      );
    }
    if (source.unitCount < 2) {
      throw InvalidAttackException(
        'City $sourceTerritoryId has only ${source.unitCount} soldier(s).',
      );
    }

    // ── Friendly move ─────────────────────────────────────────────────────
    final moving = source.unitCount - 1;
    if (target.ownerArmyId == attackingArmyId) {
      return _replace(
        state,
        source.copyWith(unitCount: 1),
        target.copyWith(unitCount: target.unitCount + moving),
      );
    }

    // ── Battle ────────────────────────────────────────────────────────────
    final army = state.army(attackingArmyId);
    final attack = attackStrength(army, source);
    final defence = defenceStrength(target);

    if (attack > defence) {
      // Soldier for soldier: what the defence cost is lost (the tank's
      // strength counts too), the rest move in.
      final survivors = (attack - defence).clamp(1, moving).toInt();
      var next = _replace(
        state,
        source.copyWith(unitCount: 1),
        target.copyWith(unitCount: survivors, ownerArmyId: attackingArmyId),
      );
      if (army.tanksReady > 0) {
        next = next.withArmy(army.copyWith(tanksUsed: army.tanksUsed + 1));
      }
      return awardMineRewards(state, next, attackingArmyId);
    }

    // Defender holds, losing as much as the attack was worth; the attackers
    // (and their tank) are lost.
    final factor = target.hasForest ? 1 + kForestDefenseBonus : 1.0;
    final defenders = max(0, ((defence - attack) / factor).ceil());
    var next = _replace(
      state,
      source.copyWith(unitCount: 1),
      target.copyWith(
        unitCount: defenders,
        ownerArmyId: defenders > 0 ? target.ownerArmyId : null,
      ),
    );
    if (army.tanksReady > 0) {
      next = next.withArmy(army.copyWith(tanks: army.tanks - 1));
    }
    return next;
  }

  @override
  GameState bomberRaid({
    required GameState state,
    required ArmyId armyId,
    required int targetTerritoryId,
  }) {
    final army = state.army(armyId);
    if (army.bombersReady <= 0) {
      throw const InvalidAttackException('No bomber is ready this turn.');
    }
    final target = _find(state, targetTerritoryId, 'target');
    if (target.ownerArmyId == armyId) {
      throw const InvalidAttackException('Bombers do not bomb own cities.');
    }
    final left = max(0, target.unitCount - kBomberDamage);
    final territories = [
      for (final t in state.territories)
        if (t.id == target.id)
          t.copyWith(
            unitCount: left,
            ownerArmyId: left > 0 ? t.ownerArmyId : null,
          )
        else
          t,
    ];
    return state
        .withArmy(army.copyWith(bombersFlown: army.bombersFlown + 1))
        .copyWith(territories: territories);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  GameState _replace(GameState state, Territory source, Territory target) {
    final updated = [
      for (final t in state.territories)
        if (t.id == source.id) source else if (t.id == target.id) target else t,
    ];
    return state.copyWith(territories: updated);
  }

  Territory _find(GameState state, int id, String role) {
    if (id >= 0 &&
        id < state.territories.length &&
        state.territories[id].id == id) {
      return state.territories[id];
    }
    for (final t in state.territories) {
      if (t.id == id) return t;
    }
    throw InvalidAttackException('No $role city with id $id.');
  }
}
