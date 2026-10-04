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
  /// 3. Tick cooldowns (and increment Direct Laser charge) for the ending army
  ///    via [AbilityService.tickCooldowns].
  /// 4. Switch [GameState.activeArmyId] to the other army.
  /// 5. If switching FROM army2 BACK TO army1, increment [GameState.currentTurn].
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
    final nextArmyId = endingArmyId == ArmyId.army1
        ? ArmyId.army2
        : ArmyId.army1;

    // Step 1 — resolve the ending army object.
    var endingArmy = endingArmyId == ArmyId.army1 ? state.army1 : state.army2;

    // Step 2 — apply income (Elma + soldiers) to the ending army, based on
    //           the current territory ownership snapshot (Requirements 8.2).
    //           A bot on "Zor" difficulty receives extra soldiers.
    final bonus =
        endingArmy.kind == ArmyKind.ai && state.difficulty == AiDifficulty.hard
        ? kHardAiBonusSoldiers
        : 0;
    endingArmy = _economy.applyTurnIncome(
      endingArmy,
      state.territories,
      bonusSoldiers: bonus,
    );

    // Step 3 — tick cooldowns and increment Direct Laser charge.
    endingArmy = _ability.tickCooldowns(endingArmy);

    // Step 4 — switch active army.
    // Step 5 — increment turn counter when switching army2 → army1
    //           (i.e., both armies have acted).
    final nextTurn = (endingArmyId == ArmyId.army2)
        ? state.currentTurn + 1
        : state.currentTurn;

    // Step 4b — apply turn-based ability unlocks to both armies for the
    //            turn that is about to be played, so an ability unlocks
    //            exactly when its turn is reached (Requirements 6.2–6.4).
    final army1 = _ability.applyTurnUnlocks(
      endingArmyId == ArmyId.army1 ? endingArmy : state.army1,
      nextTurn,
    );
    final army2 = _ability.applyTurnUnlocks(
      endingArmyId == ArmyId.army2 ? endingArmy : state.army2,
      nextTurn,
    );

    // Build updated state with the modified army and the control transfer.
    var nextState = state.copyWith(
      army1: army1,
      army2: army2,
      activeArmyId: nextArmyId,
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
