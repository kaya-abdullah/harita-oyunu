/// Special ability domain models for Harita: Kendi İmparatorluğunu Kur.
library;

// ─── Enums ──────────────────────────────────────────────────────────────────

/// All special combat abilities available in the game.
enum AbilityType {
  /// Area-damage bomb available from turn 0.
  fireBomb,

  /// Artillery bombardment; unlocks at turn 10.
  bombardment,

  /// Reinforcement spell; unlocks at turn 12.
  soldierSpell,

  /// Most powerful area weapon; unlocks at turn 45.
  /// Labelled "Mega Bomba" (TR) / "Super Blast" (EN) in the UI.
  megaBomba,

  /// Precision beam; activates when fully charged, then enters a 3-turn
  /// cooldown.
  directLaser,
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
    this.chargeLevel,
    this.maxCharge,
  });

  /// Which ability this state describes.
  final AbilityType type;

  /// Whether this ability is currently available to use.
  final bool isUnlocked;

  /// Turns remaining before the ability can be used again.
  /// `null` for abilities without a cooldown mechanism.
  final int? cooldownTurnsRemaining;

  /// Current charge level; only relevant for [AbilityType.directLaser].
  final int? chargeLevel;

  /// Maximum charge level; only relevant for [AbilityType.directLaser].
  final int? maxCharge;

  // ─── Convenience getters ──────────────────────────────────────────────────

  /// Returns `true` when the ability is on cooldown (i.e., [cooldownTurnsRemaining] > 0).
  bool get isOnCooldown =>
      cooldownTurnsRemaining != null && cooldownTurnsRemaining! > 0;

  /// Returns `true` when the Direct Laser is at full charge and ready to fire.
  bool get isFullyCharged =>
      chargeLevel != null && maxCharge != null && chargeLevel! >= maxCharge!;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  AbilityState copyWith({
    AbilityType? type,
    bool? isUnlocked,
    Object? cooldownTurnsRemaining = _sentinel,
    Object? chargeLevel = _sentinel,
    Object? maxCharge = _sentinel,
  }) {
    return AbilityState(
      type: type ?? this.type,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      cooldownTurnsRemaining: cooldownTurnsRemaining == _sentinel
          ? this.cooldownTurnsRemaining
          : cooldownTurnsRemaining as int?,
      chargeLevel: chargeLevel == _sentinel
          ? this.chargeLevel
          : chargeLevel as int?,
      maxCharge: maxCharge == _sentinel ? this.maxCharge : maxCharge as int?,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AbilityState) return false;
    return type == other.type &&
        isUnlocked == other.isUnlocked &&
        cooldownTurnsRemaining == other.cooldownTurnsRemaining &&
        chargeLevel == other.chargeLevel &&
        maxCharge == other.maxCharge;
  }

  @override
  int get hashCode => Object.hash(
    type,
    isUnlocked,
    cooldownTurnsRemaining,
    chargeLevel,
    maxCharge,
  );

  @override
  String toString() =>
      'AbilityState(type: $type, unlocked: $isUnlocked, '
      'cooldown: $cooldownTurnsRemaining, charge: $chargeLevel/$maxCharge)';
}

// ─── Internal helpers ────────────────────────────────────────────────────────

const Object _sentinel = Object();
