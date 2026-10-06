/// Turn service for Harita: Kendi İmparatorluğunu Kur.
///
/// Orchestrates end-of-turn processing: income collection, cooldown ticking,
/// army switching, turn counter advancement, and victory detection.
library;

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/victory_service.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Manages turn transitions including resource collection, state ticking, army
/// switching, and victory checking.
abstract class TurnService {
  /// Ends the currently active army's turn and returns an updated [GameState].
  ///
  /// Processing order (Requirements 8.1, 8.2):
  /// 1. Determine the *ending* army from [GameState.activeArmyId].
  /// 2. Apply income to the ending army via [EconomyService.applyTurnIncome].
  /// 3. Tick its ability cooldowns via [AbilityService.tickCooldowns].
  /// 4. Pass the turn to the next army (in [GameState.armies] order) that
  ///    still owns land; eliminated armies are skipped.
  /// 5. When play wraps around to the first army, increment
  ///    [GameState.currentTurn].
  /// 6. Check for victory; if found, set [GameState.phase] to
  ///    [GamePhase.victory] and populate [GameState.winnerId].
  ///
  /// All mutations are applied atomically — only the returned [GameState] copy
  /// reflects the new state; the input is never modified.
  GameState endTurn(GameState state);

  /// Returns `true` when [armyId] is the currently active army.
  bool isActiveArmy(GameState state, ArmyId armyId);
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [TurnService].
///
/// Depends on [EconomyService], [AbilityService], and [VictoryService], all
/// injected via constructor.
class TurnServiceImpl implements TurnService {
  const TurnServiceImpl({
    required EconomyService economyService,
    required AbilityService abilityService,
    required VictoryService victoryService,
  }) : _economy = economyService,
       _ability = abilityService,
       _victory = victoryService;

  final EconomyService _economy;
  final AbilityService _ability;
  final VictoryService _victory;

  // ─── endTurn ──────────────────────────────────────────────────────────────

  @override
  GameState endTurn(GameState state) {
    final endingArmyId = state.activeArmyId;

    // Steps 1–3 — income (diamonds + soldiers) and cooldowns for the ending
    // army. A bot on "Zor" difficulty receives extra soldiers.
    var endingArmy = state.activeArmy;
    final bonus =
        endingArmy.kind == ArmyKind.ai && state.difficulty == AiDifficulty.hard
        ? kHardAiBonusSoldiers
        : 0;
    endingArmy = _economy.applyTurnIncome(
      endingArmy,
      state.territories,
      bonusSoldiers: bonus,
    );
    endingArmy = _ability.tickCooldowns(endingArmy);

    // Steps 4–5 — next living army; a new round starts when play wraps.
    final order = [for (final a in state.armies) a.id];
    final alive = state.armiesAlive.toSet();
    final from = order.indexOf(endingArmyId);
    var nextIndex = from;
    for (var step = 1; step <= order.length; step++) {
      final i = (from + step) % order.length;
      if (alive.contains(order[i]) || step == order.length) {
        nextIndex = i;
        break;
      }
    }
    final nextTurn = nextIndex <= from
        ? state.currentTurn + 1
        : state.currentTurn;

    // Apply turn-based ability unlocks to every army for the turn that is
    // about to be played (Requirements 6.2–6.4).
    final armies = [
      for (final a in state.armies)
        _ability.applyTurnUnlocks(
          a.id == endingArmyId ? endingArmy : a,
          nextTurn,
        ),
    ];

    var nextState = state.copyWith(
      armies: armies,
      activeArmyId: order[nextIndex],
      currentTurn: nextTurn,
    );

    // Step 6 — check for victory; promote phase if a winner exists.
    final winnerId = _victory.checkVictory(nextState);
    if (winnerId != null) {
      nextState = nextState.copyWith(
        phase: GamePhase.victory,
        winnerId: winnerId,
      );
    }

    return nextState;
  }

  // ─── isActiveArmy ─────────────────────────────────────────────────────────

  @override
  bool isActiveArmy(GameState state, ArmyId armyId) {
    return state.activeArmyId == armyId;
  }
}
