/// Economy service for Harita: Kendi İmparatorluğunu Kur.
///
/// Handles per-turn income, weapon shop purchases, and shop item eligibility.
library;

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/models/weapon_item.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when an army attempts to purchase an item with insufficient diamonds.
class InsufficientDiamondsException implements Exception {
  const InsufficientDiamondsException({
    required this.requiredDiamonds,
    required this.availableDiamonds,
    required this.itemId,
  });

  /// The diamonds cost of the item that could not be purchased.
  final int requiredDiamonds;

  /// The army's current diamonds balance.
  final int availableDiamonds;

  /// The id of the item that failed to purchase.
  final String itemId;

  @override
  String toString() =>
      'InsufficientDiamondsException: cannot purchase "$itemId" — '
      'requires $requiredDiamonds diamonds but army only has $availableDiamonds.';
}

// ─── Weapon catalog ──────────────────────────────────────────────────────────

/// The complete catalog of items available in the Weapon Shop.
///
/// `getEligibleShopItems` filters this list based on current turn and army
/// ability state.
const List<WeaponItem> kWeaponCatalog = [
  WeaponItem(
    id: 'fire_bomb',
    nameKey: 'ability_fire_bomb',
    diamondCost: 220,
    unlockTurn: 0,
    card: AbilityType.fireBomb,
  ),
  WeaponItem(
    id: 'tribute',
    nameKey: 'ability_tribute',
    diamondCost: 250,
    unlockTurn: 0,
    card: AbilityType.tribute,
  ),
  WeaponItem(
    id: 'bombardment',
    nameKey: 'ability_bombardment',
    diamondCost: 300,
    unlockTurn: kTurnUnlockBombardment, // 10
    card: AbilityType.bombardment,
  ),
  WeaponItem(
    id: 'soldier_spell',
    nameKey: 'ability_soldier_spell',
    diamondCost: 250,
    unlockTurn: kTurnUnlockSoldierSpell, // 12
    card: AbilityType.soldierSpell,
  ),
  WeaponItem(
    id: 'atom_bomb',
    nameKey: 'ability_atom_bomb',
    diamondCost: 700,
    unlockTurn: kTurnUnlockAtomBomb, // 20
    card: AbilityType.atomBomb,
  ),
  WeaponItem(
    id: 'nuclear_bomb',
    nameKey: 'ability_nuclear_bomb',
    diamondCost: 1000,
    unlockTurn: kTurnUnlockNuclearBomb, // 30
    card: AbilityType.nuclearBomb,
  ),
  WeaponItem(
    id: 'mega_bomba',
    nameKey: 'ability_mega_bomba',
    diamondCost: 500,
    unlockTurn: kTurnUnlockMegaBomba, // 45
    card: AbilityType.megaBomba,
  ),
];

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Handles all resource-economy operations for a single army.
abstract class EconomyService {
  /// Applies per-turn resource generation to [army] based on its land in
  /// [territories].
  ///
  /// - Adds [kDiamondsPerTurn] (80) diamonds.
  /// - Adds [kSoldiersPerTurn] (3) soldier units plus one per
  ///   [kTilesPerBonusSoldier] owned tiles (and [bonusSoldiers]) to
  ///   [army.totalUnitPool].
  ///
  /// Returns a new [Army] copy; the original is never mutated.
  Army applyTurnIncome(
    Army army,
    List<Territory> territories, {
    int bonusSoldiers = 0,
  });

  /// Attempts to purchase [item] for [army].
  ///
  /// On success, returns a new [Army] with:
  /// - `diamondBalance` decreased by `item.diamondCost`
  /// - one more `item.card` in its hand
  ///
  /// Throws [InsufficientDiamondsException] if `army.diamondBalance < item.diamondCost`.
  /// The original [army] is never mutated regardless of outcome.
  Army purchaseItem(Army army, WeaponItem item);

  /// Returns items from the catalog that [army] is eligible to purchase
  /// given [currentTurn] and the army's current ability states.
  ///
  /// An item is eligible once `item.unlockTurn <= currentTurn`.
  List<WeaponItem> getEligibleShopItems(Army army, int currentTurn);

  /// Moves up to [count] units (default: all) from [armyId]'s undeployed
  /// `totalUnitPool` onto its own territory [territoryId], respecting base
  /// capacity (Requirement 5.4). Returns [state] unchanged when nothing can
  /// be deployed (not owned, empty pool, or base full).
  GameState deployUnits(
    GameState state,
    ArmyId armyId,
    int territoryId, {
    int? count,
  });
}

// ─── Concrete implementation ─────────────────────────────────────────────────

/// Default implementation of [EconomyService].
///
/// Uses [kWeaponCatalog] as the shop item source.  All methods are pure
/// functions that return new model copies without mutating their inputs.
class EconomyServiceImpl implements EconomyService {
  const EconomyServiceImpl();

  // ─── applyTurnIncome ────────────────────────────────────────────────────

  @override
  Army applyTurnIncome(
    Army army,
    List<Territory> territories, {
    int bonusSoldiers = 0,
  }) {
    final ownedTiles = territories.where((t) => t.ownerArmyId == army.id);
    final soldiers =
        kSoldiersPerTurn +
        ownedTiles.length ~/ kTilesPerBonusSoldier +
        bonusSoldiers;

    return army.copyWith(
      diamondBalance: army.diamondBalance + kDiamondsPerTurn,
      totalUnitPool: army.totalUnitPool + soldiers,
    );
  }

  // ─── purchaseItem ────────────────────────────────────────────────────────

  @override
  Army purchaseItem(Army army, WeaponItem item) {
    if (army.diamondBalance < item.diamondCost) {
      throw InsufficientDiamondsException(
        requiredDiamonds: item.diamondCost,
        availableDiamonds: army.diamondBalance,
        itemId: item.id,
      );
    }

    return army
        .copyWith(diamondBalance: army.diamondBalance - item.diamondCost)
        .withCard(item.card, 1);
  }

  // ─── deployUnits ───────────────────────────────────────────────────────

  @override
  GameState deployUnits(
    GameState state,
    ArmyId armyId,
    int territoryId, {
    int? count,
  }) {
    final army = state.army(armyId);
    final index = state.territories.indexWhere((t) => t.id == territoryId);
    if (index < 0) return state;
    final territory = state.territories[index];
    if (territory.ownerArmyId != armyId) return state;

    var amount = count ?? army.totalUnitPool;
    if (amount > army.totalUnitPool) amount = army.totalUnitPool;
    final cap = territory.baseCapacity;
    if (cap != null && territory.unitCount + amount > cap) {
      amount = cap - territory.unitCount;
    }
    if (amount <= 0) return state;

    final territories = [...state.territories];
    territories[index] = territory.copyWith(
      unitCount: territory.unitCount + amount,
    );
    final updatedArmy = army.copyWith(
      totalUnitPool: army.totalUnitPool - amount,
    );
    return state.withArmy(updatedArmy).copyWith(territories: territories);
  }

  // ─── getEligibleShopItems ─────────────────────────────────────────────────

  @override
  List<WeaponItem> getEligibleShopItems(Army army, int currentTurn) {
    return kWeaponCatalog
        .where((item) => item.unlockTurn <= currentTurn)
        .toList();
  }
}

// ─── Diamond and gold mines ──────────────────────────────────────────────────

/// Counts the mines [armyId] owns in [after] but did not own in [before]
/// (i.e. mines it just captured): `(diamond mines, gold mines)`.
(int, int) capturedMines(GameState before, GameState after, ArmyId armyId) {
  var diamond = 0;
  var gold = 0;
  for (var i = 0; i < after.territories.length; i++) {
    final t = after.territories[i];
    if (t.ownerArmyId != armyId) continue;
    if (!t.hasDiamondMine && !t.hasGoldMine) continue;
    final was =
        i < before.territories.length && before.territories[i].id == t.id
        ? before.territories[i]
        : before.territories.firstWhere((b) => b.id == t.id);
    if (was.ownerArmyId == armyId) continue;
    if (t.hasDiamondMine) diamond++;
    if (t.hasGoldMine) gold++;
  }
  return (diamond, gold);
}

/// Pays [armyId] [kDiamondMineReward] diamonds for every diamond mine and
/// [kGoldMineReward] for every gold mine (base) it just captured.
GameState awardMineRewards(GameState before, GameState after, ArmyId armyId) {
  final (diamond, gold) = capturedMines(before, after, armyId);
  final reward = diamond * kDiamondMineReward + gold * kGoldMineReward;
  if (reward == 0) return after;
  final army = after.army(armyId);
  return after.withArmy(
    army.copyWith(diamondBalance: army.diamondBalance + reward),
  );
}
