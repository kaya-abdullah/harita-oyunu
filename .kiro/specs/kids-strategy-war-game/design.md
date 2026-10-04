# Design Document — Harita: Kendi İmparatorluğunu Kur

## Overview

Harita: Kendi İmparatorluğunu Kur is a turn-based map strategy mobile application for children aged 9–10, built with Flutter/Dart targeting iOS 15+ and Android 10+. The Flame game engine drives the interactive map canvas. Riverpod manages reactive state. Hive provides local persistence. A JSON-based localization layer supports Turkish (TR) and English (EN). The AI opponent uses a greedy territorial strategy suitable for the target age group.

---

## Architecture

The application follows **MVVM** (Model–View–ViewModel) layered architecture with a clear separation between game domain logic, state management, and UI rendering.

```
┌──────────────────────────────────────────────────────┐
│                    Presentation Layer                │
│  Flutter Widgets / Flame Components (View)           │
│  Riverpod Notifiers / ViewModels (ViewModel)         │
├──────────────────────────────────────────────────────┤
│                    Domain Layer                      │
│  Game Engine Services (Combat, Ability, Economy)     │
│  Game State Models                                   │
├──────────────────────────────────────────────────────┤
│                 Infrastructure Layer                 │
│  Hive Persistence  │  JSON Localization  │  AI Agent │
└──────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility |
|---|---|
| View | Flame map canvas, Flutter screens (menus, HUD, shop, victory) |
| ViewModel | Riverpod `StateNotifier` / `AsyncNotifier`; bridges domain ↔ view |
| Domain | Pure game logic: combat resolution, ability unlocking, economy, turn flow |
| Infrastructure | Hive adapters, JSON locale loaders, AI strategy, save/load |

---

## Directory Structure

```
lib/
├── main.dart
├── app.dart                         # MaterialApp + Riverpod ProviderScope
├── core/
│   ├── constants.dart               # Game constants (territory count, base caps, etc.)
│   ├── localization/
│   │   ├── locale_service.dart
│   │   └── app_localizations.dart
│   └── theme/
│       └── app_theme.dart
├── domain/
│   ├── models/
│   │   ├── territory.dart
│   │   ├── army.dart
│   │   ├── game_state.dart
│   │   ├── special_ability.dart
│   │   ├── weapon_item.dart
│   │   └── save_data.dart
│   └── services/
│       ├── combat_service.dart
│       ├── ability_service.dart
│       ├── economy_service.dart
│       ├── turn_service.dart
│       └── victory_service.dart
├── infrastructure/
│   ├── persistence/
│   │   ├── hive_save_repository.dart
│   │   └── hive_adapters.dart
│   ├── ai/
│   │   └── greedy_ai_agent.dart
│   └── map/
│       └── territory_graph.dart
├── presentation/
│   ├── screens/
│   │   ├── main_menu_screen.dart
│   │   ├── game_screen.dart
│   │   ├── victory_screen.dart
│   │   └── tutorial_screen.dart
│   ├── viewmodels/
│   │   ├── game_viewmodel.dart
│   │   ├── shop_viewmodel.dart
│   │   ├── locale_viewmodel.dart
│   │   └── tutorial_viewmodel.dart
│   └── widgets/
│       ├── hud/
│       │   ├── resource_bar.dart
│       │   ├── turn_indicator.dart
│       │   └── ability_panel.dart
│       ├── shop/
│       │   └── weapon_shop_dialog.dart
│       └── map/
│           └── territory_info_panel.dart
└── game/
    ├── war_game.dart                # Flame Game root
    ├── components/
    │   ├── map_component.dart
    │   ├── territory_component.dart
    │   └── unit_sprite_component.dart
    └── overlays/
        └── hud_overlay.dart
assets/
├── maps/
│   └── territory_graph.json        # 60 territories + adjacency
├── locales/
│   ├── tr.json
│   └── en.json
├── images/
└── audio/
```

---

## Data Models

### Territory

```dart
/// Represents one of the 60 map regions.
class Territory {
  final int id;                    // 0–59
  final String name;               // Locale key
  final TerritoryType type;        // normal | bigBase | smallBase
  final List<int> adjacentIds;     // Adjacency graph edges
  int unitCount;                   // Current units stationed
  ArmyId? ownerArmyId;             // null = neutral
  int? baseCapacity;               // Only set for base types
}

enum TerritoryType { normal, bigBase, smallBase }
```

### Army

```dart
/// Represents one player's army.
class Army {
  final ArmyId id;                 // army1 | army2
  final ArmyKind kind;             // human | ai
  int elmaBalance;                 // Current Elma currency
  int totalUnitPool;               // Undeployed units
  Map<AbilityType, AbilityState> abilities;
  List<WeaponItem> inventory;
}

enum ArmyId { army1, army2 }
enum ArmyKind { human, ai }
```

### AbilityState

```dart
class AbilityState {
  final AbilityType type;
  bool isUnlocked;
  int? cooldownTurnsRemaining;   // null if no cooldown
  int? chargeLevel;              // For charge-based abilities (Direct Laser)
  int? maxCharge;
}

enum AbilityType {
  fireBomb,       // unlocked at turn 0
  bombardment,    // unlocked at turn 10
  soldierSpell,   // unlocked at turn 12
  megaBomba,      // unlocked at turn 45
  directLaser,    // charge-based + 3-turn cooldown
}
```

### GameState

```dart
/// Root immutable game state snapshot.
class GameState {
  final List<Territory> territories;    // exactly 60
  final Army army1;
  final Army army2;
  final int currentTurn;               // 1-indexed
  final ArmyId activeArmyId;
  final GamePhase phase;               // playing | victory
  final ArmyId? winnerId;              // null until victory
}

enum GamePhase { playing, victory }
```

### SaveData

```dart
/// Serializable game snapshot for Hive persistence.
@HiveType(typeId: 0)
class SaveData {
  @HiveField(0) final Map<String, dynamic> territoriesJson;
  @HiveField(1) final Map<String, dynamic> army1Json;
  @HiveField(2) final Map<String, dynamic> army2Json;
  @HiveField(3) final int currentTurn;
  @HiveField(4) final String activeArmyId;
  @HiveField(5) final String phase;
  @HiveField(6) final String? winnerId;
  @HiveField(7) final int schemaVersion;   // for migration
}
```

### WeaponItem

```dart
class WeaponItem {
  final String id;
  final String nameKey;          // Locale key
  final int elmaCost;
  final int unlockTurn;
  final AbilityType? requiredAbility;
}
```

---

## Component Interfaces

### CombatService

```dart
abstract class CombatService {
  /// Resolves an attack from [attackingArmyId] on [targetTerritoryId].
  /// Returns updated GameState with unit changes and ownership transfers applied.
  /// Throws [InvalidAttackException] if territories are not adjacent or armies don't own them.
  GameState resolveAttack({
    required GameState state,
    required ArmyId attackingArmyId,
    required int sourceTerritoryId,
    required int targetTerritoryId,
  });
}
```

Combat resolution formula (configurable via constants):
- If `attackingUnits > defendingUnits`: attacker wins, attacker loses `ceil(defendingUnits * 0.5)` units, defender territory becomes attacker's with remaining units.
- If `attackingUnits <= defendingUnits`: defender holds, defender loses `ceil(attackingUnits * 0.3)` units, attacker loses all attacking units from that territory.
- If defender unit count reaches 0: territory becomes neutral, then immediately assigned to attacker.

### AbilityService

```dart
abstract class AbilityService {
  /// Returns abilities that should be unlocked at [currentTurn].
  List<AbilityType> getAbilitiesToUnlock(int currentTurn);

  /// Applies unlock side-effects to [army] for [turnNumber].
  Army applyTurnUnlocks(Army army, int turnNumber);

  /// Attempts to activate [ability] for [army] in [state].
  /// Returns updated GameState or throws [LockedAbilityException] / [CooldownActiveException].
  GameState activateAbility({
    required GameState state,
    required ArmyId armyId,
    required AbilityType ability,
    required int targetTerritoryId,
  });

  /// Decrements cooldown counters at end of turn.
  Army tickCooldowns(Army army);
}
```

Unlock schedule (constants):

| Ability | Unlock Condition |
|---|---|
| `fireBomb` | Turn 0 (always available) |
| `bombardment` | Turn >= 10 |
| `soldierSpell` | Turn >= 12 |
| `megaBomba` | Turn >= 45 |
| `directLaser` | Charge full + cooldown == 0 |

### EconomyService

```dart
abstract class EconomyService {
  /// Applies per-turn resource generation to [army] based on owned bases in [territories].
  Army applyTurnIncome(Army army, List<Territory> territories);

  /// Attempts to purchase [item] for [army].
  /// Returns updated Army or throws [InsufficientElmaException].
  Army purchaseItem(Army army, WeaponItem item);

  /// Returns items eligible for purchase given [army]'s current state and [currentTurn].
  List<WeaponItem> getEligibleShopItems(Army army, int currentTurn);
}
```

Income rules:
- +10 Elma per Base owned (bigBase + smallBase both count).
- +3 soldier units to `totalUnitPool` per turn.

### TurnService

```dart
abstract class TurnService {
  /// Ends the active army's turn: applies income, ticks cooldowns, switches active army.
  GameState endTurn(GameState state);

  /// Returns true if [armyId] is the currently active army.
  bool isActiveArmy(GameState state, ArmyId armyId);
}
```

### VictoryService

```dart
abstract class VictoryService {
  /// Returns the winning ArmyId if one army owns all 60 territories, else null.
  ArmyId? checkVictory(GameState state);
}
```

---

## Map System

### Territory Graph

The adjacency graph is defined in `assets/maps/territory_graph.json`:

```json
{
  "territories": [
    {
      "id": 0,
      "nameKey": "territory_0",
      "type": "normal",
      "adjacentIds": [1, 5, 6],
      "baseCapacity": null
    },
    {
      "id": 1,
      "nameKey": "territory_1",
      "type": "bigBase",
      "adjacentIds": [0, 2, 7],
      "baseCapacity": 150
    }
    // ... 58 more entries
  ]
}
```

Constraints enforced at load time:
- Exactly 60 territories.
- Each `adjacentIds` entry is bidirectional (if A→B then B→A).
- All `bigBase` territories have `baseCapacity == 150`.
- All `smallBase` territories have `baseCapacity < 150`.

### TerritoryGraph Service

```dart
class TerritoryGraph {
  final List<Territory> territories;

  bool areAdjacent(int idA, int idB);
  List<Territory> getAdjacentTerritories(int id);
  List<Territory> getTerritoriesOwnedBy(ArmyId armyId);
  List<Territory> getBases();
  Territory getById(int id);
}
```

---

## Flame Game Components

### WarGame (Flame Game root)

```dart
class WarGame extends FlameGame with TapDetector {
  late MapComponent mapComponent;
  late GameViewModel gameViewModel;   // injected via constructor

  @override
  Future<void> onLoad() async {
    await add(mapComponent);
  }

  @override
  void onTap(TapUpInfo info) {
    mapComponent.handleTap(info.eventPosition.game);
  }
}
```

### MapComponent

- Renders each `TerritoryComponent` at positions derived from the territory graph JSON coordinates.
- Owner color overlay: Army 1 = blue tint, Army 2 = red tint, neutral = grey.
- Handles tap routing to `TerritoryComponent`.

### TerritoryComponent

```dart
class TerritoryComponent extends PositionComponent with TapCallbacks {
  final Territory territory;
  late Sprite neutralSprite;
  late Sprite army1Sprite;
  late Sprite army2Sprite;

  @override
  void onTapUp(TapUpEvent event) {
    // Notify GameViewModel of territory selection
  }
}
```

---

## State Management (Riverpod)

### Providers

```dart
// Core game state
final gameStateProvider = StateNotifierProvider<GameNotifier, GameState>(...);

// Shop
final shopProvider = StateNotifierProvider<ShopNotifier, ShopState>(...);

// Locale
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(...);

// Tutorial
final tutorialProvider = StateNotifierProvider<TutorialNotifier, TutorialState>(...);

// Derived selectors
final activeArmyProvider = Provider<Army>((ref) {
  final state = ref.watch(gameStateProvider);
  return state.activeArmyId == ArmyId.army1 ? state.army1 : state.army2;
});

final isVictoryProvider = Provider<bool>((ref) =>
    ref.watch(gameStateProvider).phase == GamePhase.victory);
```

### GameNotifier

```dart
class GameNotifier extends StateNotifier<GameState> {
  final CombatService _combat;
  final AbilityService _ability;
  final EconomyService _economy;
  final TurnService _turn;
  final VictoryService _victory;
  final SaveRepository _save;
  final GreedyAiAgent _ai;

  void selectTerritory(int id);
  void declareAttack(int sourceId, int targetId);
  void activateAbility(AbilityType type, int targetId);
  void endTurn();
  void openShop();
  Future<void> saveGame();
  Future<void> loadGame();
}
```

---

## AI Opponent — Greedy Strategy

The AI executes automatically when `activeArmyId == ArmyId.army2` (AI army).

### Algorithm

```dart
class GreedyAiAgent {
  AiTurnPlan planTurn(GameState state) {
    final aiTerritories = graph.getTerritoriesOwnedBy(ArmyId.army2);
    final actions = <AiAction>[];

    // 1. Prioritise attacking neutral territories adjacent to owned territories
    for (final t in aiTerritories) {
      for (final adj in graph.getAdjacentTerritories(t.id)) {
        if (adj.ownerArmyId == null && t.unitCount > 1) {
          actions.add(AttackAction(source: t.id, target: adj.id));
        }
      }
    }

    // 2. If no neutral targets, attack enemy territories with favourable odds
    if (actions.isEmpty) {
      for (final t in aiTerritories) {
        for (final adj in graph.getAdjacentTerritories(t.id)) {
          if (adj.ownerArmyId == ArmyId.army1 &&
              t.unitCount > adj.unitCount * 1.5) {
            actions.add(AttackAction(source: t.id, target: adj.id));
          }
        }
      }
    }

    // 3. Use available abilities if beneficial
    // 4. Purchase reinforcements from shop if Elma allows

    return AiTurnPlan(actions: actions);
  }
}
```

The AI executes its plan action-by-action with a small artificial delay (300–500 ms per action) for visual legibility.

---

## Localization System

### JSON Bundle Format

`assets/locales/tr.json`:
```json
{
  "app_name": "Harita: Kendi İmparatorluğunu Kur",
  "resource_name": "Elma",
  "ability_fire_bomb": "Ateş Bombası",
  "ability_mega_bomba": "Mega Bomba",
  "ability_locked": "Kilitli — Tur {turn}",
  "error_insufficient_elma": "Yeterli Elma yok!",
  "error_ability_locked": "Bu yetenek henüz açılmadı.",
  "victory_title": "{army} Kazandı!",
  "victory_turns": "{turn} Turda"
}
```

`assets/locales/en.json`:
```json
{
  "app_name": "Map: Build Your Own Empire",
  "resource_name": "Apple",
  "ability_fire_bomb": "Fire Bomb",
  "ability_mega_bomba": "Super Blast",
  "ability_locked": "Locked — Turn {turn}",
  "error_insufficient_elma": "Not enough Apples!",
  "error_ability_locked": "This ability is not yet unlocked.",
  "victory_title": "{army} Wins!",
  "victory_turns": "In {turn} Turns"
}
```

### LocaleService

```dart
class LocaleService {
  final Map<String, Map<String, String>> _bundles;

  String translate(String key, Locale locale, {Map<String, String>? params}) {
    final bundle = _bundles[locale.languageCode] ?? _bundles['en']!;
    final template = bundle[key] ?? _bundles['en']![key] ?? key;
    return _interpolate(template, params);
  }

  String _interpolate(String template, Map<String, String>? params) {
    if (params == null) return template;
    return params.entries.fold(
      template,
      (s, e) => s.replaceAll('{${e.key}}', e.value),
    );
  }
}
```

Fallback chain: requested locale → English → raw key.

---

## Persistence — Hive

### Save Repository

```dart
abstract class SaveRepository {
  Future<void> saveGameState(GameState state);
  Future<GameState?> loadGameState();
  Future<void> deleteSave();
  Future<bool> hasSave();
}

class HiveSaveRepository implements SaveRepository {
  static const _boxName = 'game_save';
  static const _saveKey = 'current_save';

  @override
  Future<void> saveGameState(GameState state) async {
    final box = await Hive.openBox<SaveData>(_boxName);
    await box.put(_saveKey, SaveData.fromGameState(state));
  }

  @override
  Future<GameState?> loadGameState() async {
    try {
      final box = await Hive.openBox<SaveData>(_boxName);
      final raw = box.get(_saveKey);
      if (raw == null) return null;
      return raw.toGameState();
    } catch (_) {
      await deleteSave();
      return null;  // Corrupted save → return null → caller shows main menu
    }
  }
}
```

---

## Screen Designs

### Main Menu Screen

- App title (localized), New Game button, Resume Game button (visible only if save exists), Language toggle (TR / EN), Tutorial button.

### Game Screen

Structure:
```
┌─────────────────────────────────────┐
│  HUD: Turn number | Active army     │
│       Elma balance (both armies)    │
├─────────────────────────────────────┤
│                                     │
│        Flame Map Canvas             │
│    (TerritoryComponents)            │
│                                     │
├─────────────────────────────────────┤
│  Ability Panel    │  Shop  │ EndTurn│
└─────────────────────────────────────┘
```

Tablet layout: side panel replaces bottom bar; map canvas expands.

### Victory Screen

Displays: winning army name, turn count, animated celebration, "New Game" and "Main Menu" buttons.

### Tutorial Screen

Step-by-step overlaid tips using a `TutorialNotifier` that advances through ordered `TutorialStep` objects. Each step highlights a UI element and shows a localized description.

---

## Layout Adaptation

```dart
LayoutBreakpoints:
  phone:  screenWidth < 600 dp  → stacked layout (map full-width, HUD below)
  tablet: screenWidth >= 600 dp → side-by-side layout (map left, panel right)
```

Implemented via a `LayoutBuilder` at the top of `GameScreen`:

```dart
LayoutBuilder(builder: (context, constraints) {
  final isTablet = constraints.maxWidth >= 600;
  return isTablet ? TabletGameLayout() : PhoneGameLayout();
})
```

---

## Error Handling

| Error | Domain Exception | UI Response |
|---|---|---|
| Attack on non-adjacent territory | `InvalidAttackException` | Toast with locale message |
| Insufficient Elma for purchase | `InsufficientElmaException` | Shop inline error message |
| Locked ability activation | `LockedAbilityException` | Tooltip with unlock turn |
| Active cooldown | `CooldownActiveException` | Ability button shows remaining turns |
| Corrupted save | caught in `loadGameState()` | Silent delete + main menu |
| Missing locale key | Fallback to EN | No user-visible error |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Layout Variant Matches Screen Width

*For any* device screen width in dp, the game SHALL select the phone layout when width < 600 and the tablet layout when width >= 600. No width value should produce an unhandled or ambiguous layout state.

**Validates: Requirements 1.2, 1.3, 1.4**

---

### Property 2: Locale String Lookup Returns Correct Bundle

*For any* valid locale and any registered string key, `LocaleService.translate` SHALL return the string from the bundle matching that locale. Switching locale and re-querying the same key SHALL return the new locale's string, not the previous one.

**Validates: Requirements 2.2**

---

### Property 3: Locale Persistence Round-Trip

*For any* valid locale value (TR or EN) written to persistent storage, reading it back in a subsequent session SHALL return the same locale value unchanged.

**Validates: Requirements 2.3**

---

### Property 4: Missing Locale Key Falls Back to English

*For any* string key that is absent from the selected non-English locale's bundle, `LocaleService.translate` SHALL return the English bundle value for that key rather than an empty string or a raw key.

**Validates: Requirements 2.4**

---

### Property 5: Territory Selection Info Completeness

*For any* territory in the map, selecting it SHALL produce an info object containing all three required fields: owner (or neutral indicator), current unit count, and a non-empty adjacent territory list.

**Validates: Requirements 3.3**

---

### Property 6: Neutral Territory Capture Transfers Ownership

*For any* neutral territory that is adjacent to a territory owned by an army, executing a move action into that neutral territory SHALL assign ownership to the attacking army. The territory SHALL NOT remain neutral after a successful move.

**Validates: Requirements 3.4**

---

### Property 7: Zero Units Clears Ownership

*For any* territory whose unit count is reduced to exactly zero, the territory's owner SHALL become null (neutral). No army SHALL own a territory with zero units.

**Validates: Requirements 3.6**

---

### Property 8: Per-Turn Elma Income Formula

*For any* army owning n bases at the start of a turn, the army's Elma balance after `EconomyService.applyTurnIncome` SHALL equal the previous balance plus (n × 10). The formula holds for any non-negative integer n including zero.

**Validates: Requirements 4.1**

---

### Property 9: Per-Turn Soldier Income

*For any* army at any point in the game, calling `EconomyService.applyTurnIncome` SHALL increase that army's `totalUnitPool` by exactly 3. The increment is constant regardless of turn number or territory count.

**Validates: Requirements 4.2**

---

### Property 10: Insufficient Elma Rejects Purchase

*For any* weapon item with an Elma cost greater than the purchasing army's current balance, `EconomyService.purchaseItem` SHALL throw `InsufficientElmaException` and leave the army's balance and inventory unchanged.

**Validates: Requirements 4.4**

---

### Property 11: Base Capacity Enforcement

*For any* base territory (Big Base or Small Base) occupied by an army, the unit count at that territory SHALL never exceed the base's configured capacity. Any unit assignment that would exceed the capacity SHALL be rejected.

**Validates: Requirements 5.2, 5.3, 5.4**

---

### Property 12: Turn-Based Ability Unlock

*For any* turn number t and any ability with a turn-based unlock threshold u, the ability SHALL be in the unlocked state if and only if t >= u. This invariant holds for all four turn-unlocked abilities: Fire Bomb (u=0), Bombardment (u=10), Soldier Spell (u=12), Mega Bomba (u=45).

**Validates: Requirements 6.1, 6.2, 6.3, 6.4**

---

### Property 13: Direct Laser Cooldown After Use

*For any* game state in which the Direct Laser is activated, the ability's cooldown SHALL be set to exactly 3 turns immediately after activation, regardless of prior game state or turn number.

**Validates: Requirements 6.6**

---

### Property 14: Locked Ability Activation Is Rejected

*For any* ability in the locked state (cooldown active, turn threshold not met, or charge insufficient), calling `AbilityService.activateAbility` SHALL throw an exception and leave the game state unchanged. No side effects SHALL occur.

**Validates: Requirements 6.7, 6.8**

---

### Property 15: Shop Eligibility Filter

*For any* combination of current turn and army state, `EconomyService.getEligibleShopItems` SHALL return only items whose `unlockTurn <= currentTurn` and whose `requiredAbility` (if any) is unlocked. No item requiring a future turn or a locked ability SHALL appear in the result.

**Validates: Requirements 7.4**

---

### Property 16: Purchase Transaction Atomicity

*For any* weapon item the army can afford, calling `EconomyService.purchaseItem` SHALL atomically decrease the army's Elma balance by exactly the item's cost AND add the item to the army's inventory. The post-purchase balance SHALL equal `priorBalance - item.elmaCost`.

**Validates: Requirements 7.3**

---

### Property 17: Turn Alternation Invariant

*For any* sequence of n turn-end events starting from Army 1, the active army after n transitions SHALL be Army 1 if n is even and Army 2 if n is odd. This alternation SHALL hold for any positive integer n.

**Validates: Requirements 8.1**

---

### Property 18: Resource Collection Before Control Transfer

*For any* army ending its turn, `TurnService.endTurn` SHALL apply income (Elma + soldiers) to the ending army before updating `activeArmyId`. The returned `GameState` SHALL reflect both the income credit and the control transfer in a single atomic update.

**Validates: Requirements 8.2**

---

### Property 19: Victory Detection Is Complete and Sound

*For any* game state where one army owns exactly 60 territories, `VictoryService.checkVictory` SHALL return that army's ID. *For any* game state where neither army owns 60 territories, it SHALL return null. No false positives or false negatives are permitted.

**Validates: Requirements 9.1**

---

### Property 20: No Actions Accepted in Victory State

*For any* game in `GamePhase.victory`, any call to action methods on `GameNotifier` (attack, ability activation, shop purchase, end turn) SHALL be rejected without modifying the game state.

**Validates: Requirements 9.3**

---

### Property 21: Font Size Minimum

*For any* text widget rendered in the application, the configured font size SHALL be greater than or equal to 16 sp. No UI text SHALL be rendered below this minimum.

**Validates: Requirements 11.1**

---

### Property 22: Contrast Ratio Compliance

*For any* text-on-background color pair defined in `AppTheme`, the calculated WCAG contrast ratio SHALL be greater than or equal to 4.5. No color pair SHALL fall below this threshold.

**Validates: Requirements 11.2**

---

### Property 23: Tooltip Presence on Action Tap

*For any* tappable ability or action button in the game, tapping it SHALL produce a non-empty, locale-appropriate tooltip string. No action button SHALL produce an empty or missing tooltip.

**Validates: Requirements 11.4**

---

### Property 24: Game State Persistence Round-Trip

*For any* valid `GameState`, serializing it to `SaveData` via `SaveData.fromGameState` and then deserializing it via `SaveData.toGameState` SHALL produce a `GameState` that is equivalent to the original in all fields: territory ownership, unit counts, army resources, turn number, active army, ability states, and cooldowns.

**Validates: Requirements 12.1**

---

### Property 25: Corrupted Save Handled Gracefully

*For any* malformed or unreadable bytes passed to `HiveSaveRepository.loadGameState`, the method SHALL return `null` without throwing an uncaught exception. The corrupted save SHALL be deleted from storage and the calling layer SHALL receive a null result, enabling the UI to display the main menu.

**Validates: Requirements 12.3**

---

### Property 26: Shop Read-Only for Inactive Army

*For any* army that is not the currently active army, opening the Weapon Shop SHALL produce a `ShopState` with `isReadOnly == true`. No purchase action SHALL be executable from a read-only shop state.

**Validates: Requirements 7.5**
