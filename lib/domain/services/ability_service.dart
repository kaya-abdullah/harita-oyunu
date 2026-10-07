/// Ability service for Harita: Kendi İmparatorluğunu Kur.
///
/// Plays cards ("kartlar") from an army's hand and deals the free card of
/// every turn ("Kart Çek").
library;

import 'dart:math';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/economy_service.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when an army plays a card it does not hold.
class NoCardException implements Exception {
  const NoCardException(this.ability);

  /// The missing card.
  final AbilityType ability;

  @override
  String toString() => 'NoCardException: no $ability card in hand.';
}

/// Thrown when the free card of this turn was already drawn.
class CardAlreadyDrawnException implements Exception {
  const CardAlreadyDrawnException();

  @override
  String toString() => 'CardAlreadyDrawnException';
}

/// Thrown when a card is aimed at a tile it cannot be used on.
class InvalidTargetException implements Exception {
  const InvalidTargetException({
    required this.targetTerritoryId,
    required this.reason,
  });

  /// The territory id that was rejected.
  final int targetTerritoryId;

  /// Human-readable explanation of why the target is invalid.
  final String reason;

  @override
  String toString() =>
      'InvalidTargetException: territory $targetTerritoryId is invalid — '
      '$reason';
}

// ─── Card table ──────────────────────────────────────────────────────────────

/// How likely each card is in the free draw ("Kart Çek"): common cards
/// often, the Nuclear Bomb rarely.
const Map<AbilityType, int> kCardDrawWeights = {
  AbilityType.fireBomb: 30,
  AbilityType.soldierSpell: 22,
  AbilityType.bombardment: 16,
  AbilityType.tribute: 14,
  AbilityType.megaBomba: 9,
  AbilityType.atomBomb: 6,
  AbilityType.nuclearBomb: 3,
};

/// Cards every army holds at game start.
const Map<AbilityType, int> kStartCards = {
  AbilityType.fireBomb: kStartFireBombs,
};

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Plays and deals cards.
abstract class AbilityService {
  /// Plays one [ability] card of [armyId] on [targetTerritoryId].
  ///
  /// - Capture cards take the target and the nearest tiles around it that
  ///   are not the army's own (see [captureArea]): Ateş Bombası 2,
  ///   Bombardıman 8, Mega Bomba 25 (target next to the army's land),
  ///   Atom Bombası 25 and Nükleer Bomba 40 (anywhere on the map). Captured
  ///   diamond mines pay [kDiamondMineReward], gold mines [kGoldMineReward].
  /// - Asker Büyüsü adds [kSoldierSpellUnits] to an own tile.
  /// - Haraç Kes takes up to [kTributeDiamonds] from the target's owner.
  ///
  /// Throws [NoCardException] without such a card in hand and
  /// [InvalidTargetException] for a wrong target. The original [state] is
  /// never mutated.
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  });

  /// Draws the free card of this turn for [armyId] ("Kart Çek"). Returns the
  /// new state and the card drawn. Atom and Nuclear Bombs come out of the
  /// draw only from turn [kTurnFirstBigBombDraw].
  ///
  /// Throws [CardAlreadyDrawnException] when it was drawn already.
  (GameState, AbilityType) drawCard(GameState state, ArmyId armyId);
}

// ─── Concrete implementation ─────────────────────────────────────────────────

/// Default implementation of [AbilityService].
class AbilityServiceImpl implements AbilityService {
  AbilityServiceImpl({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  @override
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  }) {
    final army = state.army(armyId);
    if (army.cardCount(ability) <= 0) throw NoCardException(ability);

    final target = _byId(state.territories, targetTerritoryId);
    if (target == null) {
      throw InvalidTargetException(
        targetTerritoryId: targetTerritoryId,
        reason: 'No such territory.',
      );
    }
    checkTarget(state, armyId, ability, target);

    final spent = army.withCard(ability, -1);
    switch (ability) {
      case AbilityType.soldierSpell:
        return state
            .withArmy(spent)
            .copyWith(
              territories: _applySoldierSpell(state.territories, target.id),
            );
      case AbilityType.tribute:
        final victim = state.army(target.ownerArmyId!);
        final paid = min(kTributeDiamonds, victim.diamondBalance);
        return state
            .withArmy(
              spent.copyWith(diamondBalance: army.diamondBalance + paid),
            )
            .withArmy(
              victim.copyWith(diamondBalance: victim.diamondBalance - paid),
            );
      case AbilityType.fireBomb:
      case AbilityType.bombardment:
      case AbilityType.megaBomba:
      case AbilityType.atomBomb:
      case AbilityType.nuclearBomb:
        final next = state
            .withArmy(spent)
            .copyWith(
              territories: captureTiles(
                state.territories,
                armyId,
                target.id,
                kAbilityCaptureTiles[ability]!,
              ),
            );
        return awardMineRewards(state, next, armyId);
    }
  }

  @override
  (GameState, AbilityType) drawCard(GameState state, ArmyId armyId) {
    final army = state.army(armyId);
    if (army.hasDrawnCard) throw const CardAlreadyDrawnException();
    // No Atom / Nuclear Bomb from the draw in the first turns.
    final weights = {
      for (final e in kCardDrawWeights.entries)
        if (state.currentTurn >= kTurnFirstBigBombDraw ||
            (e.key != AbilityType.atomBomb && e.key != AbilityType.nuclearBomb))
          e.key: e.value,
    };
    final total = weights.values.fold(0, (a, b) => a + b);
    var roll = _rng.nextInt(total);
    var card = AbilityType.fireBomb;
    for (final e in weights.entries) {
      if (roll < e.value) {
        card = e.key;
        break;
      }
      roll -= e.value;
    }
    final updated = army.withCard(card, 1).copyWith(hasDrawnCard: true);
    return (state.withArmy(updated), card);
  }

  /// Adds [kSoldierSpellUnits] to the friendly tile [targetTerritoryId],
  /// respecting base capacity (Requirement 5.4).
  List<Territory> _applySoldierSpell(
    List<Territory> territories,
    int targetTerritoryId,
  ) {
    return [
      for (final t in territories)
        if (t.id != targetTerritoryId)
          t
        else
          t.copyWith(
            unitCount:
                t.baseCapacity != null &&
                    t.unitCount + kSoldierSpellUnits > t.baseCapacity!
                ? max(t.baseCapacity!, t.unitCount)
                : t.unitCount + kSoldierSpellUnits,
          ),
    ];
  }
}

/// Throws [InvalidTargetException] unless [ability] of [armyId] may be
/// played on [target] (see [isValidTarget]).
void checkTarget(
  GameState state,
  ArmyId armyId,
  AbilityType ability,
  Territory target,
) {
  if (!isValidTarget(state, armyId, ability, target)) {
    throw InvalidTargetException(
      targetTerritoryId: target.id,
      reason: ability.targetsOwnTile
          ? 'Pick one of your own tiles.'
          : ability == AbilityType.tribute
          ? 'Pick a tile of another player.'
          : 'Pick a tile that is not yours'
                '${ability.hitsAnywhere ? '' : ' and borders your land'}.',
    );
  }
}

/// Whether [ability] of [armyId] may be played on [target]: Asker Büyüsü on
/// an own tile, Haraç Kes on another army's tile, Atom / Nuclear bombs on any
/// tile that is not the army's own, other bombs on such a tile next to the
/// army's land.
bool isValidTarget(
  GameState state,
  ArmyId armyId,
  AbilityType ability,
  Territory target,
) {
  if (ability.targetsOwnTile) return target.ownerArmyId == armyId;
  if (target.ownerArmyId == armyId) return false;
  if (ability == AbilityType.tribute) return target.ownerArmyId != null;
  if (ability.hitsAnywhere) return true;
  return target.adjacentIds.any(
    (id) => _byId(state.territories, id)?.ownerArmyId == armyId,
  );
}

// ─── Tile capture ("minik kare") ─────────────────────────────────────────────

/// How many tiles each offensive ability captures.
const Map<AbilityType, int> kAbilityCaptureTiles = {
  AbilityType.fireBomb: kFireBombTiles, // 2
  AbilityType.bombardment: kBombardmentTiles, // 8
  AbilityType.megaBomba: kMegaBombaTiles, // 25
  AbilityType.atomBomb: kAtomBombTiles, // 25
  AbilityType.nuclearBomb: kNuclearBombTiles, // 40
};

/// Returns the ids of the (up to) [count] tiles an ability aimed at
/// [targetId] captures for [armyId]: the target itself, then the nearest
/// tiles not owned by [armyId] (breadth-first through such tiles).
List<int> captureArea(
  List<Territory> territories,
  ArmyId armyId,
  int targetId,
  int count,
) {
  final target = _byId(territories, targetId);
  if (target == null || target.ownerArmyId == armyId || count <= 0) {
    return const [];
  }
  final result = <int>[targetId];
  final seen = {targetId};
  var frontier = [targetId];
  while (result.length < count && frontier.isNotEmpty) {
    final next = <int>[];
    for (final id in frontier) {
      for (final adj in _byId(territories, id)!.adjacentIds) {
        if (!seen.add(adj)) continue;
        final t = _byId(territories, adj);
        if (t == null || t.ownerArmyId == armyId) continue;
        next.add(adj);
      }
    }
    // Prefer enemy tiles (more units first) over empty neutral land.
    next.sort((a, b) {
      final ta = _byId(territories, a)!;
      final tb = _byId(territories, b)!;
      final ea = ta.ownerArmyId == null ? 0 : 1;
      final eb = tb.ownerArmyId == null ? 0 : 1;
      if (ea != eb) return eb - ea;
      if (ta.unitCount != tb.unitCount) return tb.unitCount - ta.unitCount;
      return a - b;
    });
    for (final id in next) {
      if (result.length >= count) break;
      result.add(id);
    }
    frontier = next;
  }
  return result;
}

/// Returns [territories] with the [captureArea] tiles taken over by
/// [armyId]; each captured tile keeps [kCapturedTileUnits] unit(s) and any
/// units previously stationed there are destroyed.
List<Territory> captureTiles(
  List<Territory> territories,
  ArmyId armyId,
  int targetId,
  int count,
) {
  final area = captureArea(territories, armyId, targetId, count).toSet();
  return [
    for (final t in territories)
      if (area.contains(t.id))
        t.copyWith(ownerArmyId: armyId, unitCount: kCapturedTileUnits)
      else
        t,
  ];
}

Territory? _byId(List<Territory> territories, int id) {
  if (id >= 0 && id < territories.length && territories[id].id == id) {
    return territories[id];
  }
  for (final t in territories) {
    if (t.id == id) return t;
  }
  return null;
}
