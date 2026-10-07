// Widget tests for the new-game picker and the Africa game screen: the city
// map with outlined armies, the Weapon Shop beside the map, the cards, the
// action buttons and dragging soldiers from a city to its neighbour.
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';
import 'package:harita/presentation/screens/game_screen.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/difficulty_picker.dart';
import 'package:harita/presentation/widgets/hud/ability_panel.dart';

class _NoSave implements SaveRepository {
  @override
  Future<void> deleteSave() async {}
  @override
  Future<bool> hasSave() async => false;
  @override
  Future<GameState?> loadGameState() async => null;
  @override
  Future<void> saveGameState(GameState state) async {}
}

Future<AppStrings> _strings(WidgetTester tester) async {
  final service = await tester.runAsync(AppLocalizations.load);
  return service!.of(kLocaleTurkish);
}

void main() {
  testWidgets('new-game picker: 1 or 2 players, 1–10 bots, Çok Kolay / Orta '
      '/ Zor', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final strings = await _strings(tester);
    NewGameChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                picked = await showNewGamePicker(context, strings),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Kaç kişi oynuyor?'), findsOneWidget);
    expect(find.text('Kaç bot oynasın?'), findsOneWidget);
    for (var n = 1; n <= kMaxBots; n++) {
      expect(find.byKey(Key('bots_$n')), findsOneWidget);
    }
    expect(find.text('Çok Kolay'), findsOneWidget);
    expect(find.text('Orta'), findsOneWidget);
    expect(find.text('Zor'), findsOneWidget);
    // One colour dot per army (you + 5 bots by default).
    expect(find.byType(CircleAvatar), findsNWidgets(6));

    await tester.tap(find.byKey(const Key('bots_10')));
    await tester.tap(find.byKey(const Key('humans_2')));
    await tester.pump();
    expect(find.byType(CircleAvatar), findsNWidgets(12));

    await tester.tap(find.byKey(const Key('difficulty_hard')));
    await tester.pumpAndSettle();
    expect(picked?.difficulty, AiDifficulty.hard);
    expect(picked?.bots, 10);
    expect(picked?.humans, 2);
  });

  for (final (name, size) in [
    ('africa_map', const Size(1280, 800)),
    ('africa_map_phone', const Size(400, 860)),
  ]) {
    testWidgets('$name: the city map, the shop beside it and a tap that '
        'selects a city', (tester) async {
      final (game, container) = await _pumpGame(tester, size, name);
      expect(game.userZoom, WarGame.startZoom);
    });
  }

  testWidgets('the Weapon Shop lists every card, tanks and bombers from the '
      'first turn', (tester) async {
    final (_, container) = await _pumpGame(tester, const Size(1280, 800), null);
    expect(find.byKey(const Key('weapon_shop')), findsOneWidget);
    for (final item in kWeaponCatalog) {
      expect(find.byKey(Key('shop_${item.id}')), findsOneWidget);
    }
    for (final name in [
      'Mega Bomba',
      'Atom Bombası',
      'Nükleer Bomba',
      'Haraç Kes',
      'Tank',
      'Bombardıman Uçağı',
    ]) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    // Buy a tank with enough diamonds.
    final n = container.read(gameProvider.notifier);
    n.state = n.state.withArmy(n.state.army1.copyWith(diamondBalance: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shop_tank')));
    await tester.pump();
    expect(container.read(gameProvider).army1.tanks, kStartTanks + 1);
    expect(container.read(gameProvider).army1.diamondBalance, 100);
  });

  testWidgets('cards show how many you hold; Kart Çek adds one', (
    tester,
  ) async {
    final (_, container) = await _pumpGame(tester, const Size(400, 860), null);
    // The hand scrolls sideways through all seven cards.
    final hand = find.descendant(
      of: find.byType(AbilityPanel),
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
    final count = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('card_count_fireBomb')),
        matching: find.byType(Text),
      ),
    );
    expect(count.data, '1');

    await tester.tap(find.byKey(const Key('btn_draw_card')));
    await tester.pump();
    final army = container.read(gameProvider).army1;
    expect(army.hasDrawnCard, isTrue);
    expect(army.cards.values.fold(0, (a, b) => a + b), 2);
    expect(find.textContaining('Kart çektin'), findsOneWidget);
  });

  testWidgets('drag soldiers from your city to a neighbour: they march and '
      'fight', (tester) async {
    final (game, container) = await _pumpGame(
      tester,
      const Size(1280, 800),
      null,
    );
    final state = container.read(gameProvider);
    final (src, dst) = _attackable(state);
    final origin = tester.getTopLeft(find.byType(GameWidget<WarGame>));
    Offset screenOf(int id) {
      final p = game.mapComponent.graph.getPosition(id);
      final s = game.camera.localToGlobal(Vector2(p.dx, p.dy));
      return origin + Offset(s.x, s.y);
    }

    final gesture = await tester.startGesture(screenOf(src));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(screenOf(src), screenOf(dst), i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // The soldiers are on their way…
    expect(container.read(battleFxProvider), isNotEmpty);
    expect(
      container.read(gameProvider).territories[dst].ownerArmyId,
      isNot(ArmyId.army1),
    );
    await tester.pump(const Duration(milliseconds: kMarchMs + 50));
    // …and took the city.
    final after = container.read(gameProvider);
    expect(after.territories[dst].ownerArmyId, ArmyId.army1);
    expect(after.territories[src].unitCount, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('pinch zoom is clamped and keeps the map on screen', (
    tester,
  ) async {
    final (game, _) = await _pumpGame(tester, const Size(400, 860), null);
    game.zoomTo(1);
    final fit = game.camera.viewfinder.zoom;
    game.zoomTo(3);
    expect(game.camera.viewfinder.zoom, closeTo(fit * 3, 1e-4));
    game.zoomTo(100);
    expect(game.userZoom, WarGame.maxUserZoom);
    game.panBy(Vector2(-100000, -100000));
    final pos = game.camera.viewfinder.position;
    final map = game.mapComponent.size;
    expect(pos.x, lessThanOrEqualTo(map.x));
    expect(pos.y, lessThanOrEqualTo(map.y));
    game.zoomTo(0.1);
    expect(game.userZoom, 1);
    expect(game.camera.viewfinder.position, map / 2);
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

/// Pumps the game screen at [size] (3 bots, Zor, fixed random numbers);
/// when [golden] is set, also compares the map with `goldens/<golden>.png`.
Future<(WarGame, ProviderContainer)> _pumpGame(
  WidgetTester tester,
  Size size,
  String? golden,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      saveRepositoryProvider.overrideWithValue(_NoSave()),
      gameRandomProvider.overrideWithValue(Random(42)),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(newGameSettingsProvider.notifier)
      .set(difficulty: AiDifficulty.hard, bots: 3);
  await tester.runAsync(() => container.read(localeServiceProvider.future));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GameScreen()),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final state = container.read(gameProvider);
  expect(state.difficulty, AiDifficulty.hard);
  expect(state.armies, hasLength(4));
  for (final id in ArmyId.values.take(4)) {
    expect(find.byKey(Key('army_chip_${id.name}')), findsOneWidget);
  }
  expect(find.byKey(const Key('diamond_balance')), findsOneWidget);
  expect(find.byKey(const Key('tank_count')), findsOneWidget);
  expect(find.byKey(const Key('bomber_count')), findsOneWidget);
  expect(find.byKey(const Key('weapon_shop')), findsOneWidget);
  for (final key in [
    'btn_draw_card',
    'btn_attack',
    'btn_bomber',
    'btn_end_turn',
  ]) {
    expect(find.byKey(Key(key)), findsOneWidget, reason: key);
  }

  final game = tester
      .widget<GameWidget<WarGame>>(find.byType(GameWidget<WarGame>))
      .game!;
  // Let the satellite picture decode (real async work), then redraw.
  for (var i = 0; i < 50 && !game.mapComponent.hasSatellite; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(game.mapComponent.hasSatellite, isTrue);
  await tester.pump();

  // Tap the player's strongest city on the Flame canvas.
  final startId = state.territories
      .where((t) => t.ownerArmyId == ArmyId.army1)
      .reduce((a, b) => a.unitCount >= b.unitCount ? a : b)
      .id;
  final world = game.mapComponent.graph.getPosition(startId);
  final screen = game.camera.localToGlobal(Vector2(world.dx, world.dy));
  final origin = tester.getTopLeft(find.byType(GameWidget<WarGame>));
  await tester.tapAt(origin + Offset(screen.x, screen.y));
  await tester.pump(const Duration(milliseconds: 100));
  expect(container.read(selectedTerritoryProvider), startId);
  expect(find.byKey(const Key('city_card')), findsOneWidget);
  expect(find.text('Kazablanka'), findsWidgets);

  if (golden != null) {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$golden.png'),
    );
  }
  return (game, container);
}
