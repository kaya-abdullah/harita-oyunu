/// Greedy AI agent for Harita: Kendi İmparatorluğunu Kur.
///
/// Plays a bot's turn: draws the free card, plays cards, sends bombers,
/// buys weapons and attacks — every other army (the players and the other
/// bots) is its enemy. How well it plays follows [GameState.difficulty].
library;

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

/// One move of a bot.
sealed class AiAction {
  const AiAction();
}

/// Draws the free card of the turn ("Kart Çek").
final class DrawCardAction extends AiAction {
  const DrawCardAction();

  @override
  String toString() => 'DrawCardAction()';
}

/// Sends soldiers (and a tank) from [sourceId] into [targetId].
final class AttackAction extends AiAction {
  const AttackAction({required this.sourceId, required this.targetId});

  final int sourceId;
  final int targetId;

  @override
  String toString() => 'AttackAction($sourceId → $targetId)';
}

/// Plays [ability] on [targetTerritoryId].
final class UseAbilityAction extends AiAction {
  const UseAbilityAction({
    required this.ability,
    required this.targetTerritoryId,
  });

  final AbilityType ability;
  final int targetTerritoryId;

  @override
  String toString() => 'UseAbilityAction($ability → $targetTerritoryId)';
}

/// Sends a bomber to [targetId].
final class BomberAction extends AiAction {
  const BomberAction({required this.targetId});

  final int targetId;

  @override
  String toString() => 'BomberAction($targetId)';
}

/// Buys [item] in the Weapon Shop.
final class PurchaseAction extends AiAction {
  const PurchaseAction({required this.item});

  final WeaponItem item;

  @override
  String toString() => 'PurchaseAction(${item.id})';
}

// ─── GreedyAiAgent ───────────────────────────────────────────────────────────

/// A greedy bot: every action is the best-looking one right now.
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

  /// Overrides the pause before each action (tests use zero).
  final Duration Function(int actionIndex)? _actionDelay;

  int _purchasesThisTurn = 0;

  Duration _delayFor(int i, int slowActions, int fastDelayMs) =>
      _actionDelay?.call(i) ??
      Duration(
        milliseconds: i < slowActions
            ? kAiActionDelayMinMs +
                  _rng.nextInt(kAiActionDelayMaxMs - kAiActionDelayMinMs + 1)
            : fastDelayMs,
      );

  /// Most actions per turn for each difficulty.
  static int maxActions(AiDifficulty d) => switch (d) {
    AiDifficulty.veryEasy => 4,
    AiDifficulty.medium => 14,
    AiDifficulty.hard => 40,
  };

  // ─── playTurn ─────────────────────────────────────────────────────────────

  /// Plays the active bot's whole turn (without ending it). Every action is
  /// reported through [onAction] as it happens, after a short pause, so the
  /// map can show it.
  Future<GameState> playTurn(
    GameState initialState, {
    int slowActions = kAiSlowActionCount,
    int fastDelayMs = kAiFastActionDelayMs,
    void Function(AiAction action, GameState before, GameState after)? onAction,
    bool Function()? shouldContinue,
  }) async {
    var state = initialState;
    final limit = maxActions(state.difficulty);
    _purchasesThisTurn = 0;

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
      if (action is PurchaseAction) _purchasesThisTurn++;
      onAction?.call(action, state, next);
      state = next;
    }
    return state;
  }

  // ─── nextAction ───────────────────────────────────────────────────────────

  /// The bot's next action, or `null` when its turn is over.
  AiAction? nextAction(GameState state, {int actionsTaken = 0}) {
    final view = _MapView(state);
    if (view.owned(view.me).isEmpty) return null;
    if (!state.activeArmy.hasDrawnCard) return const DrawCardAction();
    switch (state.difficulty) {
      case AiDifficulty.veryEasy:
        return _veryEasyAction(view);
      case AiDifficulty.medium:
        return _mediumAction(view, actionsTaken);
      case AiDifficulty.hard:
        return _hardAction(view);
    }
  }

  // ─── applyAction ──────────────────────────────────────────────────────────

  /// Applies [action]; returns [state] itself when it is rejected.
  GameState applyAction(AiAction action, GameState state) {
    final me = state.activeArmyId;
    try {
      return switch (action) {
        DrawCardAction() => _ability.drawCard(state, me).$1,
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
        BomberAction(:final targetId) => _combat.bomberRaid(
          state: state,
          armyId: me,
          targetTerritoryId: targetId,
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
    final army = view.state.activeArmy;
    final options = <AttackAction>[];
    for (final s in view.owned(me)) {
      if (s.unitCount < 2) continue;
      final attack = attackStrength(army, s);
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me) continue;
        // Timid: only cities it outnumbers two to one.
        if (attack >= defenceStrength(t) * 2) {
          options.add(AttackAction(sourceId: s.id, targetId: t.id));
        }
      }
    }
    if (options.isEmpty) return null;
    return options[_rng.nextInt(options.length)];
  }

  // ─── Orta ─────────────────────────────────────────────────────────────────

  AiAction? _mediumAction(_MapView view, int actionsTaken) {
    // A card now and then (roughly every other turn).
    if (actionsTaken <= 1 && _rng.nextBool()) {
      final use = _bestCard(view, attackOnly: true);
      if (use != null) return use;
    }

    final attack = _bestAttack(view, minOdds: kAiAttackOddsThreshold);
    if (attack != null) return attack;

    final bomber = _enablingBomber(view);
    if (bomber != null) return bomber;

    return _purchase(view.state, keep: 300);
  }

  // ─── Zor ──────────────────────────────────────────────────────────────────

  AiAction? _hardAction(_MapView view) {
    final card = _bestCard(view, attackOnly: false);
    if (card != null) return card;

    final purchase = _purchase(view.state, keep: 0);
    if (purchase != null) return purchase;

    // Soften a city first when that makes it winnable.
    final enabling = _enablingBomber(view);
    if (enabling != null) return enabling;

    final attack = _bestAttack(view, minOdds: 1.0);
    if (attack != null) return attack;

    return _harassBomber(view) ?? _consolidate(view);
  }

  // ─── Attacks ──────────────────────────────────────────────────────────────

  AttackAction? _bestAttack(_MapView view, {required double minOdds}) {
    final me = view.me;
    final army = view.state.activeArmy;
    final toEnemy = view.distanceToEnemies();
    AttackAction? best;
    var bestScore = double.negativeInfinity;
    for (final s in view.owned(me)) {
      if (s.unitCount < 2) continue;
      final attack = attackStrength(army, s);
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == me) continue;
        final defence = defenceStrength(t);
        if (attack <= defence || attack < defence * minOdds) continue;
        var score = t.ownerArmyId != null ? 40 + t.unitCount * 0.3 : 15.0;
        if (t.hasGoldMine) score += 60;
        if (t.hasDiamondMine) score += 70;
        score -= toEnemy[t.id] * 0.8;
        score += attack * 0.02;
        if (score > bestScore) {
          bestScore = score;
          best = AttackAction(sourceId: s.id, targetId: t.id);
        }
      }
    }
    return best;
  }

  /// Brings idle stacks from safe interior cities to the front.
  AttackAction? _consolidate(_MapView view) {
    final me = view.me;
    final toFront = view.distanceToFront();
    AttackAction? best;
    var bestUnits = 5;
    for (final s in view.owned(me)) {
      if (s.unitCount <= bestUnits || view.isFrontier(s)) continue;
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId != me || toFront[t.id] >= toFront[s.id]) continue;
        bestUnits = s.unitCount;
        best = AttackAction(sourceId: s.id, targetId: t.id);
        break;
      }
    }
    return best;
  }

  // ─── Bombers ──────────────────────────────────────────────────────────────

  /// A raid that makes an attack winnable next.
  BomberAction? _enablingBomber(_MapView view) {
    final army = view.state.activeArmy;
    if (army.bombersReady <= 0) return null;
    BomberAction? best;
    var bestGap = 1 << 30;
    for (final s in view.owned(view.me)) {
      if (s.unitCount < 2) continue;
      final attack = attackStrength(army, s);
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == view.me) continue;
        final gap = defenceStrength(t) - attack;
        if (gap < 0 || gap >= army.bombersReady * kBomberDamage) continue;
        if (gap < bestGap) {
          bestGap = gap;
          best = BomberAction(targetId: t.id);
        }
      }
    }
    return best;
  }

  /// A raid on the strongest enemy city next to the bot's land.
  BomberAction? _harassBomber(_MapView view) {
    if (view.state.activeArmy.bombersReady <= 0) return null;
    Territory? best;
    for (final s in view.owned(view.me)) {
      for (final adj in s.adjacentIds) {
        final t = view.byId(adj);
        if (t.ownerArmyId == null || t.ownerArmyId == view.me) continue;
        if (best == null || t.unitCount > best.unitCount) best = t;
      }
    }
    return best == null ? null : BomberAction(targetId: best.id);
  }

  // ─── Cards ────────────────────────────────────────────────────────────────

  UseAbilityAction? _bestCard(_MapView view, {required bool attackOnly}) {
    final army = view.state.activeArmy;
    const order = [
      AbilityType.nuclearBomb,
      AbilityType.atomBomb,
      AbilityType.megaBomba,
      AbilityType.bombardment,
      AbilityType.fireBomb,
    ];
    for (final type in order) {
      if (army.cardCount(type) <= 0) continue;
      final target = _bestCaptureTarget(view, type);
      if (target != null) {
        return UseAbilityAction(ability: type, targetTerritoryId: target);
      }
    }
    if (attackOnly) return null;

    if (army.cardCount(AbilityType.tribute) > 0) {
      Territory? best;
      var richest = 0;
      for (final t in view.state.territories) {
        final owner = t.ownerArmyId;
        if (owner == null || owner == view.me) continue;
        final balance = view.state.army(owner).diamondBalance;
        if (balance > richest) {
          richest = balance;
          best = t;
        }
      }
      if (best != null && richest >= 50) {
        return UseAbilityAction(
          ability: AbilityType.tribute,
          targetTerritoryId: best.id,
        );
      }
    }

    if (army.cardCount(AbilityType.soldierSpell) > 0) {
      final frontier = view.owned(view.me).where(view.isFrontier);
      if (frontier.isNotEmpty) {
        final city = frontier.reduce(
          (a, b) => a.unitCount >= b.unitCount ? a : b,
        );
        return UseAbilityAction(
          ability: AbilityType.soldierSpell,
          targetTerritoryId: city.id,
        );
      }
    }
    return null;
  }

  int? _bestCaptureTarget(_MapView view, AbilityType type) {
    final me = view.me;
    final state = view.state;
    final count = kAbilityCaptureTiles[type]!;
    final damage = kAbilityDamage[type]!;
    int? best;
    var bestValue = 0.0;
    for (final t in state.territories) {
      if (t.ownerArmyId == me) continue;
      if (!isValidTarget(state, me, type, t)) continue;
      var value = 0.0;
      for (final id in captureArea(state.territories, me, t.id, count)) {
        final c = view.byId(id);
        final isEnemy = c.ownerArmyId != null;
        if (c.unitCount > damage) {
          // Only soldiers lost: worth something against enemies.
          if (isEnemy) value += damage * 0.4;
          continue;
        }
        value += isEnemy ? 10 + c.unitCount * 1.0 : 3 + c.unitCount * 0.3;
        if (c.hasGoldMine) value += 60;
        if (c.hasDiamondMine) value += 50;
      }
      if (value > bestValue) {
        bestValue = value;
        best = t.id;
      }
    }
    return best;
  }

  // ─── Shop ─────────────────────────────────────────────────────────────────

  /// Most purchases per turn for each difficulty.
  static int maxPurchases(AiDifficulty d) => switch (d) {
    AiDifficulty.veryEasy => 0,
    AiDifficulty.medium => 1,
    AiDifficulty.hard => 2,
  };

  /// Buys a tank when out of them, otherwise the dearest affordable bomb
  /// card, always keeping [keep] diamonds and at most [maxPurchases] times
  /// a turn.
  PurchaseAction? _purchase(GameState state, {required int keep}) {
    if (_purchasesThisTurn >= maxPurchases(state.difficulty)) return null;
    final army = state.activeArmy;
    final budget = army.diamondBalance - keep;
    final items = _economy.getShopItems().where((i) => i.diamondCost <= budget);
    if (items.isEmpty) return null;
    if (army.tanks < 2) {
      for (final i in items) {
        if (i.tanks > 0) return PurchaseAction(item: i);
      }
    }
    final cards =
        items.where((i) => i.card != null && i.card!.captures).toList()
          ..sort((a, b) => b.diamondCost.compareTo(a.diamondCost));
    return cards.isEmpty ? null : PurchaseAction(item: cards.first);
  }
}

// ─── _MapView ────────────────────────────────────────────────────────────────

/// Cached lookups over one [GameState] for the active bot.
class _MapView {
  _MapView(this.state) : me = state.activeArmyId;

  final GameState state;
  final ArmyId me;
  List<Territory>? _mine;

  Territory byId(int id) => state.territories[id];

  List<Territory> owned(ArmyId army) {
    if (army == me) {
      return _mine ??= state.territories
          .where((t) => t.ownerArmyId == army)
          .toList();
    }
    return state.territories.where((t) => t.ownerArmyId == army).toList();
  }

  bool isFrontier(Territory t) =>
      t.adjacentIds.any((id) => byId(id).ownerArmyId != t.ownerArmyId);

  /// Steps from every city to the nearest enemy city.
  List<int> distanceToEnemies() => _bfs(
    state.territories.where(
      (t) => t.ownerArmyId != null && t.ownerArmyId != me,
    ),
  );

  /// Steps from every city to the nearest city that is not the bot's.
  List<int> distanceToFront() =>
      _bfs(state.territories.where((t) => t.ownerArmyId != me));

  List<int> _bfs(Iterable<Territory> sources) {
    final dist = List<int>.filled(state.territories.length, 1 << 20);
    final queue = <int>[];
    for (final t in sources) {
      dist[t.id] = 0;
      queue.add(t.id);
    }
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
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
