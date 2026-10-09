// Bot difficulty tests: "Çok Kolay" / "Orta" / "Zor" must play visibly
// differently, and "Zor" must be the strongest.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/combat_service.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/turn_service.dart';
import 'package:harita/domain/services/victory_service.dart';
import 'package:harita/infrastructure/ai/greedy_ai_agent.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

GreedyAiAgent _agent(int seed) => GreedyAiAgent(
  combat: const CombatServiceImpl(),
  ability: AbilityServiceImpl(random: Random(seed)),
  economy: const EconomyServiceImpl(),
  random: Random(seed),
  actionDelay: (_) => Duration.zero,
);

const _turn = TurnServiceImpl(
  economyService: EconomyServiceImpl(),
  victoryService: VictoryServiceImpl(),
);

int _cities(GameState s, ArmyId a) =>
    s.territories.where((t) => t.ownerArmyId == a).length;

/// Plays [turns] full rounds against a passive human; returns the final state.
Future<GameState> _simulate(AiDifficulty d, int turns, {int seed = 7}) async {
  final agent = _agent(seed);
  var s = createInitialGameState(difficulty: d, random: Random(seed));
  for (var i = 0; i < turns && s.phase == GamePhase.playing; i++) {
    s = _turn.endTurn(s); // human passes
    s = await agent.playTurn(s);
    if (s.phase == GamePhase.playing) s = _turn.endTurn(s);
  }
  return s;
}

void main() {
  test(
    'very easy bot makes at most 3 moves per turn, plays no cards',
    () async {
      final agent = _agent(1);
      final s = _turn.endTurn(
        createInitialGameState(difficulty: AiDifficulty.veryEasy),
      );
      var actions = 0;
      final after = await agent.playTurn(s, onAction: (_) => actions++);
      // 1 deploy publication + at most 3 actions.
      expect(actions, lessThanOrEqualTo(1 + 3));
      // It drew its free card but neither played nor bought one.
      expect(after.army2.hasDrawnCard, isTrue);
      expect(after.army2.cardTotal, kStartFireBombs + 1);
    },
  );

  test('hard bot draws its free card, then plays a card at a valid city', () {
    final agent = _agent(1);
    var s = _turn.endTurn(
      createInitialGameState(difficulty: AiDifficulty.hard),
    );
    expect(agent.nextAction(s), isA<DrawCardAction>());
    s = agent.applyAction(const DrawCardAction(), s);
    expect(s.army2.hasDrawnCard, isTrue);
    final action = agent.nextAction(s);
    expect(action, isA<UseAbilityAction>());
    final use = action! as UseAbilityAction;
    final target = s.territories[use.targetTerritoryId];
    expect(isValidTarget(s, ArmyId.army2, use.ability, target), isTrue);
    final after = agent.applyAction(use, s);
    expect(
      after.army2.cardCount(use.ability),
      s.army2.cardCount(use.ability) - 1,
    );
  });

  test('a hard bot plays Atom Bomb anywhere and Haraç Kes on a rich '
      'player', () {
    final agent = _agent(4);
    final start = _turn.endTurn(
      createInitialGameState(difficulty: AiDifficulty.hard),
    );

    // Atom Bomb: deep into the player's land, far from the bot.
    var s = start.withArmy(
      start.army2.copyWith(
        hasDrawnCard: true,
        cards: {AbilityType.atomBomb: 1},
      ),
    );
    final atom = agent.nextAction(s)! as UseAbilityAction;
    expect(atom.ability, AbilityType.atomBomb);
    expect(s.territories[atom.targetTerritoryId].ownerArmyId, ArmyId.army1);
    int playerSoldiers(GameState g) => g.territories
        .where((t) => t.ownerArmyId == ArmyId.army1)
        .fold(0, (n, t) => n + t.unitCount);
    final before = playerSoldiers(s);
    s = agent.applyAction(atom, s);
    expect(s.army2.cardCount(AbilityType.atomBomb), 0);
    // It hit the player's cities hard (bombs kill, they do not take land).
    expect(playerSoldiers(s), lessThan(before - 150));
    expect(s.tilesOwnedBy(ArmyId.army1), 4);

    // Haraç Kes on the player, who has 400 diamonds.
    s = start
        .withArmy(
          start.army2.copyWith(
            hasDrawnCard: true,
            cards: {AbilityType.tribute: 1},
          ),
        )
        .withArmy(start.army1.copyWith(diamondBalance: 400));
    final tribute = agent.nextAction(s);
    expect(tribute, isA<UseAbilityAction>());
    s = agent.applyAction(tribute!, s);
    expect(s.army1.diamondBalance, 400 - kTributeDiamonds);
    expect(
      s.army2.diamondBalance,
      start.army2.diamondBalance + kTributeDiamonds,
    );
  });

  test('hard bot never launches an attack it would lose', () async {
    final agent = _agent(3);
    var s = createInitialGameState(difficulty: AiDifficulty.hard);
    for (var turn = 0; turn < 8; turn++) {
      s = _turn.endTurn(s);
      for (var i = 0; i < 60; i++) {
        final a = agent.nextAction(s, actionsTaken: i);
        if (a == null) break;
        if (a is AttackAction &&
            s.territories[a.targetId].ownerArmyId != ArmyId.army2) {
          expect(
            s.territories[a.sourceId].unitCount - 1,
            greaterThan(s.territories[a.targetId].unitCount),
          );
        }
        final next = agent.applyAction(a, s);
        if (identical(next, s)) break;
        s = next;
      }
      s = _turn.endTurn(s);
    }
  });

  test('hard bot gets extra soldiers each turn, the others do not', () {
    for (final d in AiDifficulty.values) {
      final s = _turn.endTurn(createInitialGameState(difficulty: d));
      final before = s.army2.totalUnitPool;
      final after = _turn.endTurn(s).army2.totalUnitPool;
      final base = kSoldiersPerTurn + 4 * kSoldiersPerCity;
      expect(
        after - before,
        base + (d == AiDifficulty.hard ? kHardAiBonusSoldiers : 0),
        reason: '$d',
      );
    }
  });

  test('stronger difficulty conquers more of Africa', () async {
    final easy = await _simulate(AiDifficulty.veryEasy, 6);
    final medium = await _simulate(AiDifficulty.medium, 6);
    final hard = await _simulate(AiDifficulty.hard, 6);
    final e = _cities(easy, ArmyId.army2);
    final m = _cities(medium, ArmyId.army2);
    final h = hard.winnerId == ArmyId.army2
        ? kTerritoryCount
        : _cities(hard, ArmyId.army2);
    // ignore: avoid_print
    print('bot cities after 6 turns — very easy: $e, medium: $m, hard: $h');
    expect(e, lessThan(m));
    expect(m, lessThanOrEqualTo(h));
  });

  test('hard bot defeats a passive player sooner than medium', () async {
    Future<int> winTurn(AiDifficulty d) async {
      final s = await _simulate(d, 60, seed: 11);
      expect(s.winnerId, ArmyId.army2, reason: '$d should win');
      return s.currentTurn;
    }

    final medium = await winTurn(AiDifficulty.medium);
    final hard = await winTurn(AiDifficulty.hard);
    // ignore: avoid_print
    print('passive player defeated — medium: turn $medium, hard: turn $hard');
    expect(hard, lessThanOrEqualTo(medium));
  });
}
