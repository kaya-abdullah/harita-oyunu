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
  ability: const AbilityServiceImpl(),
  economy: const EconomyServiceImpl(),
  random: Random(seed),
  actionDelay: (_) => Duration.zero,
);

const _turn = TurnServiceImpl(
  economyService: EconomyServiceImpl(),
  abilityService: AbilityServiceImpl(),
  victoryService: VictoryServiceImpl(),
);

int _tiles(GameState s, ArmyId a) =>
    s.territories.where((t) => t.ownerArmyId == a).length;

/// Plays [turns] full rounds against a passive human; returns the final state.
Future<GameState> _simulate(AiDifficulty d, int turns, {int seed = 7}) async {
  final agent = _agent(seed);
  var s = createInitialGameState(difficulty: d);
  for (var i = 0; i < turns && s.phase == GamePhase.playing; i++) {
    s = _turn.endTurn(s); // human passes
    s = await agent.playTurn(s);
    if (s.phase == GamePhase.playing) s = _turn.endTurn(s);
  }
  return s;
}

void main() {
  test('very easy bot makes at most 3 moves per turn, no abilities', () async {
    final agent = _agent(1);
    final s = _turn.endTurn(
      createInitialGameState(difficulty: AiDifficulty.veryEasy),
    );
    var actions = 0;
    final after = await agent.playTurn(s, onAction: (_) => actions++);
    // 1 deploy publication + at most 3 actions.
    expect(actions, lessThanOrEqualTo(1 + 3));
    expect(after.army2.abilities[AbilityType.fireBomb]!.isOnCooldown, isFalse);
    expect(after.army2.inventory, isEmpty);
  });

  test('hard bot fires its ability first, at a tile next to its land', () {
    final s = _turn.endTurn(
      createInitialGameState(difficulty: AiDifficulty.hard),
    );
    final action = _agent(1).nextAction(s);
    expect(action, isA<UseAbilityAction>());
    final use = action! as UseAbilityAction;
    expect(use.ability, AbilityType.fireBomb);
    final target = s.territories[use.targetTerritoryId];
    expect(target.ownerArmyId, isNot(ArmyId.army2));
    expect(
      target.adjacentIds.any(
        (id) => s.territories[id].ownerArmyId == ArmyId.army2,
      ),
      isTrue,
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
      final base = kSoldiersPerTurn + kStartTileCount ~/ kTilesPerBonusSoldier;
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
    final e = _tiles(easy, ArmyId.army2);
    final m = _tiles(medium, ArmyId.army2);
    final h = hard.winnerId == ArmyId.army2
        ? kTerritoryCount
        : _tiles(hard, ArmyId.army2);
    // ignore: avoid_print
    print('bot tiles after 6 turns — very easy: $e, medium: $m, hard: $h');
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
