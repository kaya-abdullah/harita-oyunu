// Africa tile map ("minik kare") and save-format tests.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/save_data.dart';
import 'package:harita/domain/models/territory.dart';
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
  });

  test('saves from the old 60-territory version are rejected', () {
    final old = SaveData.fromGameState(createInitialGameState());
    final legacy = SaveData(
      territoriesJson: old.territoriesJson,
      army1Json: old.army1Json,
      army2Json: old.army2Json,
      currentTurn: old.currentTurn,
      activeArmyId: old.activeArmyId,
      phase: old.phase,
      schemaVersion: 1,
    );
    expect(legacy.toGameState, throwsFormatException);
  });
}
