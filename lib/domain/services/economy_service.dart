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

/// Thrown when an army attempts to purchase an item with insufficient Elma.
class InsufficientElmaException implements Exception {
  const InsufficientElmaException({
    required this.requiredElma,
    required this.availableElma,
    required this.itemId,
  });

  /// The Elma cost of the item that could not be purchased.
  final int requiredElma;

  /// The army's current Elma balance.
  final int availableElma;

  /// The id of the item that failed to purchase.
  final String itemId;

  @override
  String toString() =>
      'InsufficientElmaException: cannot purchase "$itemId" — '
      'requires $requiredElma Elma but army only has $availableElma.';
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
    elmaCost: 220,
    unlockTurn: 0,
    requiredAbility: null,
  ),
  WeaponItem(
    id: 'bombardment_pack',
    nameKey: 'shop_item_bombardment_pack',
    elmaCost: 300,
    unlockTurn: kTurnUnlockBombardment, // 10
    requiredAbility: AbilityType.bombardment,
  ),
  WeaponItem(
    id: 'soldier_spell_pack',
    nameKey: 'shop_item_soldier_spell_pack',
    elmaCost: 250,
    unlockTurn: kTurnUnlockSoldierSpell, // 12
    requiredAbility: AbilityType.soldierSpell,
  ),
  WeaponItem(
    id: 'mega_bomba_pack',
    nameKey: 'shop_item_mega_bomba_pack',
    elmaCost: 500,
    unlockTurn: kTurnUnlockMegaBomba, // 45
    requiredAbility: AbilityType.megaBomba,
  ),
  WeaponItem(
    id: 'laser_pack',
    nameKey: 'shop_item_laser_pack',
    elmaCost: 350,
    unlockTurn: 0,
    requiredAbility: AbilityType.directLaser,
  ),
];

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Handles all resource-economy operations for a single army.
abstract class EconomyService {
  /// Applies per-turn resource generation to [army] based on owned bases
  /// in [territories].
  ///
  /// - Adds `n × 10` Elma where `n` is the number of bases (bigBase or
  ///   smallBase) owned by [army].
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
  /// - `elmaBalance` decreased by `item.elmaCost`
  /// - [item] appended to `inventory`
  ///
  /// Throws [InsufficientElmaException] if `army.elmaBalance < item.elmaCost`.
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
    var ownedTiles = 0;
    var ownedBaseCount = 0;
    for (final t in territories) {
      if (t.ownerArmyId != army.id) continue;
      ownedTiles++;
      if (t.type == TerritoryType.bigBase ||
          t.type == TerritoryType.smallBase) {
        ownedBaseCount++;
      }
    }

    final elmaIncome = ownedBaseCount * kElmaPerBase; // n × 10
    final soldiers =
        kSoldiersPerTurn + ownedTiles ~/ kTilesPerBonusSoldier + bonusSoldiers;

    return army.copyWith(
      elmaBalance: army.elmaBalance + elmaIncome,
      totalUnitPool: army.totalUnitPool + soldiers,
    );
  }

  // ─── purchaseItem ────────────────────────────────────────────────────────

  @override
  Army purchaseItem(Army army, WeaponItem item) {
    if (army.elmaBalance < item.elmaCost) {
      throw InsufficientElmaException(
        requiredElma: item.elmaCost,
        availableElma: army.elmaBalance,
        itemId: item.id,
      );
    }

    return army.copyWith(
      elmaBalance: army.elmaBalance - item.elmaCost,
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
    final army = armyId == ArmyId.army1 ? state.army1 : state.army2;
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
    return state.copyWith(
      territories: territories,
      army1: armyId == ArmyId.army1 ? updatedArmy : state.army1,
      army2: armyId == ArmyId.army2 ? updatedArmy : state.army2,
    );
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
