/// Game state management (ViewModel layer) for Harita: Kendi İmparatorluğunu Kur.
///
/// Provides the [GameNotifier] and all supporting Riverpod providers that wire
/// the domain services together and expose reactive game state to the UI.
library;

import 'dart:math' show Random, min;

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
  (ref) => AbilityServiceImpl(),
);

/// Provides the [EconomyService] singleton.
final economyServiceProvider = Provider<EconomyService>(
  (ref) => const EconomyServiceImpl(),
);

/// Provides the [VictoryService] singleton.
final victoryServiceProvider = Provider<VictoryService>(
  (ref) => const VictoryServiceImpl(),
);

/// Provides the [TurnService] singleton, wired with its dependencies.
final turnServiceProvider = Provider<TurnService>(
  (ref) => TurnServiceImpl(
    economyService: ref.watch(economyServiceProvider),
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

/// Holds how many bots (1 … [kMaxBots]) join the next new game.
class NewGameBotCountNotifier extends Notifier<int> {
  @override
  int build() => kMaxBots;

  /// Sets the bot count used by the next [GameNotifier.build].
  void set(int count) => state = count.clamp(1, kMaxBots);
}

/// Provides the number of bots for the next new game.
final newGameBotCountProvider = NotifierProvider<NewGameBotCountNotifier, int>(
  NewGameBotCountNotifier.new,
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
  /// No such card in hand.
  noCard,

  /// The free card was drawn; [GameFeedback.value] is the card's index in
  /// [AbilityType.values].
  cardDrawn,

  /// The free card of this turn was already drawn.
  cardAlreadyDrawn,

  /// Haraç Kes took [GameFeedback.value] diamonds.
  tributeTaken,

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

  /// A diamond mine was captured; [GameFeedback.value] holds the diamonds
  /// earned.
  diamondMineCaptured,

  /// A gold mine (base) was captured; [GameFeedback.value] holds the
  /// diamonds earned.
  goldMineCaptured,

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

  /// Not enough diamonds for a purchase.
  insufficientDiamonds,
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
      botCount: ref.read(newGameBotCountProvider),
    );
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  /// `true` when the human player may act right now.
  bool get isHumanTurn =>
      state.phase == GamePhase.playing &&
      state.activeArmy.kind == ArmyKind.human &&
      !_aiRunning;

  /// `true` while a bot is taking its turn.
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
    final before = state;
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
        if (!_mineFeedback(before, attacker)) {
          _feedback(GameFeedbackKind.territoryConquered);
        }
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
    if (state.activeArmy.cardCount(type) <= 0) {
      _feedback(GameFeedbackKind.noCard);
      return;
    }
    armedNotifier.set(type);
    _feedback(GameFeedbackKind.abilityArmed);
  }

  /// Draws the free card of this turn ("Kart Çek") for the player.
  void drawCard() {
    if (state.phase == GamePhase.victory) return;
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    try {
      final (next, card) = _ability.drawCard(state, state.activeArmyId);
      state = next;
      _feedback(GameFeedbackKind.cardDrawn, card.index);
    } on CardAlreadyDrawnException {
      _feedback(GameFeedbackKind.cardAlreadyDrawn);
    }
  }

  /// Activates [type] for the active army targeting [targetId].
  ///
  /// Emits [GameFeedback] describing failures (no such card, invalid
  /// target).
  void activateAbility(AbilityType type, int targetId) {
    if (state.phase == GamePhase.victory) return;
    if (!isHumanTurn) {
      _feedback(GameFeedbackKind.notYourTurn);
      return;
    }
    final before = state;
    try {
      final next = _ability.activateAbility(
        state: state,
        armyId: state.activeArmyId,
        ability: type,
        targetTerritoryId: targetId,
      );
      ref.read(armedAbilityProvider.notifier).set(null);
      final me = before.activeArmyId;
      _commit(next);
      if (type == AbilityType.tribute) {
        _feedback(
          GameFeedbackKind.tributeTaken,
          state.army(me).diamondBalance - before.army(me).diamondBalance,
        );
      } else {
        _feedback(GameFeedbackKind.abilityUsed);
        _mineFeedback(before, me);
      }
    } on NoCardException {
      ref.read(armedAbilityProvider.notifier).set(null);
      _feedback(GameFeedbackKind.noCard);
    } on InvalidTargetException {
      // Keep the ability armed so the player can pick a valid target.
      _feedback(GameFeedbackKind.invalidAbilityTarget);
    } on StateError {
      _feedback(GameFeedbackKind.invalidAbilityTarget);
    }
  }

  /// Emits a diamond / gold mine message if [army] captured mines since
  /// [before]. Returns `true` when it did.
  bool _mineFeedback(GameState before, ArmyId army) {
    final (diamond, gold) = capturedMines(before, state, army);
    if (diamond == 0 && gold == 0) return false;
    final earned =
        state.army(army).diamondBalance - before.army(army).diamondBalance;
    _feedback(
      diamond > 0
          ? GameFeedbackKind.diamondMineCaptured
          : GameFeedbackKind.goldMineCaptured,
      earned,
    );
    return true;
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
      state = state.withArmy(_economy.purchaseItem(state.activeArmy, item));
      return true;
    } on InsufficientDiamondsException {
      _feedback(GameFeedbackKind.insufficientDiamonds);
      return false;
    }
  }

  // ─── endTurn ─────────────────────────────────────────────────────────────

  /// Ends the human army's turn.
  ///
  /// Processing order:
  /// 1. Applies income, unlocks and cooldowns via [TurnService.endTurn].
  /// 2. Saves the game (Requirement 12.1).
  /// 3. Runs the turns of every bot that plays before the human again.
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

  /// Plays the turns of all bots (strength follows [GameState.difficulty])
  /// one after another, ending each, until it is the human's turn again.
  Future<void> _runAiTurn() async {
    if (_aiRunning) return;
    _aiRunning = true;
    try {
      // With many bots the first moves are shown more briefly, so a round
      // stays short.
      final bots = state.armies.where((a) => a.kind == ArmyKind.ai).length;
      final many = bots > 2;
      final slowActions = many ? 2 : kAiSlowActionCount;
      final fastDelayMs = many ? kAiManyBotsFastDelayMs : kAiFastActionDelayMs;
      while (ref.mounted &&
          state.phase == GamePhase.playing &&
          state.activeArmy.kind == ArmyKind.ai) {
        // Each action is published as it happens so the map animates.
        await _ai.playTurn(
          state,
          slowActions: slowActions,
          fastDelayMs: fastDelayMs,
          onAction: (s) {
            if (ref.mounted) _commit(s);
          },
          shouldContinue: () => ref.mounted && state.phase == GamePhase.playing,
        );
        if (!ref.mounted || state.phase == GamePhase.victory) return;

        // End this bot's turn (income, cooldowns, next army).
        _commit(_turn.endTurn(state));
      }
      if (ref.mounted && state.phase == GamePhase.playing) {
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
final activeArmyProvider = Provider<Army>(
  (ref) => ref.watch(gameProvider).activeArmy,
);

/// Provides `true` when a winner has been declared.
final isVictoryProvider = Provider<bool>(
  (ref) => ref.watch(gameProvider).phase == GamePhase.victory,
);

// ─── Initial state factory ────────────────────────────────────────────────────

/// Constructs the [GameState] for a brand-new game on the Africa city map.
///
/// Army 1 (human, blue) owns America, in the middle of Africa ("Amerika biz
/// olalım"): all its four cities, [kPlayerStartUnitsPerCity] soldiers in
/// each. Every other city belongs to a bot ("şehirleri yapay zeka kontrol
/// ediyor"): each of the [botCount] bots (1 … [kMaxBots]) owns its start
/// country next to America ([kStartUnitsPerCity] soldiers in each city) and
/// the cities nearest to it ([TerritoryGraph.regions]), which hold
/// [kNeutralCityMinUnits] … [kNeutralCityMaxUnits] soldiers (picked with
/// [random]). With fewer than [kMaxBots] bots the cities of the missing
/// bots belong to nobody.
///
/// Each army begins with [kStartDiamonds] diamonds, [kStartUnitPool]
/// reserve soldiers and [kStartCards] (two Fire Bomb cards).
GameState createInitialGameState({
  AiDifficulty difficulty = AiDifficulty.medium,
  int botCount = 1,
  Random? random,
}) {
  final rng = random ?? Random();
  final graph = TerritoryGraph.bundled();
  final maxBots = min(kMaxBots, graph.startCities.length - 1);
  final count = 1 + botCount.clamp(1, maxBots).toInt();
  final ids = ArmyId.values.take(count).toList();

  final home = {
    for (var i = 0; i < count; i++)
      for (final id in graph.startCities[i]) id,
  };
  ArmyId? ownerOf(int id) {
    final region = graph.regions[id];
    return region < count ? ids[region] : null;
  }

  int unitsOf(int id, ArmyId? owner) {
    if (owner == ArmyId.army1) return kPlayerStartUnitsPerCity;
    if (home.contains(id)) return kStartUnitsPerCity;
    return kNeutralCityMinUnits +
        rng.nextInt(kNeutralCityMaxUnits - kNeutralCityMinUnits + 1);
  }

  final territories = [
    for (final t in graph.territories)
      t.copyWith(
        unitCount: unitsOf(t.id, ownerOf(t.id)),
        ownerArmyId: ownerOf(t.id),
      ),
  ];

  return GameState(
    territories: territories,
    armies: [
      for (final id in ids)
        Army(
          id: id,
          kind: id == ArmyId.army1 ? ArmyKind.human : ArmyKind.ai,
          diamondBalance: kStartDiamonds,
          totalUnitPool: kStartUnitPool,
          cards: kStartCards,
        ),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
    winnerId: null,
    difficulty: difficulty,
  );
}
