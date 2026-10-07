// Widget tests for the new-game picker and the Africa game screen.
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';
import 'package:harita/presentation/screens/game_screen.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/difficulty_picker.dart';

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
  testWidgets('new-game picker: 1–6 bots and Çok Kolay / Orta / Zor', (
    tester,
  ) async {
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

    expect(find.text('Kaç bot oynasın?'), findsOneWidget);
    for (var n = 1; n <= 6; n++) {
      expect(find.byKey(Key('bots_$n')), findsOneWidget);
    }
    expect(find.text('Çok Kolay'), findsOneWidget);
    expect(find.text('Orta'), findsOneWidget);
    expect(find.text('Zor'), findsOneWidget);
    // One colour dot per army (you + 1 bot).
    expect(find.byType(CircleAvatar), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('bots_6')));
    await tester.pump();
    expect(find.byType(CircleAvatar), findsNWidgets(7));

    await tester.tap(find.byKey(const Key('difficulty_hard')));
    await tester.pumpAndSettle();
    expect(picked?.difficulty, AiDifficulty.hard);
    expect(picked?.bots, 6);
  });

  for (final (name, size) in [
    ('africa_map', const Size(1280, 800)),
    ('africa_map_phone', const Size(400, 860)),
  ]) {
    testWidgets('$name: Africa map renders and a tap selects a tile', (
      tester,
    ) async {
      await _pumpGame(tester, size, name);
    });
  }

  testWidgets('real fingers: one finger pans, two fingers pinch-zoom, the '
      'wheel zooms, a tap still selects', (tester) async {
    final game = await _pumpGame(tester, const Size(400, 860), null);
    final rect = tester.getRect(find.byType(GameWidget<WarGame>));
    final center = rect.center;
    game.zoomTo(3);
    await tester.pump();

    // One finger drags the map: the camera follows the finger.
    final before = game.camera.viewfinder.position.clone();
    final drag = await tester.startGesture(center);
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(center + Offset(-6.0 * i, -4.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump();
    final moved = game.camera.viewfinder.position - before;
    final zoom = game.camera.viewfinder.zoom;
    // Dragged 60 × 40 px to the upper left: the view moves down-right by
    // the same distance in map units (minus the first few pixels of slop).
    expect(moved.x, closeTo(60 / zoom, 12 / zoom));
    expect(moved.y, closeTo(40 / zoom, 12 / zoom));
    expect(game.userZoom, 3, reason: 'one finger never zooms');

    // Two fingers spread apart: zoom in around the point between them.
    final anchorScreen = Vector2(center.dx - rect.left, center.dy - rect.top);
    final anchorWorld = game.camera.globalToLocal(anchorScreen);
    final a = await tester.startGesture(center - const Offset(40, 0));
    final b = await tester.startGesture(center + const Offset(40, 0));
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center - Offset(40.0 + 4 * i, 0));
      await b.moveTo(center + Offset(40.0 + 4 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
    // 80 px apart → 160 px apart: twice the zoom.
    expect(game.userZoom, closeTo(3 * 160 / 80, 0.05));
    // The map point between the fingers stayed under them.
    final after = game.camera.localToGlobal(anchorWorld);
    expect(after.x, closeTo(anchorScreen.x, 2));
    expect(after.y, closeTo(anchorScreen.y, 2));

    // Pinching in zooms back out.
    final c = await tester.startGesture(center - const Offset(80, 0));
    final d = await tester.startGesture(center + const Offset(80, 0));
    for (var i = 1; i <= 10; i++) {
      await c.moveTo(center - Offset(80.0 - 4 * i, 0));
      await d.moveTo(center + Offset(80.0 - 4 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await c.up();
    await d.up();
    await tester.pump();
    // 160 px apart → 80 px apart: half the zoom.
    expect(game.userZoom, closeTo(6 * 80 / 160, 0.05));

    // The mouse wheel zooms too.
    final wheelBefore = game.userZoom;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -20)));
    await tester.pump();
    expect(game.userZoom, greaterThan(wheelBefore));

    // A plain tap (even with a little jitter) still selects a tile.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameScreen)),
    );
    final own = container
        .read(gameProvider)
        .territories
        .firstWhere((t) => t.ownerArmyId == ArmyId.army1);
    final p = game.mapComponent.graph.positionOf(own.id).offset;
    final world = game.camera.localToGlobal(Vector2(p.dx, p.dy));
    game.camera.viewfinder.position = Vector2(p.dx, p.dy);
    await tester.pump();
    final screen = game.camera.localToGlobal(Vector2(p.dx, p.dy));
    expect(world, isNotNull);
    final tap = await tester.startGesture(
      rect.topLeft + Offset(screen.x, screen.y),
    );
    await tap.moveBy(const Offset(2, 1));
    await tap.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(selectedTerritoryProvider), own.id);
  });

  testWidgets('pinch zoom is clamped and keeps the map on screen', (
    tester,
  ) async {
    final game = await _pumpGame(tester, const Size(400, 860), null);
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

/// Pumps the game screen at [size]; when [golden] is set, also compares the
/// screen with `goldens/<golden>.png`. Returns the running [WarGame].
Future<WarGame> _pumpGame(
  WidgetTester tester,
  Size size,
  String? golden,
) async {
  {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [saveRepositoryProvider.overrideWithValue(_NoSave())],
    );
    addTearDown(container.dispose);
    container.read(newGameDifficultyProvider.notifier).set(AiDifficulty.hard);
    container.read(newGameBotCountProvider.notifier).set(3);
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
    // One chip per army in the resource bar, plus the diamond balance.
    for (final id in ArmyId.values.take(4)) {
      expect(find.byKey(Key('army_chip_${id.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('diamond_balance')), findsOneWidget);
    // No laser card any more; the Fire Bomb card is green.
    expect(find.byKey(const Key('ability_fireBomb')), findsOneWidget);
    expect(find.text('Direkt'), findsNothing);

    // Tap the centre of the player's start tile on the Flame canvas.
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
    final startId = state.territories
        .firstWhere((t) => t.ownerArmyId == ArmyId.army1)
        .id;
    final world = game.mapComponent.graph.positionOf(startId).offset;
    final screen = game.camera.localToGlobal(Vector2(world.dx, world.dy));
    final origin = tester.getTopLeft(find.byType(GameWidget<WarGame>));
    await tester.tapAt(origin + Offset(screen.x, screen.y));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(selectedTerritoryProvider), startId);

    if (golden != null) {
      await expectLater(
        find.byType(GameWidget<WarGame>),
        matchesGoldenFile('goldens/$golden.png'),
      );
    }
    return game;
  }
}
