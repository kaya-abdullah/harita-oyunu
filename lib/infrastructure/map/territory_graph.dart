/// Territory graph service for Harita: Kendi İmparatorluğunu Kur.
///
/// Loads the static map template from `assets/maps/territory_graph.json`,
/// validates structural invariants, and exposes query helpers used by
/// [CombatService], [GreedyAiAgent], and the Flame map renderer.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/infrastructure/map/territory_graph_data.dart';

// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when the territory graph JSON fails a structural validation rule.
class TerritoryGraphException implements Exception {
  const TerritoryGraphException(this.message);

  /// Human-readable description of the violated invariant.
  final String message;

  @override
  String toString() => 'TerritoryGraphException: $message';
}

// ─── Terrain ─────────────────────────────────────────────────────────────────

/// What the land of a tile looks like on the satellite picture. Purely
/// informative: terrain never changes the game.
enum Terrain {
  /// Tropical rain forest (Congo basin, Gulf of Guinea coast).
  rainforest,

  /// Open forest / woodland (miombo of Zambia, Angola, Mozambique).
  woodland,

  /// Grassland with scattered trees.
  savanna,

  /// Dry grass and scrub (Sahel, Kalahari edges).
  steppe,

  /// Sand and rock (Sahara, Namib).
  desert,
}

// ─── TerritoryPosition ───────────────────────────────────────────────────────

/// Holds the (x, y) screen-space coordinates for a territory as defined in
/// the JSON asset.  Used by the Flame renderer ([MapComponent]) to draw tiles.
///
/// This data is map-layout metadata and is intentionally kept separate from
/// the [Territory] domain model, which carries only game-logic state.
class TerritoryPosition {
  const TerritoryPosition({
    required this.id,
    required this.offset,
    this.col = 0,
    this.row = 0,
  });

  /// Matches [Territory.id].
  final int id;

  /// Centre of the tile in map world units.
  final Offset offset;

  /// Grid column of the tile.
  final int col;

  /// Grid row of the tile.
  final int row;

  @override
  String toString() => 'TerritoryPosition(id: $id, offset: $offset)';
}

// ─── TerritoryGraph ──────────────────────────────────────────────────────────

/// Immutable static map template.
///
/// The [territories] list is the **canonical map structure** — every territory
/// starts with `unitCount == 0` and `ownerArmyId == null`.  The live game
/// state keeps its own copy of this list (inside [GameState.territories]) which
/// is mutated during play.
///
/// Load via the async factory [TerritoryGraph.load].
class TerritoryGraph {
  TerritoryGraph._({
    required this.territories,
    required Map<int, TerritoryPosition> positions,
    required this.cols,
    required this.rows,
    required this.tileSize,
    required this.startIds,
    required this.outlines,
    required this.terrains,
    required this.satelliteMargin,
  }) : _positions = positions;

  /// All tiles of the Africa map in id-ascending order.
  final List<Territory> territories;

  /// Number of grid columns.
  final int cols;

  /// Number of grid rows.
  final int rows;

  /// Edge length of one tile in map world units.
  final double tileSize;

  /// Start tiles in army order: the human player first (Casablanca), then
  /// bot 1 (Cape Town, the other end of Africa), bot 2 … bot 6.
  final List<int> startIds;

  /// Real country outlines (Natural Earth) in map world units, keyed by
  /// region name key. Drawn under the tiles so Africa looks like a normal
  /// map. Each outline is a closed ring of points.
  final Map<String, List<List<Offset>>> outlines;

  /// Terrain of every tile, indexed by tile id.
  final List<Terrain> terrains;

  /// How many tiles of satellite picture (`assets/images/africa_satellite.jpg`)
  /// lie around the grid on every side. The picture covers the world rect
  /// [satelliteRect].
  final int satelliteMargin;

  /// World-space rectangle covered by the satellite picture.
  Rect get satelliteRect => Rect.fromLTWH(
    -satelliteMargin * tileSize,
    -satelliteMargin * tileSize,
    (cols + 2 * satelliteMargin) * tileSize,
    (rows + 2 * satelliteMargin) * tileSize,
  );

  /// Terrain of tile [id].
  Terrain terrainOf(int id) => terrains[id];

  /// Tile at which the human player (Army 1) starts.
  int get playerStartId => startIds.first;

  /// Tile at which the first bot (Army 2) starts.
  int get botStartId => startIds[1];

  /// Map width in world units.
  double get width => cols * tileSize;

  /// Map height in world units.
  double get height => rows * tileSize;

  /// Position lookup keyed by territory id.
  final Map<int, TerritoryPosition> _positions;

  // ─── Factory ───────────────────────────────────────────────────────────────

  /// Loads and validates the territory graph from
  /// `assets/maps/territory_graph.json`.
  ///
  /// Throws [TerritoryGraphException] if:
  /// - The JSON does not contain exactly [kTerritoryCount] territories.
  /// - Any adjacency relationship is not bidirectional.
  /// - A `bigBase` territory has a `baseCapacity` other than 150.
  /// - A `smallBase` territory has a null or >= 150 `baseCapacity`.
  static Future<TerritoryGraph> load() async {
    final jsonString = await rootBundle.loadString(
      'assets/maps/territory_graph.json',
    );
    return parse(jsonString);
  }

  /// Synchronously builds the graph from the copy of the map data embedded
  /// in [kTerritoryGraphJson] (kept identical to the JSON asset). Used to
  /// create a new game's initial state without awaiting asset loading.
  static TerritoryGraph bundled() => _bundled ??= parse(kTerritoryGraphJson);

  static TerritoryGraph? _bundled;

  /// Parses and validates a territory graph from a raw JSON string.
  static TerritoryGraph parse(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final rawList = decoded['territories'] as List<dynamic>;
    final tileSize = (decoded['tileSize'] as num? ?? 24).toDouble();

    // ── Parse ──────────────────────────────────────────────────────────────
    final territories = <Territory>[];
    final positions = <int, TerritoryPosition>{};
    final terrainById = <int, Terrain>{};

    for (final raw in rawList) {
      final map = raw as Map<String, dynamic>;

      final id = map['id'] as int;
      final nameKey = map['nameKey'] as String;
      final typeStr = map['type'] as String;
      final adjacentIds = (map['adjacentIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false);
      final baseCapacity = map['baseCapacity'] as int?;
      final col = (map['col'] as num?)?.toInt() ?? 0;
      final row = (map['row'] as num?)?.toInt() ?? 0;
      final x = (map['x'] as num?)?.toDouble() ?? (col + 0.5) * tileSize;
      final y = (map['y'] as num?)?.toDouble() ?? (row + 0.5) * tileSize;

      final type = _parseTerritoryType(typeStr, id);
      terrainById[id] = Terrain.values.firstWhere(
        (t) => t.name == map['terrain'],
        orElse: () => Terrain.savanna,
      );

      territories.add(
        Territory(
          id: id,
          name: nameKey,
          type: type,
          adjacentIds: adjacentIds,
          unitCount: 0,
          ownerArmyId: null,
          baseCapacity: baseCapacity,
          hasDiamondMine: map['diamondMine'] as bool? ?? false,
        ),
      );

      positions[id] = TerritoryPosition(
        id: id,
        offset: Offset(x, y),
        col: col,
        row: row,
      );
    }

    // Sort by id to guarantee index-stable access.
    territories.sort((a, b) => a.id.compareTo(b.id));

    // ── Validate ───────────────────────────────────────────────────────────
    _validateCount(territories);
    _validateBidirectionality(territories);
    _validateBaseCapacities(territories);

    final startIds =
        (decoded['startIds'] as List<dynamic>?)?.cast<int>() ??
        [
          decoded['playerStartId'] as int? ?? 0,
          decoded['botStartId'] as int? ?? territories.length - 1,
        ];
    if (startIds.length < 2) {
      throw const TerritoryGraphException('At least two start tiles needed.');
    }
    for (final startId in startIds) {
      if (startId < 0 || startId >= territories.length) {
        throw TerritoryGraphException('Start tile $startId does not exist.');
      }
    }

    final outlines = <String, List<List<Offset>>>{};
    final rawOutlines = decoded['outlines'] as Map<String, dynamic>? ?? {};
    rawOutlines.forEach((key, rings) {
      outlines['region_$key'] = [
        for (final ring in rings as List<dynamic>)
          [
            for (var i = 0; i + 1 < (ring as List<dynamic>).length; i += 2)
              Offset(
                (ring[i] as num).toDouble(),
                (ring[i + 1] as num).toDouble(),
              ),
          ],
      ];
    });

    return TerritoryGraph._(
      territories: List.unmodifiable(territories),
      positions: Map.unmodifiable(positions),
      cols: decoded['cols'] as int? ?? 1,
      rows: decoded['rows'] as int? ?? 1,
      tileSize: tileSize,
      startIds: List.unmodifiable(startIds),
      outlines: Map.unmodifiable(outlines),
      terrains: List.unmodifiable([
        for (final t in territories) terrainById[t.id]!,
      ]),
      satelliteMargin: decoded['satelliteMargin'] as int? ?? 0,
    );
  }

  // ─── Query helpers ─────────────────────────────────────────────────────────

  /// Returns the territory with [id].
  ///
  /// Throws [ArgumentError] if no territory with that id exists.
  Territory getById(int id) {
    // Territories are sorted and ids are contiguous, so index == id.
    if (id >= 0 && id < territories.length && territories[id].id == id) {
      return territories[id];
    }
    throw ArgumentError.value(id, 'id', 'No territory found with id $id.');
  }

  /// Returns `true` when territory [idB] appears in territory [idA]'s
  /// adjacency list (i.e. the two territories share a border).
  ///
  /// Both ids must exist; throws [ArgumentError] otherwise.
  bool areAdjacent(int idA, int idB) {
    final a = getById(idA);
    return a.adjacentIds.contains(idB);
  }

  /// Returns all [Territory] objects that border territory [id].
  ///
  /// Throws [ArgumentError] if [id] does not exist.
  List<Territory> getAdjacentTerritories(int id) {
    final origin = getById(id);
    return [for (final adjId in origin.adjacentIds) getById(adjId)];
  }

  /// Returns all territories currently owned by [armyId].
  ///
  /// This method operates on the **template** territories (all unowned at
  /// load time).  Callers working with live game state should filter
  /// [GameState.territories] directly instead.
  List<Territory> getTerritoriesOwnedBy(ArmyId armyId) {
    return territories
        .where((t) => t.ownerArmyId == armyId)
        .toList(growable: false);
  }

  /// Returns all territories classified as [TerritoryType.bigBase] or
  /// [TerritoryType.smallBase].
  List<Territory> getBases() {
    return territories
        .where(
          (t) =>
              t.type == TerritoryType.bigBase ||
              t.type == TerritoryType.smallBase,
        )
        .toList(growable: false);
  }

  /// Returns the screen-space [Offset] for territory [id] as defined in the
  /// JSON asset.
  ///
  /// Throws [ArgumentError] if [id] does not exist.
  Offset getPosition(int id) {
    final pos = _positions[id];
    if (pos == null) {
      throw ArgumentError.value(
        id,
        'id',
        'No position found for territory id $id.',
      );
    }
    return pos.offset;
  }

  /// Returns the full grid position (centre, column, row) of tile [id].
  TerritoryPosition positionOf(int id) {
    final pos = _positions[id];
    if (pos == null) {
      throw ArgumentError.value(id, 'id', 'No position for tile $id.');
    }
    return pos;
  }

  /// Returns `true` when tiles [a] and [b] are adjacent but not grid
  /// neighbours — i.e. linked by a sea bridge (Madagascar).
  bool isSeaLink(int a, int b) {
    final pa = positionOf(a);
    final pb = positionOf(b);
    return (pa.col - pb.col).abs() + (pa.row - pb.row).abs() != 1;
  }

  // ─── Private validation helpers ────────────────────────────────────────────

  static TerritoryType _parseTerritoryType(String raw, int id) {
    switch (raw) {
      case 'normal':
        return TerritoryType.normal;
      case 'bigBase':
        return TerritoryType.bigBase;
      case 'smallBase':
        return TerritoryType.smallBase;
      default:
        throw TerritoryGraphException('Territory $id has unknown type "$raw".');
    }
  }

  static void _validateCount(List<Territory> territories) {
    if (territories.length != kTerritoryCount) {
      throw TerritoryGraphException(
        'Expected exactly $kTerritoryCount territories, '
        'but found ${territories.length}.',
      );
    }
  }

  static void _validateBidirectionality(List<Territory> territories) {
    // Build an id → territory lookup for O(1) access.
    final byId = {for (final t in territories) t.id: t};

    for (final t in territories) {
      for (final adjId in t.adjacentIds) {
        final neighbour = byId[adjId];
        if (neighbour == null) {
          throw TerritoryGraphException(
            'Territory ${t.id} references adjacentId $adjId '
            'which does not exist.',
          );
        }
        if (!neighbour.adjacentIds.contains(t.id)) {
          throw TerritoryGraphException(
            'Adjacency is not bidirectional: territory ${t.id} lists $adjId '
            'as a neighbour, but territory $adjId does not list ${t.id}.',
          );
        }
      }
    }
  }

  static void _validateBaseCapacities(List<Territory> territories) {
    for (final t in territories) {
      switch (t.type) {
        case TerritoryType.bigBase:
          if (t.baseCapacity != kBigBaseCapacity) {
            throw TerritoryGraphException(
              'Territory ${t.id} is a bigBase but has '
              'baseCapacity ${t.baseCapacity} (expected $kBigBaseCapacity).',
            );
          }
        case TerritoryType.smallBase:
          if (t.baseCapacity == null || t.baseCapacity! >= kBigBaseCapacity) {
            throw TerritoryGraphException(
              'Territory ${t.id} is a smallBase but has '
              'baseCapacity ${t.baseCapacity} '
              '(must be non-null and < $kBigBaseCapacity).',
            );
          }
        case TerritoryType.normal:
          // Normal territories have no capacity constraint.
          break;
      }
    }
  }

  @override
  String toString() =>
      'TerritoryGraph(${territories.length} territories, '
      '${getBases().length} bases)';
}
