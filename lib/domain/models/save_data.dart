/// SaveData Hive model for Harita: Kendi İmparatorluğunu Kur.
///
/// Stores the complete [GameState] as JSON strings so that Hive only needs
/// to persist primitive scalar types — avoiding the combinatorial explosion of
/// nested custom-type adapters.
library;

import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/models/weapon_item.dart';

part 'save_data.g.dart';

// ─── Schema version ──────────────────────────────────────────────────────────

/// Current serialisation schema version.  Bump when breaking changes are made.
///
/// Version 2: Africa tile map + bot difficulty.
/// Version 3: fine real-outline map, diamond mines and up to 6 bots (all
/// armies in one list). Older saves are rejected and discarded by the
/// repository.
const int kSaveDataSchemaVersion = 3;

// ─── SaveData ─────────────────────────────────────────────────────────────────

/// Hive-persisted snapshot of a [GameState].
///
/// All complex game objects are serialised to JSON strings before storage so
/// that Hive only needs to handle primitive types.  The [schemaVersion] field
/// exists for future migration support.
@HiveType(typeId: 0)
class SaveData extends HiveObject {
  SaveData({
    required this.territoriesJson,
    required this.armiesJson,
    required this.currentTurn,
    required this.activeArmyId,
    required this.phase,
    required this.schemaVersion,
    this.winnerId,
    this.difficulty,
  });

  /// JSON-encoded list of all territories.
  @HiveField(0)
  final String territoriesJson;

  /// JSON-encoded list of every army, in turn order. (Field 2 held army 2
  /// before schema 3 and is no longer written.)
  @HiveField(1)
  final String armiesJson;

  /// Current turn number (1-indexed).
  @HiveField(3)
  final int currentTurn;

  /// Serialised [ArmyId] enum name of the active army.
  @HiveField(4)
  final String activeArmyId;

  /// Serialised [GamePhase] enum name.
  @HiveField(5)
  final String phase;

  /// Serialised [ArmyId] enum name of the winner, or `null` if game ongoing.
  @HiveField(6)
  final String? winnerId;

  /// Schema version for future migration support.
  @HiveField(7)
  final int schemaVersion;

  /// Serialised [AiDifficulty] enum name.
  @HiveField(8)
  final String? difficulty;

  // ─── Factory: GameState → SaveData ────────────────────────────────────────

  /// Creates a [SaveData] by serialising all fields of [state] to JSON strings.
  factory SaveData.fromGameState(GameState state) {
    return SaveData(
      territoriesJson: jsonEncode(
        state.territories.map(_territoryToJson).toList(),
      ),
      armiesJson: jsonEncode(state.armies.map(_armyToJson).toList()),
      currentTurn: state.currentTurn,
      activeArmyId: state.activeArmyId.name,
      phase: state.phase.name,
      winnerId: state.winnerId?.name,
      schemaVersion: kSaveDataSchemaVersion,
      difficulty: state.difficulty.name,
    );
  }

  // ─── Deserialise: SaveData → GameState ────────────────────────────────────

  /// Reconstructs a [GameState] from this [SaveData].
  ///
  /// Throws if the JSON is malformed or contains unexpected values.
  GameState toGameState() {
    if (schemaVersion != kSaveDataSchemaVersion) {
      throw FormatException('Unsupported save schema $schemaVersion.');
    }
    final rawTerritories = (jsonDecode(territoriesJson) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final territories = rawTerritories.map(_territoryFromJson).toList();

    final armies = (jsonDecode(armiesJson) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(_armyFromJson)
        .toList();

    return GameState(
      territories: territories,
      armies: armies,
      currentTurn: currentTurn,
      activeArmyId: _armyIdFromString(activeArmyId),
      phase: _gamePhaseFromString(phase),
      winnerId: winnerId != null ? _armyIdFromString(winnerId!) : null,
      difficulty: aiDifficultyFromName(difficulty),
    );
  }
}

// ─── Territory serialisation ──────────────────────────────────────────────────

Map<String, dynamic> _territoryToJson(Territory t) => {
  'id': t.id,
  'name': t.name,
  'type': t.type.name,
  'adjacentIds': t.adjacentIds,
  'unitCount': t.unitCount,
  'ownerArmyId': t.ownerArmyId?.name,
  'baseCapacity': t.baseCapacity,
  'diamondMine': t.hasDiamondMine,
};

Territory _territoryFromJson(Map<String, dynamic> json) => Territory(
  id: json['id'] as int,
  name: json['name'] as String,
  type: _territoryTypeFromString(json['type'] as String),
  adjacentIds: (json['adjacentIds'] as List<dynamic>).cast<int>(),
  unitCount: json['unitCount'] as int,
  ownerArmyId: json['ownerArmyId'] != null
      ? _armyIdFromString(json['ownerArmyId'] as String)
      : null,
  baseCapacity: json['baseCapacity'] as int?,
  hasDiamondMine: json['diamondMine'] as bool? ?? false,
);

// ─── Army serialisation ───────────────────────────────────────────────────────

Map<String, dynamic> _armyToJson(Army a) => {
  'id': a.id.name,
  'kind': a.kind.name,
  'diamondBalance': a.diamondBalance,
  'totalUnitPool': a.totalUnitPool,
  'abilities': a.abilities.map(
    (type, state) => MapEntry(type.name, _abilityStateToJson(state)),
  ),
  'inventory': a.inventory.map(_weaponItemToJson).toList(),
};

Army _armyFromJson(Map<String, dynamic> json) {
  final abilitiesRaw = (json['abilities'] as Map<String, dynamic>)
      .map<AbilityType, AbilityState>(
        (key, value) => MapEntry(
          _abilityTypeFromString(key),
          _abilityStateFromJson(value as Map<String, dynamic>),
        ),
      );

  final inventory = (json['inventory'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(_weaponItemFromJson)
      .toList();

  return Army(
    id: _armyIdFromString(json['id'] as String),
    kind: _armyKindFromString(json['kind'] as String),
    diamondBalance: json['diamondBalance'] as int,
    totalUnitPool: json['totalUnitPool'] as int,
    abilities: abilitiesRaw,
    inventory: inventory,
  );
}

// ─── AbilityState serialisation ───────────────────────────────────────────────

Map<String, dynamic> _abilityStateToJson(AbilityState s) => {
  'type': s.type.name,
  'isUnlocked': s.isUnlocked,
  'cooldownTurnsRemaining': s.cooldownTurnsRemaining,
};

AbilityState _abilityStateFromJson(Map<String, dynamic> json) => AbilityState(
  type: _abilityTypeFromString(json['type'] as String),
  isUnlocked: json['isUnlocked'] as bool,
  cooldownTurnsRemaining: json['cooldownTurnsRemaining'] as int?,
);

// ─── WeaponItem serialisation ─────────────────────────────────────────────────

Map<String, dynamic> _weaponItemToJson(WeaponItem w) => {
  'id': w.id,
  'nameKey': w.nameKey,
  'diamondCost': w.diamondCost,
  'unlockTurn': w.unlockTurn,
  'requiredAbility': w.requiredAbility?.name,
};

WeaponItem _weaponItemFromJson(Map<String, dynamic> json) => WeaponItem(
  id: json['id'] as String,
  nameKey: json['nameKey'] as String,
  diamondCost: json['diamondCost'] as int,
  unlockTurn: json['unlockTurn'] as int,
  requiredAbility: json['requiredAbility'] != null
      ? _abilityTypeFromString(json['requiredAbility'] as String)
      : null,
);

// ─── Enum helpers ─────────────────────────────────────────────────────────────

ArmyId _armyIdFromString(String s) =>
    ArmyId.values.firstWhere((e) => e.name == s);

ArmyKind _armyKindFromString(String s) =>
    ArmyKind.values.firstWhere((e) => e.name == s);

GamePhase _gamePhaseFromString(String s) =>
    GamePhase.values.firstWhere((e) => e.name == s);

TerritoryType _territoryTypeFromString(String s) =>
    TerritoryType.values.firstWhere((e) => e.name == s);

AbilityType _abilityTypeFromString(String s) =>
    AbilityType.values.firstWhere((e) => e.name == s);
