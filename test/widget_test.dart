// Basic dart-level smoke test (no Flutter widgets, no Hive dependency)
// Verifies the numbers asked for in the voice notes.
import 'package:flutter_test/flutter_test.dart';
import 'package:harita/core/constants.dart';

void main() {
  test('Core constants are defined correctly', () {
    expect(kTerritoryCount, 133);
    expect(kHumanStartUnits, [135, 125, 120, 110]);
    expect(kBotsNearPlayer, 3);
    expect(kMaxBots, 10);
    expect(kMaxHumans, 2);
    expect(kStartTanks, 5);
    expect(kStartBombers, 4);
    expect(kTributeDiamonds, 200);
    expect(kDiamondsPerTurn, 80);
    expect(kDiamondMineReward, 250);
    expect(kPhoneBreakpoint, 600.0);
  });
}
