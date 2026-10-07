/// Card ("kart") domain model for Harita: Kendi İmparatorluğunu Kur.
library;

// ─── Enums ──────────────────────────────────────────────────────────────────

/// All cards ("kartlar") in the game. An army holds a number of each
/// ([Army.cards]); playing one uses it up. Cards come from the free draw of
/// every turn ("Kart Çek") and from the Weapon Shop.
enum AbilityType {
  /// Captures 2 tiles next to your land.
  fireBomb,

  /// Captures 8 tiles next to your land.
  bombardment,

  /// Adds soldiers to one of your tiles.
  soldierSpell,

  /// Captures 25 tiles next to your land.
  /// Labelled "Mega Bomba" (TR) / "Super Blast" (EN) in the UI.
  megaBomba,

  /// "Atom Bombası": captures 25 tiles anywhere on the map.
  atomBomb,

  /// "Nükleer Bomba": captures 40 tiles anywhere on the map.
  nuclearBomb,

  /// "Haraç Kes": takes diamonds from the owner of the target tile.
  tribute,
}

/// Helpers describing what each card does.
extension AbilityTypeX on AbilityType {
  /// Whether the card targets one of the playing army's own tiles.
  bool get targetsOwnTile => this == AbilityType.soldierSpell;

  /// Whether the card can hit any tile on the map (not only those next to
  /// the army's land).
  bool get hitsAnywhere =>
      this == AbilityType.atomBomb ||
      this == AbilityType.nuclearBomb ||
      this == AbilityType.tribute;

  /// Whether the card captures tiles.
  bool get captures =>
      this != AbilityType.soldierSpell && this != AbilityType.tribute;
}
