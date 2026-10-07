// The Africa city map and the start of a game: regions instead of tiny
// squares, the player's four cities (135 / 125 / 120 / 110), bots close by
// but not next door, up to 10 bots, two players, forests, mines, saving.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/save_data.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/infrastructure/map/territory_graph_data.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

bool _inside(List<Offset> ring, Offset p) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

void main() {
  final graph = TerritoryGraph.bundled();

  group('map', () {
    test('embedded map data matches the JSON asset', () {
      final asset = File('assets/maps/territory_graph.json').readAsStringSync();
      expect(kTerritoryGraphJson.trim(), asset.trim());
    });

    test('Africa is divided into $kTerritoryCount city regions, not tiny '
        'squares', () {
      expect(graph.territories, hasLength(kTerritoryCount));
      expect(graph.cityName(0), 'Kazablanka');
      expect(graph.cityName(0, 'en'), 'Casablanca');
      var corners = 0;
      for (var i = 0; i < kTerritoryCount; i++) {
        final rings = graph.outlines[i];
        expect(rings, isNotEmpty, reason: graph.cityName(i));
        corners += rings.fold<int>(0, (a, r) => a + r.length);
        // Every city marker lies in its own region.
        expect(
          rings.any((r) => _inside(r, graph.getPosition(i))),
          isTrue,
          reason: graph.cityName(i),
        );
      }
      // Real outlines (coasts, borders), not squares: many corners.
      expect(corners / kTerritoryCount, greaterThan(6));
    });

    test('every city can be reached; Madagascar by sea', () {
      final dist = graph.distancesFrom([0]);
      expect(dist.every((d) => d < 1000), isTrue);
      expect(graph.seaLinks, hasLength(1));
      for (final t in graph.territories) {
        expect(t.adjacentIds, isNotEmpty);
        for (final adj in t.adjacentIds) {
          expect(graph.areAdjacent(adj, t.id), isTrue);
        }
      }
    });

    test('three forests, diamond and gold mines', () {
      expect(graph.territories.where((t) => t.hasForest), hasLength(3));
      expect(
        graph.territories.where((t) => t.hasDiamondMine).length,
        greaterThanOrEqualTo(10),
      );
      final gold = graph.territories.where((t) => t.hasGoldMine).toList();
      expect(gold.map((t) => graph.cityName(t.id, 'en')), contains('Cairo'));
    });

    test('the human start cities are four neighbouring cities', () {
      for (final group in graph.humanStarts) {
        expect(group, hasLength(4));
        final reached = graph.distancesFrom([group.first]);
        // Connected through each other.
        for (final id in group) {
          expect(reached[id], lessThanOrEqualTo(3));
        }
      }
      expect([
        for (final id in graph.humanStarts.first) graph.cityName(id, 'en'),
      ], containsAll(['Casablanca', 'Rabat', 'Fez', 'Marrakesh']));
    });
  });

  group('new game', () {
    test('the player has 4 cities with 135, 125, 120 and 110 soldiers', () {
      final s = createInitialGameState(random: Random(1));
      final mine = [
        for (final id in graph.humanStarts.first) s.territories[id],
      ];
      expect(mine.every((t) => t.ownerArmyId == ArmyId.army1), isTrue);
      expect([for (final t in mine) t.unitCount], kHumanStartUnits);
      expect(s.tilesOwnedBy(ArmyId.army1), 4);
    });

    test('3 bots start close to the player but never next door', () {
      final s = createInitialGameState(botCount: 5, random: Random(2));
      final player = graph.humanStarts.first;
      final fromPlayer = graph.distancesFrom(player);
      final near = <ArmyId>{};
      for (final t in s.territories) {
        final o = t.ownerArmyId;
        if (o == null || o == ArmyId.army1) continue;
        expect(
          fromPlayer[t.id],
          greaterThanOrEqualTo(2),
          reason: 'bot city ${graph.cityName(t.id)} is next to the player',
        );
        if (fromPlayer[t.id] == 2) near.add(o);
      }
      expect(near.length, greaterThanOrEqualTo(kBotsNearPlayer));
    });

    test('1 to 10 bots, each with its own cities; bots do not touch each '
        'other at the start', () {
      for (final bots in [1, 6, kMaxBots]) {
        final s = createInitialGameState(botCount: bots, random: Random(3));
        expect(s.armies, hasLength(1 + bots));
        for (final army in s.armies.skip(1)) {
          expect(army.kind, ArmyKind.ai);
          expect(s.tilesOwnedBy(army.id), kBotStartCities, reason: '$army');
        }
        for (final t in s.territories) {
          final o = t.ownerArmyId;
          if (o == null) continue;
          for (final adj in t.adjacentIds) {
            final other = s.territories[adj].ownerArmyId;
            expect(
              other == null || other == o,
              isTrue,
              reason: '$bots bots: ${graph.cityName(t.id)} touches $other',
            );
          }
        }
      }
    });

    test('neutral and bot cities have random soldiers', () {
      final a = createInitialGameState(random: Random(4));
      final b = createInitialGameState(random: Random(5));
      final neutral = a.territories.where((t) => t.ownerArmyId == null);
      for (final t in neutral) {
        expect(
          t.unitCount,
          inInclusiveRange(kNeutralUnitsMin, kNeutralUnitsMax),
        );
      }
      expect([
        for (final t in a.territories) t.unitCount,
      ], isNot([for (final t in b.territories) t.unitCount]));
    });

    test('every army starts with 5 tanks, 4 bombers, a Fire Bomb and '
        'diamonds', () {
      final s = createInitialGameState();
      for (final army in s.armies) {
        expect(army.tanks, kStartTanks);
        expect(army.bombers, kStartBombers);
        expect(army.cardCount(AbilityType.fireBomb), 1);
        expect(army.diamondBalance, kStartDiamonds);
      }
    });

    test('two players: the second human starts in South Africa', () {
      final s = createInitialGameState(humanCount: 2, botCount: 4);
      expect(s.humanIds, [ArmyId.army1, ArmyId.army2]);
      expect(s.armies, hasLength(6));
      for (final id in graph.humanStarts[1]) {
        expect(s.territories[id].ownerArmyId, ArmyId.army2);
      }
      expect(graph.cityName(graph.humanStarts[1].first, 'en'), 'Cape Town');
    });
  });

  test('a game survives saving and loading', () {
    var s = createInitialGameState(
      difficulty: AiDifficulty.hard,
      humanCount: 2,
      botCount: 3,
      random: Random(9),
    );
    s = s.withArmy(
      s.army1.copyWith(
        cards: {AbilityType.atomBomb: 2, AbilityType.tribute: 1},
        tanks: 3,
        tanksUsed: 2,
        bombersFlown: 1,
        hasDrawnCard: true,
      ),
    );
    final loaded = SaveData.fromGameState(s).toGameState();
    expect(loaded, s);
  });
}
