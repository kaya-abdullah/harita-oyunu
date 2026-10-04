# Implementation Plan: Harita: Kendi İmparatorluğunu Kur

## Overview

Incremental Flutter/Dart implementation using the Flame engine, Riverpod state management, and Hive persistence. The plan builds from project scaffolding and core domain models through game logic services, Flame rendering, state management wiring, UI screens, and finally persistence and the tutorial. Each step integrates with the previous, leaving no orphaned code.

---

## Tasks

- [x] 1. Project scaffolding and core constants
  - [x] 1.1 Initialise the Flutter project structure matching the design directory layout
    - Create `lib/`, `assets/maps/`, `assets/locales/`, `assets/images/`, `assets/audio/` directories
    - Add `flame`, `riverpod`, `flutter_riverpod`, `hive`, `hive_flutter`, `hive_generator`, `build_runner` dependencies to `pubspec.yaml` with pinned versions
    - Create `lib/core/constants.dart` with game constants: `kTerritoryCount = 60`, `kBigBaseCapacity = 150`, `kTurnUnlockBombardment = 10`, `kTurnUnlockSoldierSpell = 12`, `kTurnUnlockMegaBomba = 45`, `kElmaPerBase = 10`, `kSoldiersPerTurn = 3`, `kPhoneBreakpoint = 600`
    - Create `lib/app.dart` with `MaterialApp` wrapped in Riverpod `ProviderScope`
    - Create `lib/main.dart` entry point that calls `Hive.initFlutter()` and runs the app
    - _Requirements: 1.1, 1.2, 4.1, 4.2_

  - [x] 1.2 Create localization JSON bundles and `LocaleService`
    - Create `assets/locales/tr.json` with all Turkish strings (app_name, resource_name, ability names, error messages, victory strings, UI labels, tooltip strings)
    - Create `assets/locales/en.json` with all English strings matching the same keys
    - Create `lib/core/localization/locale_service.dart` implementing `translate(key, locale, {params})` with the fallback chain: requested locale → English → raw key
    - Create `lib/core/localization/app_localizations.dart` exposing a convenient extension method
    - _Requirements: 2.1, 2.2, 2.4, 10.2, 10.3_

  - [ ]* 1.3 Write property tests for LocaleService
    - **Property 2: Locale String Lookup Returns Correct Bundle** — for any registered key, translate returns the bundle string for the requested locale
    - **Property 4: Missing Locale Key Falls Back to English** — for any key absent from TR bundle, translate returns the EN value
    - **Validates: Requirements 2.2, 2.4**

  - [x] 1.4 Create `AppTheme` with child-friendly styling constraints
    - Create `lib/core/theme/app_theme.dart` with minimum font size 16 sp enforced via `TextTheme`
    - Define all text-on-background color pairs meeting WCAG 4.5:1 contrast ratio
    - Use cartoonish, colourful palette; define Army 1 (blue), Army 2 (red), neutral (grey) territory colours
    - _Requirements: 10.1, 11.1, 11.2_

  - [ ]* 1.5 Write property tests for AppTheme
    - **Property 21: Font Size Minimum** — every `TextStyle` in `AppTheme` has `fontSize >= 16`
    - **Property 22: Contrast Ratio Compliance** — every text-on-background pair in `AppTheme` has contrast ratio >= 4.5
    - **Validates: Requirements 11.1, 11.2**

- [x] 2. Domain models
  - [x] 2.1 Implement core domain model classes
    - Create `lib/domain/models/territory.dart` with `Territory`, `TerritoryType` enum
    - Create `lib/domain/models/army.dart` with `Army`, `ArmyId` enum, `ArmyKind` enum
    - Create `lib/domain/models/special_ability.dart` with `AbilityState`, `AbilityType` enum
    - Create `lib/domain/models/weapon_item.dart` with `WeaponItem`
    - Create `lib/domain/models/game_state.dart` with `GameState`, `GamePhase` enum
    - All models must be immutable; use `copyWith` methods throughout
    - _Requirements: 3.1, 3.2, 5.1, 6.1, 7.1_

  - [x] 2.2 Implement `SaveData` Hive model with adapters
    - Create `lib/domain/models/save_data.dart` with `@HiveType(typeId: 0)` annotations and all `@HiveField` entries per design
    - Implement `SaveData.fromGameState(GameState)` and `SaveData.toGameState()` serialisation round-trip
    - Run `build_runner` to generate `save_data.g.dart` Hive adapter
    - _Requirements: 12.1_

  - [ ]* 2.3 Write property tests for SaveData round-trip
    - **Property 24: Game State Persistence Round-Trip** — for any valid `GameState`, `SaveData.fromGameState(state).toGameState()` returns an equivalent state in all fields
    - **Validates: Requirements 12.1**

- [x] 3. Territory map data and graph service
  - [x] 3.1 Create `territory_graph.json` with all 60 territories
    - Populate `assets/maps/territory_graph.json` with 60 territory entries (id, nameKey, type, adjacentIds, baseCapacity)
    - Ensure bidirectional adjacency, `bigBase` entries have `baseCapacity == 150`, `smallBase` entries have `baseCapacity < 150`
    - Register the asset in `pubspec.yaml`
    - _Requirements: 3.1, 5.1, 5.2, 5.3_

  - [x] 3.2 Implement `TerritoryGraph` service
    - Create `lib/infrastructure/map/territory_graph.dart` loading from JSON asset
    - Implement `areAdjacent`, `getAdjacentTerritories`, `getTerritoriesOwnedBy`, `getBases`, `getById`
    - Validate 60 territories and bidirectional adjacency at load time; throw on violation
    - _Requirements: 3.3, 3.4, 3.5_

  - [ ]* 3.3 Write property tests for TerritoryGraph
    - **Property 5: Territory Selection Info Completeness** — for any territory id, `getById` returns an object with non-null name, non-negative unitCount field shape, and non-empty adjacentIds
    - Verify adjacency is bidirectional for all territory pairs in the graph
    - **Validates: Requirements 3.3_**

- [x] 4. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Domain services
  - [x] 5.1 Implement `EconomyService`
    - Create `lib/domain/services/economy_service.dart` with abstract interface and concrete implementation
    - `applyTurnIncome`: add `n × 10` Elma + 3 soldiers based on owned bases
    - `purchaseItem`: deduct Elma and add to inventory; throw `InsufficientElmaException` if balance insufficient
    - `getEligibleShopItems`: filter by `unlockTurn <= currentTurn` and unlocked abilities
    - _Requirements: 4.1, 4.2, 4.4, 7.3, 7.4_

  - [ ]* 5.2 Write property tests for EconomyService
    - **Property 8: Per-Turn Elma Income Formula** — for any army owning n bases, income increases Elma by exactly n × 10
    - **Property 9: Per-Turn Soldier Income** — `applyTurnIncome` always increases `totalUnitPool` by exactly 3
    - **Property 10: Insufficient Elma Rejects Purchase** — purchase throws and leaves army state unchanged when balance < item cost
    - **Property 15: Shop Eligibility Filter** — `getEligibleShopItems` never returns items with `unlockTurn > currentTurn` or requiring locked abilities
    - **Property 16: Purchase Transaction Atomicity** — post-purchase balance equals `prior - item.elmaCost` and item appears in inventory
    - **Validates: Requirements 4.1, 4.2, 4.4, 7.3, 7.4**

  - [x] 5.3 Implement `AbilityService`
    - Create `lib/domain/services/ability_service.dart` with abstract interface and concrete implementation
    - `getAbilitiesToUnlock(turn)`: return list of abilities whose threshold <= turn
    - `applyTurnUnlocks(army, turn)`: unlock applicable abilities on the army
    - `activateAbility(state, armyId, ability, targetId)`: validate not locked, not on cooldown, charge sufficient; throw specific exceptions otherwise; apply ability effect; return updated `GameState`
    - `tickCooldowns(army)`: decrement all non-null cooldown values by 1, clamped to 0
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [ ]* 5.4 Write property tests for AbilityService
    - **Property 12: Turn-Based Ability Unlock** — for all four turn-unlocked abilities, `isUnlocked == (currentTurn >= unlockTurn)` for any turn value
    - **Property 13: Direct Laser Cooldown After Use** — after `activateAbility` for `directLaser`, cooldown is exactly 3
    - **Property 14: Locked Ability Activation Is Rejected** — `activateAbility` on any locked ability throws without mutating state
    - **Validates: Requirements 6.1–6.8**

  - [x] 5.5 Implement `CombatService`
    - Create `lib/domain/services/combat_service.dart` with abstract interface and concrete implementation
    - Validate adjacency using `TerritoryGraph`; throw `InvalidAttackException` if not adjacent or attacking army does not own source
    - Apply combat resolution: attacker wins if `attacking > defending` (attacker loses `ceil(defending × 0.5)` units); defender holds otherwise (defender loses `ceil(attacking × 0.3)`, attacker loses all attacking units)
    - Transfer ownership when defender units reach 0
    - _Requirements: 3.4, 3.5, 3.6_

  - [ ]* 5.6 Write property tests for CombatService
    - **Property 6: Neutral Territory Capture Transfers Ownership** — after attack on neutral territory with winning attacker, territory owner equals attacker id
    - **Property 7: Zero Units Clears Ownership** — any territory reduced to zero units has `ownerArmyId == null`
    - **Validates: Requirements 3.4, 3.6**

  - [x] 5.7 Implement `TurnService` and `VictoryService`
    - Create `lib/domain/services/turn_service.dart`: `endTurn` applies income, ticks cooldowns, then switches `activeArmyId`; `isActiveArmy` helper
    - Create `lib/domain/services/victory_service.dart`: `checkVictory` returns winning `ArmyId` if and only if one army owns exactly 60 territories, else null
    - _Requirements: 8.1, 8.2, 8.3, 9.1_

  - [ ]* 5.8 Write property tests for TurnService and VictoryService
    - **Property 17: Turn Alternation Invariant** — after n `endTurn` calls from Army 1 start, active army equals Army 1 if n is even, Army 2 if n is odd
    - **Property 18: Resource Collection Before Control Transfer** — returned state has income applied and `activeArmyId` switched in single atomic update
    - **Property 19: Victory Detection Is Complete and Sound** — returns the correct army id when 60 territories owned, null otherwise; no false positives or negatives
    - **Validates: Requirements 8.1, 8.2, 9.1**

- [x] 6. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Hive persistence layer
  - [x] 7.1 Implement `HiveSaveRepository`
    - Create `lib/infrastructure/persistence/hive_adapters.dart` registering generated Hive adapters
    - Create `lib/infrastructure/persistence/hive_save_repository.dart` implementing `SaveRepository` interface
    - `saveGameState`: serialise and write to `game_save` box at `current_save` key
    - `loadGameState`: deserialise; on any exception, call `deleteSave` and return null
    - `hasSave`, `deleteSave` helpers
    - _Requirements: 12.1, 12.2, 12.3_

  - [ ]* 7.2 Write property tests for HiveSaveRepository
    - **Property 25: Corrupted Save Handled Gracefully** — passing malformed data to `loadGameState` returns null without throwing and deletes the save entry
    - **Validates: Requirements 12.3**

  - [x] 7.3 Implement `LocaleNotifier` and locale persistence
    - Create `lib/presentation/viewmodels/locale_viewmodel.dart` as a Riverpod `StateNotifier<Locale>`
    - Persist selected locale to a separate Hive box on every change; reload on init
    - Switch locale within 200 ms (synchronous in-memory bundle swap)
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ]* 7.4 Write property tests for locale persistence
    - **Property 3: Locale Persistence Round-Trip** — writing TR locale and re-initialising `LocaleNotifier` returns TR; same for EN
    - **Validates: Requirements 2.3**

- [x] 8. AI opponent
  - [x] 8.1 Implement `GreedyAiAgent`
    - Create `lib/infrastructure/ai/greedy_ai_agent.dart`
    - Step 1: collect AI-owned territories; find adjacent neutral territories and queue attack actions
    - Step 2: if no neutral targets, attack enemy territories where `aiUnits > enemyUnits × 1.5`
    - Step 3: activate available abilities if beneficial (any unlocked ability not on cooldown)
    - Step 4: spend available Elma on eligible shop items
    - Expose `planTurn(GameState) → AiTurnPlan`; execute each action with 300–500 ms artificial delay via `Future.delayed`
    - _Requirements: 8.1, 8.2_

- [x] 9. Riverpod state management
  - [x] 9.1 Implement `GameNotifier` and core providers
    - Create `lib/presentation/viewmodels/game_viewmodel.dart` with `GameNotifier extends StateNotifier<GameState>`
    - Inject `CombatService`, `AbilityService`, `EconomyService`, `TurnService`, `VictoryService`, `SaveRepository`, `GreedyAiAgent`
    - Implement `selectTerritory`, `declareAttack`, `activateAbility`, `endTurn`, `openShop`, `saveGame`, `loadGame`
    - Guard all action methods: reject if `GamePhase.victory` — return without state mutation
    - Wire AI execution: when `endTurn` results in `activeArmyId == army2`, automatically invoke `GreedyAiAgent.planTurn` and apply actions
    - Define `gameStateProvider`, `activeArmyProvider`, `isVictoryProvider` providers
    - _Requirements: 8.1, 8.2, 8.4, 9.3_

  - [ ]* 9.2 Write property tests for GameNotifier
    - **Property 20: No Actions Accepted in Victory State** — calling `declareAttack`, `activateAbility`, `openShop`, `endTurn` on a `victory` phase state returns without modifying state
    - **Validates: Requirements 9.3**

  - [x] 9.3 Implement `ShopNotifier` and `shopProvider`
    - Create `lib/presentation/viewmodels/shop_viewmodel.dart` with `ShopNotifier extends StateNotifier<ShopState>`
    - `ShopState` includes `items`, `isReadOnly` (true when shop opened by inactive army)
    - `isReadOnly` derived from whether calling army matches `activeArmyId`
    - _Requirements: 7.1, 7.2, 7.4, 7.5_

  - [ ]* 9.4 Write property tests for ShopNotifier
    - **Property 26: Shop Read-Only for Inactive Army** — opening shop as inactive army produces `ShopState.isReadOnly == true`; no purchase action executable
    - **Validates: Requirements 7.5**

- [x] 10. Flame map rendering
  - [x] 10.1 Implement `WarGame`, `MapComponent`, and `TerritoryComponent`
    - Create `lib/game/war_game.dart` extending `FlameGame with TapDetector`; inject `GameViewModel`; add `MapComponent` on load
    - Create `lib/game/components/map_component.dart` loading territory positions from JSON coordinates; instantiate one `TerritoryComponent` per territory; apply owner colour overlay (Army 1 = blue tint, Army 2 = red tint, neutral = grey)
    - Create `lib/game/components/territory_component.dart` extending `PositionComponent with TapCallbacks`; load neutral/army1/army2 sprites; notify `GameNotifier` on tap
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 10.2 Implement `UnitSpriteComponent` and `HudOverlay`
    - Create `lib/game/components/unit_sprite_component.dart` displaying unit count badge on each territory
    - Create `lib/game/overlays/hud_overlay.dart` as a Flutter widget overlay on the Flame canvas; show Turn number, active army indicator, and both armies' Elma balances
    - _Requirements: 3.3, 4.3, 8.3, 8.4_

- [x] 11. HUD widgets and ability panel
  - [x] 11.1 Implement HUD widgets
    - Create `lib/presentation/widgets/hud/resource_bar.dart` displaying Elma balances for both armies, always visible, respecting font-size and contrast constraints
    - Create `lib/presentation/widgets/hud/turn_indicator.dart` showing current turn number and active army name
    - Create `lib/presentation/widgets/hud/ability_panel.dart` listing all 5 abilities with unlock status; locked abilities show the unlock turn number; Direct Laser shows charge/cooldown; tapping any ability shows a locale-appropriate tooltip
    - _Requirements: 4.3, 6.7, 8.3, 8.4, 11.3, 11.4_

  - [ ]* 11.2 Write property tests for ability panel tooltip behaviour
    - **Property 23: Tooltip Presence on Action Tap** — tapping any ability/action button produces a non-empty, locale-appropriate tooltip string; no button produces an empty or missing tooltip
    - **Validates: Requirements 11.4**

  - [x] 11.3 Implement `TerritoryInfoPanel` and `WeaponShopDialog`
    - Create `lib/presentation/widgets/map/territory_info_panel.dart` showing selected territory owner, unit count, and adjacent territories list
    - Create `lib/presentation/widgets/shop/weapon_shop_dialog.dart` listing items with Elma costs in active locale; read-only mode hides purchase button; insufficient Elma shows inline error message; icon labels alongside text labels for all shop actions
    - _Requirements: 3.3, 4.4, 7.2, 7.3, 7.5, 11.3_

- [x] 12. Screen layout and navigation
  - [x] 12.1 Implement responsive `GameScreen` layout
    - Create `lib/presentation/screens/game_screen.dart` using `LayoutBuilder` to select `PhoneGameLayout` (width < 600 dp) or `TabletGameLayout` (width >= 600 dp)
    - Phone layout: full-width map canvas, HUD and ability panel stacked below
    - Tablet layout: map canvas left, side panel right with HUD and ability panel
    - Embed `WarGame` Flame canvas via `GameWidget`
    - _Requirements: 1.2, 1.3, 1.4_

  - [ ]* 12.2 Write property tests for layout selection
    - **Property 1: Layout Variant Matches Screen Width** — for width < 600 dp, `PhoneGameLayout` is selected; for width >= 600 dp, `TabletGameLayout` is selected; no width produces an unhandled layout
    - **Validates: Requirements 1.2, 1.3, 1.4**

  - [x] 12.3 Implement `MainMenuScreen` and `VictoryScreen`
    - Create `lib/presentation/screens/main_menu_screen.dart` with New Game, Resume Game (visible only if `hasSave == true`), language toggle (TR/EN), and Tutorial buttons; app title is localized
    - Create `lib/presentation/screens/victory_screen.dart` displaying winning army name and turn count in active locale; animated celebration; New Game and Main Menu buttons
    - _Requirements: 9.2, 9.3, 12.2, 2.1_

- [x] 13. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Tutorial system
  - [x] 14.1 Implement `TutorialNotifier` and `TutorialScreen`
    - Create `lib/presentation/viewmodels/tutorial_viewmodel.dart` with `TutorialNotifier extends StateNotifier<TutorialState>`
    - Define ordered `TutorialStep` objects with locale keys for each step description; steps highlight: map interaction, territory selection, resource collection, abilities, shop, end turn, victory condition
    - Create `lib/presentation/screens/tutorial_screen.dart` rendering each step as an overlaid tip highlighting the relevant UI element, with Next/Skip controls
    - Mark tutorial as completed in Hive so it is only shown to new players
    - _Requirements: 11.5_

- [x] 15. Safety and parental controls
  - [x] 15.1 Enforce parental-control constraints in code
    - Verify no advertisement widgets or external URL launchers exist anywhere in the widget tree
    - Add a `ParentalConfirmationDialog` that gates any URL launch with a confirmation prompt; wire it at any navigation-away call site
    - Ensure any in-app purchase flow invokes `LocalAuthentication` (device-level biometric/PIN) before calling the purchase API
    - _Requirements: 13.1, 13.2, 13.3_

- [x] 16. Audio and final integration
  - [x] 16.1 Integrate audio and complete asset wiring
    - Add `flame_audio` or `audioplayers` package dependency; load upbeat background music and non-frightening sound effects for attacks, ability use, turn end, and victory
    - Ensure all assets (`territory_graph.json`, locale JSONs, images, audio) are listed in `pubspec.yaml` and load without error at startup
    - Wire `GameNotifier.loadGame` call on `MainMenuScreen` Resume tap and on app startup if a save exists; wire `GameNotifier.saveGame` call at end of every turn via `TurnService`
    - _Requirements: 10.4, 10.5, 12.1, 12.2_

- [x] 17. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The design document's 26 correctness properties are mapped to property-based test sub-tasks; each property sub-task references its property number and requirement clause
- The AI opponent executes with a 300–500 ms artificial delay per action for visual legibility
- `territory_graph.json` must be authored manually (or generated via a helper script) to represent a geographically plausible island/continent with 60 territories; bidirectionality and capacity constraints are validated at load time
- Hive `build_runner` must be run after any changes to `@HiveType` annotated classes: `dart run build_runner build`
- Audio files should be royalty-free; actual audio asset filenames should be confirmed before step 16.1

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.4"] },
    { "id": 1, "tasks": ["1.3", "1.5", "2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1"] },
    { "id": 3, "tasks": ["2.3", "3.2"] },
    { "id": 4, "tasks": ["3.3", "5.1"] },
    { "id": 5, "tasks": ["5.2", "5.3"] },
    { "id": 6, "tasks": ["5.4", "5.5", "7.1"] },
    { "id": 7, "tasks": ["5.6", "5.7", "7.2", "7.3", "8.1"] },
    { "id": 8, "tasks": ["5.8", "7.4", "9.1"] },
    { "id": 9, "tasks": ["9.2", "9.3"] },
    { "id": 10, "tasks": ["9.4", "10.1"] },
    { "id": 11, "tasks": ["10.2", "11.1"] },
    { "id": 12, "tasks": ["11.2", "11.3", "12.1"] },
    { "id": 13, "tasks": ["12.2", "12.3"] },
    { "id": 14, "tasks": ["14.1"] },
    { "id": 15, "tasks": ["15.1"] },
    { "id": 16, "tasks": ["16.1"] }
  ]
}
```
