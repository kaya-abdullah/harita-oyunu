/// Weapon item domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';

// ─── WeaponItem ──────────────────────────────────────────────────────────────

/// An item available for purchase in the Weapon Shop.
///
/// Immutable by design — mutating state is done via [copyWith].
class WeaponItem {
  const WeaponItem({
    required this.id,
    required this.nameKey,
    required this.elmaCost,
    required this.unlockTurn,
    this.requiredAbility,
  });

  /// Unique string identifier for this item (used as a stable key).
  final String id;

  /// Locale key used to look up the display name.
  final String nameKey;

  /// Elma cost to purchase this item.
  final int elmaCost;

  /// The earliest turn at which this item appears in the shop.
  final int unlockTurn;

  /// An ability that must be unlocked before this item can be purchased.
  /// `null` means no ability prerequisite.
  final AbilityType? requiredAbility;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  WeaponItem copyWith({
    String? id,
    String? nameKey,
    int? elmaCost,
    int? unlockTurn,
    Object? requiredAbility = _sentinel,
  }) {
    return WeaponItem(
      id: id ?? this.id,
      nameKey: nameKey ?? this.nameKey,
      elmaCost: elmaCost ?? this.elmaCost,
      unlockTurn: unlockTurn ?? this.unlockTurn,
      requiredAbility: requiredAbility == _sentinel
          ? this.requiredAbility
          : requiredAbility as AbilityType?,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeaponItem) return false;
    return id == other.id &&
        nameKey == other.nameKey &&
        elmaCost == other.elmaCost &&
        unlockTurn == other.unlockTurn &&
        requiredAbility == other.requiredAbility;
  }

  @override
  int get hashCode =>
      Object.hash(id, nameKey, elmaCost, unlockTurn, requiredAbility);

  @override
  String toString() =>
      'WeaponItem(id: $id, cost: $elmaCost Elma, unlockTurn: $unlockTurn, '
      'requiredAbility: $requiredAbility)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

const Object _sentinel = Object();
