/// Weapon item domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';

// ─── WeaponItem ──────────────────────────────────────────────────────────────

/// An item for sale in the Weapon Shop: one card for the buyer's hand.
///
/// Immutable by design.
class WeaponItem {
  const WeaponItem({
    required this.id,
    required this.nameKey,
    required this.diamondCost,
    required this.unlockTurn,
    required this.card,
  });

  /// Unique string identifier for this item (used as a stable key).
  final String id;

  /// Locale key used to look up the display name.
  final String nameKey;

  /// Diamonds cost to purchase this item.
  final int diamondCost;

  /// The earliest turn at which this item appears in the shop.
  final int unlockTurn;

  /// The card this item adds to the buyer's hand.
  final AbilityType card;

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeaponItem) return false;
    return id == other.id &&
        nameKey == other.nameKey &&
        diamondCost == other.diamondCost &&
        unlockTurn == other.unlockTurn &&
        card == other.card;
  }

  @override
  int get hashCode => Object.hash(id, nameKey, diamondCost, unlockTurn, card);

  @override
  String toString() =>
      'WeaponItem(id: $id, cost: $diamondCost diamonds, '
      'unlockTurn: $unlockTurn, card: $card)';
}
