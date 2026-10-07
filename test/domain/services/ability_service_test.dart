// Cards: every card's effect, valid targets, the free draw ("Kart Çek")
// and the Weapon Shop.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/services/economy_service.dart';

/// A 4 × 4 grid of cities (4-neighbours). The player owns the left
/// column, bot 1 the right column; the middle is neutral.
GameState _grid({
  Map<AbilityType, int> cards = const {},
  int botDiamonds = 500,
}) {
  int id(int c, int r) => r * 4 + c;
  return GameState(
    territories: [
      for (var r = 0; r < 4; r++)
        for (var c = 0; c < 4; c++)
          Territory(
            id: id(c, r),
            name: 'city_${id(c, r)}',
            type: TerritoryType.city,
            adjacentIds: [
              if (r > 0) id(c, r - 1),
              if (c > 0) id(c - 1, r),
              if (c < 3) id(c + 1, r),
              if (r < 3) id(c, r + 1),
            ],
            unitCount: 30,
            ownerArmyId: c == 0
                ? ArmyId.army1
                : c == 3
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
        cards: cards,
      ),
      Army(id: ArmyId.army2, kind: ArmyKind.ai, diamondBalance: botDiamonds),
    ],
    currentTurn: 1,
    activeArmyId: ArmyId.army1,
    phase: GamePhase.playing,
  );
}

void main() {
  final cards = AbilityServiceImpl(random: Random(1));

  GameState play(GameState s, AbilityType type, int target) =>
      cards.activateAbility(
        state: s,
        armyId: ArmyId.army1,
        ability: type,
        targetTerritoryId: target,
      );

  int owned(GameState s) => s.tilesOwnedBy(ArmyId.army1);

  test('capture cards take 1 / 2 / 3 cities next to your land', () {
    for (final (type, count) in [
      (AbilityType.fireBomb, kFireBombCities),
      (AbilityType.bombardment, kBombardmentCities),
      (AbilityType.megaBomba, kMegaBombaCities),
    ]) {
      final s = play(_grid(cards: {type: 1}), type, 5);
      expect(owned(s), 4 + count, reason: '$type');
      expect(s.territories[5].ownerArmyId, ArmyId.army1);
      expect(s.territories[5].unitCount, kCapturedCityUnits);
      expect(s.army1.cardCount(type), 0, reason: 'the card is used up');
    }
  });

  test('bombs only kill soldiers in a strong city; it is not captured', () {
    var s = _grid(cards: {AbilityType.fireBomb: 1, AbilityType.megaBomba: 1});
    s = s.copyWith(
      territories: [
        for (final t in s.territories)
          t.id == 5 ? t.copyWith(unitCount: 135) : t,
      ],
    );
    final fire = play(s, AbilityType.fireBomb, 5);
    expect(fire.territories[5].ownerArmyId, isNull);
    expect(fire.territories[5].unitCount, 135 - kFireBombDamage);
    final mega = play(fire, AbilityType.megaBomba, 5);
    expect(
      mega.territories[5].unitCount,
      135 - kFireBombDamage - kMegaBombaDamage,
    );
    // The two weaker cities around it were emptied and captured.
    expect(owned(mega), 4 + 2);
  });

  test('Atom and Nuclear bombs hit anywhere on the map', () {
    final atom = play(
      _grid(cards: {AbilityType.atomBomb: 1}),
      AbilityType.atomBomb,
      15,
    );
    expect(owned(atom), 4 + kAtomBombCities);
    expect(atom.territories[15].ownerArmyId, ArmyId.army1);

    final nuke = play(
      _grid(cards: {AbilityType.nuclearBomb: 1}),
      AbilityType.nuclearBomb,
      11,
    );
    expect(owned(nuke), 4 + kNuclearBombCities);
    // Fire Bomb may not do that.
    expect(
      () => play(
        _grid(cards: {AbilityType.fireBomb: 1}),
        AbilityType.fireBomb,
        15,
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

  test('Asker Büyüsü adds soldiers to an own city only', () {
    final s = play(
      _grid(cards: {AbilityType.soldierSpell: 1}),
      AbilityType.soldierSpell,
      4,
    );
    expect(s.territories[4].unitCount, 30 + kSoldierSpellUnits);
    expect(
      () => play(
        _grid(cards: {AbilityType.soldierSpell: 1}),
        AbilityType.soldierSpell,
        5,
      ),
      throwsA(isA<InvalidTargetException>()),
    );
  });

  test('Haraç Kes takes 200 diamonds from the owner of the city', () {
    final s = play(
      _grid(cards: {AbilityType.tribute: 1}),
      AbilityType.tribute,
      7,
    );
    expect(s.army1.diamondBalance, kTributeDiamonds);
    expect(s.army2.diamondBalance, 500 - kTributeDiamonds);

    // A poor bot pays what it has.
    final poor = play(
      _grid(cards: {AbilityType.tribute: 1}, botDiamonds: 60),
      AbilityType.tribute,
      7,
    );
    expect(poor.army1.diamondBalance, 60);
    expect(poor.army2.diamondBalance, 0);

    // Neutral cities have nobody to pay.
    expect(
      () =>
          play(_grid(cards: {AbilityType.tribute: 1}), AbilityType.tribute, 5),
      throwsA(isA<InvalidTargetException>()),
    );
  });

  test('cards you do not hold cannot be played', () {
    expect(
      () => play(_grid(), AbilityType.fireBomb, 5),
      throwsA(isA<NoCardException>()),
    );
  });

  test('Kart Çek gives one free card per turn', () {
    final (s, card) = cards.drawCard(_grid(), ArmyId.army1);
    expect(s.army1.cardCount(card), 1);
    expect(s.army1.hasDrawnCard, isTrue);
    expect(
      () => cards.drawCard(s, ArmyId.army1),
      throwsA(isA<CardAlreadyDrawnException>()),
    );
  });

  test('every card can come out of the draw, common ones more often', () {
    final rng = AbilityServiceImpl(random: Random(7));
    final seen = <AbilityType, int>{};
    for (var i = 0; i < 3000; i++) {
      final (_, card) = rng.drawCard(_grid(), ArmyId.army1);
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

    test('sells every card, tanks and bombers from the first turn', () {
      final items = economy.getShopItems();
      expect(
        items.map((i) => i.card).whereType<AbilityType>().toSet(),
        AbilityType.values.toSet(),
      );
      expect(items.where((i) => i.tanks > 0), hasLength(1));
      expect(items.where((i) => i.bombers > 0), hasLength(1));
    });

    test('buying adds the card / tank / bomber and costs diamonds', () {
      var army = Army(
        id: ArmyId.army1,
        kind: ArmyKind.human,
        diamondBalance: 5000,
      );
      for (final item in economy.getShopItems()) {
        army = economy.purchaseItem(army, item);
      }
      for (final type in AbilityType.values) {
        expect(army.cardCount(type), 1);
      }
      expect(army.tanks, 1);
      expect(army.bombers, 1);
      final total = economy.getShopItems().fold(0, (a, i) => a + i.diamondCost);
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
