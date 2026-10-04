/// Weapon Shop dialog widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Presents a modal bottom sheet listing all eligible [WeaponItem]s with
/// their Elma cost and a purchase button.
///
/// Requirements: 4.4, 7.2, 7.3, 7.5, 11.1, 11.2, 11.3
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/weapon_item.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/viewmodels/shop_viewmodel.dart';

// ─── WeaponShopDialog ─────────────────────────────────────────────────────────

/// A [ConsumerWidget] that renders the Weapon Shop as a modal bottom sheet.
///
/// ### Usage
/// Show with:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => const WeaponShopDialog(),
/// );
/// ```
///
/// ### Behaviour
/// - **Normal mode** (active army): each item shows a "Buy" button.
/// - **Read-only mode** (inactive army, Req 7.5): buy buttons are hidden;
///   a banner informs the player this is view-only.
/// - **Insufficient Elma** (Req 4.4): an inline red error message is shown
///   below the item list after a failed purchase.
/// - **Empty shop**: a message is shown when no items are eligible.
class WeaponShopDialog extends ConsumerWidget {
  const WeaponShopDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopState = ref.watch(shopProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const _ShopLoadingSheet(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);

        return _ShopSheet(
          shopState: shopState,
          strings: strings,
          onPurchase: (item) =>
              ref.read(shopProvider.notifier).purchaseItem(item),
          onClose: () {
            ref.read(shopProvider.notifier).closeShop();
            Navigator.of(context, rootNavigator: true).pop();
          },
        );
      },
    );
  }
}

// ─── _ShopSheet ───────────────────────────────────────────────────────────────

/// The actual bottom sheet content, separated from data fetching.
class _ShopSheet extends StatelessWidget {
  const _ShopSheet({
    required this.shopState,
    required this.strings,
    required this.onPurchase,
    required this.onClose,
  });

  final ShopState shopState;
  final AppStrings strings;
  final void Function(WeaponItem item) onPurchase;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.90,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          // A single scrollable list (header + banners + items) so the sheet
          // never overflows on short landscape phone screens.
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // ── Drag handle ────────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBDBDBD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ─────────────────────────────────────────────────
              _ShopHeader(title: strings.shopTitle, onClose: onClose),

              // ── Read-only banner (Req 7.5) ──────────────────────────────
              if (shopState.isReadOnly)
                _ReadOnlyBanner(message: strings.shopReadOnly),

              // ── Error message (Req 4.4) ────────────────────────────────
              if (shopState.errorMessage != null)
                _ErrorBanner(message: strings.raw(shopState.errorMessage!)),

              // ── Item list ─────────────────────────────────────────────
              if (shopState.items.isEmpty)
                _EmptyShop(message: strings.shopEmpty)
              else
                for (var i = 0; i < shopState.items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ShopItemRow(
                      item: shopState.items[i],
                      strings: strings,
                      isReadOnly: shopState.isReadOnly,
                      onBuy: () => onPurchase(shopState.items[i]),
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

// ─── _ShopHeader ──────────────────────────────────────────────────────────────

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          // Icon alongside text label (Req 11.3)
          const Icon(
            Icons.storefront_outlined,
            color: AppTheme.army1Primary,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: AppTheme.headingStyle.copyWith(
                fontSize: 22,
                color: AppTheme.kTextDark,
              ),
            ),
          ),
          // Close button — icon label (Req 11.3)
          Tooltip(
            message: 'Close',
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              iconSize: 28,
              color: AppTheme.kTextDark,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _ReadOnlyBanner ──────────────────────────────────────────────────────────

/// Shown when the shop is opened by the inactive army (Req 7.5).
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.kWarning.withAlpha(48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.kWarning, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            color: AppTheme.kTextOnAmber,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.labelOnWarning.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _ErrorBanner ─────────────────────────────────────────────────────────────

/// Shown inline when a purchase was rejected due to insufficient Elma (Req 4.4).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.army2Light,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.army2Primary, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppTheme.army2Primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodyStyle.copyWith(
                fontSize: 16,
                color: AppTheme.army2Primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _ShopItemRow ─────────────────────────────────────────────────────────────

/// A single row in the shop item list.
///
/// Shows:
/// - 🛒 icon + localised weapon name (Req 11.3)
/// - 🍎 Elma cost with apple emoji for child-friendliness
/// - "Buy" button (hidden in read-only mode, Req 7.5)
class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.item,
    required this.strings,
    required this.isReadOnly,
    required this.onBuy,
  });

  final WeaponItem item;
  final AppStrings strings;
  final bool isReadOnly;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    // Resolve weapon name: prefer locale key lookup; fall back to the id.
    // The nameKey stores the locale key (e.g. 'ability_fire_bomb').
    // AppStrings doesn't have a dynamic lookup so we access it via the
    // known ability name keys where possible.
    final weaponName = _resolveWeaponName(item, strings);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Weapon icon + name (Req 11.3) ─────────────────────────────
          const Icon(
            Icons.military_tech_outlined,
            color: AppTheme.kAccentPurple,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weaponName,
                  style: AppTheme.bodyStyle.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.kTextDark,
                  ),
                ),
                Text(
                  strings.shopItemDesc,
                  style: AppTheme.bodyStyle.copyWith(
                    fontSize: 16,
                    color: AppTheme.kTextDark,
                  ),
                ),
                const SizedBox(height: 3),
                // Cost + Buy — wraps onto two lines on narrow phones.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      '🍎 ${strings.shopCostLabel} ${item.elmaCost}',
                      style: AppTheme.bodyStyle.copyWith(
                        fontSize: 16,
                        color: AppTheme.kAccentGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Buy button (hidden in read-only mode, Req 7.5)
                    if (!isReadOnly)
                      _BuyButton(label: strings.shopBuy, onPressed: onBuy),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves the localised weapon name from the item's [nameKey].
  ///
  /// Maps known ability name keys to the [AppStrings] getters; for unknown
  /// keys it falls back to [strings.shopCostLabel] prefix display.
  String _resolveWeaponName(WeaponItem item, AppStrings strings) =>
      strings.raw(item.nameKey);
}

// ─── _BuyButton ───────────────────────────────────────────────────────────────

/// A compact purchase button with icon + text (Req 11.3).
class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.shopping_cart_outlined, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.kAccentGreen,
        foregroundColor: AppTheme.kTextLight,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }
}

// ─── _EmptyShop ───────────────────────────────────────────────────────────────

/// Displayed when [ShopState.items] is empty.
class _EmptyShop extends StatelessWidget {
  const _EmptyShop({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Color(0xFF9E9E9E),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyStyle.copyWith(
                fontSize: 16,
                color: const Color(0xFF757575),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _ShopLoadingSheet ────────────────────────────────────────────────────────

/// Minimal placeholder while the locale service is initialising.
class _ShopLoadingSheet extends StatelessWidget {
  const _ShopLoadingSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: AppTheme.kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
