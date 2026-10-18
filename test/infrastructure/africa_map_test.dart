// Africa country-and-city map and save-format tests.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/save_data.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/infrastructure/map/territory_graph_data.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

void main() {
  final graph = TerritoryGraph.bundled();

  test('the embedded map is identical to the JSON asset', () {
    expect(
      File('assets/maps/territory_graph.json').readAsStringSync(),
      kTerritoryGraphJson,
    );
  });

  test('every country has 4 cities (the smallest ones 2 or 3)', () {
    expect(graph.territories, hasLength(kTerritoryCount));
    final countries = graph.countries.toSet();
    // Africa's 50 countries plus America in the middle.
    expect(countries, hasLength(51));
    for (final c in countries) {
      expect(graph.citiesOf(c).length, inInclusiveRange(2, 4), reason: c);
    }
    final four = countries.where((c) => graph.citiesOf(c).length == 4);
    expect(four.length, greaterThanOrEqualTo(40));
    for (final c in [
      'region_morocco',
      'region_egypt',
      'region_nigeria',
      'region_congo',
      'region_south_africa',
      'region_madagascar',
    ]) {
      expect(graph.citiesOf(c), hasLength(4), reason: c);
    }
  });

  test('each city lies in its own area, inside its country', () {
    Path pathOf(List<List<Offset>> rings) {
      final p = Path();
      for (final r in rings) {
        p.addPolygon(r, true);
      }
      return p;
    }

    for (final t in graph.territories) {
      final pos = graph.getPosition(t.id);
      expect(graph.cityOutlines[t.id], isNotEmpty);
      expect(
        pathOf(graph.cityOutlines[t.id]).contains(pos),
        isTrue,
        reason: t.name,
      );
      final country = graph.outlines[graph.countryOf(t.id)]!;
      expect(pathOf(country).contains(pos), isTrue, reason: t.name);
    }
  });

  test('cities are neighbours both ways; only Madagascar crosses the sea', () {
    var seaLinks = 0;
    for (final t in graph.territories) {
      expect(t.adjacentIds, isNotEmpty);
      for (final adj in t.adjacentIds) {
        expect(graph.getById(adj).adjacentIds, contains(t.id));
        if (graph.isSeaLink(t.id, adj)) seaLinks++;
      }
    }
    // Madagascar is linked to the mainland by exactly one (two-way) route.
    expect(seaLinks, 2);
    final link = graph.seaLinks.single;
    expect(
      {graph.countryOf(link.$1), graph.countryOf(link.$2)},
      {'region_madagascar', 'region_mozambique'},
    );
  });

  test('every city can reach every other city', () {
    final dist = graph.distancesFrom([0]);
    expect(dist.every((d) => d < kTerritoryCount), isTrue);
  });

  test('border lines join neighbours (or the coast) of every city', () {
    final coast = <int>{};
    for (final b in graph.borders) {
      expect(b.points.length, greaterThanOrEqualTo(2));
      if (b.b == null) {
        coast.add(b.a);
      } else {
        expect(graph.areAdjacent(b.a, b.b!), isTrue);
      }
    }
    // Coastal cities: Casablanca, Cape Town, Mogadishu…
    for (final name in [
      'city_casablanca',
      'city_cape_town',
      'city_mogadishu',
    ]) {
      final id = graph.territories.firstWhere((t) => t.name == name).id;
      expect(coast, contains(id), reason: name);
    }
  });

  test('big capitals are gold mines', () {
    final gold = graph.getBases().map((t) => t.name).toSet();
    expect(
      gold,
      containsAll([
        'city_cairo',
        'city_lagos',
        'city_kinshasa',
        'city_nairobi',
      ]),
    );
    expect(gold.length, inInclusiveRange(10, 15));
  });

  test('real country outlines surround their cities', () {
    expect(graph.outlines.keys.toSet(), graph.countries.toSet());
    for (final rings in graph.outlines.values) {
      expect(rings, isNotEmpty);
      for (final ring in rings) {
        expect(ring.length, greaterThanOrEqualTo(3));
      }
    }
    final cairo = graph.territories.firstWhere((t) => t.name == 'city_cairo');
    expect(graph.countryOf(cairo.id), 'region_egypt');
    final p = graph.getPosition(cairo.id);
    final egypt = graph.outlines['region_egypt']!.first;
    final xs = egypt.map((o) => o.dx);
    final ys = egypt.map((o) => o.dy);
    expect(p.dx, inInclusiveRange(xs.reduce(min), xs.reduce(max)));
    expect(p.dy, inInclusiveRange(ys.reduce(min), ys.reduce(max)));
  });

  test('terrain follows the real continent (forests, deserts)', () {
    expect(graph.terrains, hasLength(kTerritoryCount));
    Terrain mostly(String region) {
      final m = <Terrain, int>{};
      for (final id in graph.citiesOf(region)) {
        final k = graph.terrainOf(id);
        m[k] = (m[k] ?? 0) + 1;
      }
      return m.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    }

    expect(mostly('region_congo'), Terrain.rainforest);
    expect(mostly('region_gabon'), Terrain.rainforest);
    expect(mostly('region_libya'), Terrain.desert);
    expect(mostly('region_algeria'), Terrain.desert);
    expect(mostly('region_zambia'), Terrain.woodland);
    for (final t in Terrain.values) {
      expect(graph.terrains, contains(t));
    }
  });

  test('the satellite picture covers the map with the right shape', () {
    final file = File('assets/images/africa_satellite.jpg');
    expect(file.existsSync(), isTrue);
    expect(graph.satelliteMargin, greaterThan(0));
    final rect = graph.satelliteRect;
    expect(rect.left, lessThan(0));
    expect(rect.right, greaterThan(graph.width));
    // JPEG size from the SOF0 header.
    final bytes = file.readAsBytesSync();
    var i = 2;
    while (bytes[i + 1] != 0xC0 && bytes[i + 1] != 0xC2) {
      i += 2 + (bytes[i + 2] << 8 | bytes[i + 3]);
    }
    final h = bytes[i + 5] << 8 | bytes[i + 6];
    final w = bytes[i + 7] << 8 | bytes[i + 8];
    expect(w / h, closeTo(rect.width / rect.height, 0.01));
  });

  test('seven start countries: you in America in the middle, the six bots '
      'all around it', () {
    expect(graph.startCities, hasLength(kMaxBots + 1));
    final countries = [
      for (final g in graph.startCities) graph.countryOf(g.first),
    ];
    expect(countries.toSet(), hasLength(kMaxBots + 1));
    expect(countries.first, 'region_america');
    // America is round, cut out of the middle of Africa (mostly Chad,
    // which keeps its north).
    final round = graph.outlines['region_america']!;
    expect(round, hasLength(1));
    final xs = round.first.map((p) => p.dx);
    final ys = round.first.map((p) => p.dy);
    final width = xs.reduce(max) - xs.reduce(min);
    final height = ys.reduce(max) - ys.reduce(min);
    expect(width / height, closeTo(1, 0.02));
    expect(graph.citiesOf('region_chad'), hasLength(3));
    for (final g in graph.startCities) {
      // A whole country each.
      expect(g.toSet(), graph.citiesOf(graph.countryOf(g.first)).toSet());
    }
    // America has four cities: Washington (a gold mine), New York, Chicago
    // and Los Angeles.
    expect(
      graph.playerStartCities.map((id) => graph.getById(id).name).toSet(),
      {'city_washington', 'city_new_york', 'city_chicago', 'city_los_angeles'},
    );
    expect(
      graph.playerStartCities.where((id) => graph.getById(id).hasGoldMine),
      hasLength(1),
    );
    // The bots start right next to America ("bot şehirler çok yakın"):
    // most touch it, the rest are one city further.
    final dist = graph.distancesFrom(graph.playerStartCities);
    final steps = [
      for (final g in graph.startCities.skip(1))
        g.map((id) => dist[id]).reduce(min),
    ];
    expect(steps.every((d) => d <= 2), isTrue, reason: '$steps');
    expect(steps.where((d) => d == 1).length, greaterThanOrEqualTo(4));
  });

  test('diamond mines are spread over the map', () {
    final mines = graph.territories.where((t) => t.hasDiamondMine).toList();
    expect(mines.length, inInclusiveRange(10, 20));
    expect(
      mines.map((t) => graph.countryOf(t.id)).toSet(),
      containsAll([
        'region_botswana',
        'region_south_africa',
        'region_congo',
        'region_sierra_leone',
      ]),
    );
  });

  for (var bots = 1; bots <= kMaxBots; bots++) {
    test('a new game with $bots bot(s): America is yours, the bots own the '
        'rest around their start countries', () {
      final s = createInitialGameState(botCount: bots);
      expect(s.armies, hasLength(bots + 1));
      expect(s.armies.first.kind, ArmyKind.human);
      expect(s.armies.skip(1).every((a) => a.kind == ArmyKind.ai), isTrue);
      for (final a in s.armies) {
        final own = s.territories.where((t) => t.ownerArmyId == a.id);
        expect(own.map((t) => t.id).toSet(), {
          for (final t in s.territories)
            if (graph.regions[t.id] == a.id.index) t.id,
        });
        expect(
          own.map((t) => t.id).toSet(),
          containsAll(graph.startCities[a.id.index]),
        );
        final home = graph.startCities[a.id.index].toSet();
        for (final t in own) {
          if (a.id == ArmyId.army1) {
            // America starts much stronger: it is surrounded by bots.
            expect(t.unitCount, kPlayerStartUnitsPerCity);
          } else if (home.contains(t.id)) {
            expect(t.unitCount, kStartUnitsPerCity);
          } else {
            expect(
              t.unitCount,
              inInclusiveRange(kNeutralCityMinUnits, kNeutralCityMaxUnits),
            );
          }
        }
        expect(a.diamondBalance, kStartDiamonds);
        expect(a.totalUnitPool, kStartUnitPool);
        expect(a.cards, kStartCards);
        expect(a.hasDrawnCard, isFalse);
      }
    });
  }

  test('with all six bots every city of Africa belongs to someone', () {
    for (var seed = 0; seed < 5; seed++) {
      final s = createInitialGameState(
        botCount: kMaxBots,
        random: Random(seed),
      );
      expect(s.territories.where((t) => t.ownerArmyId == null), isEmpty);
      // The bots' other cities hold 50 to 70 soldiers, not all the same.
      final home = graph.startCities.expand((g) => g).toSet();
      final others = s.territories.where((t) => !home.contains(t.id));
      for (final t in others) {
        expect(
          t.unitCount,
          inInclusiveRange(kNeutralCityMinUnits, kNeutralCityMaxUnits),
        );
      }
      expect(others.map((t) => t.unitCount).toSet().length, greaterThan(5));
    }
    // Every bot holds one connected stretch of land.
    for (var army = 1; army <= kMaxBots; army++) {
      final mine = {
        for (var id = 0; id < graph.regions.length; id++)
          if (graph.regions[id] == army) id,
      };
      final seen = {mine.first};
      final queue = [mine.first];
      while (queue.isNotEmpty) {
        for (final nb in graph.getById(queue.removeLast()).adjacentIds) {
          if (mine.contains(nb) && seen.add(nb)) queue.add(nb);
        }
      }
      expect(seen, mine, reason: 'bot $army');
    }
  });

  test('cities are separate patches with empty land between them', () {
    // No two city areas touch: the land between them belongs to nobody
    // and cannot be attacked ("boş alan, saldırı yapılmaz").
    Path pathOf(int id) {
      final p = Path();
      for (final ring in graph.cityOutlines[id]) {
        p.addPolygon(ring, true);
      }
      return p;
    }

    for (final t in graph.territories) {
      expect(graph.cityOutlines[t.id], hasLength(1), reason: t.name);
      final mine = pathOf(t.id);
      // The city itself stands on its patch.
      expect(mine.contains(graph.getPosition(t.id)), isTrue, reason: t.name);
      for (final adj in t.adjacentIds) {
        // A point of the neighbour's patch is never inside this one.
        for (final p in graph.cityOutlines[adj].first) {
          expect(mine.contains(p), isFalse, reason: '${t.name} / $adj');
        }
      }
    }
  });

  test('every city and country has a Turkish and an English name', () {
    for (final lang in ['tr', 'en']) {
      final bundle =
          jsonDecode(File('assets/locales/$lang.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final t in graph.territories) {
        expect(bundle[t.name], isA<String>(), reason: '$lang ${t.name}');
        expect(
          bundle[graph.countryOf(t.id)],
          isA<String>(),
          reason: '$lang ${graph.countryOf(t.id)}',
        );
      }
      for (final key in [
        'difficulty_title',
        'difficulty_very_easy',
        'difficulty_medium',
        'difficulty_hard',
      ]) {
        expect(bundle[key], isA<String>(), reason: '$lang $key');
      }
    }
  });

  test('save data round-trips the Africa state and difficulty', () {
    for (final d in AiDifficulty.values) {
      final s = createInitialGameState(difficulty: d);
      expect(SaveData.fromGameState(s).toGameState(), s);
    }
    final six = createInitialGameState(botCount: kMaxBots);
    expect(SaveData.fromGameState(six).toGameState(), six);
  });

  test('saves from older versions (the tile map) are rejected', () {
    final old = SaveData.fromGameState(createInitialGameState());
    for (final version in [2, 4]) {
      final legacy = SaveData(
        territoriesJson: old.territoriesJson,
        armiesJson: old.armiesJson,
        currentTurn: old.currentTurn,
        activeArmyId: old.activeArmyId,
        phase: old.phase,
        schemaVersion: version,
      );
      expect(legacy.toGameState, throwsFormatException);
    }
  });

  test('bomb areas stay inside the map and skip own cities', () {
    final s = createInitialGameState(random: Random(1));
    final target = s.territories.firstWhere(
      (t) =>
          t.ownerArmyId == null &&
          t.adjacentIds.any(
            (a) => s.territories[a].ownerArmyId == ArmyId.army1,
          ),
    );
    final area = bombArea(s.territories, ArmyId.army1, target.id, 6);
    expect(area, hasLength(6));
    expect(area.first, target.id);
    for (final id in area) {
      expect(s.territories[id].ownerArmyId, isNot(ArmyId.army1));
    }
    expect(graph.getById(target.id).type, isA<TerritoryType>());
  });
}
