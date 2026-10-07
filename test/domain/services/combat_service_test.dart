// Rules of battle: attacks between neighbouring cities, tanks, forests,
// moving soldiers, bomber raids, mines, turns, income and victory.
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/combat_service.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/turn_service.dart';
import 'package:harita/domain/services/victory_service.dart';

/// A tiny map: 0 – 1 – 2 – 3 in a line.
GameState _line({
  List<int> units = const [50, 20, 10, 5],
  List<ArmyId?> owners = const [ArmyId.army1, null, ArmyId.army2, null],
  int tanks = 0,
  bool forestAt1 = false,
  TerritoryType typeAt1 = TerritoryType.city,
  bool mineAt1 = false,
  List<ArmyKind> kinds = const [ArmyKind.human, ArmyKind.ai],
}) {
  return GameState(
    territories: [
      for (var i = 0; i < 4; i++)
        Territory(
          id: i,
          name: 'city_$i',
          type: i == 1 ? typeAt1 : TerritoryType.city,
          adjacentIds: [if (i > 0) i - 1, if (i < 3) i + 1],
          unitCount: units[i],
          ownerArmyId: owners[i],
          hasForest: i == 1 && forestAt1,
          hasDiamondMine: i == 1 && mineAt1,
        ),
    ],
    armies: [
      for (var i = 0; i < kinds.length; i++)
        Army(
          id: ArmyId.values[i],
          kind: kinds[i],
          diamondBalance: 100,
          tanks: tanks,
          bombers: 2,
        ),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

void main() {
  const combat = CombatServiceImpl();

  GameState attack(GameState s, int from, int to, [ArmyId? who]) =>
      combat.resolveAttack(
        state: s,
        attackingArmyId: who ?? ArmyId.army1,
        sourceTerritoryId: from,
        targetTerritoryId: to,
      );

  group('attacks', () {
    test('the stronger side takes the city, soldier for soldier', () {
      final s = attack(_line(), 0, 1);
      // 49 attack 20 → 29 move in.
      expect(s.territories[1].ownerArmyId, ArmyId.army1);
      expect(s.territories[1].unitCount, 29);
      expect(s.territories[0].unitCount, 1);
    });

    test('a weaker attack is repelled and the defenders lose some', () {
      final s = attack(_line(units: [15, 20, 10, 5]), 0, 1);
      expect(s.territories[1].ownerArmyId, isNull);
      // 14 attackers: 20 - 14 = 6 defenders are left.
      expect(s.territories[1].unitCount, 6);
      expect(s.territories[0].unitCount, 1);
    });

    test('a tank adds strength and wins a battle soldiers alone lose', () {
      final withoutTank = attack(_line(units: [20, 30, 10, 5]), 0, 1);
      expect(withoutTank.territories[1].ownerArmyId, isNull);

      final withTank = attack(_line(units: [20, 30, 10, 5], tanks: 1), 0, 1);
      // 19 + 25 = 44 > 30 → 14 move in.
      expect(withTank.territories[1].ownerArmyId, ArmyId.army1);
      expect(withTank.territories[1].unitCount, 14);
      expect(withTank.army1.tanks, 1, reason: 'a winning tank survives');
      // …but it joined its one attack of this turn.
      expect(withTank.army1.tanksReady, 0);
      expect(attackStrength(withTank.army1, withTank.territories[1]), 13);
    });

    test('a failed attack loses the tank', () {
      final s = attack(_line(units: [10, 80, 10, 5], tanks: 2), 0, 1);
      expect(s.territories[1].ownerArmyId, isNull);
      expect(s.army1.tanks, 1);
    });

    test('forests make defenders 25 % stronger', () {
      final open = _line(units: [41, 36, 10, 5]);
      final forest = _line(units: [41, 36, 10, 5], forestAt1: true);
      expect(defenceStrength(forest.territories[1]), 45);
      expect(attack(open, 0, 1).territories[1].ownerArmyId, ArmyId.army1);
      expect(attack(forest, 0, 1).territories[1].ownerArmyId, isNull);
    });

    test('into an own city the soldiers just move', () {
      final s = attack(
        _line(owners: [ArmyId.army1, ArmyId.army1, ArmyId.army2, null]),
        0,
        1,
      );
      expect(s.territories[0].unitCount, 1);
      expect(s.territories[1].unitCount, 69);
    });

    test('bots can attack each other', () {
      final s = attack(
        _line(
          units: [5, 80, 10, 5],
          owners: [ArmyId.army1, ArmyId.army3, ArmyId.army2, null],
          kinds: const [ArmyKind.human, ArmyKind.ai, ArmyKind.ai],
        ),
        2,
        1,
        ArmyId.army2,
      );
      expect(s.territories[1].ownerArmyId, ArmyId.army3);
      final t = attack(
        _line(
          units: [5, 10, 80, 5],
          owners: [ArmyId.army1, ArmyId.army3, ArmyId.army2, null],
          kinds: const [ArmyKind.human, ArmyKind.ai, ArmyKind.ai],
        ),
        2,
        1,
        ArmyId.army2,
      );
      expect(t.territories[1].ownerArmyId, ArmyId.army2);
    });

    test('invalid attacks are rejected', () {
      final s = _line();
      expect(() => attack(s, 0, 2), throwsA(isA<InvalidAttackException>()));
      expect(() => attack(s, 1, 2), throwsA(isA<InvalidAttackException>()));
      expect(
        () => attack(_line(units: [1, 20, 10, 5]), 0, 1),
        throwsA(isA<InvalidAttackException>()),
      );
    });

    test('capturing mines pays diamonds', () {
      final diamond = attack(_line(mineAt1: true), 0, 1);
      expect(diamond.army1.diamondBalance, 100 + kDiamondMineReward);
      final gold = attack(_line(typeAt1: TerritoryType.goldMine), 0, 1);
      expect(gold.army1.diamondBalance, 100 + kGoldMineReward);
    });
  });

  group('bombers', () {
    test('a raid kills soldiers anywhere and uses one bomber', () {
      final s = combat.bomberRaid(
        state: _line(),
        armyId: ArmyId.army1,
        targetTerritoryId: 3,
      );
      expect(s.territories[3].unitCount, 0);
      expect(s.territories[3].ownerArmyId, isNull);
      final t = combat.bomberRaid(
        state: s,
        armyId: ArmyId.army1,
        targetTerritoryId: 1,
      );
      expect(t.territories[1].unitCount, 20 - kBomberDamage);
      expect(t.army1.bombersReady, 0);
      expect(
        () => combat.bomberRaid(
          state: t,
          armyId: ArmyId.army1,
          targetTerritoryId: 1,
        ),
        throwsA(isA<InvalidAttackException>()),
      );
    });

    test('bombers do not bomb own cities', () {
      expect(
        () => combat.bomberRaid(
          state: _line(),
          armyId: ArmyId.army1,
          targetTerritoryId: 0,
        ),
        throwsA(isA<InvalidAttackException>()),
      );
    });
  });

  group('turns', () {
    const turn = TurnServiceImpl(
      economyService: EconomyServiceImpl(),
      victoryService: VictoryServiceImpl(),
    );

    test('income: 80 diamonds and soldiers in every own city; bombers and '
        'the free card are ready again', () {
      var s = _line(owners: [ArmyId.army1, ArmyId.army1, ArmyId.army2, null]);
      s = s.withArmy(
        s.army1.copyWith(bombersFlown: 2, tanksUsed: 1, hasDrawnCard: true),
      );
      final next = turn.endTurn(s);
      expect(next.army1.diamondBalance, 100 + kDiamondsPerTurn);
      expect(next.territories[0].unitCount, 50 + kCityGrowth);
      expect(next.territories[1].unitCount, 20 + kCityGrowth);
      expect(next.territories[2].unitCount, 10, reason: 'not the bot yet');
      expect(next.army1.bombersReady, 2);
      expect(next.army1.tanksUsed, 0);
      expect(next.army1.hasDrawnCard, isFalse);
      expect(next.activeArmyId, ArmyId.army2);
    });

    test('hard bots grow faster, very easy bots slower', () {
      final bot = Army(id: ArmyId.army2, kind: ArmyKind.ai, diamondBalance: 0);
      expect(cityGrowthFor(bot, AiDifficulty.hard), kHardCityGrowth);
      expect(cityGrowthFor(bot, AiDifficulty.veryEasy), kVeryEasyCityGrowth);
      final human = Army(
        id: ArmyId.army1,
        kind: ArmyKind.human,
        diamondBalance: 0,
      );
      expect(cityGrowthFor(human, AiDifficulty.hard), kCityGrowth);
    });

    test('eliminated armies are skipped and the round counter grows', () {
      final s = _line(
        owners: [ArmyId.army1, null, ArmyId.army3, null],
        kinds: const [ArmyKind.human, ArmyKind.ai, ArmyKind.ai],
      );
      final next = turn.endTurn(s);
      expect(next.activeArmyId, ArmyId.army3);
      expect(next.currentTurn, 1);
      final back = turn.endTurn(next);
      expect(back.activeArmyId, ArmyId.army1);
      expect(back.currentTurn, 2);
    });
  });

  group('victory', () {
    const victory = VictoryServiceImpl();

    test('the last army standing wins', () {
      expect(
        victory.checkVictory(
          _line(owners: [ArmyId.army1, ArmyId.army1, null, null]),
        ),
        ArmyId.army1,
      );
      expect(victory.checkVictory(_line()), isNull);
    });

    test('with no human left, the biggest bot wins', () {
      final s = _line(
        owners: [ArmyId.army2, ArmyId.army2, ArmyId.army3, null],
        kinds: const [ArmyKind.human, ArmyKind.ai, ArmyKind.ai],
      );
      expect(victory.checkVictory(s), ArmyId.army2);
    });

    test('with two humans the game goes on while one of them lives', () {
      final s = _line(
        owners: [null, ArmyId.army2, ArmyId.army3, null],
        kinds: const [ArmyKind.human, ArmyKind.human, ArmyKind.ai],
      );
      expect(victory.checkVictory(s), isNull);
    });
  });
}
