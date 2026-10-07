/// Card service for Harita: Kendi İmparatorluğunu Kur.
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

/// Thrown when a card is aimed at a city it cannot be used on.
class InvalidTargetException implements Exception {
  const InvalidTargetException({
    required this.targetTerritoryId,
    required this.reason,
  });

  /// The city id that was rejected.
  final int targetTerritoryId;

  /// Human-readable explanation of why the target is invalid.
  final String reason;

  @override
  String toString() =>
      'InvalidTargetException: city $targetTerritoryId — $reason';
}

// ─── Card table ──────────────────────────────────────────────────────────────

/// How many cities each bomb card hits.
const Map<AbilityType, int> kAbilityCaptureTiles = {
  AbilityType.fireBomb: kFireBombCities,
  AbilityType.bombardment: kBombardmentCities,
  AbilityType.megaBomba: kMegaBombaCities,
  AbilityType.atomBomb: kAtomBombCities,
  AbilityType.nuclearBomb: kNuclearBombCities,
};

/// How many soldiers each bomb card kills in every city it hits.
const Map<AbilityType, int> kAbilityDamage = {
  AbilityType.fireBomb: kFireBombDamage,
  AbilityType.bombardment: kBombardmentDamage,
  AbilityType.megaBomba: kMegaBombaDamage,
  AbilityType.atomBomb: kAtomBombDamage,
  AbilityType.nuclearBomb: kNuclearBombDamage,
};

/// How likely each card is in the free draw ("Kart Çek"): common cards
/// often, the Nuclear Bomb rarely.
const Map<AbilityType, int> kCardDrawWeights = {
  AbilityType.fireBomb: 30,
  AbilityType.soldierSpell: 22,
  AbilityType.tribute: 14,
  AbilityType.bombardment: 16,
  AbilityType.megaBomba: 9,
  AbilityType.atomBomb: 4,
  AbilityType.nuclearBomb: 2,
};

/// Cards every army holds at game start.
const Map<AbilityType, int> kStartCards = {AbilityType.fireBomb: 1};

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Plays and deals cards.
abstract class AbilityService {
  /// Plays one [ability] card of [armyId] on [targetTerritoryId].
  ///
  /// - Bomb cards hit the target and the nearest cities around it that are
  ///   not the army's own, killing soldiers in each; a city left empty is
  ///   captured. Ateş Bombası 1 city (40), Bombardıman 2 (40), Mega Bomba
  ///   3 (60), Atom Bombası 4 (80), Nükleer Bomba 6 (100). Atom and
  ///   Nuclear bombs can hit any city; the others need a target next to
  ///   the army's land.
  /// - Asker Büyüsü adds [kSoldierSpellUnits] to an own city.
  /// - Haraç Kes takes up to [kTributeDiamonds] from the target's owner.
  ///
  /// Throws [NoCardException] without such a card and
  /// [InvalidTargetException] for a wrong target.
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  });

  /// Draws the free card of this turn for [armyId] ("Kart Çek"). Returns the
  /// new state and the card drawn.
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
        reason: 'No such city.',
      );
    }
    checkTarget(state, armyId, ability, target);

    final spent = army.withCard(ability, -1);
    switch (ability) {
      case AbilityType.soldierSpell:
        return state
            .withArmy(spent)
            .copyWith(
              territories: [
                for (final t in state.territories)
                  t.id == target.id
                      ? t.copyWith(unitCount: t.unitCount + kSoldierSpellUnits)
                      : t,
              ],
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
              territories: bombArea(
                state.territories,
                armyId,
                target.id,
                kAbilityCaptureTiles[ability]!,
                kAbilityDamage[ability]!,
              ),
            );
        return awardMineRewards(state, next, armyId);
    }
  }

  @override
  (GameState, AbilityType) drawCard(GameState state, ArmyId armyId) {
    final army = state.army(armyId);
    if (army.hasDrawnCard) throw const CardAlreadyDrawnException();
    final total = kCardDrawWeights.values.fold(0, (a, b) => a + b);
    var roll = _rng.nextInt(total);
    var card = AbilityType.fireBomb;
    for (final e in kCardDrawWeights.entries) {
      if (roll < e.value) {
        card = e.key;
        break;
      }
      roll -= e.value;
    }
    final updated = army.withCard(card, 1).copyWith(hasDrawnCard: true);
    return (state.withArmy(updated), card);
  }
}

/// Throws [InvalidTargetException] unless [ability] of [armyId] may be
/// played on [target].
void checkTarget(
  GameState state,
  ArmyId armyId,
  AbilityType ability,
  Territory target,
) {
  void reject(String reason) => throw InvalidTargetException(
    targetTerritoryId: target.id,
    reason: reason,
  );
  if (ability.targetsOwnCity) {
    if (target.ownerArmyId != armyId) reject('Pick one of your own cities.');
    return;
  }
  if (target.ownerArmyId == armyId) reject('Pick a city that is not yours.');
  if (ability == AbilityType.tribute) {
    if (target.ownerArmyId == null) reject('Pick a city that has an owner.');
    return;
  }
  if (!ability.hitsAnywhere &&
      !target.adjacentIds.any(
        (id) => _byId(state.territories, id)?.ownerArmyId == armyId,
      )) {
    reject('The target must be next to your land.');
  }
}

/// Whether [ability] of [armyId] may be played on [target].
bool isValidTarget(
  GameState state,
  ArmyId armyId,
  AbilityType ability,
  Territory target,
) {
  try {
    checkTarget(state, armyId, ability, target);
    return true;
  } on InvalidTargetException {
    return false;
  }
}

// ─── City capture ────────────────────────────────────────────────────────────

/// Returns the ids of the (up to) [count] cities a card aimed at
/// [targetId] hits for [armyId]: the target itself, then the nearest
/// cities not owned by [armyId] (breadth-first through such cities).
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
    // Prefer enemy cities (more soldiers first) over neutral land.
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

/// Returns [territories] after a bomb of [armyId] hit the [captureArea]
/// of [targetId]: every city there loses [damage] soldiers, and a city left
/// without soldiers is taken over by [armyId] with [kCapturedCityUnits].
List<Territory> bombArea(
  List<Territory> territories,
  ArmyId armyId,
  int targetId,
  int count,
  int damage,
) {
  final area = captureArea(territories, armyId, targetId, count).toSet();
  return [
    for (final t in territories)
      if (!area.contains(t.id))
        t
      else if (t.unitCount <= damage)
        t.copyWith(ownerArmyId: armyId, unitCount: kCapturedCityUnits)
      else
        t.copyWith(unitCount: t.unitCount - damage),
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
