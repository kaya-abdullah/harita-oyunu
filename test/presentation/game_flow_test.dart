// End-to-end game-flow tests for GameNotifier: initial state, player
// actions, AI turn, cards (hand, Kart Çek, new cards), victory and
// save/load wiring.
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
  // Most flows need neutral land next to America: one bot (Libya) only.
  c.read(newGameBotCountProvider.notifier).set(1);
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

  test('initial state uses the Africa city map graph', () {
    final s = createInitialGameState();
    final graph = TerritoryGraph.bundled();
    expect(s.territories, hasLength(kTerritoryCount));
    for (final t in s.territories) {
      expect(t.adjacentIds, graph.getById(t.id).adjacentIds);
      expect(t.type, graph.getById(t.id).type);
    }
    expect(s.currentTurn, 1);
    expect(s.activeArmyId, ArmyId.army1);
    expect(s.army1.cardCount(AbilityType.fireBomb), kStartFireBombs);
    expect(s.army1.cardCount(AbilityType.bombardment), 0);
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

  test('the player is America in the middle, six bots right next to it', () {
    final s = createInitialGameState(
      difficulty: AiDifficulty.hard,
      botCount: kMaxBots,
    );
    final graph = TerritoryGraph.bundled();
    expect(s.difficulty, AiDifficulty.hard);
    final blue = s.territories.where((t) => t.ownerArmyId == ArmyId.army1);
    expect(
      blue.map((t) => t.id).toSet(),
      graph.citiesOf('region_america').toSet(),
    );
    expect(blue.every((t) => t.unitCount == kPlayerStartUnitsPerCity), isTrue);
    final dist = graph.distancesFrom(blue.map((t) => t.id));
    for (final bot in s.armies.skip(1)) {
      final own = s.territories.where((t) => t.ownerArmyId == bot.id);
      // Its start country and the cities nearest to it: every city of
      // Africa belongs to a bot ("şehirleri yapay zeka kontrol ediyor").
      expect(own.map((t) => t.id).toSet(), {
        for (final t in s.territories)
          if (graph.regions[t.id] == bot.id.index) t.id,
      });
      final home = graph.startCities[bot.id.index].toSet();
      for (final t in own) {
        if (home.contains(t.id)) {
          expect(t.unitCount, kStartUnitsPerCity);
        } else {
          expect(
            t.unitCount,
            inInclusiveRange(kNeutralCityMinUnits, kNeutralCityMaxUnits),
          );
        }
      }
      // Every bot starts right next to America.
      expect(
        own.map((t) => dist[t.id]).reduce(min),
        lessThanOrEqualTo(2),
        reason: '${bot.id}',
      );
    }
    // America is surrounded: all its outside neighbours belong to bots.
    for (final t in blue) {
      for (final adj in t.adjacentIds) {
        expect(s.territories[adj].ownerArmyId, isNotNull);
      }
    }
  });

  testWidgets('player attacks via map taps, deploys, and AI plays its turn', (
    tester,
  ) async {
    final repo = _MemorySaveRepository();
    final c = _container(repo);
    final n = c.read(gameProvider.notifier);

    // Select an own border city; tapping it again deploys the reserve.
    final (src, dst) = _ownBorder(c.read(gameProvider), ArmyId.army1);
    n.onTerritoryTapped(src);
    expect(c.read(selectedTerritoryProvider), src);
    final pool = c.read(gameProvider).army1.totalUnitPool;
    n.onTerritoryTapped(src);
    expect(c.read(gameProvider).army1.totalUnitPool, 0);
    expect(
      c.read(gameProvider).territories[src].unitCount,
      kPlayerStartUnitsPerCity + pool,
    );

    // Tap a neutral neighbour (50–70 soldiers) → conquer it; the winners
    // keep the difference.
    final defenders = c.read(gameProvider).territories[dst].unitCount;
    n.onTerritoryTapped(dst);
    expect(c.read(gameProvider).territories[dst].ownerArmyId, ArmyId.army1);
    expect(
      c.read(gameProvider).territories[dst].unitCount,
      kPlayerStartUnitsPerCity + pool - 1 - defenders,
    );
    expect(c.read(gameProvider).territories[src].unitCount, 1);
    expect(c.read(selectedTerritoryProvider), dst);

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
    // 80 diamonds every turn (plus 250 / 150 for any mine captured).
    expect(
      s.army1.diamondBalance - diamondsBefore,
      anyOf(
        kDiamondsPerTurn,
        kDiamondsPerTurn + kDiamondMineReward,
        kDiamondsPerTurn + kGoldMineReward,
      ),
    );
    final owned = s.territories
        .where((t) => t.ownerArmyId == ArmyId.army1)
        .length;
    // Income is based on the cities owned when the turn ended (4 + 1).
    expect(s.army1.totalUnitPool, kSoldiersPerTurn + 5 * kSoldiersPerCity);
    expect(owned, greaterThanOrEqualTo(1));
    expect(
      s.territories.where((t) => t.ownerArmyId == ArmyId.army2).length,
      greaterThan(aiOwnedBefore),
    );
    expect(repo.saved, isNotNull);
  });

  testWidgets('cards: arm + tap plays one card from the hand', (tester) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);

    // A card not in hand → feedback, not armed.
    n.armAbility(AbilityType.megaBomba);
    expect(c.read(armedAbilityProvider), isNull);
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.noCard);

    n.armAbility(AbilityType.fireBomb);
    expect(c.read(armedAbilityProvider), AbilityType.fireBomb);
    // A city far away in enemy land is not a valid target: stays armed.
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

    // Fire Bomb on a bordering city kills 30 of its soldiers (the city is
    // not taken), and one Fire Bomb card is used up.
    final ownedBefore = _count(c.read(gameProvider), ArmyId.army1);
    final (_, target) = _ownBorder(c.read(gameProvider), ArmyId.army1);
    final unitsBefore = c.read(gameProvider).territories[target].unitCount;
    n.onTerritoryTapped(target);
    expect(c.read(gameProvider).territories[target].ownerArmyId, isNull);
    expect(
      c.read(gameProvider).territories[target].unitCount,
      unitsBefore - kFireBombDamage,
    );
    expect(_count(c.read(gameProvider), ArmyId.army1), ownedBefore);
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.abilityUsed);
    expect(c.read(armedAbilityProvider), isNull);
    expect(
      c.read(gameProvider).army1.cardCount(AbilityType.fireBomb),
      kStartFireBombs - 1,
    );

    // The second Fire Bomb can be played the same turn too.
    n.armAbility(AbilityType.fireBomb);
    n.onTerritoryTapped(target);
    expect(
      c.read(gameProvider).territories[target].unitCount,
      max(1, unitsBefore - 2 * kFireBombDamage),
    );
    expect(c.read(gameProvider).army1.cardCount(AbilityType.fireBomb), 0);

    // Out of Fire Bombs: buying one in the shop adds it to the hand.
    n.armAbility(AbilityType.fireBomb);
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.noCard);
    final item = kWeaponCatalog.firstWhere(
      (i) => i.card == AbilityType.fireBomb,
    );
    final st = c.read(gameProvider);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = st.withArmy(st.army1.copyWith(diamondBalance: 1000));
    expect(n.purchaseItem(item), isTrue);
    expect(c.read(gameProvider).army1.cardCount(AbilityType.fireBomb), 1);
    expect(c.read(gameProvider).army1.diamondBalance, 1000 - item.diamondCost);
  });

  test('Kart Çek: one free card per turn, again after the turn', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final before = c.read(gameProvider).army1.cardTotal;
    n.drawCard();
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.cardDrawn);
    final drawn = AbilityType.values[c.read(gameFeedbackProvider)!.value!];
    expect(c.read(gameProvider).army1.cardTotal, before + 1);
    expect(c.read(gameProvider).army1.cardCount(drawn), greaterThan(0));
    n.drawCard();
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.cardAlreadyDrawn,
    );
    expect(c.read(gameProvider).army1.cardTotal, before + 1);
    final turn = c.read(turnServiceProvider);
    final next = turn.endTurn(c.read(gameProvider));
    expect(next.army1.hasDrawnCard, isFalse);
  });

  test('Atom Bomb hits anywhere; Haraç Kes takes 200 diamonds', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    var s = c.read(gameProvider);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = s
        .withArmy(
          s.army1.copyWith(
            cards: {AbilityType.atomBomb: 1, AbilityType.tribute: 1},
          ),
        )
        .withArmy(s.army2.copyWith(diamondBalance: 500));
    // Deep in enemy land, far from the player.
    final far = s.territories.lastWhere((t) => t.ownerArmyId == ArmyId.army2);
    final ownedBefore = _count(c.read(gameProvider), ArmyId.army1);
    final botBefore = _count(c.read(gameProvider), ArmyId.army2);
    n.armAbility(AbilityType.atomBomb);
    n.onTerritoryTapped(far.id);
    s = c.read(gameProvider);
    // 80 soldiers die in each of 4 cities; the bot keeps its land.
    expect(s.territories[far.id].ownerArmyId, ArmyId.army2);
    expect(s.territories[far.id].unitCount, kBombedCityMinUnits);
    expect(_count(s, ArmyId.army1), ownedBefore);
    expect(s.tilesOwnedBy(ArmyId.army2), botBefore);

    final mine = s.army1.diamondBalance;
    final botTile = s.territories.firstWhere(
      (t) => t.ownerArmyId == ArmyId.army2,
    );
    n.armAbility(AbilityType.tribute);
    n.onTerritoryTapped(botTile.id);
    s = c.read(gameProvider);
    expect(s.army1.diamondBalance, mine + kTributeDiamonds);
    expect(s.army2.diamondBalance, 500 - kTributeDiamonds);
    expect(c.read(gameFeedbackProvider)!.kind, GameFeedbackKind.tributeTaken);
    expect(s.army1.cardTotal, 0);
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

  test('shop cards appear when their turn is reached', () {
    final economy = const EconomyServiceImpl();
    final army = createInitialGameState().army1;
    List<AbilityType> sold(int turn) => [
      for (final i in economy.getEligibleShopItems(army, turn)) i.card,
    ];
    expect(sold(1), [AbilityType.fireBomb, AbilityType.tribute]);
    expect(sold(kTurnUnlockBombardment), contains(AbilityType.bombardment));
    expect(sold(kTurnUnlockAtomBomb), contains(AbilityType.atomBomb));
    expect(sold(kTurnUnlockNuclearBomb), contains(AbilityType.nuclearBomb));
    expect(sold(kTurnUnlockMegaBomba).toSet(), AbilityType.values.toSet());
  });

  test('conquering the last territory declares victory immediately', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final s = createInitialGameState();
    const last = 100;
    final source = s.territories[last].adjacentIds.first;
    // Army 1 owns everything except one city (neutral, 1 soldier).
    final territories = [
      for (final t in s.territories)
        t.id == last
            ? t.copyWith(ownerArmyId: null, unitCount: 1)
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
            ? t.copyWith(ownerArmyId: ArmyId.army1, unitCount: 80)
            : t.id == mine.id
            ? t.copyWith(ownerArmyId: null, unitCount: 50)
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

  test('capturing a base (gold mine) pays 150 diamonds', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final s = createInitialGameState();
    final base = s.territories.firstWhere(
      (t) => t.hasGoldMine && t.ownerArmyId == null,
    );
    final source = base.adjacentIds.first;
    final territories = [
      for (final t in s.territories)
        t.id == source
            ? t.copyWith(ownerArmyId: ArmyId.army1, unitCount: 80)
            : t.id == base.id
            ? t.copyWith(ownerArmyId: null, unitCount: 50)
            : t,
    ];
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    n.state = s.copyWith(territories: territories);
    final before = c.read(gameProvider).army1.diamondBalance;
    n.declareAttack(source, base.id);
    final after = c.read(gameProvider);
    expect(after.territories[base.id].ownerArmyId, ArmyId.army1);
    expect(after.army1.diamondBalance, before + kGoldMineReward);
    expect(
      c.read(gameFeedbackProvider)!.kind,
      GameFeedbackKind.goldMineCaptured,
    );
    expect(c.read(gameFeedbackProvider)!.value, kGoldMineReward);
  });

  test('every base is a gold mine; mines are never on bases', () {
    final s = createInitialGameState();
    for (final t in s.territories) {
      expect(t.hasGoldMine, t.type != TerritoryType.normal);
      expect(t.hasGoldMine && t.hasDiamondMine, isFalse);
    }
    expect(kGoldMineReward, 150);
    expect(kGoldMineReward, lessThan(kDiamondMineReward));
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
    final playerGone = s.copyWith(
      territories: [
        for (final t in s.territories)
          if (t.ownerArmyId == ArmyId.army1)
            t.copyWith(ownerArmyId: null, unitCount: 0)
          else if (t.ownerArmyId == null)
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
    var expanded = 0;
    for (final bot in s.armies.skip(1)) {
      if (s.tilesOwnedBy(bot.id) > 4) expanded++;
      expect(bot.diamondBalance, greaterThanOrEqualTo(kStartDiamonds + 80));
    }
    // The bots sit right next to each other and to America, so they also
    // fight among themselves: at least some of them grew.
    expect(expanded, greaterThanOrEqualTo(1));
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
      expect(s.winnerId, isNot(ArmyId.army1));
      expect(s.winnerId, isNotNull);
      // ignore: avoid_print
      print('AI won on turn ${s.currentTurn}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// An own city of [army] with ≥ 2 units and one of its non-own neighbours.
(int, int) _ownBorder(GameState s, ArmyId army) {
  for (final t in s.territories) {
    if (t.ownerArmyId != army || t.unitCount < 2) continue;
    for (final adj in t.adjacentIds) {
      if (s.territories[adj].ownerArmyId != army) return (t.id, adj);
    }
  }
  throw StateError('no border city');
}

int _count(GameState s, ArmyId army) =>
    s.territories.where((t) => t.ownerArmyId == army).length;

ProviderContainer c0() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}
