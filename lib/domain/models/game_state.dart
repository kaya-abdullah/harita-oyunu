/// Root game-state domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/territory.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// High-level phase of the game.
enum GamePhase {
  /// The game is in progress and actions are accepted.
  playing,

  /// A winner has been declared; no further actions are accepted.
  victory,
}

// ─── GameState ───────────────────────────────────────────────────────────────

/// Immutable snapshot of the complete game at a single point in time.
///
/// This is the root state object consumed by Riverpod notifiers and serialised
/// by the persistence layer.  All mutations are done via [copyWith].
class GameState {
  const GameState({
    required this.territories,
    required this.army1,
    required this.army2,
    required this.currentTurn,
    required this.activeArmyId,
    required this.phase,
    this.winnerId,
    this.difficulty = AiDifficulty.medium,
  });

  /// All map territories (Africa tiles).  Order is stable (index == territory id).
  final List<Territory> territories;

  /// Army 1 (human player, blue).
  final Army army1;

  /// Army 2 (AI opponent, red).
  final Army army2;

  /// Current turn number, 1-indexed.
  final int currentTurn;

  /// Which army is currently taking its turn.
  final ArmyId activeArmyId;

  /// Whether the game is still in progress or has ended.
  final GamePhase phase;

  /// The winner's army id, populated only when [phase] is [GamePhase.victory].
  final ArmyId? winnerId;

  /// How strong the AI opponent plays in this game.
  final AiDifficulty difficulty;

  // ─── Convenience getters ──────────────────────────────────────────────────

  /// Returns the [Army] object for the army currently taking its turn.
  Army get activeArmy => activeArmyId == ArmyId.army1 ? army1 : army2;

  /// Returns `true` when a winner has been declared.
  bool get isOver => phase == GamePhase.victory;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  GameState copyWith({
    List<Territory>? territories,
    Army? army1,
    Army? army2,
    int? currentTurn,
    ArmyId? activeArmyId,
    GamePhase? phase,
    Object? winnerId = _sentinel,
    AiDifficulty? difficulty,
  }) {
    return GameState(
      territories: territories ?? this.territories,
      army1: army1 ?? this.army1,
      army2: army2 ?? this.army2,
      currentTurn: currentTurn ?? this.currentTurn,
      activeArmyId: activeArmyId ?? this.activeArmyId,
      phase: phase ?? this.phase,
      winnerId: winnerId == _sentinel ? this.winnerId : winnerId as ArmyId?,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GameState) return false;
    return _listEquals(territories, other.territories) &&
        army1 == other.army1 &&
        army2 == other.army2 &&
        currentTurn == other.currentTurn &&
        activeArmyId == other.activeArmyId &&
        phase == other.phase &&
        winnerId == other.winnerId &&
        difficulty == other.difficulty;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(territories),
    army1,
    army2,
    currentTurn,
    activeArmyId,
    phase,
    winnerId,
    difficulty,
  );

  @override
  String toString() =>
      'GameState(turn: $currentTurn, active: $activeArmyId, '
      'phase: $phase, winner: $winnerId, difficulty: $difficulty, '
      'territories: ${territories.length})';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

const Object _sentinel = Object();

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
