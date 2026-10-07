/// Card ("kart") domain model for Harita: Kendi İmparatorluğunu Kur.
library;

// ─── Enums ──────────────────────────────────────────────────────────────────

/// All cards ("kartlar") in the game. An army holds a number of each
/// ([Army.cards]); playing one uses it up. Cards come from the free draw of
/// every turn ("Kart Çek") and from the Weapon Shop.
enum AbilityType {
  /// Captures 1 city next to your land.
  fireBomb,

  /// Captures 2 cities next to your land.
  bombardment,

  /// Adds soldiers to one of your cities.
  soldierSpell,

  /// Captures 3 cities next to your land.
  /// Labelled "Mega Bomba" (TR) / "Super Blast" (EN) in the UI.
  megaBomba,

  /// Captures 4 cities anywhere on the map ("Atom Bombası").
  atomBomb,

  /// Captures 6 cities anywhere on the map ("Nükleer Bomba").
  nuclearBomb,

  /// "Haraç Kes": takes diamonds from the owner of the target city.
  tribute,
}

/// Helpers describing what each card does.
extension AbilityTypeX on AbilityType {
  /// Whether the card targets one of the playing army's own cities.
  bool get targetsOwnCity => this == AbilityType.soldierSpell;

  /// Whether the card can hit any city on the map (not only those next to
  /// the army's land).
  bool get hitsAnywhere =>
      this == AbilityType.atomBomb ||
      this == AbilityType.nuclearBomb ||
      this == AbilityType.tribute;

  /// Whether the card captures cities.
  bool get captures =>
      this != AbilityType.soldierSpell && this != AbilityType.tribute;
}
