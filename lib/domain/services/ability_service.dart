/// Ability service for Harita: Kendi İmparatorluğunu Kur.
///
/// Handles special ability unlocking, activation, and cooldown management.
library;

import 'dart:math' show max;

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/economy_service.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when an army attempts to activate an ability that has not been
/// unlocked yet (turn threshold not reached).
class LockedAbilityException implements Exception {
  const LockedAbilityException({required this.ability, this.unlockTurn});

  /// The ability that failed to activate.
  final AbilityType ability;

  /// The turn at which the ability becomes available, if turn-gated.
  /// `null` when unknown.
  final int? unlockTurn;

  @override
  String toString() {
    if (unlockTurn != null) {
      return 'LockedAbilityException: $ability is not yet unlocked '
          '(unlocks at turn $unlockTurn).';
    }
    return 'LockedAbilityException: $ability is not yet unlocked.';
  }
}

/// Thrown when an army attempts to activate an ability that is currently on
/// cooldown.
class CooldownActiveException implements Exception {
  const CooldownActiveException({
    required this.ability,
    required this.turnsRemaining,
  });

  /// The ability that is on cooldown.
  final AbilityType ability;

  /// How many turns remain before the ability is usable again.
  final int turnsRemaining;

  @override
  String toString() =>
      'CooldownActiveException: $ability is on cooldown for '
      '$turnsRemaining more turn(s).';
}

/// Thrown when the Soldier Spell is aimed at a territory not owned by the
/// activating army.
class InvalidTargetException implements Exception {
  const InvalidTargetException({
    required this.targetTerritoryId,
    required this.reason,
  });

  /// The territory id that was rejected.
  final int targetTerritoryId;

  /// Human-readable explanation of why the target is invalid.
  final String reason;

  @override
  String toString() =>
      'InvalidTargetException: territory $targetTerritoryId is invalid — '
      '$reason';
}

// ─── Ability constants ───────────────────────────────────────────────────────

/// Cooldown applied to abilities after use: once per turn.
const int kAbilityPerTurnCooldown = 1;

/// Shop pack item id that grants an extra use of each ability.
const Map<AbilityType, String> kAbilityPackItemIds = {
  AbilityType.fireBomb: 'fire_bomb_pack',
  AbilityType.bombardment: 'bombardment_pack',
  AbilityType.soldierSpell: 'soldier_spell_pack',
  AbilityType.megaBomba: 'mega_bomba_pack',
};

// ─── Unlock schedule ─────────────────────────────────────────────────────────

/// Maps each ability to the turn at which it becomes available.
const Map<AbilityType, int> kAbilityUnlockTurns = {
  AbilityType.fireBomb: 0,
  AbilityType.bombardment: kTurnUnlockBombardment, // 10
  AbilityType.soldierSpell: kTurnUnlockSoldierSpell, // 12
  AbilityType.megaBomba: kTurnUnlockMegaBomba, // 45
};

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Manages the lifecycle of the special abilities.
abstract class AbilityService {
  /// Returns the list of abilities whose turn threshold is met by
  /// [currentTurn].
  List<AbilityType> getAbilitiesToUnlock(int currentTurn);

  /// Returns a new [Army] with all applicable turn-based abilities unlocked
  /// for [turnNumber].
  ///
  /// Abilities already unlocked are left unchanged.
  Army applyTurnUnlocks(Army army, int turnNumber);

  /// Validates and applies [ability] for [armyId] targeting
  /// [targetTerritoryId].
  ///
  /// Validation order:
  /// 1. Ability must be unlocked — throws [LockedAbilityException] otherwise.
  /// 2. Ability must not be on cooldown — throws [CooldownActiveException].
  /// 3. Soldier Spell target must be owned by [armyId]; offensive abilities
  ///    must target a tile not owned by [armyId] that borders its land —
  ///    throws [InvalidTargetException].
  ///
  /// Offensive abilities capture tiles ("minik kare"): Fire Bomb 2,
  /// Bombardment 8, Mega Bomba 25 (see [captureArea]); captured diamond
  /// mines pay [kDiamondMineReward]. Soldier Spell adds [kSoldierSpellUnits]
  /// units to a friendly tile.
  ///
  /// Returns a new [GameState] with the ability effect applied; the original
  /// [state] is never mutated.
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  });

  /// Returns a new [Army] with all cooldowns decremented by 1 (clamped to 0).
  ///
  /// The original [army] is never mutated.
  Army tickCooldowns(Army army);
}

// ─── Concrete implementation ─────────────────────────────────────────────────

/// Default implementation of [AbilityService].
///
/// All methods are pure functions that return new model copies without
/// mutating their inputs.
class AbilityServiceImpl implements AbilityService {
  const AbilityServiceImpl();

  // ─── getAbilitiesToUnlock ────────────────────────────────────────────────

  @override
  List<AbilityType> getAbilitiesToUnlock(int currentTurn) {
    return kAbilityUnlockTurns.entries
        .where((entry) => currentTurn >= entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  // ─── applyTurnUnlocks ────────────────────────────────────────────────────

  @override
  Army applyTurnUnlocks(Army army, int turnNumber) {
    final abilitiesToUnlock = getAbilitiesToUnlock(turnNumber);

    // Build an updated abilities map, unlocking only those that qualify.
    final updatedAbilities = Map<AbilityType, AbilityState>.from(
      army.abilities,
    );

    for (final abilityType in abilitiesToUnlock) {
      final current = updatedAbilities[abilityType];
      if (current != null && !current.isUnlocked) {
        updatedAbilities[abilityType] = current.copyWith(isUnlocked: true);
      }
    }

    return army.copyWith(abilities: updatedAbilities);
  }

  // ─── activateAbility ─────────────────────────────────────────────────────

  @override
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  }) {
    final army = state.army(armyId);
    final abilityState = army.abilities[ability];

    // ── 1. Must be unlocked ──────────────────────────────────────────────
    if (abilityState == null || !abilityState.isUnlocked) {
      throw LockedAbilityException(
        ability: ability,
        unlockTurn: kAbilityUnlockTurns[ability],
      );
    }

    // A purchased shop pack for this ability (if any) lets the army use it
    // once more even while it is on cooldown. The pack is consumed then.
    final packIndex = _packIndex(army, ability);
    var consumePack = false;

    // ── 2. Must not be on cooldown ───────────────────────────────────────
    if (abilityState.isOnCooldown) {
      if (packIndex < 0) {
        throw CooldownActiveException(
          ability: ability,
          turnsRemaining: abilityState.cooldownTurnsRemaining!,
        );
      }
      consumePack = true;
    }

    // ── 3. Target validation ─────────────────────────────────────────────
    final target = state.territories.cast<Territory?>().firstWhere(
      (t) => t!.id == targetTerritoryId,
      orElse: () => null,
    );
    if (target == null) {
      throw InvalidTargetException(
        targetTerritoryId: targetTerritoryId,
        reason: 'No such territory.',
      );
    }
    if (ability == AbilityType.soldierSpell) {
      if (target.ownerArmyId != armyId) {
        throw InvalidTargetException(
          targetTerritoryId: targetTerritoryId,
          reason:
              'Soldier Spell can only target territories owned by the '
              'activating army (army $armyId).',
        );
      }
    } else if (target.ownerArmyId == armyId) {
      // Offensive abilities may not hit the activating army's own land.
      throw InvalidTargetException(
        targetTerritoryId: targetTerritoryId,
        reason: 'Offensive abilities cannot target your own territory.',
      );
    } else if (!_bordersArmy(state.territories, target, armyId)) {
      // Captured tiles must connect to the army's land (front line only).
      throw InvalidTargetException(
        targetTerritoryId: targetTerritoryId,
        reason: 'Target must border your own territory.',
      );
    }

    // ── Apply ability effect ─────────────────────────────────────────────
    final updatedTerritories = ability == AbilityType.soldierSpell
        ? _applySoldierSpell(state.territories, targetTerritoryId)
        : captureTiles(
            state.territories,
            armyId,
            targetTerritoryId,
            kAbilityCaptureTiles[ability]!,
          );

    // ── Update army ability state (cooldown) ─────────────────────────────
    var updatedArmy = _applyPostActivationState(army, ability, abilityState);
    if (consumePack) {
      final inventory = [...updatedArmy.inventory]..removeAt(packIndex);
      updatedArmy = updatedArmy.copyWith(inventory: inventory);
    }

    final next = state
        .withArmy(updatedArmy)
        .copyWith(territories: updatedTerritories);
    return awardDiamondMines(state, next, armyId);
  }

  // ─── tickCooldowns ───────────────────────────────────────────────────────

  @override
  Army tickCooldowns(Army army) {
    final updatedAbilities = Map<AbilityType, AbilityState>.from(
      army.abilities,
    );

    updatedAbilities.forEach((type, abilityState) {
      if (abilityState.cooldownTurnsRemaining != null) {
        // Decrement by 1, floor at 0.
        updatedAbilities[type] = abilityState.copyWith(
          cooldownTurnsRemaining: max(
            0,
            abilityState.cooldownTurnsRemaining! - 1,
          ),
        );
      }
    });

    return army.copyWith(abilities: updatedAbilities);
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Finds a territory in [territories] by [id].
  ///
  /// Throws [StateError] if no territory with [id] exists (should not happen
  /// in a well-formed game state).
  int _packIndex(Army army, AbilityType ability) {
    final packId = kAbilityPackItemIds[ability];
    return army.inventory.indexWhere((item) => item.id == packId);
  }

  /// Adds [kSoldierSpellUnits] to the friendly tile [targetTerritoryId],
  /// respecting base capacity (Requirement 5.4).
  List<Territory> _applySoldierSpell(
    List<Territory> territories,
    int targetTerritoryId,
  ) {
    return [
      for (final t in territories)
        if (t.id != targetTerritoryId)
          t
        else
          t.copyWith(
            unitCount:
                t.baseCapacity != null &&
                    t.unitCount + kSoldierSpellUnits > t.baseCapacity!
                ? max(t.baseCapacity!, t.unitCount)
                : t.unitCount + kSoldierSpellUnits,
          ),
    ];
  }

  bool _bordersArmy(List<Territory> territories, Territory t, ArmyId armyId) =>
      t.adjacentIds.any((id) => _byId(territories, id)?.ownerArmyId == armyId);

  /// Returns a new [Army] copy with [ability] put on its once-per-turn
  /// cooldown, which is cleared when this army's turn ends (see
  /// [tickCooldowns]).
  Army _applyPostActivationState(
    Army army,
    AbilityType ability,
    AbilityState abilityState,
  ) {
    final updatedAbilities = Map<AbilityType, AbilityState>.from(
      army.abilities,
    );
    updatedAbilities[ability] = abilityState.copyWith(
      cooldownTurnsRemaining: kAbilityPerTurnCooldown,
    );
    return army.copyWith(abilities: updatedAbilities);
  }
}

// ─── Tile capture ("minik kare") ─────────────────────────────────────────────

/// How many tiles each offensive ability captures.
const Map<AbilityType, int> kAbilityCaptureTiles = {
  AbilityType.fireBomb: kFireBombTiles, // 2
  AbilityType.bombardment: kBombardmentTiles, // 8
  AbilityType.megaBomba: kMegaBombaTiles, // 25
};

/// Returns the ids of the (up to) [count] tiles an ability aimed at
/// [targetId] captures for [armyId]: the target itself, then the nearest
/// tiles not owned by [armyId] (breadth-first through such tiles).
List<int> captureArea(
  List<Territory> territories,
  ArmyId armyId,
  int targetId,
  int count,
) {
  final target = _byId(territories, targetId);
  if (target == null || target.ownerArmyId == armyId || count <= 0) {
    return const [];
  }
  final result = <int>[targetId];
  final seen = {targetId};
  var frontier = [targetId];
  while (result.length < count && frontier.isNotEmpty) {
    final next = <int>[];
    for (final id in frontier) {
      for (final adj in _byId(territories, id)!.adjacentIds) {
        if (!seen.add(adj)) continue;
        final t = _byId(territories, adj);
        if (t == null || t.ownerArmyId == armyId) continue;
        next.add(adj);
      }
    }
    // Prefer enemy tiles (more units first) over empty neutral land.
    next.sort((a, b) {
      final ta = _byId(territories, a)!;
      final tb = _byId(territories, b)!;
      final ea = ta.ownerArmyId == null ? 0 : 1;
      final eb = tb.ownerArmyId == null ? 0 : 1;
      if (ea != eb) return eb - ea;
      if (ta.unitCount != tb.unitCount) return tb.unitCount - ta.unitCount;
      return a - b;
    });
    for (final id in next) {
      if (result.length >= count) break;
      result.add(id);
    }
    frontier = next;
  }
  return result;
}

/// Returns [territories] with the [captureArea] tiles taken over by
/// [armyId]; each captured tile keeps [kCapturedTileUnits] unit(s) and any
/// units previously stationed there are destroyed.
List<Territory> captureTiles(
  List<Territory> territories,
  ArmyId armyId,
  int targetId,
  int count,
) {
  final area = captureArea(territories, armyId, targetId, count).toSet();
  return [
    for (final t in territories)
      if (area.contains(t.id))
        t.copyWith(ownerArmyId: armyId, unitCount: kCapturedTileUnits)
      else
        t,
  ];
}

Territory? _byId(List<Territory> territories, int id) {
  if (id >= 0 && id < territories.length && territories[id].id == id) {
    return territories[id];
  }
  for (final t in territories) {
    if (t.id == id) return t;
  }
  return null;
}
