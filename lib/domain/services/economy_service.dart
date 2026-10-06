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
    id: 'fire_bomb_pack',
    nameKey: 'shop_item_fire_bomb_pack',
    diamondCost: 220,
    unlockTurn: 0,
    requiredAbility: null,
  ),
  WeaponItem(
    id: 'bombardment_pack',
    nameKey: 'shop_item_bombardment_pack',
    diamondCost: 300,
    unlockTurn: kTurnUnlockBombardment, // 10
    requiredAbility: AbilityType.bombardment,
  ),
  WeaponItem(
    id: 'soldier_spell_pack',
    nameKey: 'shop_item_soldier_spell_pack',
    diamondCost: 250,
    unlockTurn: kTurnUnlockSoldierSpell, // 12
    requiredAbility: AbilityType.soldierSpell,
  ),
  WeaponItem(
    id: 'mega_bomba_pack',
    nameKey: 'shop_item_mega_bomba_pack',
    diamondCost: 500,
    unlockTurn: kTurnUnlockMegaBomba, // 45
    requiredAbility: AbilityType.megaBomba,
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
  /// - [item] appended to `inventory`
  ///
  /// Throws [InsufficientDiamondsException] if `army.diamondBalance < item.diamondCost`.
  /// The original [army] is never mutated regardless of outcome.
  Army purchaseItem(Army army, WeaponItem item);

  /// Returns items from the catalog that [army] is eligible to purchase
  /// given [currentTurn] and the army's current ability states.
  ///
  /// An item is eligible when ALL of the following hold:
  /// 1. `item.unlockTurn <= currentTurn`
  /// 2. If `item.requiredAbility != null`, that ability is unlocked in [army].
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

    return army.copyWith(
      diamondBalance: army.diamondBalance - item.diamondCost,
      inventory: [...army.inventory, item],
    );
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
    return kWeaponCatalog.where((item) {
      // 1. Turn threshold must be met.
      if (item.unlockTurn > currentTurn) return false;

      // 2. Required ability (if any) must be unlocked.
      final requiredAbility = item.requiredAbility;
      if (requiredAbility != null) {
        final abilityState = army.abilities[requiredAbility];
        if (abilityState == null || !abilityState.isUnlocked) return false;
      }

      return true;
    }).toList();
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
