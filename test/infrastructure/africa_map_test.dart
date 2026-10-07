// Africa tile map ("minik kare") and save-format tests.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/save_data.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

void main() {
  final graph = TerritoryGraph.bundled();

  test('map has kTerritoryCount square tiles with unique grid cells', () {
    expect(graph.territories, hasLength(kTerritoryCount));
    final cells = <String>{};
    for (final t in graph.territories) {
      final p = graph.positionOf(t.id);
      expect(cells.add('${p.col},${p.row}'), isTrue);
      expect(p.col, inInclusiveRange(0, graph.cols - 1));
      expect(p.row, inInclusiveRange(0, graph.rows - 1));
      expect(p.offset.dx, (p.col + 0.5) * graph.tileSize);
      expect(p.offset.dy, (p.row + 0.5) * graph.tileSize);
    }
  });

  test('tiles are adjacent only to grid neighbours (plus sea links)', () {
    var seaLinks = 0;
    for (final t in graph.territories) {
      expect(t.adjacentIds, isNotEmpty);
      for (final adj in t.adjacentIds) {
        expect(graph.getById(adj).adjacentIds, contains(t.id));
        if (graph.isSeaLink(t.id, adj)) seaLinks++;
      }
    }
    // Madagascar is linked to the mainland by exactly one (two-way) bridge.
    expect(seaLinks, 2);
  });

  test('every tile can reach every other tile', () {
    final seen = {0};
    final queue = [0];
    while (queue.isNotEmpty) {
      for (final adj in graph.getById(queue.removeLast()).adjacentIds) {
        if (seen.add(adj)) queue.add(adj);
      }
    }
    expect(seen, hasLength(kTerritoryCount));
  });

  test('Africa is taller than wide and has the real cities as bases', () {
    expect(graph.rows, greaterThanOrEqualTo(graph.cols));
    final bases = graph.getBases();
    expect(bases.where((t) => t.type == TerritoryType.bigBase), hasLength(5));
    expect(bases.length, greaterThanOrEqualTo(15));
    expect(
      graph.territories.map((t) => t.name).toSet(),
      containsAll(['region_egypt', 'region_south_africa', 'region_madagascar']),
    );
  });

  test('the map is fine-grained: many tiny tiles', () {
    expect(kTerritoryCount, greaterThan(1000));
  });

  test('real country outlines are drawn for every region with tiles', () {
    final regions = graph.territories.map((t) => t.name).toSet();
    expect(graph.outlines.keys, containsAll(regions));
    for (final rings in graph.outlines.values) {
      expect(rings, isNotEmpty);
      for (final ring in rings) {
        expect(ring.length, greaterThanOrEqualTo(3));
      }
    }
    // The outline of Egypt surrounds Cairo's tile.
    final cairo = graph.positionOf(graph.startIds[2]).offset;
    final egypt = graph.outlines['region_egypt']!.first;
    final xs = egypt.map((p) => p.dx);
    final ys = egypt.map((p) => p.dy);
    expect(cairo.dx, inInclusiveRange(xs.reduce(min), xs.reduce(max)));
    expect(cairo.dy, inInclusiveRange(ys.reduce(min), ys.reduce(max)));
  });

  test('terrain follows the real continent (forests, deserts)', () {
    expect(graph.terrains, hasLength(kTerritoryCount));
    Map<Terrain, int> count(String region) {
      final m = <Terrain, int>{};
      for (final t in graph.territories.where((t) => t.name == region)) {
        final k = graph.terrainOf(t.id);
        m[k] = (m[k] ?? 0) + 1;
      }
      return m;
    }

    Terrain mostly(String region) =>
        count(region).entries.reduce((a, b) => b.value > a.value ? b : a).key;

    expect(mostly('region_congo'), Terrain.rainforest);
    expect(mostly('region_gabon'), Terrain.rainforest);
    expect(mostly('region_libya'), Terrain.desert);
    expect(mostly('region_algeria'), Terrain.desert);
    expect(mostly('region_zambia'), Terrain.woodland);
    for (final t in Terrain.values) {
      expect(graph.terrains, contains(t));
    }
  });

  test('the satellite picture covers the grid with the right shape', () {
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

  test('seven distinct start bases: you plus up to six bots', () {
    expect(graph.startIds, hasLength(kMaxBots + 1));
    expect(graph.startIds.toSet(), hasLength(kMaxBots + 1));
    for (final id in graph.startIds) {
      expect(graph.getById(id).type, isNot(TerritoryType.normal));
    }
  });

  test('diamond mines are spread over the map', () {
    final mines = graph.territories.where((t) => t.hasDiamondMine).toList();
    expect(mines.length, inInclusiveRange(15, 30));
    expect(mines.where((t) => t.type != TerritoryType.normal), isEmpty);
    expect(
      mines.map((t) => t.name).toSet(),
      containsAll([
        'region_botswana',
        'region_south_africa',
        'region_congo',
        'region_sierra_leone',
      ]),
    );
  });

  for (var bots = 1; bots <= kMaxBots; bots++) {
    test('a new game with $bots bot(s) gives every army its own land', () {
      final s = createInitialGameState(botCount: bots);
      expect(s.armies, hasLength(bots + 1));
      expect(s.armies.first.kind, ArmyKind.human);
      expect(s.armies.skip(1).every((a) => a.kind == ArmyKind.ai), isTrue);
      for (final a in s.armies) {
        expect(s.tilesOwnedBy(a.id), kStartTileCount, reason: '${a.id}');
        expect(a.diamondBalance, kStartDiamonds);
      }
      for (final a in s.armies) {
        expect(a.cards, kStartCards);
        expect(a.hasDrawnCard, isFalse);
      }
    });
  }

  test('every region has a Turkish and an English name', () {
    for (final lang in ['tr', 'en']) {
      final bundle =
          jsonDecode(File('assets/locales/$lang.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final t in graph.territories) {
        expect(bundle[t.name], isA<String>(), reason: '$lang ${t.name}');
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

  test('saves from older versions are rejected', () {
    final old = SaveData.fromGameState(createInitialGameState());
    final legacy = SaveData(
      territoriesJson: old.territoriesJson,
      armiesJson: old.armiesJson,
      currentTurn: old.currentTurn,
      activeArmyId: old.activeArmyId,
      phase: old.phase,
      schemaVersion: 2,
    );
    expect(legacy.toGameState, throwsFormatException);
  });
}
