/// Card ("kart") domain model for Harita: Kendi İmparatorluğunu Kur.
library;

// ─── Enums ──────────────────────────────────────────────────────────────────

/// All cards ("kartlar") in the game. An army holds a number of each
/// ([Army.cards]); playing one uses it up. Cards come from the free draw of
/// every turn ("Kart Çek") and from the Weapon Shop.
enum AbilityType {
  /// Kills 30 soldiers in a city next to your land.
  fireBomb,

  /// Kills 40 soldiers in each of 2 cities next to your land.
  bombardment,

  /// Adds soldiers to one of your cities.
  soldierSpell,

  /// Kills 60 soldiers in each of 3 cities next to your land.
  /// Labelled "Mega Bomba" (TR) / "Super Blast" (EN) in the UI.
  megaBomba,

  /// "Atom Bombası": kills 80 soldiers in each of 4 cities anywhere.
  atomBomb,

  /// "Nükleer Bomba": kills 100 soldiers in each of 6 cities anywhere.
  nuclearBomb,

  /// "Haraç Kes": takes diamonds from the owner of the target city.
  tribute,
}

/// Helpers describing what each card does.
extension AbilityTypeX on AbilityType {
  /// Whether the card targets one of the playing army's own cities.
  bool get targetsOwnTile => this == AbilityType.soldierSpell;

  /// Whether the card can hit any city on the map (not only those next to
  /// the army's land).
  bool get hitsAnywhere =>
      this == AbilityType.atomBomb ||
      this == AbilityType.nuclearBomb ||
      this == AbilityType.tribute;

  /// Whether the card is a bomb (kills soldiers).
  bool get captures =>
      this != AbilityType.soldierSpell && this != AbilityType.tribute;
}
