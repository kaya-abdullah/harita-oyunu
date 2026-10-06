/// Victory screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Displayed when one army conquers Africa (or eliminates the opponent).  Shows the winning
/// army's name, the turn count, a celebration animation, and navigation
/// buttons for New Game or Main Menu.
///
/// Requirements: 9.2, 9.3, 11.1, 11.3
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/screens/game_screen.dart';
import 'package:harita/presentation/screens/main_menu_screen.dart';

/// Victory screen widget.
///
/// Reads [gameProvider] directly so it always reflects the final game state
/// that triggered the win.  Navigation is handled by [Navigator.pushReplacement]
/// — no complex router required.
class VictoryScreen extends ConsumerWidget {
  const VictoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return PopScope(
      // Android back goes to the main menu instead of closing the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToMainMenu(context, ref);
      },
      child: Scaffold(
        backgroundColor: AppTheme.kBackground,
        body: localeServiceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (localeService) {
            final t = localeService.of(locale);

            // Resolve winner details — fall back gracefully if called outside
            // a victory state (should not happen in normal flow).
            final winnerId = gameState.winnerId ?? ArmyId.army1;
            final playerWon = winnerId == ArmyId.army1;
            final winnerName = t.armyName(winnerId.index);
            final winnerColor = AppTheme.armyColor(winnerId);
            final turn = gameState.currentTurn.toString();

            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isTablet = constraints.maxWidth >= 600;
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 80.0 : 32.0,
                          vertical: 32.0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Celebration animation ───────────────────────
                            _CelebrationBurst(
                              color: winnerColor,
                              icon: playerWon
                                  ? Icons.emoji_events_rounded
                                  : Icons.flag_rounded,
                            ),
                            const SizedBox(height: 32),

                            // ── Victory title ───────────────────────────────
                            Text(
                              playerWon
                                  ? t.victoryTitle(army: winnerName)
                                  : t.defeatTitle,
                              textAlign: TextAlign.center,
                              style: AppTheme.displayStyle.copyWith(
                                color: winnerColor,
                                shadows: [
                                  Shadow(
                                    color: winnerColor.withAlpha(80),
                                    offset: const Offset(0, 4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Turn count ──────────────────────────────────
                            Text(
                              t.victoryTurns(turn: turn),
                              textAlign: TextAlign.center,
                              style: AppTheme.headingStyle.copyWith(
                                color: AppTheme.kTextDark,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Text(
                              playerWon
                                  ? t.victorySubtitle
                                  : t.defeatSubtitle(winnerName),
                              textAlign: TextAlign.center,
                              style: AppTheme.bodyStyle.copyWith(
                                color: AppTheme.kTextDark,
                              ),
                            ),
                            const SizedBox(height: 48),

                            // ── New Game button ─────────────────────────────
                            _VictoryButton(
                              icon: Icons.play_arrow_rounded,
                              label: t.btnNewGame,
                              color: AppTheme.army1Primary,
                              onPressed: () => _startNewGame(context, ref),
                            ),
                            const SizedBox(height: 16),

                            // ── Main Menu button ────────────────────────────
                            _VictoryButton(
                              icon: Icons.home_rounded,
                              label: t.btnMainMenu,
                              color: AppTheme.kAccentPurple,
                              onPressed: () => _goToMainMenu(context, ref),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Navigation helpers ──────────────────────────────────────────────────

  /// Resets every game-scoped provider so the next game starts fresh.
  void _resetGame(WidgetRef ref) {
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);
    ref.invalidate(gameProvider);
    ref.invalidate(selectedTerritoryProvider);
    ref.invalidate(armedAbilityProvider);
    ref.invalidate(gameFeedbackProvider);
  }

  void _startNewGame(BuildContext context, WidgetRef ref) {
    _resetGame(ref);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  void _goToMainMenu(BuildContext context, WidgetRef ref) {
    // Invalidate so a fresh game is ready if the player starts a new one.
    _resetGame(ref);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainMenuScreen()),
    );
  }
}

// ─── Private widgets ─────────────────────────────────────────────────────────

/// Animated celebration burst that pulses with the winner's colour.
///
/// Uses an [AnimatedContainer] + [FadeTransition] combo for a simple but
/// visually satisfying effect — appropriate for the 9–10 age group.
class _CelebrationBurst extends StatefulWidget {
  const _CelebrationBurst({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  State<_CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<_CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withAlpha(30),
                ),
              ),
              // Inner solid circle
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withAlpha(60),
                  border: Border.all(color: widget.color, width: 4),
                ),
              ),
              // Trophy / star icon
              Icon(widget.icon, size: 72, color: widget.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary action button with icon + text label for the victory screen.
class _VictoryButton extends StatelessWidget {
  const _VictoryButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppTheme.kTextLight,
        textStyle: AppTheme.labelStyle,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
        shadowColor: color.withAlpha(100),
      ),
    );
  }
}
