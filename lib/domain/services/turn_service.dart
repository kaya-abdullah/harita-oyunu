/// Turn service for Harita: Kendi İmparatorluğunu Kur.
///
/// Orchestrates end-of-turn processing: income and city growth, the reset of
/// the per-turn card draw and bomber flights, army switching, turn counter
/// advancement, and victory detection.
library;

import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/victory_service.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Manages turn transitions.
abstract class TurnService {
  /// Ends the active army's turn and returns the updated [GameState]:
  ///
  /// 1. The ending army earns its income and its cities grow
  ///    ([EconomyService.applyTurnIncome]); its tanks, bombers and free
  ///    card are ready again next turn.
  /// 2. The turn passes to the next army (in [GameState.armies] order) that
  ///    still owns land; eliminated armies are skipped.
  /// 3. When play wraps around, [GameState.currentTurn] increments.
  /// 4. A winner, if any, ends the game.
  GameState endTurn(GameState state);

  /// Returns `true` when [armyId] is the currently active army.
  bool isActiveArmy(GameState state, ArmyId armyId);
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [TurnService].
class TurnServiceImpl implements TurnService {
  const TurnServiceImpl({
    required EconomyService economyService,
    required VictoryService victoryService,
  }) : _economy = economyService,
       _victory = victoryService;

  final EconomyService _economy;
  final VictoryService _victory;

  @override
  GameState endTurn(GameState state) {
    final endingArmyId = state.activeArmyId;

    var next = _economy.applyTurnIncome(state, endingArmyId);
    final ending = next.army(endingArmyId);
    next = next.withArmy(
      ending.copyWith(bombersFlown: 0, tanksUsed: 0, hasDrawnCard: false),
    );

    final order = [for (final a in state.armies) a.id];
    final alive = next.armiesAlive.toSet();
    final from = order.indexOf(endingArmyId);
    var nextIndex = from;
    for (var step = 1; step <= order.length; step++) {
      final i = (from + step) % order.length;
      if (alive.contains(order[i]) || step == order.length) {
        nextIndex = i;
        break;
      }
    }
    next = next.copyWith(
      activeArmyId: order[nextIndex],
      currentTurn: nextIndex <= from ? state.currentTurn + 1 : null,
    );

    final winnerId = _victory.checkVictory(next);
    if (winnerId != null) {
      next = next.copyWith(phase: GamePhase.victory, winnerId: winnerId);
    }
    return next;
  }

  @override
  bool isActiveArmy(GameState state, ArmyId armyId) =>
      state.activeArmyId == armyId;
}
