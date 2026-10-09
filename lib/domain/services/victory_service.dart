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
  /// Returns the [ArmyId] of the winner, or `null` while the game goes on.
  ///
  /// - The last army that still owns land wins (with a single opponent this
  ///   also covers conquering all [kTerritoryCount] cities).
  /// - If the human player ([ArmyId.army1]) has lost all land, the game is
  ///   over: the bot with the most cities wins.
  ///
  /// This is a pure read — it never mutates [state].
  ArmyId? checkVictory(GameState state);
}

// ─── Concrete implementation ──────────────────────────────────────────────────

/// Default implementation of [VictoryService].
class VictoryServiceImpl implements VictoryService {
  const VictoryServiceImpl();

  @override
  ArmyId? checkVictory(GameState state) {
    final counts = <ArmyId, int>{};
    for (final t in state.territories) {
      final owner = t.ownerArmyId;
      if (owner != null) counts[owner] = (counts[owner] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    for (final entry in counts.entries) {
      if (entry.value == kTerritoryCount) return entry.key;
    }
    if (counts.length == 1) return counts.keys.single;

    // The human player was eliminated: the strongest bot wins.
    final humanPlays = state.armies.any((a) => a.id == ArmyId.army1);
    if (humanPlays && !counts.containsKey(ArmyId.army1)) {
      return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    }
    return null;
  }
}
