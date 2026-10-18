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

/// What the land of a city looks like on the satellite picture. Purely
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

/// Holds where a city is drawn on the map (its marker), in map world units.
///
/// This data is map-layout metadata and is intentionally kept separate from
/// the [Territory] domain model, which carries only game-logic state.
class TerritoryPosition {
  const TerritoryPosition({required this.id, required this.offset});

  /// Matches [Territory.id].
  final int id;

  /// The city marker in map world units.
  final Offset offset;

  @override
  String toString() => 'TerritoryPosition(id: $id, offset: $offset)';
}

/// A border line of a city's area: between city [a] and city [b], or — when
/// [b] is `null` — along the coast of [a].
class CityBorder {
  const CityBorder(this.a, this.b, this.points);

  /// One city along the line.
  final int a;

  /// The city on the other side, or `null` for the sea.
  final int? b;

  /// The line, in map world units.
  final List<Offset> points;
}

// ─── TerritoryGraph ──────────────────────────────────────────────────────────

/// Immutable static map template: the real countries of Africa, each split
/// between its cities ("her ülkeye 4 şehir"). Every territory is one city
/// and the land around it — there is no land without a city.
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
    required this.startCities,
    required this.outlines,
    required this.cityOutlines,
    required this.countries,
    required this.borders,
    required this.seaLinks,
    required this.terrains,
    required this.satelliteMargin,
  }) : _positions = positions;

  /// All cities of the Africa map in id-ascending order.
  final List<Territory> territories;

  /// Width of the map frame, in [tileSize] units.
  final int cols;

  /// Height of the map frame, in [tileSize] units.
  final int rows;

  /// World units per 1.5° of longitude / latitude (the frame's unit).
  final double tileSize;

  /// Start countries (their cities) in army order: the human player first
  /// (America, in the middle of Africa), then bot 1 … bot 6 all around it.
  final List<List<int>> startCities;

  /// Real country outlines (Natural Earth) in map world units, keyed by
  /// region name key (e.g. `region_morocco`). Each outline is a closed ring.
  final Map<String, List<List<Offset>>> outlines;

  /// The area of every city (one or more closed rings), indexed by id.
  final List<List<List<Offset>>> cityOutlines;

  /// Region name key of every city's country, indexed by id.
  final List<String> countries;

  /// Border lines between neighbouring cities and along the coast.
  final List<CityBorder> borders;

  /// Neighbours linked over the sea (Madagascar), as id pairs.
  final List<(int, int)> seaLinks;

  /// Terrain of every city's area, indexed by id.
  final List<Terrain> terrains;

  /// How many [tileSize] units of satellite picture
  /// (`assets/images/africa_satellite.jpg`) lie around the map on every
  /// side. The picture covers the world rect [satelliteRect].
  final int satelliteMargin;

  /// World-space rectangle covered by the satellite picture.
  Rect get satelliteRect => Rect.fromLTWH(
    -satelliteMargin * tileSize,
    -satelliteMargin * tileSize,
    (cols + 2 * satelliteMargin) * tileSize,
    (rows + 2 * satelliteMargin) * tileSize,
  );

  /// Terrain of city [id].
  Terrain terrainOf(int id) => terrains[id];

  /// Region name key of the country city [id] lies in.
  String countryOf(int id) => countries[id];

  /// Ids of all cities of [country] (a region name key).
  List<int> citiesOf(String country) => [
    for (var i = 0; i < countries.length; i++)
      if (countries[i] == country) i,
  ];

  /// Start cities of the human player (Army 1).
  List<int> get playerStartCities => startCities.first;

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
  /// - The JSON does not contain exactly [kTerritoryCount] cities.
  /// - Any adjacency relationship is not bidirectional.
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

  static List<Offset> _points(List<dynamic> flat) => [
    for (var i = 0; i + 1 < flat.length; i += 2)
      Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
  ];

  /// Parses and validates a territory graph from a raw JSON string.
  static TerritoryGraph parse(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final rawList =
        (decoded['territories'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

    // ── Parse ──────────────────────────────────────────────────────────────
    final territories = <Territory>[];
    final positions = <int, TerritoryPosition>{};
    final terrains = <Terrain>[];
    final cityOutlines = <List<List<Offset>>>[];
    final countries = <String>[];

    for (final map in rawList) {
      final id = map['id'] as int;
      if (id != territories.length) {
        throw TerritoryGraphException('City ids must be 0 … n-1 (got $id).');
      }
      territories.add(
        Territory(
          id: id,
          name: map['nameKey'] as String,
          type: _parseTerritoryType(map['type'] as String, id),
          adjacentIds: List.unmodifiable(
            (map['adjacentIds'] as List<dynamic>).cast<int>(),
          ),
          unitCount: 0,
          ownerArmyId: null,
          hasDiamondMine: map['diamondMine'] as bool? ?? false,
        ),
      );
      positions[id] = TerritoryPosition(
        id: id,
        offset: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
      );
      terrains.add(
        Terrain.values.firstWhere(
          (t) => t.name == map['terrain'],
          orElse: () => Terrain.savanna,
        ),
      );
      cityOutlines.add([
        for (final ring in map['outline'] as List<dynamic>? ?? [])
          _points(ring as List<dynamic>),
      ]);
      countries.add('region_${map['country'] ?? ''}');
    }

    // ── Validate ───────────────────────────────────────────────────────────
    _validateCount(territories);
    _validateBidirectionality(territories);

    final startCities = [
      for (final group in decoded['startCities'] as List<dynamic>? ?? [])
        List<int>.unmodifiable((group as List<dynamic>).cast<int>()),
    ];
    if (startCities.length < 2) {
      throw const TerritoryGraphException('At least two start countries.');
    }
    for (final id in startCities.expand((g) => g)) {
      if (id < 0 || id >= territories.length) {
        throw TerritoryGraphException('Start city $id does not exist.');
      }
    }

    final outlines = <String, List<List<Offset>>>{};
    final rawOutlines = decoded['outlines'] as Map<String, dynamic>? ?? {};
    rawOutlines.forEach((key, rings) {
      outlines['region_$key'] = [
        for (final ring in rings as List<dynamic>)
          _points(ring as List<dynamic>),
      ];
    });

    final borders = [
      for (final raw in decoded['borders'] as List<dynamic>? ?? [])
        CityBorder(
          (raw as List<dynamic>)[0] as int,
          (raw[1] as int) < 0 ? null : raw[1] as int,
          _points(raw[2] as List<dynamic>),
        ),
    ];

    return TerritoryGraph._(
      territories: List.unmodifiable(territories),
      positions: Map.unmodifiable(positions),
      cols: decoded['cols'] as int? ?? 1,
      rows: decoded['rows'] as int? ?? 1,
      tileSize: (decoded['tileSize'] as num? ?? 24).toDouble(),
      startCities: List.unmodifiable(startCities),
      outlines: Map.unmodifiable(outlines),
      cityOutlines: List.unmodifiable(cityOutlines),
      countries: List.unmodifiable(countries),
      borders: List.unmodifiable(borders),
      seaLinks: List.unmodifiable([
        for (final pair in decoded['seaLinks'] as List<dynamic>? ?? [])
          ((pair as List<dynamic>)[0] as int, pair[1] as int),
      ]),
      terrains: List.unmodifiable(terrains),
      satelliteMargin: decoded['satelliteMargin'] as int? ?? 0,
    );
  }

  // ─── Query helpers ─────────────────────────────────────────────────────────

  /// Returns the territory with [id].
  ///
  /// Throws [ArgumentError] if no territory with that id exists.
  Territory getById(int id) {
    if (id >= 0 && id < territories.length) return territories[id];
    throw ArgumentError.value(id, 'id', 'No city found with id $id.');
  }

  /// Returns `true` when territory [idB] appears in territory [idA]'s
  /// adjacency list (i.e. the two cities' areas share a border).
  ///
  /// Both ids must exist; throws [ArgumentError] otherwise.
  bool areAdjacent(int idA, int idB) => getById(idA).adjacentIds.contains(idB);

  /// Returns all [Territory] objects that border territory [id].
  ///
  /// Throws [ArgumentError] if [id] does not exist.
  List<Territory> getAdjacentTerritories(int id) => [
    for (final adjId in getById(id).adjacentIds) getById(adjId),
  ];

  /// Returns all territories currently owned by [armyId].
  ///
  /// This method operates on the **template** territories (all unowned at
  /// load time).  Callers working with live game state should filter
  /// [GameState.territories] directly instead.
  List<Territory> getTerritoriesOwnedBy(ArmyId armyId) =>
      territories.where((t) => t.ownerArmyId == armyId).toList(growable: false);

  /// Returns all gold-mine cities (big capitals).
  List<Territory> getBases() => territories
      .where((t) => t.type != TerritoryType.normal)
      .toList(growable: false);

  /// Returns the city marker [Offset] of territory [id].
  ///
  /// Throws [ArgumentError] if [id] does not exist.
  Offset getPosition(int id) => positionOf(id).offset;

  /// Returns the position (city marker) of city [id].
  TerritoryPosition positionOf(int id) {
    final pos = _positions[id];
    if (pos == null) {
      throw ArgumentError.value(id, 'id', 'No position for city $id.');
    }
    return pos;
  }

  /// Returns `true` when cities [a] and [b] are linked over the sea
  /// (Madagascar).
  bool isSeaLink(int a, int b) =>
      seaLinks.any((l) => (l.$1 == a && l.$2 == b) || (l.$1 == b && l.$2 == a));

  /// Steps (through neighbours) from the nearest of [from] to every city.
  List<int> distancesFrom(Iterable<int> from) {
    final dist = List<int>.filled(territories.length, 1 << 20);
    final queue = <int>[];
    for (final id in from) {
      dist[id] = 0;
      queue.add(id);
    }
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      for (final adj in territories[id].adjacentIds) {
        if (dist[adj] > dist[id] + 1) {
          dist[adj] = dist[id] + 1;
          queue.add(adj);
        }
      }
    }
    return dist;
  }

  // ─── Private validation helpers ────────────────────────────────────────────

  static TerritoryType _parseTerritoryType(String raw, int id) {
    for (final t in TerritoryType.values) {
      if (t.name == raw) return t;
    }
    throw TerritoryGraphException('City $id has unknown type "$raw".');
  }

  static void _validateCount(List<Territory> territories) {
    if (territories.length != kTerritoryCount) {
      throw TerritoryGraphException(
        'Expected exactly $kTerritoryCount cities, '
        'but found ${territories.length}.',
      );
    }
  }

  static void _validateBidirectionality(List<Territory> territories) {
    for (final t in territories) {
      for (final adjId in t.adjacentIds) {
        if (adjId < 0 || adjId >= territories.length) {
          throw TerritoryGraphException(
            'City ${t.id} references neighbour $adjId which does not exist.',
          );
        }
        if (!territories[adjId].adjacentIds.contains(t.id)) {
          throw TerritoryGraphException(
            'Adjacency is not bidirectional: city ${t.id} lists $adjId '
            'as a neighbour, but city $adjId does not list ${t.id}.',
          );
        }
      }
    }
  }

  @override
  String toString() =>
      'TerritoryGraph(${territories.length} cities, '
      '${getBases().length} gold mines)';
}
