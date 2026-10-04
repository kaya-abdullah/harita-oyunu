/// Unit tests for AbilityServiceImpl.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

/// Builds a minimal [Territory] for testing.
Territory makeTerritory({
  int id = 0,
  int unitCount = 10,
  ArmyId? ownerArmyId,
  TerritoryType type = TerritoryType.normal,
  List<int> adjacentIds = const [],
}) {
  return Territory(
    id: id,
    name: 'territory_$id',
    type: type,
    adjacentIds: adjacentIds,
    unitCount: unitCount,
    ownerArmyId: ownerArmyId,
  );
}

/// Builds a default [AbilityState] for the given [type].
///
/// Turn-based abilities default to unlocked; Direct Laser starts locked with
/// charge 0 / maxCharge 3.
AbilityState makeAbilityState(
  AbilityType type, {
  bool isUnlocked = true,
  int? cooldownTurnsRemaining,
  int? chargeLevel,
  int? maxCharge,
}) {
  if (type == AbilityType.directLaser) {
    return AbilityState(
      type: type,
      isUnlocked: isUnlocked,
      cooldownTurnsRemaining: cooldownTurnsRemaining ?? 0,
      chargeLevel: chargeLevel ?? 0,
      maxCharge: maxCharge ?? 3,
    );
  }
  return AbilityState(
    type: type,
    isUnlocked: isUnlocked,
    cooldownTurnsRemaining: cooldownTurnsRemaining,
    chargeLevel: chargeLevel,
    maxCharge: maxCharge,
  );
}

/// Returns a fully-populated [Army] with all abilities in a sensible default
/// state.
Army makeArmy({
  ArmyId id = ArmyId.army1,
  Map<AbilityType, AbilityState>? abilities,
}) {
  final defaultAbilities = <AbilityType, AbilityState>{
    AbilityType.fireBomb: makeAbilityState(AbilityType.fireBomb),
    AbilityType.bombardment: makeAbilityState(AbilityType.bombardment),
    AbilityType.soldierSpell: makeAbilityState(AbilityType.soldierSpell),
    AbilityType.megaBomba: makeAbilityState(AbilityType.megaBomba),
    AbilityType.directLaser: makeAbilityState(
      AbilityType.directLaser,
      chargeLevel: 3, // fully charged so tests can activate it by default
    ),
  };
  return Army(
    id: id,
    kind: ArmyKind.human,
    elmaBalance: 100,
    totalUnitPool: 20,
    abilities: Map.unmodifiable(abilities ?? defaultAbilities),
    inventory: const [],
  );
}

/// Builds a straight line of tiles 0 … n-1 (each adjacent to its
/// neighbours) owned as given by [owners]; units default to 4 per tile.
GameState makeLine(List<ArmyId?> owners, {List<int>? units}) {
  final n = owners.length;
  return GameState(
    territories: [
      for (var i = 0; i < n; i++)
        makeTerritory(
          id: i,
          unitCount: units?[i] ?? 4,
          ownerArmyId: owners[i],
          adjacentIds: [if (i > 0) i - 1, if (i < n - 1) i + 1],
        ),
    ],
    army1: makeArmy(id: ArmyId.army1),
    army2: makeArmy(id: ArmyId.army2),
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

/// Builds a two-territory [GameState] for activation tests.
GameState makeState({
  Territory? territory0,
  Territory? territory1,
  Army? army1,
  Army? army2,
  int currentTurn = 1,
}) {
  final t0 =
      territory0 ??
      makeTerritory(id: 0, unitCount: 20, ownerArmyId: ArmyId.army1);
  final t1 =
      territory1 ??
      makeTerritory(id: 1, unitCount: 10, ownerArmyId: ArmyId.army2);

  // The two tiles always border each other.
  return GameState(
    territories: [
      t0.copyWith(adjacentIds: const [1]),
      t1.copyWith(adjacentIds: const [0]),
    ],
    army1: army1 ?? makeArmy(id: ArmyId.army1),
    army2: army2 ?? makeArmy(id: ArmyId.army2),
    currentTurn: currentTurn,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

// ─── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AbilityServiceImpl service;

  setUp(() {
    service = const AbilityServiceImpl();
  });

  // ── getAbilitiesToUnlock ───────────────────────────────────────────────────

  group('getAbilitiesToUnlock', () {
    test('turn 0 unlocks only fireBomb', () {
      final result = service.getAbilitiesToUnlock(0);
      expect(result, contains(AbilityType.fireBomb));
      expect(result, isNot(contains(AbilityType.bombardment)));
      expect(result, isNot(contains(AbilityType.soldierSpell)));
      expect(result, isNot(contains(AbilityType.megaBomba)));
      expect(result, isNot(contains(AbilityType.directLaser)));
    });

    test('turn 10 unlocks fireBomb + bombardment', () {
      final result = service.getAbilitiesToUnlock(10);
      expect(
        result,
        containsAll([AbilityType.fireBomb, AbilityType.bombardment]),
      );
      expect(result, isNot(contains(AbilityType.soldierSpell)));
    });

    test('turn 12 unlocks fireBomb + bombardment + soldierSpell', () {
      final result = service.getAbilitiesToUnlock(12);
      expect(
        result,
        containsAll([
          AbilityType.fireBomb,
          AbilityType.bombardment,
          AbilityType.soldierSpell,
        ]),
      );
      expect(result, isNot(contains(AbilityType.megaBomba)));
    });

    test('turn 45 unlocks all four turn-based abilities', () {
      final result = service.getAbilitiesToUnlock(45);
      expect(
        result,
        containsAll([
          AbilityType.fireBomb,
          AbilityType.bombardment,
          AbilityType.soldierSpell,
          AbilityType.megaBomba,
        ]),
      );
      // directLaser is charge-based — never returned here.
      expect(result, isNot(contains(AbilityType.directLaser)));
    });

    test('turn 9 does not unlock bombardment', () {
      expect(
        service.getAbilitiesToUnlock(9),
        isNot(contains(AbilityType.bombardment)),
      );
    });

    test('turn 44 does not unlock megaBomba', () {
      expect(
        service.getAbilitiesToUnlock(44),
        isNot(contains(AbilityType.megaBomba)),
      );
    });
  });

  // ── applyTurnUnlocks ──────────────────────────────────────────────────────

  group('applyTurnUnlocks', () {
    test('marks locked fireBomb as unlocked at turn 0', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            isUnlocked: false,
          ),
        },
      );
      final result = service.applyTurnUnlocks(army, 0);
      expect(result.abilities[AbilityType.fireBomb]!.isUnlocked, isTrue);
    });

    test('does not downgrade an already-unlocked ability', () {
      final army = makeArmy();
      final result = service.applyTurnUnlocks(army, 10);
      // fireBomb was already unlocked; should remain so.
      expect(result.abilities[AbilityType.fireBomb]!.isUnlocked, isTrue);
    });

    test('bombardment is unlocked at turn 10', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(AbilityType.fireBomb),
          AbilityType.bombardment: makeAbilityState(
            AbilityType.bombardment,
            isUnlocked: false,
          ),
        },
      );
      final result = service.applyTurnUnlocks(army, kTurnUnlockBombardment);
      expect(result.abilities[AbilityType.bombardment]!.isUnlocked, isTrue);
    });

    test('bombardment is NOT unlocked at turn 9', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(AbilityType.fireBomb),
          AbilityType.bombardment: makeAbilityState(
            AbilityType.bombardment,
            isUnlocked: false,
          ),
        },
      );
      final result = service.applyTurnUnlocks(army, kTurnUnlockBombardment - 1);
      expect(result.abilities[AbilityType.bombardment]!.isUnlocked, isFalse);
    });

    test('returns a new immutable Army instance (no mutation)', () {
      final army = makeArmy();
      final result = service.applyTurnUnlocks(army, 50);
      expect(identical(army, result), isFalse);
    });
  });

  // ── activateAbility — validation ──────────────────────────────────────────

  group('activateAbility — validation', () {
    test('throws LockedAbilityException when ability is not unlocked', () {
      final lockedArmy = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            isUnlocked: false,
          ),
        },
      );
      final state = makeState(army1: lockedArmy);

      expect(
        () => service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 1,
        ),
        throwsA(isA<LockedAbilityException>()),
      );
    });

    test('throws CooldownActiveException when cooldown > 0', () {
      final armyOnCooldown = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            cooldownTurnsRemaining: 2,
          ),
        },
      );
      final state = makeState(army1: armyOnCooldown);

      expect(
        () => service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 1,
        ),
        throwsA(isA<CooldownActiveException>()),
      );
    });

    test(
      'throws InsufficientChargeException when Direct Laser not fully charged',
      () {
        final underchargedArmy = makeArmy(
          abilities: {
            AbilityType.directLaser: makeAbilityState(
              AbilityType.directLaser,
              chargeLevel: 1,
              maxCharge: 3,
            ),
          },
        );
        final state = makeState(army1: underchargedArmy);

        expect(
          () => service.activateAbility(
            state: state,
            armyId: ArmyId.army1,
            ability: AbilityType.directLaser,
            targetTerritoryId: 1,
          ),
          throwsA(isA<InsufficientChargeException>()),
        );
      },
    );

    test('throws InvalidTargetException for unknown territory id', () {
      final state = makeState();
      expect(
        () => service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 999,
        ),
        throwsA(isA<InvalidTargetException>()),
      );
    });

    test('game state is unchanged when LockedAbilityException is thrown', () {
      final lockedArmy = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            isUnlocked: false,
          ),
        },
      );
      final state = makeState(army1: lockedArmy);

      try {
        service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 1,
        );
      } on LockedAbilityException {
        // Expected — verify state is untouched.
      }

      // Original state must be unchanged.
      expect(state.territories[1].unitCount, 10);
      expect(state.army1.abilities[AbilityType.fireBomb]!.isUnlocked, isFalse);
    });
  });

  // ── activateAbility — tile capture ("minik kare") ───────────────────────

  group('activateAbility — tile capture', () {
    const a1 = ArmyId.army1;
    const a2 = ArmyId.army2;

    test('fireBomb captures exactly 1 tile', () {
      final state = makeLine([a1, a2, a2, a2, a2]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.fireBomb,
        targetTerritoryId: 1,
      );
      expect(r.territories[1].ownerArmyId, a1);
      expect(r.territories[1].unitCount, kCapturedTileUnits);
      expect(r.territories[2].ownerArmyId, a2);
      expect(r.territories[2].unitCount, 4);
    });

    test('bombardment captures exactly 3 tiles', () {
      final state = makeLine([a1, a2, a2, a2, a2, a2]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.bombardment,
        targetTerritoryId: 1,
      );
      final owners = r.territories.map((t) => t.ownerArmyId).toList();
      expect(owners, [a1, a1, a1, a1, a2, a2]);
    });

    test('directLaser (instant 🔫 card) captures exactly 5 tiles', () {
      final state = makeLine([a1, null, a2, null, a2, a2, a2]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.directLaser,
        targetTerritoryId: 1,
      );
      final captured = r.territories.where((t) => t.ownerArmyId == a1).length;
      expect(captured, 1 + 5);
      expect(r.territories[6].ownerArmyId, a2);
    });

    test('megaBomba captures 9 tiles', () {
      final state = makeLine([a1, ...List.filled(12, a2)]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.megaBomba,
        targetTerritoryId: 1,
      );
      expect(r.territories.where((t) => t.ownerArmyId == a1).length, 1 + 9);
    });

    test('captured tiles lose their units and keep the captured unit', () {
      final state = makeLine([a1, a2, a2], units: [4, 30, 7]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.bombardment,
        targetTerritoryId: 1,
      );
      expect(r.territories[1].unitCount, kCapturedTileUnits);
      expect(r.territories[2].unitCount, kCapturedTileUnits);
    });

    test('captures fewer tiles when the area runs out (never own land)', () {
      // Only 2 foreign tiles exist; own tile 3 behind them is untouched.
      final state = makeLine([a1, a2, null, a1], units: [4, 4, 0, 9]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.directLaser,
        targetTerritoryId: 1,
      );
      expect(r.territories.every((t) => t.ownerArmyId == a1), isTrue);
      expect(r.territories[3].unitCount, 9);
    });

    test('target must border the army (no capture deep in enemy land)', () {
      final state = makeLine([a1, a2, a2, a2]);
      expect(
        () => service.activateAbility(
          state: state,
          armyId: a1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 3,
        ),
        throwsA(isA<InvalidTargetException>()),
      );
    });

    test('offensive abilities cannot target own tiles', () {
      final state = makeLine([a1, a1, a2]);
      expect(
        () => service.activateAbility(
          state: state,
          armyId: a1,
          ability: AbilityType.fireBomb,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidTargetException>()),
      );
    });

    test('capturing the area can be neutral land too', () {
      final state = makeLine([a1, null, null], units: [4, 0, 0]);
      final r = service.activateAbility(
        state: state,
        armyId: a1,
        ability: AbilityType.fireBomb,
        targetTerritoryId: 1,
      );
      expect(r.territories[1].ownerArmyId, a1);
      expect(r.territories[2].ownerArmyId, isNull);
    });

    test('kAbilityCaptureTiles matches the requested sizes', () {
      expect(kAbilityCaptureTiles[AbilityType.fireBomb], 1);
      expect(kAbilityCaptureTiles[AbilityType.bombardment], 3);
      expect(kAbilityCaptureTiles[AbilityType.directLaser], 5);
      expect(kAbilityCaptureTiles[AbilityType.megaBomba], 9);
      expect(kAbilityCaptureTiles.containsKey(AbilityType.soldierSpell), false);
    });
  });

  // ── activateAbility — soldierSpell ────────────────────────────────────────

  group('activateAbility — soldierSpell', () {
    test('adds 15 units to a friendly territory', () {
      final state = makeState(
        territory0: makeTerritory(
          id: 0,
          unitCount: 20,
          ownerArmyId: ArmyId.army1,
        ),
      );
      final result = service.activateAbility(
        state: state,
        armyId: ArmyId.army1,
        ability: AbilityType.soldierSpell,
        targetTerritoryId: 0,
      );
      expect(result.territories[0].unitCount, 35); // 20 + 15
    });

    test('throws InvalidTargetException when targeting an enemy territory', () {
      final state = makeState(
        territory1: makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
        ),
      );
      expect(
        () => service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.soldierSpell,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidTargetException>()),
      );
    });

    test(
      'throws InvalidTargetException when targeting a neutral territory',
      () {
        final state = makeState(
          territory1: makeTerritory(id: 1, unitCount: 5, ownerArmyId: null),
        );
        expect(
          () => service.activateAbility(
            state: state,
            armyId: ArmyId.army1,
            ability: AbilityType.soldierSpell,
            targetTerritoryId: 1,
          ),
          throwsA(isA<InvalidTargetException>()),
        );
      },
    );
  });

  // ── activateAbility — directLaser ─────────────────────────────────────────

  group('activateAbility — directLaser', () {
    test('sets cooldown to 3 turns after activation', () {
      final state = makeState();
      final result = service.activateAbility(
        state: state,
        armyId: ArmyId.army1,
        ability: AbilityType.directLaser,
        targetTerritoryId: 1,
      );
      expect(
        result.army1.abilities[AbilityType.directLaser]!.cooldownTurnsRemaining,
        kDirectLaserCooldown,
      );
    });

    test('resets charge to 0 after activation', () {
      final state = makeState();
      final result = service.activateAbility(
        state: state,
        armyId: ArmyId.army1,
        ability: AbilityType.directLaser,
        targetTerritoryId: 1,
      );
      expect(result.army1.abilities[AbilityType.directLaser]!.chargeLevel, 0);
    });

    test('activates when chargeLevel == maxCharge (exactly full)', () {
      final fullyCharged = makeArmy(
        abilities: {
          AbilityType.directLaser: makeAbilityState(
            AbilityType.directLaser,
            chargeLevel: 3,
            maxCharge: 3,
            cooldownTurnsRemaining: 0,
          ),
        },
      );
      final state = makeState(army1: fullyCharged);

      expect(
        () => service.activateAbility(
          state: state,
          armyId: ArmyId.army1,
          ability: AbilityType.directLaser,
          targetTerritoryId: 1,
        ),
        returnsNormally,
      );
    });
  });

  // ── activateAbility — immutability ────────────────────────────────────────

  group('activateAbility — immutability', () {
    test('original game state is not mutated by fireBomb activation', () {
      final state = makeState();
      final originalUnitCount = state.territories[1].unitCount;

      service.activateAbility(
        state: state,
        armyId: ArmyId.army1,
        ability: AbilityType.fireBomb,
        targetTerritoryId: 1,
      );

      expect(state.territories[1].unitCount, originalUnitCount);
      expect(state.territories[1].ownerArmyId, ArmyId.army2);
    });

    test('activating on army2 does not alter army1', () {
      final state = makeState(army2: makeArmy(id: ArmyId.army2));
      final result = service.activateAbility(
        state: state,
        armyId: ArmyId.army2,
        ability: AbilityType.fireBomb,
        targetTerritoryId: 0,
      );
      // army1 should be unchanged.
      expect(result.army1, state.army1);
    });
  });

  // ── tickCooldowns ─────────────────────────────────────────────────────────

  group('tickCooldowns', () {
    test('decrements non-zero cooldown by 1', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            cooldownTurnsRemaining: 3,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(result.abilities[AbilityType.fireBomb]!.cooldownTurnsRemaining, 2);
    });

    test('clamps cooldown to 0, not negative', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            cooldownTurnsRemaining: 1,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(result.abilities[AbilityType.fireBomb]!.cooldownTurnsRemaining, 0);
    });

    test('null cooldown is not modified', () {
      final army = makeArmy(
        abilities: {
          AbilityType.fireBomb: makeAbilityState(
            AbilityType.fireBomb,
            cooldownTurnsRemaining: null,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(
        result.abilities[AbilityType.fireBomb]!.cooldownTurnsRemaining,
        isNull,
      );
    });

    test('Direct Laser charge increments when cooldown is 0 and not full', () {
      final army = makeArmy(
        abilities: {
          AbilityType.directLaser: makeAbilityState(
            AbilityType.directLaser,
            cooldownTurnsRemaining: 0,
            chargeLevel: 1,
            maxCharge: 3,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(result.abilities[AbilityType.directLaser]!.chargeLevel, 2);
    });

    test('Direct Laser charge does NOT increment when on cooldown', () {
      final army = makeArmy(
        abilities: {
          AbilityType.directLaser: makeAbilityState(
            AbilityType.directLaser,
            cooldownTurnsRemaining: 2,
            chargeLevel: 0,
            maxCharge: 3,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(result.abilities[AbilityType.directLaser]!.chargeLevel, 0);
    });

    test('Direct Laser charge stays at maxCharge when already full', () {
      final army = makeArmy(
        abilities: {
          AbilityType.directLaser: makeAbilityState(
            AbilityType.directLaser,
            cooldownTurnsRemaining: 0,
            chargeLevel: 3,
            maxCharge: 3,
          ),
        },
      );
      final result = service.tickCooldowns(army);
      expect(result.abilities[AbilityType.directLaser]!.chargeLevel, 3);
    });

    test('Direct Laser cooldown is decremented each tick', () {
      final army = makeArmy(
        abilities: {
          AbilityType.directLaser: makeAbilityState(
            AbilityType.directLaser,
            cooldownTurnsRemaining: 3,
            chargeLevel: 0,
            maxCharge: 3,
          ),
        },
      );
      Army current = army;
      // Tick 1: cooldown 3 → 2, no charge (still on cooldown after tick)
      current = service.tickCooldowns(current);
      expect(
        current.abilities[AbilityType.directLaser]!.cooldownTurnsRemaining,
        2,
      );
      expect(current.abilities[AbilityType.directLaser]!.chargeLevel, 0);

      // Tick 2: cooldown 2 → 1, no charge
      current = service.tickCooldowns(current);
      expect(
        current.abilities[AbilityType.directLaser]!.cooldownTurnsRemaining,
        1,
      );
      expect(current.abilities[AbilityType.directLaser]!.chargeLevel, 0);

      // Tick 3: cooldown 1 → 0, charge increments 0 → 1
      current = service.tickCooldowns(current);
      expect(
        current.abilities[AbilityType.directLaser]!.cooldownTurnsRemaining,
        0,
      );
      expect(current.abilities[AbilityType.directLaser]!.chargeLevel, 1);
    });

    test('returns a new immutable Army instance', () {
      final army = makeArmy();
      final result = service.tickCooldowns(army);
      expect(identical(army, result), isFalse);
    });
  });
}
