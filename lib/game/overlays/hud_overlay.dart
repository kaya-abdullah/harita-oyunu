/// HUD overlay widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Displayed on top of the Flame game canvas as a semi-transparent bar at the
/// top of the screen.  Shows real-time game info sourced from Riverpod state:
///   • Current turn number  (Requirement 8.3)
///   • Active army indicator with army colour  (Requirement 8.4)
///   • Army 1 Elma balance with apple emoji  (Requirement 4.3)
///   • Army 2 Elma balance with apple emoji  (Requirement 4.3)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/localization/locale_service.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

// ─── HudOverlay ──────────────────────────────────────────────────────────────

/// A semi-transparent HUD bar pinned to the top of the game screen.
///
/// Rebuilds automatically whenever the [GameState], active [Locale], or
/// [LocaleService] changes.  Uses [localeServiceProvider]'s [AsyncValue]
/// gracefully — while the asset bundle loads, English hard-coded fallbacks
/// keep the HUD readable.
class HudOverlay extends ConsumerWidget {
  const HudOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    // Obtain strings via the async service, falling back to bare English
    // literals while the bundle loads or if an error occurs.
    final strings = localeServiceAsync.when(
      data: (service) => service.of(locale),
      loading: () => null,
      error: (_, __) => null,
    );

    return _HudBar(gameState: gameState, locale: locale, strings: strings);
  }
}

// ─── _HudBar ─────────────────────────────────────────────────────────────────

/// Internal stateless widget that renders the HUD content.
///
/// Separating this from [HudOverlay] keeps the build method clean and makes
/// the layout trivially testable without Riverpod infrastructure.
class _HudBar extends StatelessWidget {
  const _HudBar({
    required this.gameState,
    required this.locale,
    required this.strings,
  });

  final GameState gameState;
  final Locale locale;
  final AppStrings? strings; // null while locale bundles are still loading

  // ─── Label helpers ────────────────────────────────────────────────────────

  /// Returns the localized "Turn: X" label, falling back to English.
  String _turnLabel(int turn) {
    if (strings != null) {
      return '${strings!.turnLabel} $turn';
    }
    return 'Turn: $turn';
  }

  /// Returns the localized active-army name, falling back to English.
  String _activeArmyLabel(ArmyId armyId) {
    if (strings != null) {
      return armyId == ArmyId.army1 ? strings!.army1Name : strings!.army2Name;
    }
    return armyId == ArmyId.army1 ? 'Army 1' : 'Army 2';
  }

  /// Returns the color associated with [armyId].
  Color _armyColor(ArmyId armyId) {
    return armyId == ArmyId.army1
        ? AppTheme.army1Primary
        : AppTheme.army2Primary;
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isVictory = gameState.phase == GamePhase.victory;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          // Semi-transparent dark bar — provides sufficient contrast for
          // white/light text (>4.5:1) per Requirement 11.2.
          color: const Color(0xCC1A1A2E), // deep navy, ~80 % opacity
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: isVictory
              ? _VictoryBadge(winnerId: gameState.winnerId, strings: strings)
              : _PlayingHud(
                  gameState: gameState,
                  turnLabel: _turnLabel(gameState.currentTurn),
                  activeArmyLabel: _activeArmyLabel(gameState.activeArmyId),
                  activeArmyColor: _armyColor(gameState.activeArmyId),
                  strings: strings,
                ),
        ),
      ),
    );
  }
}

// ─── _PlayingHud ─────────────────────────────────────────────────────────────

/// HUD content shown while the game is in [GamePhase.playing].
///
/// Layout (phone, row):
/// ┌─────────────────────────────────────────────────────┐
/// │  Tur: 3  │  [●] 1. Ordu  │  🍎 50  │  🍎 50        │
/// └─────────────────────────────────────────────────────┘
class _PlayingHud extends StatelessWidget {
  const _PlayingHud({
    required this.gameState,
    required this.turnLabel,
    required this.activeArmyLabel,
    required this.activeArmyColor,
    required this.strings,
  });

  final GameState gameState;
  final String turnLabel;
  final String activeArmyLabel;
  final Color activeArmyColor;
  final AppStrings? strings;

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder-style sizing via MediaQuery so items wrap gracefully
    // on narrow phones without overflowing.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Turn counter ─────────────────────────────────────────────────
          _HudChip(
            child: Text(
              turnLabel,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Active army indicator ────────────────────────────────────────
          _HudChip(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Colour dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: activeArmyColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  activeArmyLabel,
                  style: TextStyle(
                    color: activeArmyColor == AppTheme.army1Primary
                        ? AppTheme.army1Light
                        : AppTheme.army2Light,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── Army 1 Elma balance ──────────────────────────────────────────
          _ElmaChip(
            armyColor: AppTheme.army1Light,
            elmaBalance: gameState.army1.elmaBalance,
          ),

          const SizedBox(width: 4),

          // ── Army 2 Elma balance ──────────────────────────────────────────
          _ElmaChip(
            armyColor: AppTheme.army2Light,
            elmaBalance: gameState.army2.elmaBalance,
          ),
        ],
      ),
    );
  }
}

// ─── _VictoryBadge ────────────────────────────────────────────────────────────

/// Compact badge shown in the HUD bar when a winner has been declared.
class _VictoryBadge extends StatelessWidget {
  const _VictoryBadge({required this.winnerId, required this.strings});

  final ArmyId? winnerId;
  final AppStrings? strings;

  @override
  Widget build(BuildContext context) {
    final winnerName = winnerId == null
        ? 'Winner'
        : winnerId == ArmyId.army1
        ? (strings?.army1Name ?? 'Army 1')
        : (strings?.army2Name ?? 'Army 2');

    final victoryText =
        strings?.victoryTitle(army: winnerName) ?? '$winnerName Wins!';

    return Center(
      child: Text(
        victoryText,
        style: const TextStyle(
          color: Color(0xFFFFD600), // vivid yellow — high contrast on dark bg
          fontSize: 20.0,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── _HudChip ─────────────────────────────────────────────────────────────────

/// Lightly rounded pill container used to group related HUD information.
class _HudChip extends StatelessWidget {
  const _HudChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF), // white, 20 % opacity
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

// ─── _ElmaChip ───────────────────────────────────────────────────────────────

/// Displays one army's Elma balance as "🍎 {balance}".
///
/// Text colour is derived from the army's light tint colour so the chip is
/// visually associated with the correct army.  The dark HUD background
/// guarantees contrast >= 4.5:1 for the army tint colours.
class _ElmaChip extends StatelessWidget {
  const _ElmaChip({required this.armyColor, required this.elmaBalance});

  final Color armyColor;
  final int elmaBalance;

  @override
  Widget build(BuildContext context) {
    return _HudChip(
      child: Text(
        '🍎 $elmaBalance',
        style: TextStyle(
          color: armyColor,
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
