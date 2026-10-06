/// Special ability domain models for Harita: Kendi İmparatorluğunu Kur.
library;

// ─── Enums ──────────────────────────────────────────────────────────────────

/// All special combat abilities ("kartlar") available in the game.
enum AbilityType {
  /// Fire bomb available from turn 0.
  fireBomb,

  /// Artillery bombardment; unlocks at turn 10.
  bombardment,

  /// Reinforcement spell; unlocks at turn 12.
  soldierSpell,

  /// Most powerful area weapon; unlocks at turn 45.
  /// Labelled "Mega Bomba" (TR) / "Super Blast" (EN) in the UI.
  megaBomba,
}

// ─── AbilityState ─────────────────────────────────────────────────────────

/// Runtime state of a single special ability for one army.
///
/// Immutable by design — mutating state is done via [copyWith].
class AbilityState {
  const AbilityState({
    required this.type,
    required this.isUnlocked,
    this.cooldownTurnsRemaining,
  });

  /// Which ability this state describes.
  final AbilityType type;

  /// Whether this ability is currently available to use.
  final bool isUnlocked;

  /// Turns remaining before the ability can be used again.
  /// `null` for abilities that have not been used yet.
  final int? cooldownTurnsRemaining;

  // ─── Convenience getters ──────────────────────────────────────────────────

  /// Returns `true` when the ability is on cooldown (i.e., [cooldownTurnsRemaining] > 0).
  bool get isOnCooldown =>
      cooldownTurnsRemaining != null && cooldownTurnsRemaining! > 0;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  AbilityState copyWith({
    AbilityType? type,
    bool? isUnlocked,
    Object? cooldownTurnsRemaining = _sentinel,
  }) {
    return AbilityState(
      type: type ?? this.type,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      cooldownTurnsRemaining: cooldownTurnsRemaining == _sentinel
          ? this.cooldownTurnsRemaining
          : cooldownTurnsRemaining as int?,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AbilityState) return false;
    return type == other.type &&
        isUnlocked == other.isUnlocked &&
        cooldownTurnsRemaining == other.cooldownTurnsRemaining;
  }

  @override
  int get hashCode => Object.hash(type, isUnlocked, cooldownTurnsRemaining);

  @override
  String toString() =>
      'AbilityState(type: $type, unlocked: $isUnlocked, '
      'cooldown: $cooldownTurnsRemaining)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

const Object _sentinel = Object();
