/// The player's cards ("Kartların") for Harita: Kendi İmparatorluğunu Kur.
///
/// A panel that folds open and shut: its header shows how many cards the
/// player holds, the free "Kart Çek" button and the open / close arrow; the
/// body lists every card with how many of it are in hand. Tap a card, then a
/// city on the map, to play it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

/// Localised name of a card.
String abilityDisplayName(AbilityType type, AppStrings strings) =>
    switch (type) {
      AbilityType.fireBomb => strings.abilityFireBomb,
      AbilityType.bombardment => strings.abilityBombardment,
      AbilityType.soldierSpell => strings.abilitySoldierSpell,
      AbilityType.megaBomba => strings.abilityMegaBomba,
      AbilityType.atomBomb => strings.abilityAtomBomb,
      AbilityType.nuclearBomb => strings.abilityNuclearBomb,
      AbilityType.tribute => strings.abilityTribute,
    };

/// What a card does, in one sentence.
String abilityTooltip(AbilityType type, AppStrings strings) => switch (type) {
  AbilityType.fireBomb => strings.tooltipFireBomb,
  AbilityType.bombardment => strings.tooltipBombardment,
  AbilityType.soldierSpell => strings.tooltipSoldierSpell,
  AbilityType.megaBomba => strings.tooltipMegaBomba,
  AbilityType.atomBomb => strings.tooltipAtomBomb,
  AbilityType.nuclearBomb => strings.tooltipNuclearBomb,
  AbilityType.tribute => strings.tooltipTribute,
};

/// Icon of a card.
IconData abilityIcon(AbilityType type) => switch (type) {
  AbilityType.fireBomb => Icons.local_fire_department_rounded,
  AbilityType.bombardment => Icons.flare_rounded,
  AbilityType.soldierSpell => Icons.groups_rounded,
  AbilityType.megaBomba => Icons.brightness_7_rounded,
  AbilityType.atomBomb => Icons.blur_on_rounded,
  AbilityType.nuclearBomb => Icons.dangerous_rounded,
  AbilityType.tribute => Icons.payments_rounded,
};

// ─── Open / closed state ─────────────────────────────────────────────────────

/// Whether the card panel is open (it starts open).
class CardPanelOpenNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Opens a closed panel and closes an open one.
  void toggle() => state = !state;
}

/// Provides whether the card panel is open.
final cardPanelOpenProvider = NotifierProvider<CardPanelOpenNotifier, bool>(
  CardPanelOpenNotifier.new,
);

// ─── AbilityPanel ─────────────────────────────────────────────────────────────

/// The folding card panel.
class AbilityPanel extends ConsumerWidget {
  const AbilityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final army = gameState.army1;
    final armed = ref.watch(armedAbilityProvider);
    final open = ref.watch(cardPanelOpenProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        final canDraw =
            gameState.activeArmyId == army.id &&
            gameState.phase == GamePhase.playing &&
            !army.hasDrawnCard;
        void tap() =>
            ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);

        return Container(
          color: AppTheme.kBackground,
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header: title, Kart Çek, open / close ─────────────────
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('cards_toggle'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        tap();
                        ref.read(cardPanelOpenProvider.notifier).toggle();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              open
                                  ? Icons.expand_more_rounded
                                  : Icons.expand_less_rounded,
                              color: AppTheme.kTextDark,
                              semanticLabel: open
                                  ? strings.cardsHide
                                  : strings.cardsShow,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.style_rounded,
                              size: 20,
                              color: AppTheme.kAccentPurple,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${strings.cardsTitle} (${army.cardTotal})',
                                key: const Key('cards_title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.kTextDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const Key('btn_draw_card'),
                    onPressed: canDraw
                        ? () {
                            tap();
                            ref.read(gameProvider.notifier).drawCard();
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.kAccentPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                    ),
                    icon: const Icon(Icons.add_card_rounded, size: 18),
                    label: Text(
                      strings.btnDrawCard,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Body: every card with its count ───────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: open
                    ? SizedBox(
                        height: 70,
                        child: ListView(
                          key: const Key('cards_list'),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 4),
                          children: [
                            for (final type in AbilityType.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _CardButton(
                                  type: type,
                                  count: army.cardCount(type),
                                  name: abilityDisplayName(type, strings),
                                  tooltip: abilityTooltip(type, strings),
                                  isArmed: armed == type,
                                  onTap: () {
                                    tap();
                                    ref
                                        .read(gameProvider.notifier)
                                        .armAbility(type);
                                  },
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── _CardButton ─────────────────────────────────────────────────────────────

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.type,
    required this.count,
    required this.name,
    required this.tooltip,
    required this.isArmed,
    required this.onTap,
  });

  final AbilityType type;
  final int count;
  final String name;
  final String tooltip;
  final bool isArmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.abilityColor(type);
    final has = count > 0;
    final bg = has ? color : AppTheme.kNeutralLight;
    final fg = has ? AppTheme.kTextLight : AppTheme.kTextDark.withAlpha(110);
    final words = name.split(' ');
    final lines = words.length > 1
        ? [words.first, words.skip(1).join(' ')]
        : [name];
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        key: Key('ability_${type.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 88,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isArmed ? AppTheme.kWarning : Colors.transparent,
              width: isArmed ? 4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(abilityIcon(type), size: 20, color: fg),
                    // Shrink a long word ("Bombardıman") instead of
                    // breaking it.
                    for (final line in lines)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          line,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  key: Key('card_count_${type.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: has ? AppTheme.kSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: has ? color : fg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
