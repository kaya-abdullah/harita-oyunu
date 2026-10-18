// End-to-end test of the whole app as the player sees it: the bomb intro,
// the menu, a new game (no picker: America against six Orta bots), playing
// on the tilted 3D Africa map (cards: hand, Kart Çek, folding panel, Fire
// Bomb; attack, shop), the bots' turns, going back to the menu
// and resuming the saved game.
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
        // Fixed card draws and bot choices, so the round is the same every
        // run.
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

    // ── 1. Intro: bomb, smoke, then the menu ──────────────────────────────
    expect(find.byKey(const Key('intro_overlay')), findsOneWidget);
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

    // ── 3. No bot picker ("bot seçme olmasın"): straight into the game ────
    await frames(10);
    expect(find.text('Kaç bot oynasın?'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
    var state = container.read(gameProvider);
    expect(state.armies, hasLength(kMaxBots + 1));
    expect(state.difficulty, AiDifficulty.medium);
    expect(state.territories, hasLength(kTerritoryCount));
    for (final id in ArmyId.values) {
      expect(find.byKey(Key('army_chip_${id.name}')), findsOneWidget);
    }
    // The card panel: every card (the new Atom Bomb, Nuclear Bomb and Haraç
    // Kes too) with how many are in hand; it scrolls sideways.
    final hand = find.descendant(
      of: find.byKey(const Key('cards_list')),
      matching: find.byType(Scrollable),
    );
    for (final type in AbilityType.values) {
      await tester.scrollUntilVisible(
        find.byKey(Key('ability_${type.name}')),
        80,
        scrollable: hand,
      );
      expect(find.byKey(Key('ability_${type.name}')), findsOneWidget);
    }
    await tester.drag(hand, const Offset(2000, 0));
    await tester.pump();
    expect(find.text('Kartların ($kStartFireBombs)'), findsOneWidget);

    // Kart Çek: one free card.
    await tester.tap(find.byKey(const Key('btn_draw_card')));
    await tester.pump();
    expect(find.text('Kartların (${kStartFireBombs + 1})'), findsOneWidget);
    expect(find.textContaining('Kart çektin'), findsOneWidget);
    expect(container.read(gameProvider).army1.hasDrawnCard, isTrue);

    // The panel folds shut and opens again.
    await tester.tap(find.byKey(const Key('cards_toggle')));
    await frames(3);
    expect(find.byKey(const Key('cards_list')), findsNothing);
    await tester.tap(find.byKey(const Key('cards_toggle')));
    await frames(3);
    expect(find.byKey(const Key('cards_list')), findsOneWidget);

    final game = tester
        .widget<GameWidget<WarGame>>(find.byType(GameWidget<WarGame>))
        .game!;
    // The map is tilted in 3D: canvas points go through the widget
    // transforms to find where they show on screen.
    final canvas = tester.renderObject<RenderBox>(
      find.byType(GameWidget<WarGame>),
    );
    Future<void> tapCity(int id) async {
      final p = game.mapComponent.graph.positionOf(id).offset;
      // Bring the city into the middle of the view first (the tilted map
      // shows less at its near corners).
      game.camera.viewfinder.position = Vector2(p.dx, p.dy);
      await tester.pump();
      final s = game.camera.localToGlobal(Vector2(p.dx, p.dy));
      await tester.tapAt(canvas.localToGlobal(Offset(s.x, s.y)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The map opens zoomed in on America; centre the first city.
    expect(game.userZoom, WarGame.startZoom);
    final start =
        state.territories[game.mapComponent.graph.playerStartCities.first];
    final startPos = game.mapComponent.graph.positionOf(start.id).offset;
    game.panBy(
      (game.camera.localToGlobal(Vector2(startPos.dx, startPos.dy)) -
              game.size / 2) *
          -1,
    );
    await tester.pump();

    // Every city of America is ours with 150 soldiers; every other city
    // holds 50–70 soldiers (no empty land).
    for (final t in state.territories) {
      if (t.ownerArmyId == ArmyId.army1) {
        expect(t.unitCount, kPlayerStartUnitsPerCity);
      } else if (t.ownerArmyId == null) {
        expect(
          t.unitCount,
          inInclusiveRange(kNeutralCityMinUnits, kNeutralCityMaxUnits),
        );
      }
    }

    // ── 4. Attack: select an own border city, add the reserve, then tap a
    //       neighbour (all of America's neighbours are bot cities) ────────
    final (src, dst) = _border(state);
    await tapCity(src);
    expect(container.read(selectedTerritoryProvider), src);
    // The info panel names the city and its country.
    expect(find.textContaining(' · Amerika'), findsOneWidget);
    await tapCity(src); // deploys the 20 reserve soldiers
    state = container.read(gameProvider);
    expect(state.territories[src].unitCount, kPlayerStartUnitsPerCity + 20);
    final defenders = state.territories[dst].unitCount;
    await tapCity(dst);
    state = container.read(gameProvider);
    expect(state.territories[dst].ownerArmyId, ArmyId.army1);
    // Soldier for soldier: the winners keep the difference.
    expect(
      state.territories[dst].unitCount,
      kPlayerStartUnitsPerCity + 20 - 1 - defenders,
    );

    // ── 5. Fire Bomb card: kills 30 soldiers in a neighbouring city ───────
    final before = state.tilesOwnedBy(ArmyId.army1);
    await tester.tap(find.byKey(const Key('ability_fireBomb')));
    await tester.pump();
    expect(container.read(armedAbilityProvider), AbilityType.fireBomb);
    final (_, target) = _border(container.read(gameProvider));
    final targetUnits = container
        .read(gameProvider)
        .territories[target]
        .unitCount;
    await tapCity(target);
    state = container.read(gameProvider);
    expect(state.tilesOwnedBy(ArmyId.army1), before);
    expect(
      state.territories[target].unitCount,
      max(kBombedCityMinUnits, targetUnits - kFireBombDamage),
    );
    expect(
      container.read(gameFeedbackProvider)?.kind,
      GameFeedbackKind.abilityUsed,
    );

    // ── 6. Shop: cards cost diamonds ──────────────────────────────────────
    await tester.tap(find.text('Silah Dükkanı'));
    await frames();
    expect(find.byKey(const Key('shop_item_fire_bomb')), findsOneWidget);
    expect(find.byKey(const Key('shop_item_tribute')), findsOneWidget);
    expect(find.textContaining('Maliyet: 220'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await frames();

    // ── 7. End the turn: all six bots play, then it is our turn again ─────
    final diamonds = state.army1.diamondBalance;
    final ownersBefore = [for (final t in state.territories) t.ownerArmyId];
    await tester.tap(find.text('Turu Bitir'));
    await tester.pump();
    expect(container.read(gameProvider.notifier).isHumanTurn, isFalse);
    for (var i = 0; i < 600; i++) {
      if (container.read(gameProvider.notifier).isHumanTurn) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    state = container.read(gameProvider);
    expect(state.activeArmyId, ArmyId.army1);
    expect(state.currentTurn, 2);
    // Income was paid (a bot may have taken some with Haraç Kes).
    expect(
      state.army1.diamondBalance,
      greaterThanOrEqualTo(diamonds + 80 - kTributeDiamonds * kMaxBots),
    );
    expect(state.army1.hasDrawnCard, isFalse, reason: 'a new free card');
    // The bots played: cities changed hands.
    expect([
      for (final t in state.territories) t.ownerArmyId,
    ], isNot(ownersBefore));
    expect(repo.saved?.currentTurn, 2);

    // ── 8. Back to the menu and resume ────────────────────────────────────
    await tester.tap(find.byIcon(Icons.home_rounded));
    await frames();
    expect(find.byType(MainMenuScreen), findsOneWidget);
    expect(find.text('Devam Et'), findsOneWidget);
    await tester.tap(find.text('Devam Et'));
    await frames(10);
    expect(find.byType(GameScreen), findsOneWidget);
    state = container.read(gameProvider);
    expect(state.currentTurn, 2);
    expect(state.armies, hasLength(kMaxBots + 1));
  });
}

/// An own city with ≥ 2 units and a neighbour that is neither own nor
/// another army's (neutral), or any non-own neighbour as a fallback.
(int, int) _border(GameState s) {
  (int, int)? fallback;
  for (final t in s.territories) {
    if (t.ownerArmyId != ArmyId.army1 || t.unitCount < 2) continue;
    for (final adj in t.adjacentIds) {
      final o = s.territories[adj].ownerArmyId;
      if (o == null) return (t.id, adj);
      if (o != ArmyId.army1) fallback ??= (t.id, adj);
    }
  }
  return fallback!;
}
