// Cards: every card's effect, valid targets, the hand with counts, the free
// draw ("Kart Çek") and the Weapon Shop.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/economy_service.dart';

const _size = 10;

/// A 10 × 10 grid of tiles (4-neighbours). The player owns the left
/// column, bot 1 the right column; the rest is neutral. Tile 1 holds a
/// diamond mine.
GameState _grid({
  Map<AbilityType, int> cards = const {},
  int botDiamonds = 500,
}) {
  int id(int c, int r) => r * _size + c;
  return GameState(
    territories: [
      for (var r = 0; r < _size; r++)
        for (var c = 0; c < _size; c++)
          Territory(
            id: id(c, r),
            name: 'tile_${id(c, r)}',
            type: TerritoryType.normal,
            adjacentIds: [
              if (r > 0) id(c, r - 1),
              if (c > 0) id(c - 1, r),
              if (c < _size - 1) id(c + 1, r),
              if (r < _size - 1) id(c, r + 1),
            ],
            unitCount: 5,
            ownerArmyId: c == 0
                ? ArmyId.army1
                : c == _size - 1
                ? ArmyId.army2
                : null,
            hasDiamondMine: id(c, r) == 1,
          ),
    ],
    armies: [
      Army(
        id: ArmyId.army1,
        kind: ArmyKind.human,
        diamondBalance: 0,
        totalUnitPool: 0,
        cards: cards,
      ),
      Army(
        id: ArmyId.army2,
        kind: ArmyKind.ai,
        diamondBalance: botDiamonds,
        totalUnitPool: 0,
      ),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

void main() {
  final service = AbilityServiceImpl(random: Random(1));

  GameState play(GameState s, AbilityType type, int target) =>
      service.activateAbility(
        state: s,
        armyId: ArmyId.army1,
        ability: type,
        targetTerritoryId: target,
      );

  int owned(GameState s) => s.tilesOwnedBy(ArmyId.army1);

  test('bomb cards capture 2 / 8 / 25 tiles next to your land and are used '
      'up', () {
    for (final (type, count) in [
      (AbilityType.fireBomb, kFireBombTiles),
      (AbilityType.bombardment, kBombardmentTiles),
      (AbilityType.megaBomba, kMegaBombaTiles),
    ]) {
      final s = play(_grid(cards: {type: 2}), type, 11);
      expect(owned(s), _size + count, reason: '$type');
      expect(s.territories[11].ownerArmyId, ArmyId.army1);
      expect(s.army1.cardCount(type), 1, reason: 'one card is used up');
    }
  });

  test('the same card can be played again while you hold more', () {
    var s = _grid(cards: {AbilityType.fireBomb: 2});
    s = play(s, AbilityType.fireBomb, 11);
    s = play(s, AbilityType.fireBomb, 21);
    expect(s.army1.cardCount(AbilityType.fireBomb), 0);
    expect(
      () => play(s, AbilityType.fireBomb, 31),
      throwsA(isA<NoCardException>()),
    );
  });

  test('Atom and Nuclear bombs hit anywhere on the map', () {
    final atom = play(
      _grid(cards: {AbilityType.atomBomb: 1}),
      AbilityType.atomBomb,
      _size * _size - 1,
    );
    expect(owned(atom), _size + kAtomBombTiles);
    expect(atom.territories[_size * _size - 1].ownerArmyId, ArmyId.army1);

    final nuke = play(
      _grid(cards: {AbilityType.nuclearBomb: 1}),
      AbilityType.nuclearBomb,
      55,
    );
    expect(owned(nuke), _size + kNuclearBombTiles);

    // A Fire Bomb may not do that.
    expect(
      () => play(
        _grid(cards: {AbilityType.fireBomb: 1}),
        AbilityType.fireBomb,
        55,
      ),
      throwsA(isA<InvalidTargetException>()),
    );
  });

  test('capturing a diamond mine with a card pays out', () {
    final s = play(
      _grid(cards: {AbilityType.fireBomb: 1}),
      AbilityType.fireBomb,
      1,
    );
    expect(s.army1.diamondBalance, kDiamondMineReward);
  });

  test('Asker Büyüsü adds soldiers to an own tile only', () {
    final s = play(
      _grid(cards: {AbilityType.soldierSpell: 1}),
      AbilityType.soldierSpell,
      10,
    );
    expect(s.territories[10].unitCount, 5 + kSoldierSpellUnits);
    expect(
      () => play(
        _grid(cards: {AbilityType.soldierSpell: 1}),
        AbilityType.soldierSpell,
        11,
      ),
      throwsA(isA<InvalidTargetException>()),
    );
  });

  test('Haraç Kes takes 200 diamonds from the owner of the tile', () {
    final s = play(
      _grid(cards: {AbilityType.tribute: 1}),
      AbilityType.tribute,
      _size - 1,
    );
    expect(s.army1.diamondBalance, kTributeDiamonds);
    expect(s.army2.diamondBalance, 500 - kTributeDiamonds);

    // A poor bot pays what it has.
    final poor = play(
      _grid(cards: {AbilityType.tribute: 1}, botDiamonds: 60),
      AbilityType.tribute,
      _size - 1,
    );
    expect(poor.army1.diamondBalance, 60);
    expect(poor.army2.diamondBalance, 0);

    // Neutral tiles have nobody to pay.
    expect(
      () =>
          play(_grid(cards: {AbilityType.tribute: 1}), AbilityType.tribute, 5),
      throwsA(isA<InvalidTargetException>()),
    );
  });

  test('cards you do not hold cannot be played', () {
    expect(
      () => play(_grid(), AbilityType.fireBomb, 11),
      throwsA(isA<NoCardException>()),
    );
  });

  test('isValidTarget follows the card rules', () {
    final s = _grid();
    final own = s.territories[10];
    final border = s.territories[11];
    final far = s.territories[55];
    final enemy = s.territories[19];
    bool ok(AbilityType type, Territory t) =>
        isValidTarget(s, ArmyId.army1, type, t);
    expect(ok(AbilityType.fireBomb, border), isTrue);
    expect(ok(AbilityType.fireBomb, far), isFalse);
    expect(ok(AbilityType.fireBomb, own), isFalse);
    expect(ok(AbilityType.atomBomb, far), isTrue);
    expect(ok(AbilityType.nuclearBomb, enemy), isTrue);
    expect(ok(AbilityType.tribute, enemy), isTrue);
    expect(ok(AbilityType.tribute, far), isFalse);
    expect(ok(AbilityType.soldierSpell, own), isTrue);
    expect(ok(AbilityType.soldierSpell, border), isFalse);
  });

  test('Kart Çek gives one free card per turn', () {
    final (s, card) = service.drawCard(_grid(), ArmyId.army1);
    expect(s.army1.cardCount(card), 1);
    expect(s.army1.hasDrawnCard, isTrue);
    expect(
      () => service.drawCard(s, ArmyId.army1),
      throwsA(isA<CardAlreadyDrawnException>()),
    );
  });

  test('no Atom or Nuclear Bomb from the draw in the first turns', () {
    final rng = AbilityServiceImpl(random: Random(3));
    for (var i = 0; i < 2000; i++) {
      final (_, card) = rng.drawCard(_grid(), ArmyId.army1);
      expect(card, isNot(AbilityType.atomBomb));
      expect(card, isNot(AbilityType.nuclearBomb));
    }
  });

  test('every card can come out of the draw, common ones more often', () {
    final rng = AbilityServiceImpl(random: Random(7));
    final seen = <AbilityType, int>{};
    final late = _grid().copyWith(currentTurn: kTurnFirstBigBombDraw);
    for (var i = 0; i < 3000; i++) {
      final (_, card) = rng.drawCard(late, ArmyId.army1);
      seen[card] = (seen[card] ?? 0) + 1;
    }
    expect(seen.keys.toSet(), AbilityType.values.toSet());
    expect(
      seen[AbilityType.fireBomb]!,
      greaterThan(seen[AbilityType.nuclearBomb]!),
    );
  });

  group('Weapon Shop', () {
    const economy = EconomyServiceImpl();

    test('sells every card', () {
      expect(
        kWeaponCatalog.map((i) => i.card).toSet(),
        AbilityType.values.toSet(),
      );
    });

    test('buying adds the card to the hand and costs diamonds', () {
      var army = Army(
        id: ArmyId.army1,
        kind: ArmyKind.human,
        diamondBalance: 5000,
        totalUnitPool: 0,
      );
      for (final item in kWeaponCatalog) {
        army = economy.purchaseItem(army, item);
      }
      for (final type in AbilityType.values) {
        expect(army.cardCount(type), 1);
      }
      final total = kWeaponCatalog.fold(0, (a, i) => a + i.diamondCost);
      expect(army.diamondBalance, 5000 - total);
      expect(
        () => economy.purchaseItem(
          army.copyWith(diamondBalance: 0),
          kWeaponCatalog.first,
        ),
        throwsA(isA<InsufficientDiamondsException>()),
      );
    });
  });
}
