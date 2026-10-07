/// Army domain model for Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:harita/domain/models/special_ability.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Identifies an army. [army1] is the human player; [army2] … [army7] are
/// the bots (up to [kMaxBots]), in turn order.
enum ArmyId {
  /// The human player (blue).
  army1,

  /// Bot 1 (red).
  army2,

  /// Bot 2.
  army3,

  /// Bot 3.
  army4,

  /// Bot 4.
  army5,

  /// Bot 5.
  army6,

  /// Bot 6.
  army7,
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
    required this.totalUnitPool,
    Map<AbilityType, int> cards = const {},
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

  /// Undeployed soldier units available to place on territories.
  final int totalUnitPool;

  /// Cards in hand ("kartlar"): how many of each (types with none are left
  /// out). Playing a card uses one up.
  final Map<AbilityType, int> cards;

  /// Whether the free card of this turn ("Kart Çek") was drawn.
  final bool hasDrawnCard;

  /// Number of [type] cards in hand.
  int cardCount(AbilityType type) => cards[type] ?? 0;

  /// Number of cards in hand.
  int get cardTotal => cards.values.fold(0, (a, b) => a + b);

  /// Returns a copy with [delta] more (or fewer) [type] cards.
  Army withCard(AbilityType type, int delta) =>
      copyWith(cards: {...cards, type: cardCount(type) + delta});

  // ─── copyWith ─────────────────────────────────────────────────────────────

  Army copyWith({
    ArmyId? id,
    ArmyKind? kind,
    int? diamondBalance,
    int? totalUnitPool,
    Map<AbilityType, int>? cards,
    bool? hasDrawnCard,
  }) {
    return Army(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      diamondBalance: diamondBalance ?? this.diamondBalance,
      totalUnitPool: totalUnitPool ?? this.totalUnitPool,
      cards: cards ?? this.cards,
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
        totalUnitPool == other.totalUnitPool &&
        _mapEquals(cards, other.cards) &&
        hasDrawnCard == other.hasDrawnCard;
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    diamondBalance,
    totalUnitPool,
    Object.hashAllUnordered(
      cards.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    hasDrawnCard,
  );

  @override
  String toString() =>
      'Army(id: $id, kind: $kind, diamonds: $diamondBalance, '
      'unitPool: $totalUnitPool, cards: $cards)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
