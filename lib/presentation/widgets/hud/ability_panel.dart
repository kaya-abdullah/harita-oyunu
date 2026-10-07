/// The player's hand of cards ("Kartların") for Harita.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/widgets/common/game_names.dart';

export 'package:harita/presentation/widgets/common/game_names.dart'
    show abilityDisplayName, abilityIcon;

// ─── AbilityPanel ─────────────────────────────────────────────────────────────

/// A scrollable row with every card and how many of it the player holds.
/// Tap a card, then a city, to play it.
class AbilityPanel extends ConsumerWidget {
  const AbilityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final army = ref.watch(viewerArmyProvider);
    final armed = ref.watch(armedAbilityProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        return Container(
          color: AppTheme.kBackground,
          height: 74,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            children: [
              for (final type in AbilityType.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _CardButton(
                    type: type,
                    count: army.cardCount(type),
                    name: abilityDisplayName(type, strings),
                    tooltip: abilityTooltip(type, strings),
                    isArmed: armed == type,
                    onTap: () {
                      ref
                          .read(audioServiceProvider)
                          .playSfx(AudioService.sfxButtonTap);
                      ref.read(gameProvider.notifier).armAbility(type);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A card name on one or two lines, shrunk to fit instead of breaking a
/// long word ("Bombardıman").
class _CardName extends StatelessWidget {
  const _CardName({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: color,
    );
    final words = name.split(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line
            in words.length > 1
                ? [words.first, words.skip(1).join(' ')]
                : [name])
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(line, style: style, maxLines: 1),
          ),
      ],
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
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        key: Key('ability_${type.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 92,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isArmed ? AppTheme.kWarning : Colors.transparent,
              width: isArmed ? 4 : 1,
            ),
            boxShadow: has
                ? [
                    BoxShadow(
                      color: color.withAlpha(90),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(abilityIcon(type), size: 22, color: fg),
                    _CardName(name: name, color: fg),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  key: Key('card_count_${type.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
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
