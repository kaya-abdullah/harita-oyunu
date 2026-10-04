/// AbilityPanel HUD widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Shows all 5 special abilities for the currently active army with their
/// current unlock / cooldown / charge status, and reveals a locale-appropriate
/// Snackbar tooltip when the user taps any ability button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/special_ability.dart';
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
    case AbilityType.directLaser:
      return strings.abilityDirectLaser;
  }
}

// ─── AbilityPanel ─────────────────────────────────────────────────────────────

/// Row of the five special abilities of the human army (Army 1).
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
      case AbilityType.directLaser:
        return strings.tooltipDirectLaser;
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

  static String emojiFor(AbilityType type) => _AbilityButton._emojis[type]!;

  static const Map<AbilityType, String> _emojis = {
    AbilityType.fireBomb: '🔥',
    AbilityType.bombardment: '💣',
    AbilityType.soldierSpell: '⚔️',
    AbilityType.megaBomba: '💥',
    AbilityType.directLaser: '🔫',
  };

  // ── Emoji icon per ability ──────────────────────────────────────────────

  String get _emoji => emojiFor(abilityType);

  // ── Turn threshold for locked abilities ─────────────────────────────────

  int? get _unlockTurn {
    switch (abilityType) {
      case AbilityType.fireBomb:
        return 0;
      case AbilityType.bombardment:
        return kTurnUnlockBombardment;
      case AbilityType.soldierSpell:
        return kTurnUnlockSoldierSpell;
      case AbilityType.megaBomba:
        return kTurnUnlockMegaBomba;
      case AbilityType.directLaser:
        return null; // charge-based, no fixed turn threshold
    }
  }

  // ── Computed state ───────────────────────────────────────────────────────

  bool get _isUnlocked => abilityState?.isUnlocked ?? false;
  bool get _isOnCooldown => abilityState?.isOnCooldown ?? false;
  int get _cooldownLeft => abilityState?.cooldownTurnsRemaining ?? 0;
  bool get _isChargebased => abilityType == AbilityType.directLaser;
  int get _chargeLevel => abilityState?.chargeLevel ?? 0;
  int get _maxCharge => abilityState?.maxCharge ?? 3;
  bool get _isFullyCharged => abilityState?.isFullyCharged ?? false;

  // ── Visual logic ─────────────────────────────────────────────────────────

  Color get _backgroundColor {
    if (!_isUnlocked) return AppTheme.kNeutralLight;
    if (_isOnCooldown) return AppTheme.kWarning.withAlpha(200);
    if (_isChargebased && !_isFullyCharged) {
      return AppTheme.kAccentPurple.withAlpha(60);
    }
    return AppTheme.kAccentGreen;
  }

  Color get _foregroundColor {
    if (!_isUnlocked) return AppTheme.kTextDark.withAlpha(120);
    if (_isOnCooldown) return AppTheme.kTextOnAmber;
    if (_isChargebased && !_isFullyCharged) return AppTheme.kAccentPurple;
    return AppTheme.kTextLight;
  }

  // ── Status badge text ────────────────────────────────────────────────────

  String? _badgeText(BuildContext context) {
    if (!_isUnlocked) {
      final unlock = _unlockTurn;
      if (unlock != null && unlock > 0) return '🔒 $unlock';
      if (abilityType == AbilityType.directLaser) return '🔒';
      return '🔒 0';
    }
    if (_isOnCooldown) return '⏱ $_cooldownLeft';
    if (_isChargebased) return '⚡$_chargeLevel/$_maxCharge';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badgeText(context);

    return Tooltip(
      // Flutter Tooltip as a second fallback; primary feedback is SnackBar.
      message: tooltip,
      preferBelow: false,
      child: InkWell(
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
                  : _isUnlocked && !_isOnCooldown
                  ? _foregroundColor.withAlpha(120)
                  : Colors.transparent,
              width: isArmed ? 4 : 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji icon
              Text(
                _emoji,
                style: const TextStyle(fontSize: 22),
                textAlign: TextAlign.center,
              ),

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

              // Status badge (lock / cooldown / charge)
              if (badge != null) ...[
                const SizedBox(height: 2),
                Text(
                  badge,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _isOnCooldown
                        ? AppTheme.kTextOnAmber
                        : _foregroundColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
