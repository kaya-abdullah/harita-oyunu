# Requirements Document

## Introduction

Harita: Kendi İmparatorluğunu Kur is a turn-based map strategy mobile game designed for children aged 9–10. The game runs on iOS and Android (tablet and phone form factors) and supports both Turkish and English languages. Two armies compete to conquer 60 territories on an island/continent map. Players collect resources, build armies, unlock special abilities by turn number, and purchase weapons through an in-game shop — all presented with child-friendly, cartoonish visuals and age-appropriate naming (e.g., "Mega Bomba" instead of nuclear bomb).

---

## Glossary

- **Game**: The Harita: Kendi İmparatorluğunu Kur application.
- **Player**: A human user controlling one of the two armies.
- **Army**: A collection of soldiers and resources controlled by one Player.
- **Territory**: One of the 60 map regions that can be owned and contested.
- **Base**: A special Territory that generates resources; comes in Big Base or Small Base variants.
- **Big Base**: A Base with an army capacity cap of 150 units.
- **Small Base**: A Base with a lower army capacity than a Big Base.
- **Elma**: The in-game resource currency (Turkish for "apple"). Produced per turn.
- **Turn**: One complete round of play for both armies; the atomic unit of game time.
- **Special Ability**: A combat power that becomes available at a specific turn number or charge condition.
- **Fire Bomb**: A Special Ability available from turn 0.
- **Bombardment**: A Special Ability that unlocks at turn 10.
- **Soldier Spell**: A Special Ability that unlocks at turn 12.
- **Mega Bomba**: A child-friendly Special Ability (formerly "Super Blast") that unlocks at turn 45; the game's most powerful area weapon.
- **Direct Laser**: A Special Ability that activates when fully charged and has a 3-turn cooldown.
- **Weapon Shop**: The in-game store where Players spend Elma to acquire weapons and upgrades.
- **Locale**: The active language setting; either Turkish (TR) or English (EN).
- **UI**: The on-screen user interface presented to the Player.

---

## Requirements

### Requirement 1 — Platform Support

**User Story:** As a child player, I want to play the game on my tablet or phone, so that I can enjoy the game on the device I own.

#### Acceptance Criteria

1. THE Game SHALL run natively on iOS (version 15 and above) and Android (version 10 and above).
2. THE Game SHALL support both phone and tablet screen sizes by adapting its layout to the available screen resolution.
3. WHEN the Game is launched on a device with a screen width below 600 dp, THE Game SHALL display a phone-optimised layout.
4. WHEN the Game is launched on a device with a screen width of 600 dp or above, THE Game SHALL display a tablet-optimised layout.

---

### Requirement 2 — Language Selection

**User Story:** As a player, I want to switch the game language between Turkish and English, so that I can play in my preferred language.

#### Acceptance Criteria

1. THE Game SHALL support Turkish (TR) and English (EN) as selectable Locales.
2. WHEN the Player selects a Locale from the language toggle, THE Game SHALL render all UI text, tooltips, ability names, and error messages in the chosen Locale within 200 ms.
3. THE Game SHALL persist the last selected Locale across sessions so that the same Locale is active on the next launch.
4. IF a UI string is missing for the selected Locale, THEN THE Game SHALL display the English fallback string.

---

### Requirement 3 — Map and Territory System

**User Story:** As a player, I want to conquer territories on a map, so that I can expand my Army and win the game.

#### Acceptance Criteria

1. THE Game SHALL present a map composed of exactly 60 Territories arranged in an island/continent layout.
2. THE Game SHALL visually distinguish each Territory by its current owner (Army 1 colour, Army 2 colour, or neutral).
3. WHEN a Player selects a Territory, THE Game SHALL display the Territory's owner, current unit count, and adjacent Territory list.
4. WHEN an Army unit moves into an unoccupied Territory, THE Game SHALL assign ownership of that Territory to the attacking Army.
5. WHEN two Armies occupy adjacent Territories and an attack is declared, THE Game SHALL resolve combat according to the combat resolution rules defined in the Design document.
6. IF an Army's unit count on a Territory reaches zero, THEN THE Game SHALL remove that Army's ownership of the Territory and mark it as neutral.

---

### Requirement 4 — Resource System (Elma)

**User Story:** As a player, I want to collect Elma each turn, so that I can fund my Army and purchase weapons.

#### Acceptance Criteria

1. WHEN a Turn begins, THE Game SHALL add 10 Elma to each Army's treasury for every Base the Army owns.
2. WHEN a Turn begins, THE Game SHALL add 3 soldier units to each Army's total unit pool.
3. THE Game SHALL display each Army's current Elma balance in the UI at all times during gameplay.
4. IF an Army attempts to purchase an item from the Weapon Shop with insufficient Elma, THEN THE Game SHALL reject the purchase and display an insufficient-funds message in the active Locale.

---

### Requirement 5 — Base Types

**User Story:** As a player, I want to capture different base types, so that I can manage my Army capacity strategically.

#### Acceptance Criteria

1. THE Game SHALL classify each Base Territory as either a Big Base or a Small Base.
2. WHILE an Army occupies a Big Base, THE Game SHALL enforce a maximum Army capacity of 150 units at that Base.
3. WHILE an Army occupies a Small Base, THE Game SHALL enforce a maximum Army capacity lower than 150 units, as defined per map configuration.
4. IF an Army's unit count at a Base reaches the Base's capacity limit, THEN THE Game SHALL prevent additional units from being assigned to that Base.

---

### Requirement 6 — Special Abilities

**User Story:** As a player, I want to unlock and use special abilities as the game progresses, so that I can employ diverse combat strategies.

#### Acceptance Criteria

1. THE Game SHALL make the Fire Bomb ability available to both Armies from Turn 0.
2. WHEN Turn 10 is reached, THE Game SHALL unlock the Bombardment ability for both Armies.
3. WHEN Turn 12 is reached, THE Game SHALL unlock the Soldier Spell ability for both Armies.
4. WHEN Turn 45 is reached, THE Game SHALL unlock the Mega Bomba ability for both Armies.
5. WHILE the Direct Laser ability is fully charged, THE Game SHALL make the Direct Laser available for the active Army to use.
6. WHEN the Direct Laser ability is used, THE Game SHALL begin a 3-turn cooldown during which the Direct Laser is unavailable.
7. WHEN a Special Ability has not yet been unlocked, THE Game SHALL display the ability as locked and show the unlock turn number in the UI.
8. IF a Player attempts to activate a locked Special Ability, THEN THE Game SHALL reject the action and display a locked-ability message in the active Locale.

---

### Requirement 7 — Weapon Shop

**User Story:** As a player, I want to purchase weapons and upgrades from a shop, so that I can strengthen my Army with Elma I have collected.

#### Acceptance Criteria

1. THE Game SHALL provide a Weapon Shop accessible from the main game UI during the Player's Turn.
2. THE Weapon Shop SHALL display all available items with their Elma cost in the active Locale.
3. WHEN a Player purchases an item, THE Game SHALL deduct the item's Elma cost from the Army's treasury and add the item to the Army's inventory.
4. WHEN a Player opens the Weapon Shop, THE Game SHALL display only items the Player's Army is eligible to purchase given their current Turn and unlocked abilities.
5. IF the Weapon Shop is opened outside the Player's active Turn, THEN THE Game SHALL display the shop in a read-only view without allowing purchases.

---

### Requirement 8 — Turn Structure

**User Story:** As a player, I want a clear turn-based flow, so that each Army takes actions in a fair, ordered sequence.

#### Acceptance Criteria

1. THE Game SHALL alternate turns between Army 1 and Army 2 in a fixed sequence.
2. WHEN a Player ends their Turn, THE Game SHALL trigger end-of-turn resource collection (Elma and soldier units) before passing control to the next Army.
3. THE Game SHALL display the current Turn number prominently in the UI at all times during gameplay.
4. THE Game SHALL display a visual indicator identifying which Army's Turn is currently active.
5. WHEN Turn 1 begins, THE Game SHALL designate Army 1 as the first active Army.

---

### Requirement 9 — Victory Condition

**User Story:** As a player, I want a clear win condition, so that I know when the game is over.

#### Acceptance Criteria

1. WHEN an Army controls all 60 Territories simultaneously, THE Game SHALL declare that Army the winner.
2. WHEN a winner is declared, THE Game SHALL display a victory screen with the winning Army's name and Turn count in the active Locale.
3. WHEN a winner is declared, THE Game SHALL cease accepting further game actions until the Player chooses to start a new game or return to the main menu.

---

### Requirement 10 — Child-Friendly Theming and Visuals

**User Story:** As a parent, I want the game to use age-appropriate visuals and language, so that the content is suitable for my 9–10 year old child.

#### Acceptance Criteria

1. THE Game SHALL use a cartoonish, colourful visual style for all characters, map elements, and UI components.
2. THE Game SHALL label the most powerful area weapon "Mega Bomba" (TR) / "Super Blast" (EN) throughout all UI text, tooltips, and ability descriptions.
3. THE Game SHALL use the term "Elma" (apple) as the resource name in the Turkish Locale and "Apple" in the English Locale.
4. THE Game SHALL avoid depictions of realistic violence, blood, or distressing imagery in all visual assets.
5. THE Game SHALL use sound effects and music that are upbeat and non-frightening.

---

### Requirement 11 — Accessibility and Usability for Children

**User Story:** As a child player, I want the UI to be easy to read and navigate, so that I can play without adult assistance.

#### Acceptance Criteria

1. THE Game SHALL use a minimum font size of 16 sp for all in-game text.
2. THE Game SHALL use high-contrast colour combinations (minimum 4.5:1 contrast ratio) for all text displayed on backgrounds.
3. THE Game SHALL provide icon-based labels alongside text labels for all primary UI actions.
4. WHEN a Player taps an ability or action button, THE Game SHALL display a brief tooltip describing that ability or action in the active Locale.
5. THE Game SHALL provide an interactive tutorial that guides a new Player through the core mechanics before the first game begins.

---

### Requirement 12 — Game State Persistence

**User Story:** As a player, I want my game to be saved automatically, so that I can continue a match after closing the app.

#### Acceptance Criteria

1. THE Game SHALL automatically save the complete game state (Territory ownership, Army resources, Turn number, ability cooldowns) at the end of every Turn.
2. WHEN the Game is relaunched after an interrupted session, THE Game SHALL offer the Player the option to resume the most recently saved game.
3. IF a saved game file is corrupted or unreadable, THEN THE Game SHALL discard the corrupted save and present the Player with the main menu.

---

### Requirement 13 — Parental Controls and Safe Play

**User Story:** As a parent, I want the game to be free of external links and purchases without consent, so that my child plays safely.

#### Acceptance Criteria

1. THE Game SHALL not display advertisements to the Player during gameplay.
2. THE Game SHALL not contain links that navigate the Player outside the application without a parental-confirmation prompt.
3. WHERE in-app purchase functionality is implemented, THE Game SHALL require device-level authentication before completing any purchase transaction.
