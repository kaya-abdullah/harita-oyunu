/// Economy service for Harita: Kendi İmparatorluğunu Kur.
///
/// Handles per-turn income, city growth and the Weapon Shop.
library;

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
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
      'requires $requiredDiamonds diamonds but army only has '
      '$availableDiamonds.';
}

// ─── Weapon catalog ──────────────────────────────────────────────────────────

/// Everything for sale in the Weapon Shop — all of it from the first turn
/// ("oyuna girdiğimiz gibi yazsın"): every card, tanks and bombers.
const List<WeaponItem> kWeaponCatalog = [
  WeaponItem(
    id: 'fire_bomb',
    nameKey: 'ability_fire_bomb',
    diamondCost: 220,
    card: AbilityType.fireBomb,
  ),
  WeaponItem(
    id: 'bombardment',
    nameKey: 'ability_bombardment',
    diamondCost: 300,
    card: AbilityType.bombardment,
  ),
  WeaponItem(
    id: 'soldier_spell',
    nameKey: 'ability_soldier_spell',
    diamondCost: 250,
    card: AbilityType.soldierSpell,
  ),
  WeaponItem(
    id: 'mega_bomba',
    nameKey: 'ability_mega_bomba',
    diamondCost: 500,
    card: AbilityType.megaBomba,
  ),
  WeaponItem(
    id: 'atom_bomb',
    nameKey: 'ability_atom_bomb',
    diamondCost: 700,
    card: AbilityType.atomBomb,
  ),
  WeaponItem(
    id: 'nuclear_bomb',
    nameKey: 'ability_nuclear_bomb',
    diamondCost: 1000,
    card: AbilityType.nuclearBomb,
  ),
  WeaponItem(
    id: 'tribute',
    nameKey: 'ability_tribute',
    diamondCost: 250,
    card: AbilityType.tribute,
  ),
  WeaponItem(id: 'tank', nameKey: 'shop_item_tank', diamondCost: 200, tanks: 1),
  WeaponItem(
    id: 'bomber',
    nameKey: 'shop_item_bomber',
    diamondCost: 350,
    bombers: 1,
  ),
];

/// Soldiers each city of [army] gains at the end of its turn: bots grow
/// faster on "Zor" and slower on "Çok Kolay".
int cityGrowthFor(Army army, AiDifficulty difficulty) {
  if (army.isHuman) return kCityGrowth;
  return switch (difficulty) {
    AiDifficulty.veryEasy => kVeryEasyCityGrowth,
    AiDifficulty.medium => kCityGrowth,
    AiDifficulty.hard => kHardCityGrowth,
  };
}

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Handles all resource-economy operations.
abstract class EconomyService {
  /// End-of-turn income of [armyId]: [kDiamondsPerTurn] diamonds and
  /// [cityGrowthFor] soldiers in each of its cities.
  GameState applyTurnIncome(GameState state, ArmyId armyId);

  /// Buys [item] for [army]: pays its cost and adds the card, tank or
  /// bomber. Throws [InsufficientDiamondsException] when it cannot pay.
  Army purchaseItem(Army army, WeaponItem item);

  /// Everything for sale (the whole [kWeaponCatalog]).
  List<WeaponItem> getShopItems();
}

// ─── Concrete implementation ─────────────────────────────────────────────────

/// Default implementation of [EconomyService].
class EconomyServiceImpl implements EconomyService {
  const EconomyServiceImpl();

  @override
  GameState applyTurnIncome(GameState state, ArmyId armyId) {
    final army = state.army(armyId);
    final growth = cityGrowthFor(army, state.difficulty);
    return state
        .withArmy(
          army.copyWith(diamondBalance: army.diamondBalance + kDiamondsPerTurn),
        )
        .copyWith(
          territories: [
            for (final t in state.territories)
              t.ownerArmyId == armyId
                  ? t.copyWith(unitCount: t.unitCount + growth)
                  : t,
          ],
        );
  }

  @override
  Army purchaseItem(Army army, WeaponItem item) {
    if (army.diamondBalance < item.diamondCost) {
      throw InsufficientDiamondsException(
        requiredDiamonds: item.diamondCost,
        availableDiamonds: army.diamondBalance,
        itemId: item.id,
      );
    }
    var bought = army.copyWith(
      diamondBalance: army.diamondBalance - item.diamondCost,
      tanks: army.tanks + item.tanks,
      bombers: army.bombers + item.bombers,
    );
    final card = item.card;
    if (card != null) bought = bought.withCard(card, 1);
    return bought;
  }

  @override
  List<WeaponItem> getShopItems() => kWeaponCatalog;
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
/// [kGoldMineReward] for every gold mine it just captured.
GameState awardMineRewards(GameState before, GameState after, ArmyId armyId) {
  final (diamond, gold) = capturedMines(before, after, armyId);
  final reward = diamond * kDiamondMineReward + gold * kGoldMineReward;
  if (reward == 0) return after;
  final army = after.army(armyId);
  return after.withArmy(
    army.copyWith(diamondBalance: army.diamondBalance + reward),
  );
}
