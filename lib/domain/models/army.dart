/// Army domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/weapon_item.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Identifies which of the two armies this is.
enum ArmyId {
  /// The first army (human player by default; colour: blue).
  army1,

  /// The second army (AI opponent by default; colour: red).
  army2,
}

/// Specifies whether the army is controlled by a human or the AI.
enum ArmyKind {
  /// Controlled by a human player.
  human,

  /// Controlled by the greedy AI agent.
  ai,
}

// ─── Army ────────────────────────────────────────────────────────────────────

/// Represents one player's army and its associated resources.
///
/// Immutable by design — mutating state is done via [copyWith].
class Army {
  const Army({
    required this.id,
    required this.kind,
    required this.elmaBalance,
    required this.totalUnitPool,
    required this.abilities,
    required this.inventory,
  });

  /// Which army this is (army1 or army2).
  final ArmyId id;

  /// Whether this army is human-controlled or AI-controlled.
  final ArmyKind kind;

  /// Current Elma (apple currency) balance.
  final int elmaBalance;

  /// Undeployed soldier units available to place on territories.
  final int totalUnitPool;

  /// Runtime state for each of the five special abilities.
  ///
  /// The map is stored as an unmodifiable view to prevent accidental mutation.
  final Map<AbilityType, AbilityState> abilities;

  /// Items purchased from the Weapon Shop.
  final List<WeaponItem> inventory;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  Army copyWith({
    ArmyId? id,
    ArmyKind? kind,
    int? elmaBalance,
    int? totalUnitPool,
    Map<AbilityType, AbilityState>? abilities,
    List<WeaponItem>? inventory,
  }) {
    return Army(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      elmaBalance: elmaBalance ?? this.elmaBalance,
      totalUnitPool: totalUnitPool ?? this.totalUnitPool,
      // Wrap in an unmodifiable map so callers cannot mutate through the copy.
      abilities: Map.unmodifiable(abilities ?? this.abilities),
      inventory: List.unmodifiable(inventory ?? this.inventory),
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Army) return false;
    return id == other.id &&
        kind == other.kind &&
        elmaBalance == other.elmaBalance &&
        totalUnitPool == other.totalUnitPool &&
        _mapEquals(abilities, other.abilities) &&
        _listEquals(inventory, other.inventory);
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    elmaBalance,
    totalUnitPool,
    Object.hashAll(abilities.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(inventory),
  );

  @override
  String toString() =>
      'Army(id: $id, kind: $kind, elma: $elmaBalance, '
      'unitPool: $totalUnitPool, inventorySize: ${inventory.length})';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
