/// Game state management (ViewModel layer) for Harita: Kendi İmparatorluğunu Kur.
///
/// Provides the [GameNotifier] and all supporting Riverpod providers that wire
/// the domain services together and expose reactive game state to the UI.
library;

import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/models/weapon_item.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/combat_service.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/domain/services/turn_service.dart';
import 'package:harita/domain/services/victory_service.dart';
import 'package:harita/infrastructure/ai/greedy_ai_agent.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';

// ─── Service providers ───────────────────────────────────────────────────────

/// Provides the [CombatService] singleton.
final combatServiceProvider = Provider<CombatService>(
  (ref) => const CombatServiceImpl(),
);

/// Provides the [AbilityService] singleton.
final abilityServiceProvider = Provider<AbilityService>(
  (ref) => const AbilityServiceImpl(),
);

/// Provides the [EconomyService] singleton.
final economyServiceProvider = Provider<EconomyService>(
  (ref) => const EconomyServiceImpl(),
);

/// Provides the [VictoryService] singleton.
final victoryServiceProvider = Provider<VictoryService>(
  (ref) => const VictoryServiceImpl(),
);

/// Provides the [TurnService] singleton, wired with its three dependencies.
final turnServiceProvider = Provider<TurnService>(
  (ref) => TurnServiceImpl(
    economyService: ref.watch(economyServiceProvider),
    abilityService: ref.watch(abilityServiceProvider),
    victoryService: ref.watch(victoryServiceProvider),
  ),
);

/// Provides the [GreedyAiAgent] singleton.
final aiAgentProvider = Provider<GreedyAiAgent>(
  (ref) => GreedyAiAgent(
    combat: ref.watch(combatServiceProvider),
    ability: ref.watch(abilityServiceProvider),
    economy: ref.watch(economyServiceProvider),
  ),
);

/// Provides the [SaveRepository] singleton.
final saveRepositoryProvider = Provider<SaveRepository>(
  (ref) => HiveSaveRepository(),
);

// ─── New-game difficulty provider ────────────────────────────────────────────

/// Holds the bot difficulty chosen in the main menu for the next new game.
class NewGameDifficultyNotifier extends Notifier<AiDifficulty> {
  @override
  AiDifficulty build() => AiDifficulty.medium;

  /// Sets the difficulty used by the next [GameNotifier.build].
  void set(AiDifficulty difficulty) => state = difficulty;
}

/// Provides the difficulty for the next new game.
final newGameDifficultyProvider =
    NotifierProvider<NewGameDifficultyNotifier, AiDifficulty>(
      NewGameDifficultyNotifier.new,
    );

// ─── Selected territory provider ─────────────────────────────────────────────

/// Minimal [Notifier] that holds the currently-selected territory id (`null`
/// when nothing is selected).
///
/// Kept separate from [gameProvider] so territory tap events do not force
/// full game-state rebuilds in unrelated widgets.
class SelectedTerritoryNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Sets the selected territory to [id].
  void select(int? id) => state = id;
}

/// Provides the currently selected territory id, or `null` if none.
final selectedTerritoryProvider =
    NotifierProvider<SelectedTerritoryNotifier, int?>(
      SelectedTerritoryNotifier.new,
    );

// ─── Armed ability provider ──────────────────────────────────────────────────

/// Holds the ability the human player has "armed" (tapped in the ability
/// panel) and that will be fired at the next territory tapped on the map.
/// `null` when no ability is armed.
class ArmedAbilityNotifier extends Notifier<AbilityType?> {
  @override
  AbilityType? build() => null;

  /// Sets (or clears, with `null`) the armed ability.
  void set(AbilityType? type) => state = type;
}

/// Provides the currently armed ability, or `null`.
final armedAbilityProvider =
    NotifierProvider<ArmedAbilityNotifier, AbilityType?>(
      ArmedAbilityNotifier.new,
    );

// ─── Feedback provider ───────────────────────────────────────────────────────

/// Kinds of user feedback produced by player actions. The UI maps each kind
/// to a localized message (Requirements 4.4, 6.8).
enum GameFeedbackKind {
  /// Ability not unlocked yet; [GameFeedback.value] holds the unlock turn.
  abilityLocked,

  /// Ability on cooldown; [GameFeedback.value] holds the turns remaining.
  abilityCooldown,

  /// Direct Laser not fully charged; [GameFeedback.value] holds the charge.
  laserCharging,

  /// Ability cannot be used on the tapped territory.
  invalidAbilityTarget,

  /// Ability was armed; tap a territory to use it.
  abilityArmed,

  /// Ability was used successfully.
  abilityUsed,

  /// Attack/move is not possible (not adjacent, too few units, base full).
  invalidAttack,

  /// Territory was conquered.
  territoryConquered,

  /// Attack failed; defender held.
  attackRepelled,

  /// Units moved between own territories.
  unitsMoved,

  /// Reinforcements deployed; [GameFeedback.value] holds the amount.
  unitsDeployed,

  /// Nothing to deploy / base full.
  cannotDeploy,

  /// Action attempted while it is not the human player's turn.
  notYourTurn,

  /// Not enough Elma for a purchase.
  insufficientElma,
}

/// A single feedback event. A new instance is emitted for every event so
/// listeners fire even when the same kind repeats.
class GameFeedback {
  GameFeedback(this.kind, [this.value]);

  /// What happened.
  final GameFeedbackKind kind;

  /// Optional number associated with the event (turn, count, …).
  final int? value;
}

/// Holds the most recent [GameFeedback] (or `null`).
class GameFeedbackNotifier extends Notifier<GameFeedback?> {
  @override
  GameFeedback? build() => null;

  /// Emits [feedback].
  void emit(GameFeedback? feedback) => state = feedback;
}

/// Provides the latest [GameFeedback] for UI snackbars/toasts.
final gameFeedbackProvider =
    NotifierProvider<GameFeedbackNotifier, GameFeedback?>(
      GameFeedbackNotifier.new,
    );

// ─── GameNotifier ─────────────────────────────────────────────────────────────

/// Central [Notifier] that owns the mutable [GameState] and exposes all
/// player-facing actions (attack, ability use, shop, deploy, end turn,
/// save/load).
///
/// All action methods guard against [GamePhase.victory] and against being
/// called while it is not the human player's turn (e.g. during the AI turn).
///
/// When [endTurn] results in the AI army becoming active, the
/// [GreedyAiAgent] is invoked automatically to execute the AI's turn.
class GameNotifier extends Notifier<GameState> {
  // ─── Lazily resolved service references ──────────────────────────────────

  CombatService get _combat => ref.read(combatServiceProvider);
  AbilityService get _ability => ref.read(abilityServiceProvider);
  EconomyService get _economy => ref.read(economyServiceProvider);
  VictoryService get _victory => ref.read(victoryServiceProvider);
  TurnService get _turn => ref.read(turnServiceProvider);
  SaveRepository get _save => ref.read(saveRepositoryProvider);
  GreedyAiAgent get _ai => ref.read(aiAgentProvider);

  bool _aiRunning = false;

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  GameState build() {
    _aiRunning = false;
    return createInitialGameState(
      difficulty: ref.read(newGameDifficultyProvider),
    );
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  /// `true` when the human player may act right now.
  bool get isHumanTurn =>
      state.phase == GamePhase.playing &&
      state.activeArmy.kind == ArmyKind.human &&
      !_aiRunning;

  /// `true` while the AI opponent is taking its turn.
  bool get isAiTurn => _aiRunning || state.activeArmy.kind == ArmyKind.ai;

  void _feedback(GameFeedbackKind kind, [int? value]) =>
      ref.read(gameFeedbackProvider.notifier).emit(GameFeedback(kind, value));

  /// Applies [next] and promotes the phase to victory if a winner exists.
  void _commit(GameState next) {
    final winner = _victory.checkVictory(next);
    if (winner != null && next.phase != GamePhase.victory) {
      next = next.copyWith(phase: GamePhase.victory, winnerId: winner);
    }
    state = next;
    if (state.phase == GamePhase.victory) {
      ref.read(armedAbilityProvider.notifier).set(null);
      _onGameOver();
    }
  }

  /// A finished game should not be offered for resuming (Requirement 12.2).
  Future<void> _onGameOver() async {
    try {
      await _save.deleteSave();
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  // ─── selectTerritory ─────────────────────────────────────────────────────

  /// Records [id] as the currently selected territory in
  /// [selectedTerritoryProvider].
  ///
  /// Guards against victory state so taps during the end screen are ignored.
  void selectTerritory(int? id) {
    if (state.phase == GamePhase.victory) return;
    ref.read(selectedTerritoryProvider.notifier).select(id);
  }

  // ─── onTerritoryTapped ───────────────────────────────────────────────────

  /// Handles a tap on territory [id] on the map:
  ///
  /// 1. If an ability is armed, fires it at [id].
  /// 2. If one of the player's territories is selected and [id] is adjacent
  ///    to it, attacks [id] (or moves units if [id] is the player's own).
  /// 3. Tapping the selected own territory again deploys reinforcements
  ///    from the unit pool onto it.
  /// 4. Otherwise selects [id].
  void onTerritoryTapped(int id) {
    if (state.phase == GamePhase.victory) return;

    final armed = ref.read(armedAbilityProvider);
    if (armed != null && isHumanTurn) {
      activateAbility(armed, id);
      return;
    }

    final selectedId = ref.read(selectedTerritoryProvider);
    if (isHumanTurn && selectedId != null) {
      final source = _territory(selectedId);
      if (source != null && source.ownerArmyId == state.activeArmyId) {
        if (selectedId == id) {
          deployReinforcements(id);
          return;
        }
        if (source.adjacentIds.contains(id)) {
          declareAttack(selectedId, id);
          return;
        }
      }
    }

    selectTerritory(id);
  }

  Territory? _territory(int id) {
    for (final t in state.territories) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ─── declareAttack ───────────────────────────────────────────────────────

  /// Resolves an attack from [sourceId] into [targetId] (or a unit move when
  /// [targetId] is already owned by the active army).
  void declareAttack(int sourceId, int targetId) {
    if (state.phase == GamePhase.victory) return;
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    final targetBefore = _territory(targetId);
    final wasOwn = targetBefore?.ownerArmyId == state.activeArmyId;
    try {
      final next = _combat.resolveAttack(
        state: state,
        attackingArmyId: state.activeArmyId,
        sourceTerritoryId: sourceId,
        targetTerritoryId: targetId,
      );
      final attacker = state.activeArmyId;
      _commit(next);
      final targetAfter = _territory(targetId);
      if (wasOwn) {
        _feedback(GameFeedbackKind.unitsMoved);
      } else if (targetAfter?.ownerArmyId == attacker) {
        _feedback(GameFeedbackKind.territoryConquered);
      } else {
        _feedback(GameFeedbackKind.attackRepelled);
      }
      // Keep the selection on the territory that now holds the army so the
      // player can keep advancing.
      selectTerritory(
        targetAfter?.ownerArmyId == attacker ? targetId : sourceId,
      );
    } on InvalidAttackException {
      _feedback(GameFeedbackKind.invalidAttack);
    }
  }

  // ─── Abilities ───────────────────────────────────────────────────────────

  /// Arms [type] so the next map tap fires it (or disarms when [type] is
  /// already armed or `null`). Emits locked/cooldown feedback instead of
  /// arming when the ability cannot be used (Requirement 6.8).
  void armAbility(AbilityType? type) {
    if (state.phase == GamePhase.victory) return;
    final armedNotifier = ref.read(armedAbilityProvider.notifier);
    if (type == null || ref.read(armedAbilityProvider) == type) {
      armedNotifier.set(null);
      return;
    }
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    final error = abilityBlocker(type);
    if (error != null) {
      ref.read(gameFeedbackProvider.notifier).emit(error);
      return;
    }
    armedNotifier.set(type);
    _feedback(GameFeedbackKind.abilityArmed);
  }

  /// Returns the feedback explaining why [type] cannot currently be used by
  /// the active army, or `null` if it is usable.
  GameFeedback? abilityBlocker(AbilityType type) {
    final army = state.activeArmy;
    final s = army.abilities[type];
    if (s == null || !s.isUnlocked) {
      return GameFeedback(
        GameFeedbackKind.abilityLocked,
        kAbilityUnlockTurns[type],
      );
    }
    final hasPack = army.inventory.any(
      (item) => item.id == kAbilityPackItemIds[type],
    );
    if (hasPack) return null;
    if (s.isOnCooldown) {
      return GameFeedback(
        GameFeedbackKind.abilityCooldown,
        s.cooldownTurnsRemaining,
      );
    }
    if (type == AbilityType.directLaser && !s.isFullyCharged) {
      return GameFeedback(GameFeedbackKind.laserCharging, s.chargeLevel ?? 0);
    }
    return null;
  }

  /// Activates [type] for the active army targeting [targetId].
  ///
  /// Emits [GameFeedback] describing failures (locked, cooldown, charge,
  /// invalid target).
  void activateAbility(AbilityType type, int targetId) {
    if (state.phase == GamePhase.victory) return;
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    try {
      final next = _ability.activateAbility(
        state: state,
        armyId: state.activeArmyId,
        ability: type,
        targetTerritoryId: targetId,
      );
      ref.read(armedAbilityProvider.notifier).set(null);
      _commit(next);
      _feedback(GameFeedbackKind.abilityUsed);
    } on LockedAbilityException catch (e) {
      ref.read(armedAbilityProvider.notifier).set(null);
      _feedback(GameFeedbackKind.abilityLocked, e.unlockTurn);
    } on CooldownActiveException catch (e) {
      ref.read(armedAbilityProvider.notifier).set(null);
      _feedback(GameFeedbackKind.abilityCooldown, e.turnsRemaining);
    } on InsufficientChargeException catch (e) {
      ref.read(armedAbilityProvider.notifier).set(null);
      _feedback(GameFeedbackKind.laserCharging, e.chargeLevel);
    } on InvalidTargetException {
      // Keep the ability armed so the player can pick a valid target.
      _feedback(GameFeedbackKind.invalidAbilityTarget);
    } on StateError {
      _feedback(GameFeedbackKind.invalidAbilityTarget);
    }
  }

  // ─── deployReinforcements ────────────────────────────────────────────────

  /// Places the active army's undeployed unit pool (Requirement 4.2) onto
  /// its own territory [territoryId], up to the base capacity.
  void deployReinforcements(int territoryId, {int? count}) {
    if (state.phase == GamePhase.victory) return;
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    final before = state.activeArmy.totalUnitPool;
    final next = _economy.deployUnits(
      state,
      state.activeArmyId,
      territoryId,
      count: count,
    );
    final deployed = before - next.activeArmy.totalUnitPool;
    if (deployed <= 0) {
      _feedback(GameFeedbackKind.cannotDeploy);
      return;
    }
    state = next;
    _feedback(GameFeedbackKind.unitsDeployed, deployed);
  }

  // ─── purchaseItem ────────────────────────────────────────────────────────

  /// Buys [item] for the human army. Returns `false` (and emits
  /// insufficient-funds feedback) when the purchase is rejected.
  bool purchaseItem(WeaponItem item) {
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return false;
    }
    try {
      final army = _economy.purchaseItem(state.activeArmy, item);
      state = state.activeArmyId == ArmyId.army1
          ? state.copyWith(army1: army)
          : state.copyWith(army2: army);
      return true;
    } on InsufficientElmaException {
      _feedback(GameFeedbackKind.insufficientElma);
      return false;
    }
  }

  // ─── endTurn ─────────────────────────────────────────────────────────────

  /// Ends the human army's turn.
  ///
  /// Processing order:
  /// 1. Applies income, unlocks and cooldowns via [TurnService.endTurn].
  /// 2. Saves the game (Requirement 12.1).
  /// 3. If the new active army is AI-controlled, runs the AI turn.
  void endTurn() {
    if (!isHumanTurn) return;
    ref.read(armedAbilityProvider.notifier).set(null);
    selectTerritory(null);
    _commit(_turn.endTurn(state));
    if (state.phase == GamePhase.victory) return;

    // Persist progress at the end of every turn (Requirement 12.1, 12.2).
    saveGame();

    if (state.activeArmy.kind == ArmyKind.ai) {
      _runAiTurn();
    }
  }

  // ─── openShop ────────────────────────────────────────────────────────────

  /// Kept for API compatibility; the shop UI is driven by [shopProvider].
  void openShop() {}

  // ─── saveGame ────────────────────────────────────────────────────────────

  /// Serialises and persists the current [GameState] via [SaveRepository].
  ///
  /// Any persistence error is swallowed so save failures cannot crash the game.
  Future<void> saveGame() async {
    if (state.phase == GamePhase.victory) return;
    try {
      await _save.saveGameState(state);
    } catch (_) {
      // Persistence failure must never disrupt gameplay.
    }
  }

  // ─── loadGame ────────────────────────────────────────────────────────────

  /// Loads a previously saved [GameState] and replaces the current state.
  ///
  /// Returns `true` when a save was loaded. If no save exists, or the save
  /// is corrupted, the current state is left unchanged and `false` is
  /// returned (Requirement 12.3). If the save was taken while the AI was
  /// about to play, the AI turn is resumed automatically.
  Future<bool> loadGame() async {
    GameState? loaded;
    try {
      loaded = await _save.loadGameState();
    } catch (_) {
      loaded = null;
    }
    if (loaded == null || !ref.mounted) return false;
    _aiRunning = false;
    ref.read(selectedTerritoryProvider.notifier).select(null);
    ref.read(armedAbilityProvider.notifier).set(null);
    state = loaded;
    if (state.phase == GamePhase.playing &&
        state.activeArmy.kind == ArmyKind.ai) {
      _runAiTurn();
    }
    return true;
  }

  /// Returns `true` if a resumable save exists.
  Future<bool> hasSave() async {
    try {
      return await _save.hasSave();
    } catch (_) {
      return false;
    }
  }

  // ─── Private: AI turn ────────────────────────────────────────────────────

  /// Plays the AI's full turn asynchronously (strength follows
  /// [GameState.difficulty]), then ends it and returns control to the human.
  Future<void> _runAiTurn() async {
    if (_aiRunning) return;
    _aiRunning = true;
    try {
      // Each action is published as it happens so the map animates.
      await _ai.playTurn(
        state,
        onAction: (s) {
          if (ref.mounted) _commit(s);
        },
        shouldContinue: () => ref.mounted && state.phase == GamePhase.playing,
      );
      if (!ref.mounted || state.phase == GamePhase.victory) return;

      // End the AI's turn (applies income, ticks cooldowns, switches army).
      _commit(_turn.endTurn(state));
      if (state.phase == GamePhase.playing) {
        await saveGame();
      }
    } finally {
      _aiRunning = false;
    }
  }
}

/// Root [NotifierProvider] for the entire [GameState].
final gameProvider = NotifierProvider<GameNotifier, GameState>(
  GameNotifier.new,
);

// ─── Derived selectors ────────────────────────────────────────────────────────

/// Provides the [Army] currently taking its turn.
final activeArmyProvider = Provider<Army>((ref) {
  final s = ref.watch(gameProvider);
  return s.activeArmyId == ArmyId.army1 ? s.army1 : s.army2;
});

/// Provides `true` when a winner has been declared.
final isVictoryProvider = Provider<bool>(
  (ref) => ref.watch(gameProvider).phase == GamePhase.victory,
);

// ─── Initial state factory ────────────────────────────────────────────────────

/// Constructs the [GameState] for a brand-new game on the Africa tile map.
///
/// Army 1 (human, blue) starts at one end of Africa (around Casablanca) and
/// Army 2 (bot, red) at the other end (around Cape Town): each owns the
/// [kStartTileCount] tiles closest to its start base, with
/// [kStartUnitsPerTile] units on each. Everything else starts neutral.
///
/// Each army begins with 50 Elma, 10 reserve soldiers and the default
/// abilities (`fireBomb` and the charge-based `directLaser` unlocked).
GameState createInitialGameState({
  AiDifficulty difficulty = AiDifficulty.medium,
}) {
  final graph = TerritoryGraph.bundled();
  final army1Zone = _startZone(graph, graph.playerStartId);
  final army2Zone = _startZone(graph, graph.botStartId);

  ArmyId? ownerOf(int id) => army1Zone.contains(id)
      ? ArmyId.army1
      : army2Zone.contains(id)
      ? ArmyId.army2
      : null;

  final territories = [
    for (final t in graph.territories)
      t.copyWith(
        unitCount: ownerOf(t.id) != null ? kStartUnitsPerTile : 0,
        ownerArmyId: ownerOf(t.id),
      ),
  ];

  final abilities = _buildInitialAbilities();

  Army army(ArmyId id, ArmyKind kind) => Army(
    id: id,
    kind: kind,
    elmaBalance: 50,
    totalUnitPool: 10,
    abilities: Map.unmodifiable(abilities),
    inventory: const [],
  );

  return GameState(
    territories: territories,
    army1: army(ArmyId.army1, ArmyKind.human),
    army2: army(ArmyId.army2, ArmyKind.ai),
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
    winnerId: null,
    difficulty: difficulty,
  );
}

// ─── Initial-state helpers ────────────────────────────────────────────────────

/// The [kStartTileCount] tiles nearest (breadth-first) to [startId].
Set<int> _startZone(TerritoryGraph graph, int startId) {
  final zone = <int>{startId};
  final queue = Queue<int>()..add(startId);
  while (queue.isNotEmpty && zone.length < kStartTileCount) {
    for (final adj in graph.getById(queue.removeFirst()).adjacentIds) {
      if (zone.length >= kStartTileCount) break;
      if (zone.add(adj)) queue.add(adj);
    }
  }
  return zone;
}

/// Constructs the default [AbilityState] map shared by both armies at game
/// start.
///
/// - [AbilityType.fireBomb] — unlocked (available at turn 0), no cooldown.
/// - [AbilityType.bombardment] — locked, no cooldown.
/// - [AbilityType.soldierSpell] — locked, no cooldown.
/// - [AbilityType.megaBomba] — locked, no cooldown.
/// - [AbilityType.directLaser] — locked (charge-based), chargeLevel 0,
///   maxCharge 3, cooldown 0.
Map<AbilityType, AbilityState> _buildInitialAbilities() {
  return {
    AbilityType.fireBomb: const AbilityState(
      type: AbilityType.fireBomb,
      isUnlocked: true,
    ),
    AbilityType.bombardment: const AbilityState(
      type: AbilityType.bombardment,
      isUnlocked: false,
    ),
    AbilityType.soldierSpell: const AbilityState(
      type: AbilityType.soldierSpell,
      isUnlocked: false,
    ),
    AbilityType.megaBomba: const AbilityState(
      type: AbilityType.megaBomba,
      isUnlocked: false,
    ),
    // Direct Laser is charge-based: always "unlocked", usable once charged.
    AbilityType.directLaser: const AbilityState(
      type: AbilityType.directLaser,
      isUnlocked: true,
      cooldownTurnsRemaining: 0,
      chargeLevel: 0,
      maxCharge: 3,
    ),
  };
}
