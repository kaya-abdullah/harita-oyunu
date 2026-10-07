// Game-flow tests for GameNotifier: sending soldiers (with the march),
// cards, Kart Çek, bombers, the shop, the bots' turns, two players on one
// phone, victory and saving.
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/economy_service.dart';
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

ProviderContainer _container(
  _MemorySaveRepository repo, {
  int bots = 3,
  int humans = 1,
  AiDifficulty difficulty = AiDifficulty.medium,
}) {
  final c = ProviderContainer(
    overrides: [
      saveRepositoryProvider.overrideWithValue(repo),
      gameRandomProvider.overrideWithValue(Random(5)),
    ],
  );
  addTearDown(c.dispose);
  c
      .read(newGameSettingsProvider.notifier)
      .set(difficulty: difficulty, bots: bots, humans: humans);
  return c;
}

/// Pumps fake time until a human may act again (or the game is over).
Future<void> _waitForBots(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 600; i++) {
    if (c.read(gameProvider).phase == GamePhase.victory) return;
    if (c.read(gameProvider.notifier).isHumanTurn) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('the bots did not finish');
}

/// An own city with soldiers and a weaker neutral neighbour.
(int, int) _attackable(GameState s, ArmyId me) {
  for (final t in s.territories) {
    if (t.ownerArmyId != me || t.unitCount < 50) continue;
    for (final adj in t.adjacentIds) {
      final n = s.territories[adj];
      if (n.ownerArmyId == null && n.unitCount < 40) return (t.id, adj);
    }
  }
  throw StateError('no attack found');
}

void main() {
  testWidgets('drag-attack: soldiers march first, then take the city', (
    tester,
  ) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final (src, dst) = _attackable(c.read(gameProvider), ArmyId.army1);
    final tanks = c.read(gameProvider).army1.tanks;

    final done = n.dispatchTroops(src, dst);
    // Marching: an animation with a tank, nothing decided yet, no other
    // action accepted.
    final fx = c.read(battleFxProvider).single;
    expect(fx.kind, BattleFxKind.march);
    expect(fx.withTank, isTrue);
    expect(n.isHumanTurn, isFalse);
    expect(c.read(gameProvider).territories[dst].ownerArmyId, isNull);

    await tester.pump(const Duration(milliseconds: kMarchMs));
    await done;
    final s = c.read(gameProvider);
    expect(s.territories[dst].ownerArmyId, ArmyId.army1);
    expect(s.territories[src].unitCount, 1);
    expect(s.army1.tanks, tanks, reason: 'a winning tank survives');
    expect(
      c.read(gameFeedbackProvider)?.kind,
      GameFeedbackKind.territoryConquered,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(c.read(battleFxProvider), isEmpty);
  });

  testWidgets('tapping your city, then a neighbour, also attacks', (
    tester,
  ) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final (src, dst) = _attackable(c.read(gameProvider), ArmyId.army1);
    await n.onTerritoryTapped(src);
    expect(c.read(selectedTerritoryProvider), src);
    final done = n.onTerritoryTapped(dst);
    await tester.pump(const Duration(milliseconds: kMarchMs));
    await done;
    expect(c.read(gameProvider).territories[dst].ownerArmyId, ArmyId.army1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('soldiers only go to neighbours', (tester) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final s = c.read(gameProvider);
    final far = s.territories.firstWhere(
      (t) =>
          t.ownerArmyId == null && !s.territories[0].adjacentIds.contains(t.id),
    );
    await n.dispatchTroops(0, far.id);
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.invalidAttack);
    expect(c.read(battleFxProvider), isEmpty);
  });

  test('Kart Çek once per turn, then play the card on a city', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    n.drawCard();
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.cardDrawn);
    expect(c.read(gameProvider).army1.hasDrawnCard, isTrue);
    n.drawCard();
    expect(
      c.read(gameFeedbackProvider)?.kind,
      GameFeedbackKind.cardAlreadyDrawn,
    );

    // Play the Fire Bomb on a weak neutral neighbour: tap card, tap city.
    final (_, dst) = _attackable(c.read(gameProvider), ArmyId.army1);
    n.armAbility(AbilityType.fireBomb);
    expect(c.read(armedAbilityProvider), AbilityType.fireBomb);
    n.onTerritoryTapped(dst);
    final s = c.read(gameProvider);
    expect(s.territories[dst].ownerArmyId, ArmyId.army1);
    expect(s.army1.cardCount(AbilityType.fireBomb), lessThanOrEqualTo(1));
    expect(c.read(armedAbilityProvider), isNull);
    expect(
      c.read(battleFxProvider).map((f) => f.kind),
      contains(BattleFxKind.blast),
    );

    // A card you do not hold cannot be armed.
    n.armAbility(AbilityType.nuclearBomb);
    if (s.army1.cardCount(AbilityType.nuclearBomb) == 0) {
      expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.noCard);
    }
  });

  test('Atom bomb anywhere and Haraç Kes from a bot', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    var s = c.read(gameProvider);
    n.state = s
        .withArmy(
          s.army1.copyWith(
            cards: {AbilityType.atomBomb: 1, AbilityType.tribute: 1},
          ),
        )
        .withArmy(s.army2.copyWith(diamondBalance: 500));
    // Far away from the player: a city of bot 3 (weak enough for the bomb).
    final far = n.state.territories.lastWhere(
      (t) => t.ownerArmyId == ArmyId.army4,
    );
    n.state = n.state.copyWith(
      territories: [
        for (final t in n.state.territories)
          t.id == far.id ? t.copyWith(unitCount: kAtomBombDamage) : t,
      ],
    );
    n.armAbility(AbilityType.atomBomb);
    n.onTerritoryTapped(far.id);
    s = c.read(gameProvider);
    expect(s.territories[far.id].ownerArmyId, ArmyId.army1);
    expect(
      c.read(battleFxProvider).map((f) => f.kind),
      contains(BattleFxKind.nuke),
    );

    final botCity = s.territories.firstWhere(
      (t) => t.ownerArmyId == ArmyId.army2,
    );
    final mine = s.army1.diamondBalance;
    n.armAbility(AbilityType.tribute);
    n.onTerritoryTapped(botCity.id);
    s = c.read(gameProvider);
    expect(s.army1.diamondBalance, mine + kTributeDiamonds);
    expect(s.army2.diamondBalance, 500 - kTributeDiamonds);
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.tributeTaken);
  });

  testWidgets('a bomber flies to any city and kills soldiers there', (
    tester,
  ) async {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final target = c
        .read(gameProvider)
        .territories
        .firstWhere((t) => t.ownerArmyId == ArmyId.army3);
    n.armBomber();
    expect(c.read(armedToolProvider), const ArmedBomber());
    final done = n.onTerritoryTapped(target.id);
    expect(c.read(battleFxProvider).single.kind, BattleFxKind.bomber);
    await tester.pump(const Duration(milliseconds: kBomberFlightMs));
    await done;
    final s = c.read(gameProvider);
    expect(
      s.territories[target.id].unitCount,
      target.unitCount - kBomberDamage,
    );
    expect(s.army1.bombersReady, kStartBombers - 1);
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.bomberHit);
    await tester.pump(const Duration(seconds: 2));
  });

  test('buying in the shop', () {
    final c = _container(_MemorySaveRepository());
    final n = c.read(gameProvider.notifier);
    final bomber = kWeaponCatalog.firstWhere((i) => i.bombers > 0);
    expect(n.purchaseItem(bomber), isFalse);
    expect(
      c.read(gameFeedbackProvider)?.kind,
      GameFeedbackKind.insufficientDiamonds,
    );
    n.state = n.state.withArmy(n.state.army1.copyWith(diamondBalance: 1000));
    expect(n.purchaseItem(bomber), isTrue);
    expect(c.read(gameProvider).army1.bombers, kStartBombers + 1);
    final nuke = kWeaponCatalog.firstWhere(
      (i) => i.card == AbilityType.megaBomba,
    );
    expect(n.purchaseItem(nuke), isTrue);
    expect(c.read(gameProvider).army1.cardCount(AbilityType.megaBomba), 1);
  });

  testWidgets('end turn: the bots play (and fight each other), then it is the '
      'player again', (tester) async {
    final repo = _MemorySaveRepository();
    final c = _container(repo, bots: 6);
    final n = c.read(gameProvider.notifier);
    final diamonds = c.read(gameProvider).army1.diamondBalance;
    n.endTurn();
    expect(n.isHumanTurn, isFalse);
    n.drawCard();
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.notYourTurn);
    await _waitForBots(tester, c);
    final s = c.read(gameProvider);
    expect(s.activeArmyId, ArmyId.army1);
    expect(s.currentTurn, 2);
    expect(s.army1.diamondBalance, greaterThanOrEqualTo(diamonds + 80));
    // Every bot drew its card and grew.
    for (final bot in s.armies.skip(1)) {
      expect(s.tilesOwnedBy(bot.id), greaterThanOrEqualTo(kBotStartCities));
    }
    expect(repo.saved?.currentTurn, 2);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('two players share the phone', (tester) async {
    final c = _container(_MemorySaveRepository(), bots: 2, humans: 2);
    final n = c.read(gameProvider.notifier);
    var s = c.read(gameProvider);
    expect(s.humanIds, [ArmyId.army1, ArmyId.army2]);
    expect(c.read(viewerArmyProvider).id, ArmyId.army1);

    n.endTurn();
    // Player 2 plays straight after player 1 — no bot in between.
    s = c.read(gameProvider);
    expect(s.activeArmyId, ArmyId.army2);
    expect(n.isHumanTurn, isTrue);
    expect(c.read(viewerArmyProvider).id, ArmyId.army2);
    final fb = c.read(gameFeedbackProvider);
    expect(fb?.kind, GameFeedbackKind.nextPlayer);
    expect(fb?.value, ArmyId.army2.index);

    // Player 2 can attack with their own cities.
    final (src, dst) = _attackable(s, ArmyId.army2);
    final done = n.dispatchTroops(src, dst);
    await tester.pump(const Duration(milliseconds: kMarchMs));
    await done;
    expect(c.read(gameProvider).territories[dst].ownerArmyId, ArmyId.army2);

    n.endTurn();
    await _waitForBots(tester, c);
    s = c.read(gameProvider);
    expect(s.activeArmyId, ArmyId.army1);
    expect(c.read(gameFeedbackProvider)?.kind, GameFeedbackKind.nextPlayer);
    await tester.pump(const Duration(seconds: 2));
  });

  test('conquering the last enemy city wins the game', () {
    final c = _container(_MemorySaveRepository(), bots: 1);
    final n = c.read(gameProvider.notifier);
    final s = c.read(gameProvider);
    // Leave the bot one city and give the player a card to take it.
    final botCities = [
      for (final t in s.territories)
        if (t.ownerArmyId == ArmyId.army2) t.id,
    ];
    n.state = s
        .copyWith(
          territories: [
            for (final t in s.territories)
              t.id == botCities.last
                  ? t.copyWith(unitCount: 5)
                  : t.ownerArmyId == ArmyId.army2
                  ? t.copyWith(ownerArmyId: null)
                  : t,
          ],
        )
        .withArmy(s.army1.copyWith(cards: {AbilityType.atomBomb: 1}));
    n.activateAbility(AbilityType.atomBomb, botCities.last);
    final end = c.read(gameProvider);
    expect(end.phase, GamePhase.victory);
    expect(end.winnerId, ArmyId.army1);
  });

  test('save and load', () async {
    final repo = _MemorySaveRepository();
    final c = _container(repo, humans: 2);
    final n = c.read(gameProvider.notifier);
    n.drawCard();
    await n.saveGame();
    final saved = c.read(gameProvider);
    n.state = createInitialGameState();
    expect(await n.loadGame(), isTrue);
    expect(c.read(gameProvider), saved);
  });
}
