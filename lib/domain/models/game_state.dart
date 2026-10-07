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
  GameState({
    required this.territories,
    required List<Army> armies,
    required this.currentTurn,
    required this.activeArmyId,
    required this.phase,
    this.winnerId,
    this.difficulty = AiDifficulty.medium,
  }) : armies = List.unmodifiable(armies) {
    assert(armies.isNotEmpty, 'A game needs at least one army.');
  }

  /// All map territories (Africa tiles).  Order is stable (index == territory id).
  final List<Territory> territories;

  /// Every army in the game, in turn order. The first one is the human
  /// player ([ArmyId.army1]); the others are bots.
  final List<Army> armies;

  /// Current turn number, 1-indexed.
  final int currentTurn;

  /// Which army is currently taking its turn.
  final ArmyId activeArmyId;

  /// Whether the game is still in progress or has ended.
  final GamePhase phase;

  /// The winner's army id, populated only when [phase] is [GamePhase.victory].
  final ArmyId? winnerId;

  /// How strong the AI opponents play in this game.
  final AiDifficulty difficulty;

  // ─── Convenience getters ──────────────────────────────────────────────────

  /// The human player's army.
  Army get army1 => army(ArmyId.army1);

  /// The first bot's army.
  Army get army2 => army(ArmyId.army2);

  /// Returns the [Army] with [id]. Throws [StateError] if it is not playing.
  Army army(ArmyId id) => armies.firstWhere((a) => a.id == id);

  /// Returns the [Army] with [id], or `null` if it is not in this game.
  Army? armyOrNull(ArmyId id) {
    for (final a in armies) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Returns the [Army] object for the army currently taking its turn.
  Army get activeArmy => army(activeArmyId);

  /// Returns `true` when a winner has been declared.
  bool get isOver => phase == GamePhase.victory;

  /// Number of tiles owned by [id].
  int tilesOwnedBy(ArmyId id) =>
      territories.where((t) => t.ownerArmyId == id).length;

  /// Ids of the armies that still own at least one tile, in turn order.
  List<ArmyId> get armiesAlive {
    final owners = {for (final t in territories) t.ownerArmyId};
    return [
      for (final a in armies)
        if (owners.contains(a.id)) a.id,
    ];
  }

  /// Returns a copy with [updated] replacing the army that has the same id.
  GameState withArmy(Army updated) => copyWith(
    armies: [for (final a in armies) a.id == updated.id ? updated : a],
  );

  // ─── copyWith ─────────────────────────────────────────────────────────────

  GameState copyWith({
    List<Territory>? territories,
    List<Army>? armies,
    int? currentTurn,
    ArmyId? activeArmyId,
    GamePhase? phase,
    Object? winnerId = _sentinel,
    AiDifficulty? difficulty,
  }) {
    return GameState(
      territories: territories ?? this.territories,
      armies: armies ?? this.armies,
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
        _listEquals(armies, other.armies) &&
        currentTurn == other.currentTurn &&
        activeArmyId == other.activeArmyId &&
        phase == other.phase &&
        winnerId == other.winnerId &&
        difficulty == other.difficulty;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(territories),
    Object.hashAll(armies),
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
      'armies: ${armies.length}, territories: ${territories.length})';
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
