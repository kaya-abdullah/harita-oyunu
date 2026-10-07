/// Weapon item domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';

// ─── WeaponItem ──────────────────────────────────────────────────────────────

/// An item for sale in the Weapon Shop: one card, a tank or a bomber.
/// Everything is on sale from the first turn.
///
/// Immutable by design.
class WeaponItem {
  const WeaponItem({
    required this.id,
    required this.nameKey,
    required this.diamondCost,
    this.card,
    this.tanks = 0,
    this.bombers = 0,
  });

  /// Unique string identifier for this item (used as a stable key).
  final String id;

  /// Locale key used to look up the display name.
  final String nameKey;

  /// Diamonds cost to purchase this item.
  final int diamondCost;

  /// The card this item adds to the buyer's hand, if any.
  final AbilityType? card;

  /// Tanks this item adds.
  final int tanks;

  /// Bombers this item adds.
  final int bombers;

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeaponItem) return false;
    return id == other.id &&
        nameKey == other.nameKey &&
        diamondCost == other.diamondCost &&
        card == other.card &&
        tanks == other.tanks &&
        bombers == other.bombers;
  }

  @override
  int get hashCode =>
      Object.hash(id, nameKey, diamondCost, card, tanks, bombers);

  @override
  String toString() => 'WeaponItem(id: $id, cost: $diamondCost diamonds)';
}
