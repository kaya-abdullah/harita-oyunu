// End-to-end test of the whole app as the player sees it: the bomb intro,
// the menu, the new-game picker (3 bots, Zor), the city map with the shop
// beside it, Kart Çek, dragging soldiers to a city, a card, a bomber,
// buying a tank, the bots' turns, going back to the menu and resuming —
// then a two-player game where the phone passes between the players.
import 'dart:io';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/ai/greedy_ai_agent.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';
import 'package:harita/presentation/screens/game_screen.dart';
import 'package:harita/presentation/screens/intro_screen.dart';
import 'package:harita/presentation/screens/main_menu_screen.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/viewmodels/tutorial_viewmodel.dart';

/// Tutorial progress kept in memory (no device storage in tests).
class _MemoryTutorial extends TutorialNotifier {
  @override
  Future<void> init() async {}
}

class _MemorySave implements SaveRepository {
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

void main() {
  // The tutorial writes its "seen" flag in the background; give Hive a
  // throw-away folder so that write has somewhere to go.
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync().path));

  testWidgets('play a whole round end to end', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _MemorySave();
    final container = ProviderContainer(
      overrides: [
        saveRepositoryProvider.overrideWithValue(repo),
        tutorialProvider.overrideWith(_MemoryTutorial.new),
        gameRandomProvider.overrideWithValue(Random(11)),
        abilityServiceProvider.overrideWithValue(
          AbilityServiceImpl(random: Random(12)),
        ),
        aiAgentProvider.overrideWith(
          (ref) => GreedyAiAgent(
            combat: ref.watch(combatServiceProvider),
            ability: ref.watch(abilityServiceProvider),
            economy: ref.watch(economyServiceProvider),
            random: Random(13),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(localeServiceProvider.future));

    Future<void> frames([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: IntroScreen()),
      ),
    );

    // ── 1. Intro: the drawn atom bomb, smoke, then the menu ───────────────
    expect(find.byKey(const Key('intro_overlay')), findsOneWidget);
    expect(find.byKey(const Key('intro_photo')), findsNothing);
    await tester.pump(IntroScreen.duration);
    await frames();
    expect(find.byKey(const Key('intro_overlay')), findsNothing);
    expect(find.text('Yeni Oyun'), findsOneWidget);
    expect(find.text('Nasıl Oynanır?'), findsOneWidget);
    expect(find.text('Devam Et'), findsNothing);

    // ── 2. New game: first the how-to-play steps (skipped) ────────────────
    await tester.tap(find.text('Yeni Oyun'));
    await frames();
    expect(find.text('Atla'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    await frames();

    // ── 3. Picker: 1 player, 3 bots, Zor ──────────────────────────────────
    expect(find.text('Kaç kişi oynuyor?'), findsOneWidget);
    expect(find.text('Kaç bot oynasın?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bots_3')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('difficulty_hard')));
    await tester.tap(find.byKey(const Key('difficulty_hard')));
    await frames(10);

    expect(find.byType(GameScreen), findsOneWidget);
    var state = container.read(gameProvider);
    expect(state.armies, hasLength(4));
    expect(state.difficulty, AiDifficulty.hard);
    expect(state.territories, hasLength(kTerritoryCount));
    expect(state.tilesOwnedBy(ArmyId.army1), 4);
    for (final id in ArmyId.values.take(4)) {
      expect(find.byKey(Key('army_chip_${id.name}')), findsOneWidget);
    }
    // The shop is open beside the map with everything for sale.
    expect(find.byKey(const Key('weapon_shop')), findsOneWidget);
    expect(find.byKey(const Key('shop_fire_bomb')), findsOneWidget);

    final game = tester
        .widget<GameWidget<WarGame>>(find.byType(GameWidget<WarGame>))
        .game!;
    final origin = tester.getTopLeft(find.byType(GameWidget<WarGame>));
    Offset screenOf(int id) {
      final p = game.mapComponent.graph.getPosition(id);
      final s = game.camera.localToGlobal(Vector2(p.dx, p.dy));
      return origin + Offset(s.x, s.y);
    }

    Future<void> tapCity(int id) async {
      await tester.tapAt(screenOf(id));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ── 4. Kart Çek ──────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('btn_draw_card')));
    await tester.pump();
    state = container.read(gameProvider);
    expect(state.army1.hasDrawnCard, isTrue);
    expect(state.army1.cards.values.fold(0, (a, b) => a + b), 2);

    // ── 5. Saldır: drag soldiers from a city to a weaker neighbour ────────
    await tester.tap(find.byKey(const Key('btn_attack')));
    await tester.pump();
    expect(find.textContaining('sürükle'), findsWidgets);
    final (src, dst) = _attackable(state);
    game.camera.viewfinder.position = Vector2(
      (game.mapComponent.graph.getPosition(src).dx +
              game.mapComponent.graph.getPosition(dst).dx) /
          2,
      (game.mapComponent.graph.getPosition(src).dy +
              game.mapComponent.graph.getPosition(dst).dy) /
          2,
    );
    await tester.pump();
    final gesture = await tester.startGesture(screenOf(src));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(screenOf(src), screenOf(dst), i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: kMarchMs + 100));
    state = container.read(gameProvider);
    expect(state.territories[dst].ownerArmyId, ArmyId.army1);
    expect(state.tilesOwnedBy(ArmyId.army1), 5);
    await frames(20);

    // ── 6. Fire Bomb card: tap the card, then a city ──────────────────────
    final target = _bombable(state);
    await tester.tap(find.byKey(const Key('ability_fireBomb')));
    await tester.pump();
    expect(container.read(armedAbilityProvider), AbilityType.fireBomb);
    await tapCity(target);
    state = container.read(gameProvider);
    expect(state.territories[target].ownerArmyId, ArmyId.army1);
    expect(
      container.read(gameFeedbackProvider)?.kind,
      GameFeedbackKind.abilityUsed,
    );
    await frames(20);

    // ── 7. Bomber: the Uçak button, then a bot city ──────────────────────
    final botCity = state.territories.firstWhere(
      (t) => t.ownerArmyId == ArmyId.army2,
    );
    await tester.tap(find.byKey(const Key('btn_bomber')));
    await tester.pump();
    expect(container.read(armedToolProvider), const ArmedBomber());
    game.camera.viewfinder.position = Vector2(
      game.mapComponent.graph.getPosition(botCity.id).dx,
      game.mapComponent.graph.getPosition(botCity.id).dy,
    );
    await tester.pump();
    await tapCity(botCity.id);
    await tester.pump(const Duration(milliseconds: kBomberFlightMs + 100));
    state = container.read(gameProvider);
    expect(
      state.territories[botCity.id].unitCount,
      botCity.unitCount - kBomberDamage,
    );
    expect(state.army1.bombersReady, kStartBombers - 1);
    await frames(20);

    // ── 8. Shop: buy a tank ───────────────────────────────────────────────
    final notifier = container.read(gameProvider.notifier);
    // ignore: invalid_use_of_protected_member
    notifier.state = state.withArmy(state.army1.copyWith(diamondBalance: 300));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('shop_tank')),
      100,
      scrollable: find.descendant(
        of: find.byKey(const Key('weapon_shop')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('shop_tank')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shop_tank')));
    await tester.pump();
    expect(container.read(gameProvider).army1.tanks, kStartTanks + 1);

    // ── 9. End the turn: the bots play, then it is our turn again ─────────
    await tester.tap(find.byKey(const Key('btn_end_turn')));
    await tester.pump();
    expect(container.read(gameProvider.notifier).isHumanTurn, isFalse);
    for (var i = 0; i < 600; i++) {
      if (container.read(gameProvider.notifier).isHumanTurn) break;
      if (container.read(gameProvider).phase == GamePhase.victory) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    state = container.read(gameProvider);
    expect(state.phase, GamePhase.playing);
    expect(state.activeArmyId, ArmyId.army1);
    expect(state.currentTurn, 2);
    expect(state.army1.hasDrawnCard, isFalse, reason: 'a new free card');
    for (final bot in state.armies.skip(1)) {
      expect(bot.hasDrawnCard, isFalse);
    }
    // The bots played: some of them grew (one may already be wiped out by
    // the others).
    expect(
      state.armies
          .skip(1)
          .any((b) => state.tilesOwnedBy(b.id) > kBotStartCities),
      isTrue,
    );
    expect(repo.saved?.currentTurn, 2);
    await frames(20);

    // ── 10. Back to the menu and resume ───────────────────────────────────
    await tester.tap(find.byIcon(Icons.home_rounded));
    await frames();
    expect(find.byType(MainMenuScreen), findsOneWidget);
    expect(find.text('Devam Et'), findsOneWidget);
    await tester.tap(find.text('Devam Et'));
    await frames(10);
    expect(find.byType(GameScreen), findsOneWidget);
    state = container.read(gameProvider);
    expect(state.currentTurn, 2);
    expect(state.armies, hasLength(4));

    // ── 11. A two-player game: the phone passes to Oyuncu 2 ───────────────
    await tester.tap(find.byIcon(Icons.home_rounded));
    await frames();
    await tester.tap(find.text('Yeni Oyun'));
    await frames();
    if (find.text('Atla').evaluate().isNotEmpty) {
      await tester.tap(find.text('Atla'));
      await frames();
    }
    await tester.tap(find.byKey(const Key('humans_2')));
    await tester.tap(find.byKey(const Key('bots_2')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('difficulty_medium')));
    await tester.tap(find.byKey(const Key('difficulty_medium')));
    await frames(10);
    state = container.read(gameProvider);
    expect(state.humanIds, [ArmyId.army1, ArmyId.army2]);
    expect(find.text('Oyuncu 1'), findsWidgets);
    await tester.tap(find.byKey(const Key('btn_end_turn')));
    await tester.pump();
    expect(container.read(gameProvider).activeArmyId, ArmyId.army2);
    expect(find.textContaining('Oyuncu 2'), findsWidgets);
    await frames(40);
  });
}

/// An own city with soldiers and a weaker neutral neighbour.
(int, int) _attackable(GameState s) {
  for (final t in s.territories) {
    if (t.ownerArmyId != ArmyId.army1 || t.unitCount < 50) continue;
    for (final adj in t.adjacentIds) {
      final n = s.territories[adj];
      if (n.ownerArmyId == null && n.unitCount < 40) return (t.id, adj);
    }
  }
  throw StateError('no attack found');
}

/// A neutral city next to the player's land that a Fire Bomb empties.
int _bombable(GameState s) {
  for (final t in s.territories) {
    if (t.ownerArmyId != null || t.unitCount > kFireBombDamage) continue;
    if (t.adjacentIds.any(
      (a) => s.territories[a].ownerArmyId == ArmyId.army1,
    )) {
      return t.id;
    }
  }
  throw StateError('no target found');
}
