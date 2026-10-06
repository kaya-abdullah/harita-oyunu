// End-to-end game-flow tests for GameNotifier: initial state, player
// actions, AI turn, abilities, victory and save/load wiring.
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/infrastructure/map/territory_graph_data.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

class _MemorySaveRepository implements SaveRepository {
  GameState? saved;

  @override
  Future<void> deleteSave() async => saved = null;

  @override
  Future<bool> hasSave() async => saved != null;

  @override
  Future<GameState?> loadGameState() async => saved;

  @override
  Future<void> saveGameState(GameState state) async => saved = state;
}

ProviderContainer _container(_MemorySaveRepository repo) {
  final c = ProviderContainer(
    overrides: [saveRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Pumps fake time until the AI has handed control back (or game over).
Future<void> _waitForAi(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 400; i++) {
    final s = c.read(gameProvider);
    if (s.phase == GamePhase.victory) return;
    if (c.read(gameProvider.notifier).isHumanTurn) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('AI turn did not finish');
}

void main() {
  test('embedded map data matches the JSON asset', () {
    final asset = File('assets/maps/territory_graph.json').readAsStringSync();
    expect(kTerritoryGraphJson.trim(), asset.trim());
  });

  test('initial state uses the Africa tile map graph', () {
    final s = createInitialGameState();
    final graph = TerritoryGraph.bundled();
    expect(s.territories, hasLength(kTerritoryCount));
    for (final t in s.territories) {
      expect(t.adjacentIds, graph.getById(t.id).adjacentIds);
      expect(t.type, graph.getById(t.id).type);
    }
    expect(s.currentTurn, 1);
    expect(s.activeArmyId, ArmyId.army1);
    expect(s.army1.abilities[AbilityType.fireBomb]!.isUnlocked, isTrue);
    expect(s.army1.abilities[AbilityType.bombardment]!.isUnlocked, isFalse);
    expect(
      s.territories.where((t) => t.ownerArmyId == ArmyId.army1),
      isNotEmpty,
    );
    expect(
      s.territories.where((t) => t.ownerArmyId == ArmyId.army2),
      isNotEmpty,
    );
    expect(s.difficulty, AiDifficulty.medium);
  });

  test('armies start at opposite ends of Africa with equal forces', () {
    final s = createInitialGameState(difficulty: AiDifficulty.hard);
    final graph = TerritoryGraph.bundled();
    expect(s.difficulty, AiDifficulty.hard);
    final blue = s.territories.where((t) => t.ownerArmyId == ArmyId.army1);
    final red = s.territories.where((t) => t.ownerArmyId == ArmyId.army2);
    expect(blue, hasLength(kStartTileCount));
    expect(red, hasLength(kStartTileCount));
    expect(blue.every((t) => t.unitCount == kStartUnitsPerTile), isTrue);
    expect(red.every((t) => t.unitCount == kStartUnitsPerTile), isTrue);
    // Each starts on its own base.
    expect(s.territories[graph.playerStartId].ownerArmyId, ArmyId.army1);
    expect(s.territories[graph.botStartId].ownerArmyId, ArmyId.army2);
    expect(
      s.territories[graph.playerStartId].type,
      isNot(TerritoryType.normal),
    );
    // Player in the far north, bot in the far south.
    final blueRows = blue.map((t) => graph.positionOf(t.id).row);
    final redRows = red.map((t) => graph.positionOf(t.id).row);
    expect(blueRows.reduce(max), lessThan(graph.rows ~/ 3));
    expect(redRows.reduce(min), greaterThan(graph.rows * 2 ~/ 3));
  });

  testWidgets('player attacks via map taps, deploys, and AI plays its turn', (
    tester,
  ) async {
    final repo = _MemorySaveRepository();
    final c = _container(repo);
    final n = c.read(gameProvider.notifier);

    // Select an own border tile then tap a neutral neighbour → conquer.
    final (src, dst) = _ownBorder(c.read(gameProvider), ArmyId.army1);
    n.onTerritoryTapped(src);
    expect(c.read(selectedTerritoryProvider), src);
    n.onTerritoryTapped(dst);
    expect(c.read(gameProvider).territories[dst].ownerArmyId, ArmyId.army1);
    expect(c.read(selectedTerritoryProvider), dst);

    // Tapping the selected territory again deploys the unit pool.
    final pool = c.read(gameProvider).army1.totalUnitPool;
    final before = c.read(gameProvider).territories[dst].unitCount;
    n.onTerritoryTapped(dst);
    expect(c.read(gameProvider).army1.totalUnitPool, 0);
    expect(c.read(gameProvider).territories[dst].unitCount, before + pool);

    final diamondsBefore = c.read(gameProvider).army1.diamondBalance;
    final aiOwnedBefore = c
        .read(gameProvider)
        .territories
        .where((t) => t.ownerArmyId == ArmyId.army2)
        .length;

    n.endTurn();
    expect(n.isHumanTurn, isFalse);
    // Human actions are rejected during the AI turn.
    n.endTurn();
    await _waitForAi(tester, c);

    final s = c.read(gameProvider);
    expect(s.activeArmyId, ArmyId.army1);
    expect(s.currentTurn, 2);
    // 80 diamonds every turn (plus 250 for any mine captured).
    expect(
      s.army1.diamondBalance - diamondsBefore,
      anyOf(kDiamondsPerTurn, kDiamondsPerTurn + kDiamondMineReward),
    );
    final owned = s.territories
        .where((t) => t.ownerArmyId == ArmyId.army1)
        .length;
    // Income is based on the tiles owned when the turn ended.
    expect(
      s.army1.totalUnitPool,
      kSoldiersPerTurn + (kStartTileCount + 1) ~/ kTilesPerBonusSoldier,
    );
    expect(owned, greaterThanOrEqualTo(1));
    expect(
      s.territories.where((t) => t.ownerArmyId == ArmyId.army2).length,
      greaterThan(aiOwnedBefore),
    );
    expect(repo.saved, isNotNull);
  });

  testWidgets('abilities: arm + tap fires once per turn', (tester) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);

    // Locked ability → feedback, not armed.
    n.armAbility(AbilityType.megaBomba);
    expect(c.read(armedAbilityProvider), isNull);
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.abilityLocked);
    expect(c.read(gameFeedbackProvider)!.value, kTurnUnlockMegaBomba);

    n.armAbility(AbilityType.fireBomb);
    expect(c.read(armedAbilityProvider), AbilityType.fireBomb);
    // A tile far away in enemy land is not a valid target: stays armed.
    final enemyTile = c
        .read(gameProvider)
        .territories
        .firstWhere((t) => t.ownerArmyId == ArmyId.army2);
    n.onTerritoryTapped(enemyTile.id);
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.invalidAbilityTarget,
    );
    expect(c.read(armedAbilityProvider), AbilityType.fireBomb);
    expect(
      c.read(gameProvider).territories[enemyTile.id].ownerArmyId,
      ArmyId.army2,
    );

    // Fire Bomb on a bordering tile captures that tile and one more.
    final ownedBefore = _count(c.read(gameProvider), ArmyId.army1);
    final (_, target) = _ownBorder(c.read(gameProvider), ArmyId.army1);
    n.onTerritoryTapped(target);
    expect(c.read(gameProvider).territories[target].ownerArmyId, ArmyId.army1);
    expect(
      _count(c.read(gameProvider), ArmyId.army1),
      ownedBefore + kFireBombTiles,
    );
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.abilityUsed);
    expect(c.read(armedAbilityProvider), isNull);

    // Second use the same turn is blocked by the per-turn cooldown...
    n.armAbility(AbilityType.fireBomb);
    expect(c.read(armedAbilityProvider), isNull);
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.abilityCooldown,
    );

    // ...unless a shop pack is owned.
    final pack = kWeaponCatalog.firstWhere(
      (item) => item.id == 'fire_bomb_pack',
    );
    final st = c.read(gameProvider);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = st.withArmy(st.army1.copyWith(diamondBalance: 1000));
    expect(n.purchaseItem(pack), isTrue);
    n.armAbility(AbilityType.fireBomb);
    expect(c.read(armedAbilityProvider), AbilityType.fireBomb);
    final (_, second) = _ownBorder(c.read(gameProvider), ArmyId.army1);
    n.onTerritoryTapped(second);
    expect(c.read(gameProvider).territories[second].ownerArmyId, ArmyId.army1);
    expect(c.read(gameProvider).army1.inventory, isEmpty);
  });

  test('purchase with insufficient diamonds is rejected', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final item = kWeaponCatalog.first;
    expect(n.purchaseItem(item), isFalse);
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.insufficientDiamonds,
    );
  });

  test('abilities unlock exactly when their turn is reached', () {
    final c = _container(_MemorySaveRepository());
    final turn = c.read(turnServiceProvider);
    var s = createInitialGameState();
    while (s.currentTurn < kTurnUnlockBombardment) {
      expect(s.army1.abilities[AbilityType.bombardment]!.isUnlocked, isFalse);
      s = turn.endTurn(turn.endTurn(s));
    }
    expect(s.currentTurn, kTurnUnlockBombardment);
    expect(s.army1.abilities[AbilityType.bombardment]!.isUnlocked, isTrue);
    expect(s.army2.abilities[AbilityType.bombardment]!.isUnlocked, isTrue);
    expect(s.army1.abilities[AbilityType.soldierSpell]!.isUnlocked, isFalse);
  });

  test('conquering the last territory declares victory immediately', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final s = createInitialGameState();
    const last = 100;
    final source = s.territories[last].adjacentIds.first;
    // Army 1 owns everything except one tile (neutral, 0 units).
    final territories = [
      for (final t in s.territories)
        t.id == last
            ? t.copyWith(ownerArmyId: null, unitCount: 0)
            : t.copyWith(ownerArmyId: ArmyId.army1, unitCount: 5),
    ];
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = s.copyWith(territories: territories);
    n.declareAttack(source, last);
    final after = c.read(gameProvider);
    expect(after.phase, GamePhase.victory);
    expect(after.winnerId, ArmyId.army1);

    // No further actions are accepted.
    n.endTurn();
    expect(c.read(gameProvider).currentTurn, after.currentTurn);
  });

  test('eliminating every enemy territory is a victory', () {
    final victory = c0().read(victoryServiceProvider);
    final s = createInitialGameState();
    final territories = [
      for (final t in s.territories)
        t.ownerArmyId == ArmyId.army2
            ? t.copyWith(ownerArmyId: null, unitCount: 0)
            : t,
    ];
    expect(
      victory.checkVictory(s.copyWith(territories: territories)),
      ArmyId.army1,
    );
  });

  test('capturing a diamond mine by attack pays 250 diamonds', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final s = createInitialGameState();
    final mine = s.territories.firstWhere((t) => t.hasDiamondMine);
    final source = mine.adjacentIds.first;
    final territories = [
      for (final t in s.territories)
        t.id == source
            ? t.copyWith(ownerArmyId: ArmyId.army1, unitCount: 10)
            : t.id == mine.id
            ? t.copyWith(ownerArmyId: null, unitCount: 0)
            : t,
    ];
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = s.copyWith(territories: territories);
    final before = c.read(gameProvider).army1.diamondBalance;
    n.declareAttack(source, mine.id);
    final after = c.read(gameProvider);
    expect(after.territories[mine.id].ownerArmyId, ArmyId.army1);
    expect(after.army1.diamondBalance, before + kDiamondMineReward);
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.diamondMineCaptured,
    );
    expect(c.read(gameFeedbackProvider)!.value, kDiamondMineReward);

    // Moving units onto an own mine pays nothing more.
    n.declareAttack(mine.id, source);
    expect(
      c.read(gameProvider).army1.diamondBalance,
      after.army1.diamondBalance,
    );
  });

  test('every army earns 80 diamonds at the end of its turn', () {
    final turn = c0().read(turnServiceProvider);
    final s = createInitialGameState(botCount: 3);
    final next = turn.endTurn(s);
    expect(next.army1.diamondBalance, kStartDiamonds + kDiamondsPerTurn);
    expect(next.army2.diamondBalance, kStartDiamonds);
    expect(next.activeArmyId, ArmyId.army2);
  });

  test('turns go round all bots and skip eliminated ones', () {
    final turn = c0().read(turnServiceProvider);
    var s = createInitialGameState(botCount: 3);
    // Bot 2 (army3) loses all its land.
    s = s.copyWith(
      territories: [
        for (final t in s.territories)
          t.ownerArmyId == ArmyId.army3
              ? t.copyWith(ownerArmyId: null, unitCount: 0)
              : t,
      ],
    );
    final order = <ArmyId>[];
    for (var i = 0; i < 6; i++) {
      s = turn.endTurn(s);
      order.add(s.activeArmyId);
    }
    expect(order, [
      ArmyId.army2,
      ArmyId.army4,
      ArmyId.army1,
      ArmyId.army2,
      ArmyId.army4,
      ArmyId.army1,
    ]);
    expect(s.currentTurn, 3);
  });

  test('victory: the last army standing wins; losing all land loses', () {
    final victory = c0().read(victoryServiceProvider);
    final s = createInitialGameState(botCount: 3);
    expect(victory.checkVictory(s), isNull);

    // Only one bot left besides the player: the game goes on.
    final oneBotLeft = s.copyWith(
      territories: [
        for (final t in s.territories)
          t.ownerArmyId == ArmyId.army2 || t.ownerArmyId == ArmyId.army3
              ? t.copyWith(ownerArmyId: null, unitCount: 0)
              : t,
      ],
    );
    expect(victory.checkVictory(oneBotLeft), isNull);

    // Every bot gone: the player wins.
    final allBotsGone = s.copyWith(
      territories: [
        for (final t in s.territories)
          t.ownerArmyId != ArmyId.army1
              ? t.copyWith(ownerArmyId: null, unitCount: 0)
              : t,
      ],
    );
    expect(victory.checkVictory(allBotsGone), ArmyId.army1);

    // The player gone: the bot with the most land wins.
    var bigger = 0;
    final playerGone = s.copyWith(
      territories: [
        for (final t in s.territories)
          if (t.ownerArmyId == ArmyId.army1)
            t.copyWith(ownerArmyId: null, unitCount: 0)
          else if (t.ownerArmyId == null && bigger++ < 5)
            t.copyWith(ownerArmyId: ArmyId.army4, unitCount: 1)
          else
            t,
      ],
    );
    expect(victory.checkVictory(playerGone), ArmyId.army4);
  });

  testWidgets('with six bots every bot plays before the player again', (
    tester,
  ) async {
    final repo = _MemorySaveRepository();
    final c = _container(repo);
    c.read(newGameBotCountProvider.notifier).set(kMaxBots);
    final n = c.read(gameProvider.notifier);
    final start = c.read(gameProvider);
    expect(start.armies, hasLength(kMaxBots + 1));

    n.endTurn();
    expect(n.isHumanTurn, isFalse);
    await _waitForAi(tester, c);

    final s = c.read(gameProvider);
    expect(s.activeArmyId, ArmyId.army1);
    expect(s.currentTurn, 2);
    for (final bot in s.armies.skip(1)) {
      expect(
        s.tilesOwnedBy(bot.id),
        greaterThan(kStartTileCount),
        reason: '${bot.id} should have expanded',
      );
      expect(bot.diamondBalance, greaterThanOrEqualTo(kStartDiamonds + 80));
    }
    expect(repo.saved?.armies, hasLength(kMaxBots + 1));
  });

  testWidgets('loading a save taken before the AI turn resumes the AI', (
    tester,
  ) async {
    final repo = _MemorySaveRepository();
    final c = _container(repo);
    final turn = c.read(turnServiceProvider);
    repo.saved = turn.endTurn(createInitialGameState()); // army2 to play
    final n = c.read(gameProvider.notifier);
    expect(await n.loadGame(), isTrue);
    await _waitForAi(tester, c);
    expect(c.read(gameProvider).activeArmyId, ArmyId.army1);
    expect(c.read(gameProvider).currentTurn, 2);
  });

  testWidgets(
    'a passive player is eventually defeated by the AI',
    (tester) async {
      final c = _container(_MemorySaveRepository());
      final n = c.read(gameProvider.notifier);
      for (var i = 0; i < 300; i++) {
        if (c.read(gameProvider).phase == GamePhase.victory) break;
        n.endTurn();
        await _waitForAi(tester, c);
      }
      await tester.pump(const Duration(seconds: 2));
      final s = c.read(gameProvider);
      expect(s.phase, GamePhase.victory);
      expect(s.winnerId, ArmyId.army2);
      // ignore: avoid_print
      print('AI won on turn ${s.currentTurn}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// An own tile of [army] with ≥ 2 units and one of its non-own neighbours.
(int, int) _ownBorder(GameState s, ArmyId army) {
  for (final t in s.territories) {
    if (t.ownerArmyId != army || t.unitCount < 2) continue;
    for (final adj in t.adjacentIds) {
      if (s.territories[adj].ownerArmyId != army) return (t.id, adj);
    }
  }
  throw StateError('no border tile');
}

int _count(GameState s, ArmyId army) =>
    s.territories.where((t) => t.ownerArmyId == army).length;

ProviderContainer c0() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}
