/// Territory domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/army.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Classifies a city by its value on the map.
enum TerritoryType {
  /// An ordinary city.
  city,

  /// A big capital that is a gold mine: capturing it pays
  /// [kGoldMineReward] diamonds.
  goldMine,
}

// ─── Territory ───────────────────────────────────────────────────────────────

/// One city of the Africa map together with the region around it.
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
    this.hasDiamondMine = false,
    this.hasForest = false,
  });

  /// Unique identifier, 0 … kTerritoryCount - 1.
  final int id;

  /// Stable key of the city (e.g. `city_cairo`); the display name comes
  /// from the map ([TerritoryGraph.cityName]).
  final String name;

  /// Whether this is a gold-mine city.
  final TerritoryType type;

  /// IDs of the neighbouring cities (bidirectional).
  final List<int> adjacentIds;

  /// Soldiers in this city — the number drawn on it.
  final int unitCount;

  /// The army that currently owns this city, or `null` if neutral.
  final ArmyId? ownerArmyId;

  /// Whether a diamond mine lies in this region. Capturing it pays
  /// [kDiamondMineReward] diamonds.
  final bool hasDiamondMine;

  /// Whether this region is a forest: defenders count
  /// [kForestDefenseBonus] more.
  final bool hasForest;

  /// Whether this city is a gold mine.
  bool get hasGoldMine => type == TerritoryType.goldMine;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  Territory copyWith({
    int? id,
    String? name,
    TerritoryType? type,
    List<int>? adjacentIds,
    int? unitCount,
    // Use a sentinel so callers can explicitly clear the owner (set to null).
    Object? ownerArmyId = _sentinel,
    bool? hasDiamondMine,
    bool? hasForest,
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
      hasDiamondMine: hasDiamondMine ?? this.hasDiamondMine,
      hasForest: hasForest ?? this.hasForest,
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
        hasDiamondMine == other.hasDiamondMine &&
        hasForest == other.hasForest;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    Object.hashAll(adjacentIds),
    unitCount,
    ownerArmyId,
    hasDiamondMine,
    hasForest,
  );

  @override
  String toString() =>
      'Territory(id: $id, name: $name, units: $unitCount, '
      'owner: $ownerArmyId)';
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
