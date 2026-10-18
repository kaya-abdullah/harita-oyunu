// Balance: America sits in the middle with all six bots around it. It must
// not be wiped out right away, even by a player who only places reserves.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/combat_service.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/turn_service.dart';
import 'package:harita/domain/services/victory_service.dart';
import 'package:harita/infrastructure/ai/greedy_ai_agent.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

const _turn = TurnServiceImpl(
  economyService: EconomyServiceImpl(),
  victoryService: VictoryServiceImpl(),
);

void main() {
  test(
    'a passive America survives five rounds against six Orta bots',
    () async {
      for (var seed = 1; seed <= 8; seed++) {
        final agent = GreedyAiAgent(
          combat: const CombatServiceImpl(),
          ability: AbilityServiceImpl(random: Random(seed)),
          economy: const EconomyServiceImpl(),
          random: Random(seed),
          actionDelay: (_) => Duration.zero,
        );
        var s = createInitialGameState(
          difficulty: AiDifficulty.medium,
          botCount: kMaxBots,
          random: Random(seed),
        );
        for (var round = 0; round < 5 * (kMaxBots + 1); round++) {
          expect(s.phase, GamePhase.playing, reason: 'seed $seed');
          if (s.activeArmy.kind == ArmyKind.human) {
            // Only places the reserve soldiers.
            s = agent.deployReinforcements(s);
          } else if (s.tilesOwnedBy(s.activeArmyId) > 0) {
            s = await agent.playTurn(s);
          }
          s = _turn.endTurn(s);
        }
        expect(s.tilesOwnedBy(ArmyId.army1), greaterThan(0), reason: '$seed');
      }
    },
  );
}
