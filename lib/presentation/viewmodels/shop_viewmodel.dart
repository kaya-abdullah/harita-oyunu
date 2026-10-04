/// Weapon Shop state management (ViewModel layer) for Harita: Kendi İmparatorluğunu Kur.
///
/// Provides [ShopNotifier] and [shopProvider] which manage the shop dialog
/// lifecycle: opening, purchasing, and closing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/weapon_item.dart';
import 'package:harita/domain/services/economy_service.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

// ─── ShopState ────────────────────────────────────────────────────────────────

/// Immutable snapshot of the Weapon Shop's UI state.
///
/// - [items]        — eligible items for the current army and turn.
/// - [isOpen]       — whether the shop dialog is currently shown.
/// - [isReadOnly]   — `true` when opened by the inactive army (Req 7.5).
/// - [errorMessage] — non-null when the last purchase was rejected due to
///                    insufficient Elma (Req 4.4).
class ShopState {
  const ShopState({
    required this.items,
    required this.isOpen,
    required this.isReadOnly,
    this.errorMessage,
  });

  /// Creates the initial closed state with an empty item list.
  const ShopState.initial()
    : items = const [],
      isOpen = false,
      isReadOnly = false,
      errorMessage = null;

  /// All items the requesting army is eligible to see in the shop.
  final List<WeaponItem> items;

  /// Whether the shop dialog is currently open.
  final bool isOpen;

  /// `true` when the army that opened the shop is not the active army.
  ///
  /// In read-only mode the shop is visible but purchases are blocked (Req 7.5).
  final bool isReadOnly;

  /// Set to a locale-key string when the last purchase failed due to
  /// insufficient Elma; `null` when no error is active.
  final String? errorMessage;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  ShopState copyWith({
    List<WeaponItem>? items,
    bool? isOpen,
    bool? isReadOnly,
    Object? errorMessage = _sentinel,
  }) {
    return ShopState(
      items: items ?? this.items,
      isOpen: isOpen ?? this.isOpen,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ShopState) return false;
    return _listEquals(items, other.items) &&
        isOpen == other.isOpen &&
        isReadOnly == other.isReadOnly &&
        errorMessage == other.errorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(items), isOpen, isReadOnly, errorMessage);

  @override
  String toString() =>
      'ShopState(isOpen: $isOpen, isReadOnly: $isReadOnly, '
      'items: ${items.length}, error: $errorMessage)';
}

// ─── ShopNotifier ─────────────────────────────────────────────────────────────

/// Manages the Weapon Shop's lifecycle and purchase transactions.
///
/// ### Responsibilities
/// - Computes eligible items via [EconomyService.getEligibleShopItems].
/// - Enforces read-only mode when the requesting army is not the active one
///   (Requirement 7.5).
/// - Delegates purchase logic to [EconomyService.purchaseItem] and propagates
///   the resulting army update back to [gameProvider] (Requirements 7.2, 7.3).
/// - Surfaces [InsufficientElmaException] as an [ShopState.errorMessage] for
///   the UI to display (Requirement 4.4).
class ShopNotifier extends Notifier<ShopState> {
  // ─── Lazily resolved service references ──────────────────────────────────

  EconomyService get _economy => ref.read(economyServiceProvider);

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  ShopState build() => const ShopState.initial();

  // ─── openShop ────────────────────────────────────────────────────────────

  /// Opens the Weapon Shop for [requestingArmy].
  ///
  /// Processing:
  /// 1. Reads the current [GameState] from [gameProvider].
  /// 2. Fetches eligible items via [EconomyService.getEligibleShopItems]
  ///    using the requesting army's state and the current turn (Req 7.4).
  /// 3. Sets [ShopState.isReadOnly] to `true` if [requestingArmy] is not the
  ///    currently active army (Req 7.5).
  void openShop(ArmyId requestingArmy) {
    final gameState = ref.read(gameProvider);

    // Resolve the army object for the requesting side.
    final army = requestingArmy == ArmyId.army1
        ? gameState.army1
        : gameState.army2;

    final eligibleItems = _economy.getEligibleShopItems(
      army,
      gameState.currentTurn,
    );

    // Purchases are only allowed for the human army during its own turn
    // (Requirement 7.5); the AI's turn shows a read-only shop.
    final isReadOnly =
        requestingArmy != gameState.activeArmyId ||
        !ref.read(gameProvider.notifier).isHumanTurn;

    state = ShopState(
      items: eligibleItems,
      isOpen: true,
      isReadOnly: isReadOnly,
      // Clear any previous error when re-opening.
      errorMessage: null,
    );
  }

  // ─── purchaseItem ─────────────────────────────────────────────────────────

  /// Attempts to purchase [item] for the active army.
  ///
  /// Guards:
  /// - Does nothing if the shop is in read-only mode (Req 7.5).
  ///
  /// On success:
  /// - Deducts Elma and adds the item to the army's inventory via
  ///   [EconomyService.purchaseItem].
  /// - Writes the updated army back to [gameProvider] so all game-state
  ///   consumers reflect the change (Req 7.3).
  /// - Refreshes the eligible items list (the purchase may have affected
  ///   ability states or balance).
  /// - Clears any active error message.
  ///
  /// On failure ([InsufficientElmaException]):
  /// - Sets [ShopState.errorMessage] to `'error_insufficient_elma'` (Req 4.4).
  /// - Leaves the game state unchanged.
  void purchaseItem(WeaponItem item) {
    // Read-only shops do not allow purchases.
    if (state.isReadOnly) return;

    final notifier = ref.read(gameProvider.notifier);
    if (!notifier.isHumanTurn) {
      state = state.copyWith(isReadOnly: true);
      return;
    }

    final army = ref.read(gameProvider).activeArmy;
    if (army.elmaBalance < item.elmaCost) {
      // Surface a locale-key so the UI can display the correct message.
      state = state.copyWith(errorMessage: 'error_insufficient_elma');
      return;
    }

    if (!notifier.purchaseItem(item)) {
      state = state.copyWith(errorMessage: 'error_insufficient_elma');
      return;
    }

    // Refresh the eligible items list with the updated army state.
    final gameState = ref.read(gameProvider);
    final refreshedItems = _economy.getEligibleShopItems(
      gameState.activeArmy,
      gameState.currentTurn,
    );

    state = state.copyWith(
      items: refreshedItems,
      errorMessage: null, // clear any prior error
    );
  }

  // ─── closeShop ────────────────────────────────────────────────────────────

  /// Closes the shop and resets all state to the initial empty snapshot.
  void closeShop() {
    state = const ShopState.initial();
  }
}

// ─── shopProvider ─────────────────────────────────────────────────────────────

/// Root [NotifierProvider] for the Weapon Shop state.
///
/// Consumers watch this provider to react to shop open/close events,
/// item list changes, read-only mode transitions, and purchase errors.
final shopProvider = NotifierProvider<ShopNotifier, ShopState>(
  ShopNotifier.new,
);

// ─── Internal helpers ────────────────────────────────────────────────────────

const Object _sentinel = Object();

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
