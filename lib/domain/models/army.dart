/// Army domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Identifies an army, in turn order. [army1] is always a human player;
/// in a two-player game [army2] is the second human. The others are bots
/// (up to [kMaxBots]).
enum ArmyId {
  army1,
  army2,
  army3,
  army4,
  army5,
  army6,
  army7,
  army8,
  army9,
  army10,
  army11,
  army12,
}

/// Specifies whether the army is controlled by a human or the AI.
enum ArmyKind {
  /// Controlled by a human player.
  human,

  /// Controlled by the greedy AI agent.
  ai,
}

// ─── Army ────────────────────────────────────────────────────────────────────

/// Represents one player's army and its associated resources.
///
/// Immutable by design — mutating state is done via [copyWith].
class Army {
  Army({
    required this.id,
    required this.kind,
    required this.diamondBalance,
    Map<AbilityType, int> cards = const {},
    this.tanks = 0,
    this.bombers = 0,
    this.bombersFlown = 0,
    this.tanksUsed = 0,
    this.hasDrawnCard = false,
  }) : cards = Map.unmodifiable({
         for (final e in cards.entries)
           if (e.value > 0) e.key: e.value,
       });

  /// Which army this is.
  final ArmyId id;

  /// Whether this army is human-controlled or AI-controlled.
  final ArmyKind kind;

  /// Current diamond (Elmas) balance.
  final int diamondBalance;

  /// Cards in hand: how many of each (types with none are left out).
  final Map<AbilityType, int> cards;

  /// Tanks. Each joins one attack per turn (see [kTankPower]).
  final int tanks;

  /// Tanks that already joined an attack this turn.
  final int tanksUsed;

  /// Bombers. Each flies one raid per turn (see [kBomberDamage]).
  final int bombers;

  /// Bombers that already flew this turn.
  final int bombersFlown;

  /// Whether the free card of this turn ("Kart Çek") was drawn.
  final bool hasDrawnCard;

  /// Number of [type] cards in hand.
  int cardCount(AbilityType type) => cards[type] ?? 0;

  /// Bombers that can still fly this turn.
  int get bombersReady => bombers - bombersFlown;

  /// Tanks that can still join an attack this turn.
  int get tanksReady => tanks - tanksUsed;

  /// Whether this army is played by a person.
  bool get isHuman => kind == ArmyKind.human;

  /// Returns a copy with [delta] more (or fewer) [type] cards.
  Army withCard(AbilityType type, int delta) =>
      copyWith(cards: {...cards, type: cardCount(type) + delta});

  // ─── copyWith ─────────────────────────────────────────────────────────────

  Army copyWith({
    ArmyId? id,
    ArmyKind? kind,
    int? diamondBalance,
    Map<AbilityType, int>? cards,
    int? tanks,
    int? bombers,
    int? bombersFlown,
    int? tanksUsed,
    bool? hasDrawnCard,
  }) {
    return Army(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      diamondBalance: diamondBalance ?? this.diamondBalance,
      cards: cards ?? this.cards,
      tanks: tanks ?? this.tanks,
      bombers: bombers ?? this.bombers,
      bombersFlown: bombersFlown ?? this.bombersFlown,
      tanksUsed: tanksUsed ?? this.tanksUsed,
      hasDrawnCard: hasDrawnCard ?? this.hasDrawnCard,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Army) return false;
    return id == other.id &&
        kind == other.kind &&
        diamondBalance == other.diamondBalance &&
        _mapEquals(cards, other.cards) &&
        tanks == other.tanks &&
        bombers == other.bombers &&
        bombersFlown == other.bombersFlown &&
        tanksUsed == other.tanksUsed &&
        hasDrawnCard == other.hasDrawnCard;
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    diamondBalance,
    Object.hashAllUnordered(
      cards.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    tanks,
    bombers,
    bombersFlown,
    tanksUsed,
    hasDrawnCard,
  );

  @override
  String toString() =>
      'Army(id: $id, kind: $kind, diamonds: $diamondBalance, '
      'cards: $cards, tanks: $tanks, bombers: $bombers)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
