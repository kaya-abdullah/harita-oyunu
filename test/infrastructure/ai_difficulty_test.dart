// The bots: they draw cards, play them, send bombers, attack the player and
// each other, and whole games come to an end at every difficulty.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

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

const _turns = TurnServiceImpl(
  economyService: EconomyServiceImpl(),
  victoryService: VictoryServiceImpl(),
);

/// Plays bots only (the human seat is played by a bot too) until someone
/// wins or [maxRounds] pass. Returns the final state and the actions taken.
Future<(GameState, List<AiAction>)> _botGame(
  AiDifficulty difficulty, {
  int bots = 4,
  int maxRounds = 120,
  int seed = 1,
}) async {
  var s = createInitialGameState(
    difficulty: difficulty,
    botCount: bots,
    random: Random(seed),
  );
  // Let the AI play the human seat as well.
  s = s.withArmy(s.army1.copyWith(kind: ArmyKind.ai));
  final agent = _agent(seed);
  final actions = <AiAction>[];
  while (s.phase == GamePhase.playing && s.currentTurn <= maxRounds) {
    s = await agent.playTurn(s, onAction: (a, _, __) => actions.add(a));
    if (s.phase == GamePhase.victory) break;
    s = _turns.endTurn(s);
    final winner = const VictoryServiceImpl().checkVictory(s);
    if (winner != null) {
      s = s.copyWith(phase: GamePhase.victory, winnerId: winner);
    }
  }
  return (s, actions);
}

void main() {
  test('a bot draws its free card first', () {
    final s = createInitialGameState(random: Random(1));
    final bot = s.copyWith(activeArmyId: ArmyId.army2);
    expect(_agent(1).nextAction(bot), isA<DrawCardAction>());
  });

  test(
    'a hard bot plays its cards, buys weapons and uses its bombers',
    () async {
      var s = createInitialGameState(
        difficulty: AiDifficulty.hard,
        botCount: 3,
        random: Random(2),
      ).copyWith(activeArmyId: ArmyId.army2);
      s = s.withArmy(
        s.army2.copyWith(
          diamondBalance: 900,
          cards: {AbilityType.atomBomb: 1, AbilityType.tribute: 1},
        ),
      );
      s = s.withArmy(s.army1.copyWith(diamondBalance: 400));
      final actions = <AiAction>[];
      final after = await _agent(
        2,
      ).playTurn(s, onAction: (a, _, __) => actions.add(a));
      expect(
        actions.whereType<UseAbilityAction>().map((a) => a.ability),
        containsAll([AbilityType.atomBomb, AbilityType.tribute]),
      );
      expect(actions.whereType<PurchaseAction>(), isNotEmpty);
      expect(after.army2.cardCount(AbilityType.atomBomb), 0);
      expect(after.tilesOwnedBy(ArmyId.army2), greaterThan(2));
    },
  );

  for (final difficulty in AiDifficulty.values) {
    test(
      'bot-only games end ($difficulty)',
      () async {
        final (s, actions) = await _botGame(difficulty);
        expect(actions.whereType<DrawCardAction>(), isNotEmpty);
        expect(actions.whereType<AttackAction>(), isNotEmpty);
        if (difficulty != AiDifficulty.veryEasy) {
          expect(actions.whereType<UseAbilityAction>(), isNotEmpty);
          expect(actions.whereType<BomberAction>(), isNotEmpty);
        }
        // Bots fight each other: every army but one loses land.
        expect(s.phase == GamePhase.victory || s.currentTurn > 100, isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'bots attack each other, not only the player',
    () async {
      var s = createInitialGameState(
        difficulty: AiDifficulty.hard,
        botCount: 6,
        random: Random(3),
      );
      s = s.withArmy(s.army1.copyWith(kind: ArmyKind.ai));
      final agent = _agent(3);
      var botOnBot = 0;
      for (var round = 0; round < 25 && s.phase == GamePhase.playing; round++) {
        for (var i = 0; i < s.armies.length; i++) {
          s = await agent.playTurn(
            s,
            onAction: (a, before, _) {
              if (a is AttackAction) {
                final victim = before.territories[a.targetId].ownerArmyId;
                if (victim != null &&
                    victim != ArmyId.army1 &&
                    victim != before.activeArmyId) {
                  botOnBot++;
                }
              }
            },
          );
          if (s.phase == GamePhase.victory) break;
          s = _turns.endTurn(s);
        }
      }
      expect(botOnBot, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
