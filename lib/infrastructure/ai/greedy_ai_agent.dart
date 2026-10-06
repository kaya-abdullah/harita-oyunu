/// AI agent for Harita: Kendi İmparatorluğunu Kur.
///
/// A fully local, rule-based bot — no external API calls, no internet access.
/// The agent picks one action at a time from the *current* [GameState] (so
/// later moves build on earlier conquests) and its strength depends on the
/// game's [AiDifficulty]:
///
/// - **Çok Kolay** (veryEasy): a few random, timid moves; no abilities/shop.
/// - **Orta** (medium): greedy expansion, attacks enemies at 1.5× odds,
///   occasionally uses an ability.
/// - **Zor** (hard): scores every winning attack (enemy bases and diamond
///   mines first), marches stacks toward the front, fires every ability at
///   the most valuable area and buys ability packs.
///
/// The agent always plays the active army ([GameState.activeArmyId]); every
/// other army — the human or another bot — is an enemy.
library;

import 'dart:collection';
import 'dart:math';

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

// ─── AI actions ──────────────────────────────────────────────────────────────

/// Base class for a single AI action.
sealed class AiAction {
  const AiAction();
}

/// Attack (or friendly move) from [sourceId] into [targetId].
final class AttackAction extends AiAction {
  const AttackAction({required this.sourceId, required this.targetId});

  /// The territory the AI is attacking from (owned by the AI).
  final int sourceId;

  /// The territory being attacked (or reinforced, if owned by the AI).
  final int targetId;

  @override
  String toString() => 'AttackAction(source: $sourceId → target: $targetId)';
}

/// Use a special ability targeting [targetTerritoryId].
final class UseAbilityAction extends AiAction {
  const UseAbilityAction({
    required this.ability,
    required this.targetTerritoryId,
  });

  /// The ability to activate.
  final AbilityType ability;

  /// The territory the ability is directed at.
  final int targetTerritoryId;

  @override
  String toString() =>
      'UseAbilityAction(ability: $ability, target: $targetTerritoryId)';
}

/// Purchase [item] from the Weapon Shop.
final class PurchaseAction extends AiAction {
  const PurchaseAction({required this.item});

  /// The item to buy.
  final WeaponItem item;

  @override
  String toString() => 'PurchaseAction(item: ${item.id})';
}

// ─── GreedyAiAgent ───────────────────────────────────────────────────────────

/// Rule-based AI opponent whose play strength follows [GameState.difficulty].
class GreedyAiAgent {
  GreedyAiAgent({
    required CombatService combat,
    required AbilityService ability,
    required EconomyService economy,
    Random? random,
    Duration Function(int actionIndex)? actionDelay,
  }) : _combat = combat,
       _ability = ability,
       _economy = economy,
       _rng = random ?? Random(),
       _actionDelay = actionDelay;

  final CombatService _combat;
  final AbilityService _ability;
  final EconomyService _economy;
  final Random _rng;

  /// Overrides the pause before each action (e.g. zero in simulations).
  final Duration Function(int actionIndex)? _actionDelay;

  Duration _delayFor(int i, int slowActions, int fastDelayMs) =>
      _actionDelay?.call(i) ??
      Duration(
        milliseconds: i < slowActions
            ? kAiActionDelayMinMs +
                  _rng.nextInt(kAiActionDelayMaxMs - kAiActionDelayMinMs + 1)
            : fastDelayMs,
      );

  /// Upper bound of actions the bot takes in one turn.
  static int maxActions(AiDifficulty d) => switch (d) {
    AiDifficulty.veryEasy => 3,
    AiDifficulty.medium => 12,
    AiDifficulty.hard => 35,
  };

  // ─── playTurn ─────────────────────────────────────────────────────────────

  /// Plays a whole AI turn (without ending it): deploys reinforcements, then
  /// repeatedly picks and applies [nextAction] until nothing useful is left
  /// or [maxActions] is reached.
  ///
  /// The first [slowActions] actions are spaced 300–500 ms apart so the
  /// player can follow them; later ones wait only [fastDelayMs] so long
  /// turns on the big map stay quick. [onAction] receives every intermediate
  /// state.
  Future<GameState> playTurn(
    GameState initialState, {
    int slowActions = kAiSlowActionCount,
    int fastDelayMs = kAiFastActionDelayMs,
    void Function(GameState state)? onAction,
    bool Function()? shouldContinue,
  }) async {
    var state = deployReinforcements(initialState);
    onAction?.call(state);
    final limit = maxActions(state.difficulty);

    for (var i = 0; i < limit; i++) {
      if (shouldContinue != null && !shouldContinue()) break;
      if (state.phase != GamePhase.playing) break;
      final action = nextAction(state, actionsTaken: i);
      if (action == null) break;

      await Future<void>.delayed(_delayFor(i, slowActions, fastDelayMs));
      if (shouldContinue != null && !shouldContinue()) break;

      final next = applyAction(action, state);
      // A rejected action would be chosen again; end the turn instead.
      if (identical(next, state)) break;
      state = next;
      onAction?.call(state);
    }
    return state;
  }

  // ─── nextAction ───────────────────────────────────────────────────────────

  /// Chooses the single best action for the AI in [state], or `null` when it
  /// has nothing worthwhile left to do this turn. Pure: never mutates [state].
  AiAction? nextAction(GameState state, {int actionsTaken = 0}) {
    final view = _MapView(state);
    if (view.owned(view.me).isEmpty) return null;
    switch (state.difficulty) {
      case AiDifficulty.veryEasy:
        return _veryEasyAction(view);
      case AiDifficulty.medium:
        return _mediumAction(view, actionsTaken);
      case AiDifficulty.hard:
        return _hardAction(view);
    }
  }

  // ─── deployReinforcements ─────────────────────────────────────────────────

  /// Places the active bot's undeployed unit pool onto its land.
  ///
  /// - veryEasy: on a random owned tile.
  /// - medium: on the strongest frontier tile.
  /// - hard: on the frontier tile closest to the enemy (biggest stack wins
  ///   ties), so the bot always pushes with one big army.
  GameState deployReinforcements(GameState state) {
    if (state.activeArmy.totalUnitPool <= 0) return state;
    final view = _MapView(state);
    final me = view.me;
    final owned = view.owned(me).where(_hasRoom).toList();
    if (owned.isEmpty) return state;

    List<Territory> order;
    switch (state.difficulty) {
      case AiDifficulty.veryEasy:
        order = [...owned]..shuffle(_rng);
      case AiDifficulty.medium:
        final frontier = owned.where(view.isFrontier).toList();
        order = (frontier.isEmpty ? owned : frontier)
          ..sort((a, b) => b.unitCount.compareTo(a.unitCount));
      case AiDifficulty.hard:
        final toEnemy = view.distanceToEnemies();
        final frontier = owned.where(view.isFrontier).toList();
        order = (frontier.isEmpty ? owned : frontier)
          ..sort((a, b) {
            final d = toEnemy[a.id].compareTo(toEnemy[b.id]);
            return d != 0 ? d : b.unitCount.compareTo(a.unitCount);
          });
    }

    var result = state;
    for (final t in order) {
      if (result.activeArmy.totalUnitPool <= 0) break;
      result = _economy.deployUnits(result, me, t.id);
    }
    return result;
  }

  // ─── applyAction ──────────────────────────────────────────────────────────

  /// Applies [action] to [state]. Returns [state] itself (identical) when the
  /// action is no longer valid, so a stale decision can never crash a turn.
  GameState applyAction(AiAction action, GameState state) {
    final me = state.activeArmyId;
    try {
      return switch (action) {
        AttackAction(:final sourceId, :final targetId) => _combat.resolveAttack(
          state: state,
          attackingArmyId: me,
          sourceTerritoryId: sourceId,
          targetTerritoryId: targetId,
        ),
        UseAbilityAction(:final ability, :final targetTerritoryId) =>
          _ability.activateAbility(
            state: state,
            armyId: me,
            ability: ability,
            targetTerritoryId: targetTerritoryId,
          ),
        PurchaseAction(:final item) => state.withArmy(
          _economy.purchaseItem(state.activeArmy, item),
        ),
      };
    } on Exception {
      return state;
    } on StateError {
      return state;
    }
  }

  // ─── Çok Kolay ────────────────────────────────────────────────────────────

  AiAction? _veryEasyAction(_MapView view) {
    final me = view.me;
    final options = <AttackAction>[];
    for (final s in view.owned(me)) {
      if (s.unitCount < 2) continue;
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me) continue;
        // Timid: only empty land or enemies it outnumbers two to one.
        if (t.ownerArmyId == null || s.unitCount - 1 >= t.unitCount * 2) {
          options.add(AttackAction(sourceId: s.id, targetId: t.id));
        }
      }
    }
    if (options.isEmpty) return null;
    return options[_rng.nextInt(options.length)];
  }

  // ─── Orta ─────────────────────────────────────────────────────────────────

  AiAction? _mediumAction(_MapView view, int actionsTaken) {
    // An ability now and then (roughly every other turn).
    if (actionsTaken == 0 && _rng.nextBool()) {
      final use = _bestAbility(view, offensiveOnly: true, allowPacks: false);
      if (use != null) return use;
    }

    final me = view.me;
    AttackAction? best;
    var bestScore = double.negativeInfinity;
    for (final s in view.owned(me)) {
      if (s.unitCount < 2) continue;
      final attackers = s.unitCount - 1;
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me) continue;
        final double score;
        if (t.ownerArmyId == null) {
          score =
              10.0 +
              (view.isBase(t) ? 20 : 0) +
              (t.hasDiamondMine ? 25 : 0) +
              attackers / 100;
        } else if (attackers >= t.unitCount * kAiAttackOddsThreshold &&
            attackers > t.unitCount) {
          score =
              15.0 +
              (view.isBase(t) ? 20 : 0) +
              (t.hasDiamondMine ? 25 : 0) +
              attackers / 100;
        } else {
          continue;
        }
        if (score > bestScore) {
          bestScore = score;
          best = AttackAction(sourceId: s.id, targetId: t.id);
        }
      }
    }
    if (best != null) return best;

    final purchase = _cheapestUsefulPurchase(view.state);
    return purchase;
  }

  // ─── Zor ──────────────────────────────────────────────────────────────────

  AiAction? _hardAction(_MapView view) {
    // 1. Fire every available ability at the most valuable area first.
    final ability = _bestAbility(view, offensiveOnly: false, allowPacks: true);
    if (ability != null) return ability;

    // 2. Buy an ability pack when rich enough (keeps the pressure up).
    final purchase = _bestPackPurchase(view.state);
    if (purchase != null) return purchase;

    // 3. The best guaranteed-win attack.
    final me = view.me;
    final toEnemy = view.distanceToEnemies();
    AttackAction? best;
    var bestScore = double.negativeInfinity;
    for (final s in view.owned(me)) {
      if (s.unitCount < 2) continue;
      final attackers = s.unitCount - 1;
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me) continue;
        if (attackers <= t.unitCount) continue; // would lose — never do it
        var score = 0.0;
        final enemy = t.ownerArmyId;
        if (enemy != null) {
          score += 40 + t.unitCount * 0.5;
          if (view.isBase(t)) score += 120;
          // Finishing off isolated enemy tiles cuts the enemy apart.
          if (!view.hasFriendlyNeighbour(t, enemy)) score += 15;
        } else {
          score += 12;
          if (view.isBase(t)) score += 60;
        }
        if (t.hasDiamondMine) score += 70;
        // March toward the player and keep big stacks moving.
        score -= toEnemy[t.id] * 0.8;
        score += attackers * 0.05;
        if (score > bestScore) {
          bestScore = score;
          best = AttackAction(sourceId: s.id, targetId: t.id);
        }
      }
    }
    if (best != null) return best;

    // 4. Bring idle interior stacks to the front.
    return _consolidate(view);
  }

  /// Moves an interior stack one step toward the nearest non-owned tile.
  AttackAction? _consolidate(_MapView view) {
    final me = view.me;
    final toFront = view.distanceToFront(me);
    AttackAction? best;
    var bestUnits = 2;
    for (final s in view.owned(me)) {
      if (s.unitCount <= bestUnits || view.isFrontier(s)) continue;
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId != me || toFront[t.id] >= toFront[s.id]) continue;
        if (!_hasRoom(t)) continue;
        bestUnits = s.unitCount;
        best = AttackAction(sourceId: s.id, targetId: t.id);
        break;
      }
    }
    return best;
  }

  // ─── Abilities ────────────────────────────────────────────────────────────

  /// Returns the most valuable ability use, or `null` if no ability is ready
  /// (or worth it). With [allowPacks], abilities on cooldown are still used
  /// when the army owns the matching shop pack.
  UseAbilityAction? _bestAbility(
    _MapView view, {
    required bool offensiveOnly,
    required bool allowPacks,
  }) {
    final me = view.me;
    final army = view.state.activeArmy;
    const order = [
      AbilityType.megaBomba,
      AbilityType.bombardment,
      AbilityType.fireBomb,
    ];
    for (final type in order) {
      if (!_canUse(army, type, allowPacks)) continue;
      final target = _bestCaptureTarget(view, kAbilityCaptureTiles[type]!);
      if (target != null) {
        return UseAbilityAction(ability: type, targetTerritoryId: target);
      }
    }
    if (offensiveOnly) return null;

    if (_canUse(army, AbilityType.soldierSpell, allowPacks)) {
      final frontier = view.owned(me).where(view.isFrontier).where(_hasRoom);
      if (frontier.isNotEmpty) {
        final tile = frontier.reduce(
          (a, b) => a.unitCount >= b.unitCount ? a : b,
        );
        return UseAbilityAction(
          ability: AbilityType.soldierSpell,
          targetTerritoryId: tile.id,
        );
      }
    }
    return null;
  }

  bool _canUse(Army army, AbilityType type, bool allowPacks) {
    final s = army.abilities[type];
    if (s == null || !s.isUnlocked) return false;
    if (!s.isOnCooldown) return true;
    return allowPacks &&
        army.inventory.any((i) => i.id == kAbilityPackItemIds[type]);
  }

  /// Picks the tile bordering AI land whose [captureArea] of [count] tiles is
  /// worth the most (enemy units, bases, enemy land), or `null` if none.
  int? _bestCaptureTarget(_MapView view, int count) {
    final me = view.me;
    int? best;
    var bestValue = 0.0;
    final tried = <int>{};
    for (final s in view.owned(me)) {
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me || !tried.add(adj)) continue;
        var value = 0.0;
        for (final id in captureArea(view.state.territories, me, adj, count)) {
          final c = view.byId(id);
          final isEnemy = c.ownerArmyId != null;
          value += isEnemy ? 10 + c.unitCount * 2.0 : 3;
          if (view.isBase(c)) value += isEnemy ? 60 : 25;
          if (c.hasDiamondMine) value += 50;
        }
        if (value > bestValue) {
          bestValue = value;
          best = adj;
        }
      }
    }
    return best;
  }

  // ─── Shop ─────────────────────────────────────────────────────────────────

  PurchaseAction? _cheapestUsefulPurchase(GameState state) {
    final army = state.activeArmy;
    final affordable =
        _economy
            .getEligibleShopItems(army, state.currentTurn)
            .where((i) => i.diamondCost <= army.diamondBalance)
            .where((i) => !army.inventory.any((owned) => owned.id == i.id))
            .toList()
          ..sort((a, b) => a.diamondCost.compareTo(b.diamondCost));
    return affordable.isEmpty ? null : PurchaseAction(item: affordable.first);
  }

  PurchaseAction? _bestPackPurchase(GameState state) {
    final army = state.activeArmy;
    final affordable =
        _economy
            .getEligibleShopItems(army, state.currentTurn)
            .where((i) => i.diamondCost <= army.diamondBalance)
            .where((i) => !army.inventory.any((owned) => owned.id == i.id))
            .toList()
          ..sort((a, b) => b.diamondCost.compareTo(a.diamondCost));
    return affordable.isEmpty ? null : PurchaseAction(item: affordable.first);
  }

  static bool _hasRoom(Territory t) =>
      t.baseCapacity == null || t.unitCount < t.baseCapacity!;
}

// ─── _MapView ────────────────────────────────────────────────────────────────

/// Read-only helper over a [GameState] with O(1) tile lookup and BFS maps.
class _MapView {
  _MapView(this.state)
    : me = state.activeArmyId,
      _byId = {for (final t in state.territories) t.id: t};

  final GameState state;

  /// The bot that is playing.
  final ArmyId me;
  final Map<int, Territory> _byId;
  final Map<ArmyId, List<Territory>> _owned = {};

  Territory byId(int id) => _byId[id]!;

  List<Territory> owned(ArmyId army) => _owned[army] ??= state.territories
      .where((t) => t.ownerArmyId == army)
      .toList();

  bool isBase(Territory t) => t.type != TerritoryType.normal;

  /// `true` when [t] touches a tile its owner does not own.
  bool isFrontier(Territory t) =>
      t.adjacentIds.any((id) => byId(id).ownerArmyId != t.ownerArmyId);

  bool hasFriendlyNeighbour(Territory t, ArmyId army) =>
      t.adjacentIds.any((id) => byId(id).ownerArmyId == army);

  /// Steps from every tile to the nearest tile owned by another army.
  List<int> distanceToEnemies() => _bfs(
    state.territories.where(
      (t) => t.ownerArmyId != null && t.ownerArmyId != me,
    ),
  );

  /// Steps from every tile to the nearest tile *not* owned by [army].
  List<int> distanceToFront(ArmyId army) =>
      _bfs(state.territories.where((t) => t.ownerArmyId != army));

  List<int> _bfs(Iterable<Territory> sources) {
    final maxId = state.territories.fold<int>(0, (m, t) => max(m, t.id));
    final dist = List<int>.filled(maxId + 1, 1 << 20);
    final queue = Queue<int>();
    for (final t in sources) {
      dist[t.id] = 0;
      queue.add(t.id);
    }
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      for (final adj in byId(id).adjacentIds) {
        if (dist[adj] > dist[id] + 1) {
          dist[adj] = dist[id] + 1;
          queue.add(adj);
        }
      }
    }
    return dist;
  }
}
