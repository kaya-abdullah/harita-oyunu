/// AbilityPanel HUD widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Shows the ability cards of the human army with their current unlock /
/// cooldown status. Each card has its own colour (the Fire Bomb card is
/// green); tapping a card arms it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

/// Localised display name for [type].
String abilityDisplayName(AbilityType type, AppStrings strings) {
  switch (type) {
    case AbilityType.fireBomb:
      return strings.abilityFireBomb;
    case AbilityType.bombardment:
      return strings.abilityBombardment;
    case AbilityType.soldierSpell:
      return strings.abilitySoldierSpell;
    case AbilityType.megaBomba:
      return strings.abilityMegaBomba;
  }
}

/// Icon shown on the card of [type].
IconData abilityIcon(AbilityType type) => switch (type) {
  AbilityType.fireBomb => Icons.local_fire_department_rounded,
  AbilityType.bombardment => Icons.flare_rounded,
  AbilityType.soldierSpell => Icons.groups_rounded,
  AbilityType.megaBomba => Icons.brightness_7_rounded,
};

// ─── AbilityPanel ─────────────────────────────────────────────────────────────

/// Row of the ability cards of the human army (Army 1).
///
/// Tapping a ready ability arms it (see [abilityTargetingProvider]); the next
/// territory tapped on the map becomes its target. Tapping a locked / cooling
/// down ability explains why it cannot be used (Requirements 6.7, 6.8, 11.4).
class AbilityPanel extends ConsumerWidget {
  const AbilityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final humanArmy = gameState.army1;
    final armed = ref.watch(armedAbilityProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        final currentTurn = gameState.currentTurn;

        return Container(
          color: AppTheme.kBackground,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: AbilityType.values.map((type) {
              final abilityState = humanArmy.abilities[type];
              final name = abilityDisplayName(type, strings);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _AbilityButton(
                    abilityType: type,
                    abilityState: abilityState,
                    currentTurn: currentTurn,
                    tooltip: _tooltipFor(type, strings),
                    name: name,
                    isArmed: armed == type,
                    onTap: () => _onAbilityTap(ref, type),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Arms / disarms [type]. The [GameNotifier] emits a [GameFeedback] that
  /// the game screen turns into a localized message (locked turn, cooldown,
  /// "tap a territory", …) — Requirements 6.7, 6.8, 11.4.
  void _onAbilityTap(WidgetRef ref, AbilityType type) {
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);
    ref.read(gameProvider.notifier).armAbility(type);
  }

  String _tooltipFor(AbilityType type, AppStrings strings) {
    switch (type) {
      case AbilityType.fireBomb:
        return strings.tooltipFireBomb;
      case AbilityType.bombardment:
        return strings.tooltipBombardment;
      case AbilityType.soldierSpell:
        return strings.tooltipSoldierSpell;
      case AbilityType.megaBomba:
        return strings.tooltipMegaBomba;
    }
  }
}

// ─── _AbilityButton ──────────────────────────────────────────────────────────

/// A single ability button tile inside [AbilityPanel].
class _AbilityButton extends StatelessWidget {
  const _AbilityButton({
    required this.abilityType,
    required this.abilityState,
    required this.currentTurn,
    required this.tooltip,
    required this.name,
    required this.isArmed,
    required this.onTap,
  });

  final AbilityType abilityType;
  final AbilityState? abilityState;
  final int currentTurn;
  final String tooltip;
  final String name;
  final bool isArmed;
  final VoidCallback onTap;

  // ── Computed state ───────────────────────────────────────────────────────

  int get _unlockTurn => kAbilityUnlockTurns[abilityType] ?? 0;
  bool get _isUnlocked => abilityState?.isUnlocked ?? false;
  bool get _isOnCooldown => abilityState?.isOnCooldown ?? false;
  int get _cooldownLeft => abilityState?.cooldownTurnsRemaining ?? 0;
  bool get _isReady => _isUnlocked && !_isOnCooldown;

  // ── Visual logic ─────────────────────────────────────────────────────────

  Color get _cardColor => AppTheme.abilityColor(abilityType);

  Color get _backgroundColor {
    if (!_isUnlocked) return AppTheme.kNeutralLight;
    if (_isOnCooldown) return Color.lerp(_cardColor, Colors.white, 0.65)!;
    return _cardColor;
  }

  Color get _foregroundColor {
    if (!_isUnlocked) return AppTheme.kTextDark.withAlpha(120);
    if (_isOnCooldown) return AppTheme.kTextDark;
    return AppTheme.kTextLight;
  }

  // ── Status badge ─────────────────────────────────────────────────────────

  (IconData, String)? get _badge {
    if (!_isUnlocked) return (Icons.lock_rounded, '$_unlockTurn');
    if (_isOnCooldown) return (Icons.timer_rounded, '$_cooldownLeft');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;

    return Tooltip(
      // Flutter Tooltip as a second fallback; primary feedback is SnackBar.
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        key: Key('ability_${abilityType.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isArmed
                  ? AppTheme.kWarning
                  : _isReady
                  ? _cardColor.withAlpha(160)
                  : Colors.transparent,
              width: isArmed ? 4 : 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(abilityIcon(abilityType), size: 24, color: _foregroundColor),
              const SizedBox(height: 2),

              // Short ability name — min 16 sp
              Text(
                _shortName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _foregroundColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Status badge (lock / cooldown)
              if (badge != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.$1, size: 15, color: _foregroundColor),
                    const SizedBox(width: 2),
                    Text(
                      badge.$2,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _foregroundColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Abbreviated name for compact button ─────────────────────────────────

  String get _shortName {
    // Use first word of the ability name so it fits in the compact button.
    return name.split(' ').first;
  }
}
