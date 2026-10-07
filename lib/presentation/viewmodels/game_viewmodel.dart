/// Game state management (ViewModel layer) for Harita: Kendi İmparatorluğunu Kur.
///
/// Provides the [GameNotifier] and all supporting Riverpod providers that wire
/// the domain services together and expose reactive game state to the UI.
library;

import 'dart:math';

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
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

/// Provides the [TurnService] singleton.
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

/// Random numbers for a new game's soldiers; tests fix the seed.
final gameRandomProvider = Provider<Random?>((ref) => null);

/// Waits [ms] milliseconds; tests can replace it to skip animations.
final animationDelayProvider = Provider<Future<void> Function(int ms)>(
  (ref) =>
      (ms) => Future<void>.delayed(Duration(milliseconds: ms)),
);

// ─── New-game settings ───────────────────────────────────────────────────────

/// The choices made in the New Game dialog.
typedef NewGameSettings = ({AiDifficulty difficulty, int bots, int humans});

/// Holds the settings for the next new game.
class NewGameSettingsNotifier extends Notifier<NewGameSettings> {
  @override
  NewGameSettings build() =>
      (difficulty: AiDifficulty.medium, bots: 5, humans: 1);

  /// Sets the settings used by the next [GameNotifier.build].
  void set({AiDifficulty? difficulty, int? bots, int? humans}) => state = (
    difficulty: difficulty ?? state.difficulty,
    bots: (bots ?? state.bots).clamp(1, kMaxBots).toInt(),
    humans: (humans ?? state.humans).clamp(1, kMaxHumans).toInt(),
  );
}

/// Provides the settings for the next new game.
final newGameSettingsProvider =
    NotifierProvider<NewGameSettingsNotifier, NewGameSettings>(
      NewGameSettingsNotifier.new,
    );

// ─── Selection and armed tools ──────────────────────────────────────────────

/// Holds the currently selected city id (`null` when nothing is selected).
class SelectedTerritoryNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Sets the selected city to [id].
  void select(int? id) => state = id;
}

/// Provides the currently selected city id, or `null` if none.
final selectedTerritoryProvider =
    NotifierProvider<SelectedTerritoryNotifier, int?>(
      SelectedTerritoryNotifier.new,
    );

/// What the next tap on the map does, besides selecting and attacking:
/// play a card or send a bomber.
sealed class ArmedTool {
  const ArmedTool();
}

/// A card is armed: tap a city to play it there.
final class ArmedCard extends ArmedTool {
  const ArmedCard(this.type);

  /// The card to play.
  final AbilityType type;

  @override
  bool operator ==(Object other) => other is ArmedCard && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// A bomber is armed: tap a city to bomb it.
final class ArmedBomber extends ArmedTool {
  const ArmedBomber();

  @override
  bool operator ==(Object other) => other is ArmedBomber;

  @override
  int get hashCode => 1;
}

/// Holds the armed tool, or `null`.
class ArmedToolNotifier extends Notifier<ArmedTool?> {
  @override
  ArmedTool? build() => null;

  /// Sets (or clears, with `null`) the armed tool.
  void set(ArmedTool? tool) => state = tool;
}

/// Provides the armed tool, or `null`.
final armedToolProvider = NotifierProvider<ArmedToolNotifier, ArmedTool?>(
  ArmedToolNotifier.new,
);

/// The armed card, or `null` (convenience view of [armedToolProvider]).
final armedAbilityProvider = Provider<AbilityType?>((ref) {
  final tool = ref.watch(armedToolProvider);
  return tool is ArmedCard ? tool.type : null;
});

// ─── Battle effects (animations) ─────────────────────────────────────────────

/// Kinds of animation drawn on the map.
enum BattleFxKind {
  /// Soldiers (and a tank) marching from one city to another.
  march,

  /// A bomber flying to a city and bombing it.
  bomber,

  /// An explosion on a city (cards).
  blast,

  /// A big mushroom-cloud blast (Atom / Nuclear bomb).
  nuke,
}

/// One animation on the map.
class BattleFx {
  BattleFx({
    required this.kind,
    required this.from,
    required this.to,
    required this.army,
    required this.durationMs,
    this.withTank = false,
  });

  /// What is shown.
  final BattleFxKind kind;

  /// Start point (world coordinates).
  final Offset from;

  /// End point (world coordinates).
  final Offset to;

  /// Whose units move.
  final ArmyId army;

  /// How long it lasts.
  final int durationMs;

  /// Whether a tank rolls along with the soldiers.
  final bool withTank;
}

/// Holds the animations currently playing.
class BattleFxNotifier extends Notifier<List<BattleFx>> {
  @override
  List<BattleFx> build() => const [];

  /// Starts [fx]; it is removed again once its time is up.
  void add(BattleFx fx) {
    state = [...state, fx];
    Future<void>.delayed(Duration(milliseconds: fx.durationMs + 200), () {
      if (ref.mounted) state = [...state]..remove(fx);
    });
  }
}

/// Provides the animations currently playing.
final battleFxProvider = NotifierProvider<BattleFxNotifier, List<BattleFx>>(
  BattleFxNotifier.new,
);

// ─── Feedback provider ───────────────────────────────────────────────────────

/// Kinds of user feedback produced by player actions. The UI maps each kind
/// to a localized message.
enum GameFeedbackKind {
  /// No such card in hand.
  noCard,

  /// The card cannot be used on the tapped city.
  invalidAbilityTarget,

  /// A card was armed; tap a city to use it.
  abilityArmed,

  /// A card was played.
  abilityUsed,

  /// The free card was drawn; [GameFeedback.value] is the card's index in
  /// [AbilityType.values].
  cardDrawn,

  /// The free card of this turn was already drawn.
  cardAlreadyDrawn,

  /// A bomber was armed; tap a city to bomb.
  bomberArmed,

  /// A bomber bombed a city; [GameFeedback.value] is the soldiers lost.
  bomberHit,

  /// No bomber is ready this turn.
  noBomber,

  /// The bomber cannot bomb that city.
  invalidBomberTarget,

  /// The Saldır button: how to attack.
  attackHint,

  /// Attack/move is not possible (not adjacent, too few soldiers).
  invalidAttack,

  /// A city was conquered.
  territoryConquered,

  /// A diamond mine was captured; [GameFeedback.value] holds the diamonds.
  diamondMineCaptured,

  /// A gold mine was captured; [GameFeedback.value] holds the diamonds.
  goldMineCaptured,

  /// Attack failed; defender held. [GameFeedback.value] is 1 when the tank
  /// was lost.
  attackRepelled,

  /// Soldiers moved between own cities.
  unitsMoved,

  /// Haraç Kes took [GameFeedback.value] diamonds.
  tributeTaken,

  /// Action attempted while it is not a human player's turn.
  notYourTurn,

  /// Not enough diamonds for a purchase.
  insufficientDiamonds,

  /// Something was bought.
  purchased,

  /// The phone passes to the next human player; [GameFeedback.value] is
  /// the [ArmyId.index] of that player.
  nextPlayer,
}

/// A single feedback event. A new instance is emitted for every event so
/// listeners fire even when the same kind repeats.
class GameFeedback {
  GameFeedback(this.kind, [this.value]);

  /// What happened.
  final GameFeedbackKind kind;

  /// Optional number associated with the event.
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

/// Central [Notifier] that owns the [GameState] and exposes every action a
/// human player can take: drag soldiers to a city, play a card, send a
/// bomber, draw a card, buy weapons, end the turn, save and load.
///
/// All actions are refused while bots play, while an animation runs and
/// once the game is over. After a human ends the turn the bots that follow
/// play automatically.
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
  bool _busy = false;

  TerritoryGraph get _graph => TerritoryGraph.bundled();

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  GameState build() {
    _aiRunning = false;
    _busy = false;
    final settings = ref.read(newGameSettingsProvider);
    return createInitialGameState(
      difficulty: settings.difficulty,
      botCount: settings.bots,
      humanCount: settings.humans,
      random: ref.read(gameRandomProvider),
    );
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  /// `true` when a human player may act right now.
  bool get isHumanTurn =>
      state.phase == GamePhase.playing &&
      state.activeArmy.isHuman &&
      !_aiRunning &&
      !_busy;

  /// `true` while a bot is taking its turn.
  bool get isAiTurn => _aiRunning || !state.activeArmy.isHuman;

  void _feedback(GameFeedbackKind kind, [int? value]) =>
      ref.read(gameFeedbackProvider.notifier).emit(GameFeedback(kind, value));

  void _fx(BattleFx fx) => ref.read(battleFxProvider.notifier).add(fx);

  Future<void> _wait(int ms) => ref.read(animationDelayProvider)(ms);

  Offset _pos(int id) => _graph.getPosition(id);

  /// Applies [next] and promotes the phase to victory if a winner exists.
  void _commit(GameState next) {
    final winner = _victory.checkVictory(next);
    if (winner != null && next.phase != GamePhase.victory) {
      next = next.copyWith(phase: GamePhase.victory, winnerId: winner);
    }
    state = next;
    if (state.phase == GamePhase.victory) {
      ref.read(armedToolProvider.notifier).set(null);
      _onGameOver();
    }
  }

  /// A finished game should not be offered for resuming.
  Future<void> _onGameOver() async {
    try {
      await _save.deleteSave();
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  bool _guardTurn() {
    if (state.phase == GamePhase.victory) return false;
    if (!isHumanTurn) {
      if (!_busy) _feedback(GameFeedbackKind.notYourTurn);
      return false;
    }
    return true;
  }

  // ─── Selection ───────────────────────────────────────────────────────────

  /// Records [id] as the selected city.
  void selectTerritory(int? id) {
    if (state.phase == GamePhase.victory) return;
    ref.read(selectedTerritoryProvider.notifier).select(id);
  }

  /// Handles a tap on city [id]:
  ///
  /// 1. An armed card or bomber is used on [id].
  /// 2. With one of the player's cities selected, a neighbouring [id] is
  ///    attacked (or reinforced when it is the player's own).
  /// 3. Otherwise [id] is selected.
  Future<void> onTerritoryTapped(int id) async {
    if (state.phase == GamePhase.victory) return;

    final armed = ref.read(armedToolProvider);
    if (armed != null && isHumanTurn) {
      switch (armed) {
        case ArmedCard(:final type):
          activateAbility(type, id);
        case ArmedBomber():
          await sendBomber(id);
      }
      return;
    }

    final selectedId = ref.read(selectedTerritoryProvider);
    if (isHumanTurn && selectedId != null && selectedId != id) {
      final source = state.territories[selectedId];
      if (source.ownerArmyId == state.activeArmyId &&
          source.adjacentIds.contains(id)) {
        await dispatchTroops(selectedId, id);
        return;
      }
    }
    selectTerritory(id);
  }

  // ─── Attack: drag soldiers from a city to another ────────────────────────

  /// Whether the active human may send soldiers from [sourceId] to
  /// [targetId] right now.
  bool canDispatch(int sourceId, int targetId) {
    if (!isHumanTurn || sourceId == targetId) return false;
    final source = state.territories[sourceId];
    return source.ownerArmyId == state.activeArmyId &&
        source.unitCount >= 2 &&
        source.adjacentIds.contains(targetId);
  }

  /// Sends all but one soldier (and a tank) from [sourceId] to [targetId]:
  /// they march there and then fight — or just move in when [targetId] is
  /// the player's own city.
  Future<void> dispatchTroops(int sourceId, int targetId) async {
    if (!_guardTurn()) return;
    if (!canDispatch(sourceId, targetId)) {
      _feedback(GameFeedbackKind.invalidAttack);
      return;
    }
    final me = state.activeArmyId;
    final own = state.territories[targetId].ownerArmyId == me;
    final tank = !own && state.activeArmy.tanksReady > 0;
    ref.read(armedToolProvider.notifier).set(null);

    _busy = true;
    try {
      _fx(
        BattleFx(
          kind: BattleFxKind.march,
          from: _pos(sourceId),
          to: _pos(targetId),
          army: me,
          durationMs: kMarchMs,
          withTank: tank,
        ),
      );
      await _wait(kMarchMs);
      if (!ref.mounted) return;

      final before = state;
      final GameState next;
      try {
        next = _combat.resolveAttack(
          state: state,
          attackingArmyId: me,
          sourceTerritoryId: sourceId,
          targetTerritoryId: targetId,
        );
      } on InvalidAttackException {
        _feedback(GameFeedbackKind.invalidAttack);
        return;
      }
      _commit(next);
      final won = state.territories[targetId].ownerArmyId == me;
      if (own) {
        _feedback(GameFeedbackKind.unitsMoved);
      } else if (won) {
        if (!_mineFeedback(before, me)) {
          _feedback(GameFeedbackKind.territoryConquered);
        }
      } else {
        final tankLost = state.army(me).tanks < before.army(me).tanks;
        _feedback(GameFeedbackKind.attackRepelled, tankLost ? 1 : 0);
      }
      selectTerritory(won ? targetId : sourceId);
    } finally {
      _busy = false;
    }
  }

  /// The Saldır button: explains how to attack.
  void showAttackHint() {
    ref.read(armedToolProvider.notifier).set(null);
    _feedback(GameFeedbackKind.attackHint);
  }

  // ─── Cards ───────────────────────────────────────────────────────────────

  /// Arms [type] so the next map tap plays it (or disarms when it is armed
  /// already or `null`).
  void armAbility(AbilityType? type) {
    if (state.phase == GamePhase.victory) return;
    final armed = ref.read(armedToolProvider.notifier);
    if (type == null || ref.read(armedToolProvider) == ArmedCard(type)) {
      armed.set(null);
      return;
    }
    if (!_guardTurn()) return;
    if (state.activeArmy.cardCount(type) <= 0) {
      _feedback(GameFeedbackKind.noCard);
      return;
    }
    armed.set(ArmedCard(type));
    _feedback(GameFeedbackKind.abilityArmed);
  }

  /// Plays [type] of the active army on [targetId].
  void activateAbility(AbilityType type, int targetId) {
    if (!_guardTurn()) return;
    final before = state;
    final me = state.activeArmyId;
    try {
      final next = _ability.activateAbility(
        state: state,
        armyId: me,
        ability: type,
        targetTerritoryId: targetId,
      );
      ref.read(armedToolProvider.notifier).set(null);
      _cardFx(type, me, targetId, before, next);
      _commit(next);
      if (type == AbilityType.tribute) {
        _feedback(
          GameFeedbackKind.tributeTaken,
          state.army(me).diamondBalance - before.army(me).diamondBalance,
        );
      } else {
        _feedback(GameFeedbackKind.abilityUsed, type.index);
        _mineFeedback(before, me);
      }
    } on NoCardException {
      ref.read(armedToolProvider.notifier).set(null);
      _feedback(GameFeedbackKind.noCard);
    } on InvalidTargetException {
      // Keep the card armed so the player can pick a valid target.
      _feedback(GameFeedbackKind.invalidAbilityTarget);
    }
  }

  void _cardFx(
    AbilityType type,
    ArmyId army,
    int targetId,
    GameState before,
    GameState after,
  ) {
    final big = type == AbilityType.atomBomb || type == AbilityType.nuclearBomb;
    final hit = type.captures
        ? captureArea(
            before.territories,
            army,
            targetId,
            kAbilityCaptureTiles[type]!,
          )
        : [targetId];
    for (final i in hit) {
      final nuke = big && i == targetId;
      _fx(
        BattleFx(
          kind: nuke ? BattleFxKind.nuke : BattleFxKind.blast,
          from: _pos(i),
          to: _pos(i),
          army: army,
          durationMs: nuke ? 1600 : 900,
        ),
      );
    }
  }

  /// Draws the free card of this turn ("Kart Çek").
  void drawCard() {
    if (!_guardTurn()) return;
    try {
      final (next, card) = _ability.drawCard(state, state.activeArmyId);
      _commit(next);
      _feedback(GameFeedbackKind.cardDrawn, card.index);
    } on CardAlreadyDrawnException {
      _feedback(GameFeedbackKind.cardAlreadyDrawn);
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

  // ─── Bombers ─────────────────────────────────────────────────────────────

  /// Arms a bomber so the next map tap bombs that city (or disarms it).
  void armBomber() {
    if (state.phase == GamePhase.victory) return;
    final armed = ref.read(armedToolProvider.notifier);
    if (ref.read(armedToolProvider) is ArmedBomber) {
      armed.set(null);
      return;
    }
    if (!_guardTurn()) return;
    if (state.activeArmy.bombersReady <= 0) {
      _feedback(GameFeedbackKind.noBomber);
      return;
    }
    armed.set(const ArmedBomber());
    _feedback(GameFeedbackKind.bomberArmed);
  }

  /// One bomber of the active army flies to [targetId] and bombs it.
  Future<void> sendBomber(int targetId) async {
    if (!_guardTurn()) return;
    final me = state.activeArmyId;
    if (state.activeArmy.bombersReady <= 0) {
      ref.read(armedToolProvider.notifier).set(null);
      _feedback(GameFeedbackKind.noBomber);
      return;
    }
    if (state.territories[targetId].ownerArmyId == me) {
      _feedback(GameFeedbackKind.invalidBomberTarget);
      return;
    }
    ref.read(armedToolProvider.notifier).set(null);
    _busy = true;
    try {
      _fx(
        BattleFx(
          kind: BattleFxKind.bomber,
          from: _airfield(me, targetId),
          to: _pos(targetId),
          army: me,
          durationMs: kBomberFlightMs,
        ),
      );
      await _wait(kBomberFlightMs);
      if (!ref.mounted) return;
      final before = state.territories[targetId].unitCount;
      try {
        _commit(
          _combat.bomberRaid(
            state: state,
            armyId: me,
            targetTerritoryId: targetId,
          ),
        );
      } on InvalidAttackException {
        _feedback(GameFeedbackKind.invalidBomberTarget);
        return;
      }
      _fx(
        BattleFx(
          kind: BattleFxKind.blast,
          from: _pos(targetId),
          to: _pos(targetId),
          army: me,
          durationMs: 700,
        ),
      );
      _feedback(
        GameFeedbackKind.bomberHit,
        before - state.territories[targetId].unitCount,
      );
    } finally {
      _busy = false;
    }
  }

  /// Where a bomber of [army] takes off for [targetId]: its city nearest
  /// to the target.
  Offset _airfield(ArmyId army, int targetId) {
    final to = _pos(targetId);
    Offset? best;
    for (final t in state.territories) {
      if (t.ownerArmyId != army) continue;
      final p = _pos(t.id);
      if (best == null || (p - to).distance < (best - to).distance) best = p;
    }
    return best ?? to;
  }

  // ─── Shop ────────────────────────────────────────────────────────────────

  /// Buys [item] for the active human. Returns `false` (and emits
  /// feedback) when the purchase is rejected.
  bool purchaseItem(WeaponItem item) {
    if (!_guardTurn()) return false;
    try {
      state = state.withArmy(_economy.purchaseItem(state.activeArmy, item));
      _feedback(GameFeedbackKind.purchased);
      return true;
    } on InsufficientDiamondsException {
      _feedback(GameFeedbackKind.insufficientDiamonds);
      return false;
    }
  }

  // ─── endTurn ─────────────────────────────────────────────────────────────

  /// Ends the human's turn: income, saving, then the bots that follow.
  void endTurn() {
    if (!isHumanTurn) return;
    ref.read(armedToolProvider.notifier).set(null);
    selectTerritory(null);
    _commit(_turn.endTurn(state));
    if (state.phase == GamePhase.victory) return;

    saveGame();

    if (!state.activeArmy.isHuman) {
      _runAiTurn();
    } else {
      _announceHuman();
    }
  }

  /// Tells the players whose turn it is when several share the phone.
  void _announceHuman() {
    if (state.humanIds.length > 1 && state.activeArmy.isHuman) {
      _feedback(GameFeedbackKind.nextPlayer, state.activeArmyId.index);
    }
  }

  // ─── Save / load ─────────────────────────────────────────────────────────

  /// Persists the current [GameState]; errors are swallowed.
  Future<void> saveGame() async {
    if (state.phase == GamePhase.victory) return;
    try {
      await _save.saveGameState(state);
    } catch (_) {
      // Persistence failure must never disrupt gameplay.
    }
  }

  /// Loads a previously saved [GameState]. Returns `true` when a save was
  /// loaded; bots whose turn it was continue automatically.
  Future<bool> loadGame() async {
    GameState? loaded;
    try {
      loaded = await _save.loadGameState();
    } catch (_) {
      loaded = null;
    }
    if (loaded == null || !ref.mounted) return false;
    _aiRunning = false;
    _busy = false;
    ref.read(selectedTerritoryProvider.notifier).select(null);
    ref.read(armedToolProvider.notifier).set(null);
    state = loaded;
    if (state.phase == GamePhase.playing && !state.activeArmy.isHuman) {
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

  // ─── Private: bot turns ──────────────────────────────────────────────────

  /// Plays the turns of all bots one after another until a human plays.
  Future<void> _runAiTurn() async {
    if (_aiRunning) return;
    _aiRunning = true;
    try {
      final bots = state.armies.where((a) => !a.isHuman).length;
      final many = bots > 2;
      final slowActions = many ? 2 : kAiSlowActionCount;
      final fastDelayMs = many ? kAiManyBotsFastDelayMs : kAiFastActionDelayMs;
      while (ref.mounted &&
          state.phase == GamePhase.playing &&
          !state.activeArmy.isHuman) {
        await _ai.playTurn(
          state,
          slowActions: slowActions,
          fastDelayMs: fastDelayMs,
          onAction: (action, before, after) {
            if (!ref.mounted) return;
            _botFx(action, before, after);
            _commit(after);
          },
          shouldContinue: () => ref.mounted && state.phase == GamePhase.playing,
        );
        if (!ref.mounted || state.phase == GamePhase.victory) return;
        _commit(_turn.endTurn(state));
      }
      if (ref.mounted && state.phase == GamePhase.playing) {
        await saveGame();
        _announceHuman();
      }
    } finally {
      _aiRunning = false;
    }
  }

  void _botFx(AiAction action, GameState before, GameState after) {
    final me = before.activeArmyId;
    switch (action) {
      case AttackAction(:final sourceId, :final targetId):
        _fx(
          BattleFx(
            kind: BattleFxKind.march,
            from: _pos(sourceId),
            to: _pos(targetId),
            army: me,
            durationMs: 450,
            withTank:
                before.army(me).tanksReady > 0 &&
                before.territories[targetId].ownerArmyId != me,
          ),
        );
      case BomberAction(:final targetId):
        _fx(
          BattleFx(
            kind: BattleFxKind.bomber,
            from: _airfield(me, targetId),
            to: _pos(targetId),
            army: me,
            durationMs: 600,
          ),
        );
      case UseAbilityAction(:final ability, :final targetTerritoryId):
        _cardFx(ability, me, targetTerritoryId, before, after);
      case DrawCardAction():
      case PurchaseAction():
        break;
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

/// Provides the human army whose view the screen shows.
final viewerArmyProvider = Provider<Army>((ref) {
  final state = ref.watch(gameProvider);
  return state.army(state.viewerId);
});

/// Provides `true` when a winner has been declared.
final isVictoryProvider = Provider<bool>(
  (ref) => ref.watch(gameProvider).phase == GamePhase.victory,
);

// ─── Initial state factory ────────────────────────────────────────────────────

/// Constructs the [GameState] for a brand-new game on the Africa city map.
///
/// - Each human ([humanCount], 1 or 2) starts with four neighbouring cities
///   holding [kHumanStartUnits] soldiers: the first in Morocco, the second
///   in South Africa.
/// - The [botCount] bots (1 … [kMaxBots]) own [kBotStartCities] cities
///   each. The first [kBotsNearPlayer] start close to the first player —
///   two steps away, never right next door; the others are spread over
///   Africa. Their soldiers are random ([kBotStartUnitsMin] …
///   [kBotStartUnitsMax]).
/// - Every other city is neutral with a random garrison
///   ([kNeutralUnitsMin] … [kNeutralUnitsMax]).
/// - Every army starts with [kStartDiamonds] diamonds, [kStartCards],
///   [kStartTanks] tanks and [kStartBombers] bombers.
GameState createInitialGameState({
  AiDifficulty difficulty = AiDifficulty.medium,
  int botCount = 5,
  int humanCount = 1,
  Random? random,
}) {
  final rng = random ?? Random();
  final graph = TerritoryGraph.bundled();
  final humans = humanCount.clamp(1, kMaxHumans).toInt();
  final bots = botCount.clamp(1, kMaxBots).toInt();
  final ids = ArmyId.values.take(humans + bots).toList();

  final owner = <int, ArmyId>{};
  final units = <int, int>{};
  for (var h = 0; h < humans; h++) {
    final cities = graph.humanStarts[h];
    for (var i = 0; i < cities.length; i++) {
      owner[cities[i]] = ids[h];
      units[cities[i]] = kHumanStartUnits[i % kHumanStartUnits.length];
    }
  }
  final homes = botHomes(graph, owner.keys.toSet(), bots);
  for (var b = 0; b < bots; b++) {
    for (final city in homes[b]) {
      owner[city] = ids[humans + b];
      units[city] =
          kBotStartUnitsMin +
          rng.nextInt(kBotStartUnitsMax - kBotStartUnitsMin + 1);
    }
  }

  final territories = [
    for (final t in graph.territories)
      t.copyWith(
        ownerArmyId: owner[t.id],
        unitCount:
            units[t.id] ??
            kNeutralUnitsMin +
                rng.nextInt(kNeutralUnitsMax - kNeutralUnitsMin + 1),
      ),
  ];

  return GameState(
    territories: territories,
    armies: [
      for (final id in ids)
        Army(
          id: id,
          kind: id.index < humans ? ArmyKind.human : ArmyKind.ai,
          diamondBalance: kStartDiamonds,
          cards: kStartCards,
          tanks: kStartTanks,
          bombers: kStartBombers,
        ),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
    winnerId: null,
    difficulty: difficulty,
  );
}

/// The start cities of [count] bots ([kBotStartCities] each), given the
/// cities the humans already hold ([taken]).
///
/// The first [kBotsNearPlayer] bots start two steps from the first player's
/// cities (spread apart); the others take the cities farthest from everyone
/// else. No bot city is next to another army's city.
List<List<int>> botHomes(TerritoryGraph graph, Set<int> taken, int count) {
  final occupied = {...taken};
  final firstPlayer = graph.humanStarts.first.where(taken.contains).toList();
  final fromPlayer = graph.distancesFrom(
    firstPlayer.isEmpty ? graph.humanStarts.first : firstPlayer,
  );
  final homes = <List<int>>[];

  bool free(int id) {
    if (occupied.contains(id)) return false;
    return !graph.territories[id].adjacentIds.any(occupied.contains);
  }

  for (var b = 0; b < count; b++) {
    final distToOccupied = graph.distancesFrom(occupied);
    final near = b < kBotsNearPlayer;
    int? start;
    for (final t in graph.territories) {
      if (!free(t.id)) continue;
      if (near && fromPlayer[t.id] != 2) continue;
      if (start == null) {
        start = t.id;
        continue;
      }
      // Near bots: spread around the player; others: as far as possible.
      final better = distToOccupied[t.id] > distToOccupied[start];
      if (better) start = t.id;
    }
    start ??= _anyFree(graph, occupied);
    if (start == null) break;
    final cities = [start];
    occupied.add(start);
    while (cities.length < kBotStartCities) {
      int? next;
      for (final adj in graph.territories[cities.last].adjacentIds) {
        if (occupied.contains(adj)) continue;
        final touchesOther = graph.territories[adj].adjacentIds.any(
          (n) => occupied.contains(n) && !cities.contains(n),
        );
        if (touchesOther) continue;
        if (near && fromPlayer[adj] < 2) continue;
        next = adj;
        break;
      }
      if (next == null) break;
      cities.add(next);
      occupied.add(next);
    }
    homes.add(cities);
  }
  return homes;
}

int? _anyFree(TerritoryGraph graph, Set<int> occupied) {
  for (final t in graph.territories) {
    if (!occupied.contains(t.id)) return t.id;
  }
  return null;
}
