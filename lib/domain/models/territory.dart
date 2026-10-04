/// Territory domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/army.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Classifies a territory by its strategic role on the map.
enum TerritoryType {
  /// A standard contestable region with no capacity limit.
  normal,

  /// A resource-generating base with a capacity of 150 units.
  bigBase,

  /// A resource-generating base with a capacity below 150 units.
  smallBase,
}

// ─── Territory ───────────────────────────────────────────────────────────────

/// Represents one small square tile ("minik kare") of the Africa map.
///
/// Immutable by design — mutating state is done via [copyWith].
class Territory {
  const Territory({
    required this.id,
    required this.name,
    required this.type,
    required this.adjacentIds,
    required this.unitCount,
    this.ownerArmyId,
    this.baseCapacity,
  });

  /// Unique identifier, 0 … kTerritoryCount - 1.
  final int id;

  /// Locale key used to look up the display name.
  final String name;

  /// Strategic classification of this territory.
  final TerritoryType type;

  /// IDs of territories directly reachable from this one (bidirectional).
  final List<int> adjacentIds;

  /// Number of units currently stationed here.
  final int unitCount;

  /// The army that currently owns this territory, or `null` if neutral.
  final ArmyId? ownerArmyId;

  /// Maximum unit capacity; only set for [TerritoryType.bigBase] and
  /// [TerritoryType.smallBase] territories.
  final int? baseCapacity;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  Territory copyWith({
    int? id,
    String? name,
    TerritoryType? type,
    List<int>? adjacentIds,
    int? unitCount,
    // Use a sentinel so callers can explicitly clear the owner (set to null).
    Object? ownerArmyId = _sentinel,
    Object? baseCapacity = _sentinel,
  }) {
    return Territory(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      adjacentIds: adjacentIds ?? this.adjacentIds,
      unitCount: unitCount ?? this.unitCount,
      ownerArmyId: ownerArmyId == _sentinel
          ? this.ownerArmyId
          : ownerArmyId as ArmyId?,
      baseCapacity: baseCapacity == _sentinel
          ? this.baseCapacity
          : baseCapacity as int?,
    );
  }

  // ─── Equality ────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Territory) return false;
    return id == other.id &&
        name == other.name &&
        type == other.type &&
        _listEquals(adjacentIds, other.adjacentIds) &&
        unitCount == other.unitCount &&
        ownerArmyId == other.ownerArmyId &&
        baseCapacity == other.baseCapacity;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    Object.hashAll(adjacentIds),
    unitCount,
    ownerArmyId,
    baseCapacity,
  );

  @override
  String toString() =>
      'Territory(id: $id, name: $name, type: $type, '
      'units: $unitCount, owner: $ownerArmyId)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

/// Sentinel object used to distinguish "not provided" from explicit `null`
/// in [Territory.copyWith] optional nullable parameters.
const Object _sentinel = Object();

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
