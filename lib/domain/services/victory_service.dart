/// Victory service for Harita: Kendi İmparatorluğunu Kur.
///
/// Determines whether a win condition has been reached.
library;

import 'package:harita/core/constants.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Checks whether a victory condition has been satisfied.
abstract class VictoryService {
  /// Returns the [ArmyId] of the winning army if and only if that army owns
  /// all [kTerritoryCount] tiles (or the opponent has none left), otherwise returns `null`.
  ///
  /// - Returns [ArmyId.army1] when army1 owns all tiles.
  /// - Returns [ArmyId.army2] when army2 owns all tiles.
  /// - Returns `null` in all other cases (no winner yet).
  ///
  /// This is a pure read — it never mutates [state].
  ArmyId? checkVictory(GameState state);
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [VictoryService].
///
/// Counts territories owned by each army; returns the winning [ArmyId] when
/// any army's count equals [kTerritoryCount], otherwise null.
class VictoryServiceImpl implements VictoryService {
  const VictoryServiceImpl();

  @override
  ArmyId? checkVictory(GameState state) {
    var army1Count = 0;
    var army2Count = 0;

    for (final territory in state.territories) {
      if (territory.ownerArmyId == ArmyId.army1) {
        army1Count++;
      } else if (territory.ownerArmyId == ArmyId.army2) {
        army2Count++;
      }
    }

    if (army1Count == kTerritoryCount) return ArmyId.army1;
    if (army2Count == kTerritoryCount) return ArmyId.army2;

    // Elimination: an army that has lost every territory can never act
    // again, so its opponent is declared the winner (defeat detection).
    if (army1Count == 0 && army2Count > 0) return ArmyId.army2;
    if (army2Count == 0 && army1Count > 0) return ArmyId.army1;
    return null;
  }
}
