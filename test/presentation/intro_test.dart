// Widget tests for the atomic-bomb intro that reveals the main menu.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harita/domain/models/game_state.dart';
import 'package:harita/infrastructure/persistence/hive_save_repository.dart';
import 'package:harita/presentation/screens/intro_screen.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

class _NoSave implements SaveRepository {
  _NoSave({this.has = false});

  final bool has;

  @override
  Future<void> deleteSave() async {}
  @override
  Future<bool> hasSave() async => has;
  @override
  Future<GameState?> loadGameState() async => null;
  @override
  Future<void> saveGameState(GameState state) async {}
}

Future<void> _pumpIntro(WidgetTester tester, {bool hasSave = false}) async {
  final container = ProviderContainer(
    overrides: [
      saveRepositoryProvider.overrideWithValue(_NoSave(has: hasSave)),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(localeServiceProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IntroScreen()),
    ),
  );
}

void main() {
  testWidgets('the bomb intro plays, then the smoke clears to the menu', (
    tester,
  ) async {
    await _pumpIntro(tester, hasSave: true);
    await tester.pump();

    // The intro covers the screen; the menu is hidden under it.
    expect(find.byKey(const Key('intro_overlay')), findsOneWidget);
    final hidden = tester.widget<Opacity>(
      find.ancestor(of: find.text('Yeni Oyun'), matching: find.byType(Opacity)),
    );
    expect(hidden.opacity, 0);

    // Bomb falls, explodes, smoke rolls in...
    for (var ms = 0; ms < 3000; ms += 250) {
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('intro_overlay')), findsOneWidget);
    }
    // ...and clears: the menu with New Game / Resume / How to Play shows.
    await tester.pump(IntroScreen.duration);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('intro_overlay')), findsNothing);
    expect(find.text('Yeni Oyun'), findsOneWidget);
    expect(find.text('Devam Et'), findsOneWidget);
    expect(find.text('Nasıl Oynanır?'), findsOneWidget);
    final shown = tester.widget<Opacity>(
      find.ancestor(of: find.text('Yeni Oyun'), matching: find.byType(Opacity)),
    );
    expect(shown.opacity, 1);
  });

  testWidgets('tapping skips the intro', (tester) async {
    await _pumpIntro(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('intro_overlay')));
    await tester.pump();
    expect(find.byKey(const Key('intro_overlay')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Yeni Oyun'), findsOneWidget);
    expect(find.text('Devam Et'), findsNothing); // no save yet
  });
}
