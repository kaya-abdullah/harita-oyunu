/// The Weapon Shop ("Silah Dükkanı") panel for Harita.
///
/// It is always open at the side of the map ("yan tarafta tam silah
/// dükkanı") and lists everything for sale from the first turn: every card,
/// tanks and bombers. Tap an item to buy it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/weapon_item.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/game_names.dart';

// ─── WeaponShopPanel ──────────────────────────────────────────────────────────

/// The shop column. [compact] is the narrow version next to the map on a
/// phone held upright.
class WeaponShopPanel extends ConsumerWidget {
  const WeaponShopPanel({super.key, this.compact = false});

  /// Narrow layout: icon, name and price stacked.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameProvider);
    final army = ref.watch(viewerArmyProvider);
    final canBuy = state.activeArmy.isHuman && state.activeArmyId == army.id;
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        final items = ref.read(economyServiceProvider).getShopItems();
        return Container(
          key: const Key('weapon_shop'),
          decoration: const BoxDecoration(
            color: Color(0xFF263238),
            border: Border(left: BorderSide(color: Color(0xFF37474F))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      color: AppTheme.kWarning,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        strings.shopTitle,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.kTextLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _ShopItemTile(
                          item: item,
                          strings: strings,
                          compact: compact,
                          affordable:
                              canBuy && army.diamondBalance >= item.diamondCost,
                          armyColor: AppTheme.armyColor(army.id),
                          onBuy: () {
                            ref
                                .read(audioServiceProvider)
                                .playSfx(AudioService.sfxButtonTap);
                            ref.read(gameProvider.notifier).purchaseItem(item);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [name] on at most two lines, split between words only.
List<String> _lines(String name) {
  final words = name.split(' ');
  return words.length > 1 ? [words.first, words.skip(1).join(' ')] : [name];
}

// ─── _ShopItemTile ───────────────────────────────────────────────────────────

class _ShopItemTile extends StatelessWidget {
  const _ShopItemTile({
    required this.item,
    required this.strings,
    required this.compact,
    required this.affordable,
    required this.armyColor,
    required this.onBuy,
  });

  final WeaponItem item;
  final AppStrings strings;
  final bool compact;
  final bool affordable;
  final Color armyColor;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final color = card != null
        ? AppTheme.abilityColor(card)
        : const Color(0xFF546E7A);
    final name = card != null
        ? abilityDisplayName(card, strings)
        : strings.raw(item.nameKey);
    final description = card != null
        ? abilityTooltip(card, strings)
        : item.tanks > 0
        ? strings.shopTankDesc
        : strings.shopBomberDesc;
    final Widget icon = card != null
        ? Icon(abilityIcon(card), color: AppTheme.kTextLight, size: 22)
        : UnitGlyph(
            kind: item.tanks > 0 ? UnitGlyphKind.tank : UnitGlyphKind.bomber,
            color: armyColor,
            size: 28,
          );
    final price = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.diamond_rounded, size: 13, color: AppTheme.kDiamond),
        const SizedBox(width: 2),
        Text(
          '${item.diamondCost}',
          style: const TextStyle(
            color: AppTheme.kTextLight,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );

    return Tooltip(
      message: description,
      child: Opacity(
        opacity: affordable ? 1 : 0.55,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: Key('shop_${item.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: onBuy,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: compact
                  ? Column(
                      children: [
                        icon,
                        for (final line in _lines(name))
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              line,
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppTheme.kTextLight,
                                fontSize: 12,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        price,
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(width: 30, child: Center(child: icon)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: AppTheme.kTextLight,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xE6FFFFFF),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        price,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
