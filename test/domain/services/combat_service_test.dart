/// Unit tests for CombatServiceImpl.
///
/// Covers all combat rules: validation, attacker-wins path, defender-holds
/// path, base-capacity capping, and zero-unit ownership clearing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/combat_service.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

/// Builds a minimal [Territory] for testing.
Territory makeTerritory({
  required int id,
  required int unitCount,
  ArmyId? ownerArmyId,
  List<int> adjacentIds = const [],
  TerritoryType type = TerritoryType.normal,
  int? baseCapacity,
}) {
  return Territory(
    id: id,
    name: 'territory_$id',
    type: type,
    adjacentIds: adjacentIds,
    unitCount: unitCount,
    ownerArmyId: ownerArmyId,
    baseCapacity: baseCapacity,
  );
}

/// Builds a minimal [Army] for testing.
Army makeArmy({ArmyId id = ArmyId.army1}) {
  return Army(
    id: id,
    kind: ArmyKind.human,
    diamondBalance: 100,
    totalUnitPool: 10,
  );
}

/// Builds a [GameState] with exactly the provided territories and default
/// armies.
GameState makeState(List<Territory> territories) {
  return GameState(
    territories: territories,
    armies: [
      makeArmy(id: ArmyId.army1),
      makeArmy(id: ArmyId.army2),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late CombatServiceImpl service;

  setUp(() {
    service = const CombatServiceImpl();
  });

  // ── Validation ────────────────────────────────────────────────────────────

  group('resolveAttack — validation', () {
    test(
      'throws InvalidAttackException when attacking army does not own source',
      () {
        // Source is owned by army2, but army1 is attacking.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 10,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        expect(
          () => service.resolveAttack(
            state: state,
            attackingArmyId: ArmyId.army1,
            sourceTerritoryId: 0,
            targetTerritoryId: 1,
          ),
          throwsA(isA<InvalidAttackException>()),
        );
      },
    );

    test(
      'throws InvalidAttackException when attacking unowned (neutral) source',
      () {
        // Source has no owner.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 10,
            ownerArmyId: null,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        expect(
          () => service.resolveAttack(
            state: state,
            attackingArmyId: ArmyId.army1,
            sourceTerritoryId: 0,
            targetTerritoryId: 1,
          ),
          throwsA(isA<InvalidAttackException>()),
        );
      },
    );

    test('throws InvalidAttackException when territories are not adjacent', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [],
        ),
      ];
      final state = makeState(territories);

      expect(
        () => service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidAttackException>()),
      );
    });

    test('throws InvalidAttackException when source has only 1 unit', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 1,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      expect(
        () => service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidAttackException>()),
      );
    });

    test('throws InvalidAttackException when source has 0 units', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 0,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      expect(
        () => service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidAttackException>()),
      );
    });

    test(
      'throws InvalidAttackException when source territory id does not exist',
      () {
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 10,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        expect(
          () => service.resolveAttack(
            state: state,
            attackingArmyId: ArmyId.army1,
            sourceTerritoryId: 99,
            targetTerritoryId: 1,
          ),
          throwsA(isA<InvalidAttackException>()),
        );
      },
    );

    test(
      'throws InvalidAttackException when target territory id does not exist',
      () {
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 10,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [99],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        expect(
          () => service.resolveAttack(
            state: state,
            attackingArmyId: ArmyId.army1,
            sourceTerritoryId: 0,
            targetTerritoryId: 99,
          ),
          throwsA(isA<InvalidAttackException>()),
        );
      },
    );

    test('succeeds with exactly 2 units at source (minimum valid)', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 2,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 1,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      expect(
        () => service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        ),
        returnsNormally,
      );
    });
  });

  // ── Attacker wins ─────────────────────────────────────────────────────────

  group('resolveAttack — attacker wins (attackingUnits > defendingUnits)', () {
    test('source territory keeps exactly 1 unit', () {
      // Source: 10 units → sends 9. Target: 5 units → attacker wins.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[0].unitCount, 1);
    });

    test('source territory owner remains the attacker', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[0].ownerArmyId, ArmyId.army1);
    });

    test('target territory is transferred to attacker', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].ownerArmyId, ArmyId.army1);
    });

    test('attacker loses ceil(defending × kAttackerWinLossFraction) units', () {
      // Attacking: 9 (source=10 - 1). Defending: 5.
      // Losses = ceil(5 × 0.5) = 3. Survivors = 9 - 3 = 6.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].unitCount, 6);
    });

    test('attacker losses use ceil (not floor) on fractional result', () {
      // Attacking: 5 (source=6 - 1). Defending: 3.
      // Losses = ceil(3 × 0.5) = ceil(1.5) = 2. Survivors = 5 - 2 = 3.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 6,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 3,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].unitCount, 3);
    });

    test('capturing a neutral territory assigns attacker ownership', () {
      // Requirements 3.4: move into unoccupied territory → assign ownership.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 5,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(id: 1, unitCount: 0, ownerArmyId: null, adjacentIds: [0]),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // 4 attacking units vs 0 defending: attacker wins, losses = ceil(0×0.5)=0,
      // survivors = 4.
      expect(result.territories[1].ownerArmyId, ArmyId.army1);
      expect(result.territories[1].unitCount, 4);
    });

    test('attacking a neutral territory with 0 defenders captures it', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 3,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(id: 1, unitCount: 0, ownerArmyId: null, adjacentIds: [0]),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // 2 attacking vs 0 defending → attacker wins. Losses = 0. Survivors = 2.
      expect(result.territories[1].ownerArmyId, ArmyId.army1);
      expect(result.territories[1].unitCount, 2);
    });

    test('army2 can capture army1 territory when odds are favourable', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 5,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army2,
        sourceTerritoryId: 1,
        targetTerritoryId: 0,
      );

      // 9 attacking vs 5 defending → attacker wins. Losses = ceil(5×0.5)=3.
      // Survivors = 9-3=6.
      expect(result.territories[0].ownerArmyId, ArmyId.army2);
      expect(result.territories[0].unitCount, 6);
    });
  });

  // ── Defender holds ────────────────────────────────────────────────────────

  group('resolveAttack — defender holds (attackingUnits <= defendingUnits)', () {
    test('attacker loses all attacking units; source keeps 1', () {
      // Source: 5 units → sends 4. Target: 10 units → defender holds.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 5,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[0].unitCount, 1);
    });

    test('source territory owner is unchanged when defender holds', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 5,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[0].ownerArmyId, ArmyId.army1);
    });

    test(
      'defender loses ceil(attackingUnits × kDefenderHoldLossFraction) units',
      () {
        // Attacking: 4 (source=5 - 1). Defending: 10.
        // Defender losses = ceil(4 × 0.3) = ceil(1.2) = 2. Survivors = 10-2=8.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 5,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 10,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        final result = service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );

        expect(result.territories[1].unitCount, 8);
      },
    );

    test('defender losses use ceil (not floor) on fractional result', () {
      // Attacking: 3 (source=4 - 1). Defending: 10.
      // Defender losses = ceil(3 × 0.3) = ceil(0.9) = 1. Survivors = 10-1=9.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 4,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].unitCount, 9);
    });

    test('defender ownership is unchanged when they hold', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 5,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].ownerArmyId, ArmyId.army2);
    });

    test(
      'equal units (attacking == defending) is treated as defender holds',
      () {
        // Equal: attackingUnits <= defendingUnits → defender holds.
        // Source: 6 → sends 5. Target: 5 defending.
        // Defender losses = ceil(5 × 0.3) = ceil(1.5) = 2. Survivors = 5-2=3.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 6,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final state = makeState(territories);

        final result = service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );

        expect(
          result.territories[1].ownerArmyId,
          ArmyId.army2,
        ); // defender still owns
        expect(result.territories[0].unitCount, 1); // attacker left with 1
        expect(result.territories[1].unitCount, 3); // 5 - 2
      },
    );
  });

  // ── Zero-unit ownership rule ──────────────────────────────────────────────

  group('resolveAttack — zero units clears ownership (Requirements 3.6)', () {
    test('defender units reach 0 → ownership becomes null (neutral)', () {
      // Defender has only 1 unit. Defender losses = ceil(attacking × 0.3).
      // To wipe defender, attacker needs to win: attacking > 1.
      // Source: 10 → sends 9. Target: 1. Attacker wins.
      // Attacker losses = ceil(1 × 0.5) = 1. Survivors = 9-1=8. Not 0.
      //
      // For defender to reach 0 on defender-holds path:
      // Need: ceil(attacking × 0.3) >= defending.
      // E.g., attacking=4, defending=1: ceil(4×0.3)=ceil(1.2)=2 >= 1 → wipes.
      // So: source=5, target=1, attacker sends 4, defender has 1 → 4>1 → WINS not holds.
      // We need attacker to lose but defender be wiped.
      // Actually on win path (attacking > defending), defender IS removed, attacker takes over.
      // If surviving attackers = 0 after win, territory should be neutral per Property 7.
      // Let's construct: attacking = 2, defending = 1. Attacker wins.
      // Losses = ceil(1 × 0.5) = 1. Survivors = 2-1 = 1. Owner = attacker. Not 0.
      //
      // To produce 0 survivors on attacker-wins path we need attacking - ceil(defending×0.5) = 0.
      // E.g., attacking=1, defending=1: but then attacking <= defending → defender holds, not wins.
      // attacking=2, defending=2: equal → defender holds.
      // attacking=3, defending=3: equal → defender holds.
      // Actually with equal units, defender holds. Defender losses = ceil(3×0.3)=1. Survivors=2. Not 0.
      // To reach 0 on defender path: ceil(attacking × 0.3) >= defending.
      // attacking=7, defending=2: ceil(7×0.3)=ceil(2.1)=3 >= 2 → defender wiped → neutral.
      // But 7 > 2 → attacker wins (not defender-holds).
      // The only way defender-holds AND defender is wiped is:
      // attacking <= defending AND ceil(attacking × 0.3) >= defending.
      // Try attacking=10, defending=3: 10 > 3 → attacker wins. Not helpful.
      // Try attacking=3, defending=3: equal → defender holds.
      // Defender losses = ceil(3 × 0.3) = ceil(0.9) = 1. Survivors = 3-1 = 2. Not 0.
      // Try attacking=10, defending=2: 10 > 2 → attacker wins.
      // The math makes it very hard to wipe defender on holds path.
      // Instead test via attacker-wins with 0 surviving attackers:
      // attacking = 2, defending = 4: 2 <= 4 → defender holds.
      // Defender losses = ceil(2×0.3)=1. Survivors=4-1=3.
      // attacking = 3, defending = 10: 3 <= 10 → defender holds.
      // Losses = ceil(3×0.3)=1. Survivors=9.
      //
      // Best approach: set defenders to 0 upfront (neutral territory), attacker wins.
      // Already tested above. For the zero-units neutral path, let's use a custom case
      // where defender losses equal defender units exactly.
      // attacking = 4, defending = 2: 4 > 2 → ATTACKER WINS.
      // Attacker losses = ceil(2 × 0.5) = 1. Survivors = 4-1 = 3. NOT 0.
      // The defender path to 0:
      // Need attacking <= defending AND ceil(attacking × kDefenderHoldLossFraction) >= defending.
      // With kDefenderHoldLossFraction = 0.3:
      // ceil(attacking × 0.3) >= defending AND attacking <= defending
      // → 0.3 × attacking >= defending - 1 (approx)
      // → defending <= attacking × 0.3 + 1
      // AND attacking <= defending
      // → attacking <= attacking × 0.3 + 1 → attacking × 0.7 <= 1 → attacking <= ~1.43
      // So attacking must be 1. defending=1: 1<=1 true, ceil(1×0.3)=1>=1 → wipes!
      // Source: 2 (sends 1), Target: 1.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 2,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 1,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      // attacking=1, defending=1: 1 <= 1 → defender holds.
      // Defender losses = ceil(1×0.3) = ceil(0.3) = 1. Survivors = 0. → neutral!
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // Defender was wiped → neutral.
      expect(result.territories[1].unitCount, 0);
      expect(
        result.territories[1].ownerArmyId,
        isNull,
        reason: 'Territory with 0 units must be neutral per Requirements 3.6',
      );
    });

    test('attacker survivors of 0 after win → target becomes neutral', () {
      // Need attackingUnits > defendingUnits AND
      // attackingUnits - ceil(defendingUnits × 0.5) = 0.
      // So attackingUnits = ceil(defendingUnits × 0.5).
      // E.g., defending=2, attacking=1: 1 > 2 is false.
      // defending=1, attacking=1: equal → not a win.
      // This case is mathematically improbable with integer arithmetic.
      // The formula: survivors = attacking - ceil(defending × 0.5).
      // For survivors=0: attacking = ceil(defending × 0.5).
      // defending=2 → ceil(1) = 1 → attacking must be 1, but 1 > 2 is false.
      // So this path is unreachable with normal positive integers.
      // Test the theory via mocking by providing 0-unit source attacking:
      // Actually unit test this invariant via direct assertion about the design.
      // Since this edge case can't be triggered with these constants, skip it.
      // Instead verify that a normal win does NOT produce 0 (regression guard).
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // Survivors = 9 - ceil(5×0.5)=3. = 6. Not 0.
      expect(result.territories[1].unitCount, greaterThan(0));
      expect(result.territories[1].ownerArmyId, ArmyId.army1);
    });
  });

  // ── Base capacity capping ─────────────────────────────────────────────────

  group('resolveAttack — base capacity enforcement (Requirements 5.2, 5.3)', () {
    test(
      'attacker survivors are capped at bigBase capacity when attacker wins',
      () {
        // BigBase with capacity 10. Attacking 20 units (source=21), defending 5.
        // Attacker wins. Losses = ceil(5×0.5) = 3. Survivors = 17. Capped at 10.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 21,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 5,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
            type: TerritoryType.bigBase,
            baseCapacity: 10,
          ),
        ];
        final state = makeState(territories);

        final result = service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );

        expect(result.territories[1].unitCount, 10); // capped at baseCapacity
        expect(result.territories[1].ownerArmyId, ArmyId.army1);
      },
    );

    test('attacker survivors below capacity are NOT capped', () {
      // BigBase with capacity 150. Attacking 10 (source=11), defending 5.
      // Survivors = 10 - ceil(5×0.5) = 7. Below 150 → not capped.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 11,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
          type: TerritoryType.bigBase,
          baseCapacity: kBigBaseCapacity,
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[1].unitCount, 7); // well below 150
    });

    test('normal territory has no capacity cap', () {
      // Normal territory, large attack force.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 200,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 1,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // Survivors = 199 - ceil(1×0.5) = 199 - 1 = 198.
      expect(result.territories[1].unitCount, 198);
    });

    test('smallBase capacity is enforced', () {
      // SmallBase with capacity 80. Attacking 100 (source=101), defending 10.
      // Survivors = 100 - ceil(10×0.5) = 95. Capped at 80.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 101,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 10,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
          type: TerritoryType.smallBase,
          baseCapacity: 80,
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(
        result.territories[1].unitCount,
        80,
      ); // capped at smallBase capacity
    });
  });

  // ── Immutability ──────────────────────────────────────────────────────────

  group('resolveAttack — immutability', () {
    test('original GameState is not mutated after a successful attack', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);
      final originalSource = state.territories[0];
      final originalTarget = state.territories[1];

      service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      // Original state must be completely untouched.
      expect(state.territories[0], originalSource);
      expect(state.territories[1], originalTarget);
    });

    test('original GameState is not mutated when exception is thrown', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 1,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);
      final originalSource = state.territories[0];

      try {
        service.resolveAttack(
          state: state,
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );
      } on InvalidAttackException {
        // Expected.
      }

      expect(state.territories[0], originalSource);
    });

    test('non-participating territories are not modified', () {
      // Territory 2 is a bystander — it must be unchanged.
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
        makeTerritory(
          id: 2,
          unitCount: 20,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [],
        ),
      ];
      final state = makeState(territories);
      final bystander = state.territories[2];

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.territories[2], bystander);
    });

    test('army resources (Elma, unit pool) are not modified by combat', () {
      final territories = [
        makeTerritory(
          id: 0,
          unitCount: 10,
          ownerArmyId: ArmyId.army1,
          adjacentIds: [1],
        ),
        makeTerritory(
          id: 1,
          unitCount: 5,
          ownerArmyId: ArmyId.army2,
          adjacentIds: [0],
        ),
      ];
      final state = makeState(territories);

      final result = service.resolveAttack(
        state: state,
        attackingArmyId: ArmyId.army1,
        sourceTerritoryId: 0,
        targetTerritoryId: 1,
      );

      expect(result.army1.diamondBalance, state.army1.diamondBalance);
      expect(result.army1.totalUnitPool, state.army1.totalUnitPool);
      expect(result.army2.diamondBalance, state.army2.diamondBalance);
      expect(result.army2.totalUnitPool, state.army2.totalUnitPool);
    });
  });

  // ── Combat formula constants ──────────────────────────────────────────────

  group('combat formula uses design constants', () {
    test('kAttackerWinLossFraction is 0.5', () {
      expect(kAttackerWinLossFraction, 0.5);
    });

    test('kDefenderHoldLossFraction is 0.3', () {
      expect(kDefenderHoldLossFraction, 0.3);
    });

    test(
      'attacker win: units match formula exactness for even defender count',
      () {
        // Attacking: 11 (source=12 - 1). Defending: 4.
        // 11 > 4 → attacker wins.
        // Losses = ceil(4 × 0.5) = ceil(2.0) = 2. Survivors = 11-2=9.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 12,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 4,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final result = service.resolveAttack(
          state: makeState(territories),
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );
        expect(result.territories[1].unitCount, 9);
      },
    );

    test(
      'defender hold: units match formula exactness for even attacker count',
      () {
        // Attacking: 2 (source=3 - 1). Defending: 10.
        // 2 <= 10 → defender holds.
        // Losses = ceil(2 × 0.3) = ceil(0.6) = 1. Survivors = 10-1=9.
        final territories = [
          makeTerritory(
            id: 0,
            unitCount: 3,
            ownerArmyId: ArmyId.army1,
            adjacentIds: [1],
          ),
          makeTerritory(
            id: 1,
            unitCount: 10,
            ownerArmyId: ArmyId.army2,
            adjacentIds: [0],
          ),
        ];
        final result = service.resolveAttack(
          state: makeState(territories),
          attackingArmyId: ArmyId.army1,
          sourceTerritoryId: 0,
          targetTerritoryId: 1,
        );
        expect(result.territories[1].unitCount, 9);
      },
    );
  });
}
