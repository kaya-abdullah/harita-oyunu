// Basic dart-level smoke test (no Flutter widgets, no Hive dependency)
// Verifies that the core domain constants and models compile and are accessible.
import 'package:flutter_test/flutter_test.dart';
import 'package:harita/core/constants.dart';

void main() {
  test('Core constants are defined correctly', () {
    expect(kTerritoryCount, 1163);
    expect(kBigBaseCapacity, 150);
    expect(kTurnUnlockBombardment, 10);
    expect(kTurnUnlockSoldierSpell, 12);
    expect(kTurnUnlockMegaBomba, 45);
    expect(kDiamondsPerTurn, 80);
    expect(kDiamondMineReward, 250);
    expect(kMaxBots, 6);
    expect(kSoldiersPerTurn, 3);
    expect(kPhoneBreakpoint, 600.0);
  });
}
