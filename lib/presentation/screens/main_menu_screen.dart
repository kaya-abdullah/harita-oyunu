/// Main menu screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Displays the app title, New Game (→ bot difficulty picker), Resume (if save exists), Language toggle
/// (TR / EN), and Tutorial buttons.
///
/// Requirements: 2.1, 2.2, 2.3, 9.2, 12.2, 11.1, 11.3
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/viewmodels/tutorial_viewmodel.dart';
import 'package:harita/presentation/screens/game_screen.dart';
import 'package:harita/presentation/screens/tutorial_screen.dart';
import 'package:harita/presentation/widgets/common/difficulty_picker.dart';

/// Provider that exposes whether a saved game currently exists.
///
/// Re-evaluated whenever the provider is refreshed (e.g. after starting a
/// new game or resuming).
final _hasSaveProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.read(saveRepositoryProvider).hasSave();
  } catch (_) {
    return false;
  }
});

/// Main menu screen shown on launch and when the player returns from the game.
class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);
    final hasSaveAsync = ref.watch(_hasSaveProvider);

    return Scaffold(
      backgroundColor: AppTheme.kBackground,
      body: localeServiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (localeService) {
          final t = localeService.of(locale);
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
                          // ── App title ───────────────────────────────────
                          _AppTitle(title: t.appName),
                          const SizedBox(height: 48),

                          // ── Language toggle ─────────────────────────────
                          _LanguageToggle(
                            currentLocale: locale,
                            onLocaleSelected: (l) {
                              ref
                                  .read(audioServiceProvider)
                                  .playSfx(AudioService.sfxButtonTap);
                              ref.read(localeProvider.notifier).setLocale(l);
                            },
                          ),
                          const SizedBox(height: 40),

                          // ── New Game button ─────────────────────────────
                          _MenuButton(
                            icon: Icons.play_arrow_rounded,
                            label: t.btnNewGame,
                            color: AppTheme.army1Primary,
                            onPressed: () => _startNewGame(context, ref),
                          ),
                          const SizedBox(height: 16),

                          // ── Resume button (conditional) ─────────────────
                          hasSaveAsync.when(
                            loading: () => const SizedBox(height: 16),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (hasSave) => hasSave
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _MenuButton(
                                        icon: Icons.restore_rounded,
                                        label: t.btnResume,
                                        color: AppTheme.kAccentGreen,
                                        onPressed: () =>
                                            _resumeGame(context, ref),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),

                          // ── Tutorial button ─────────────────────────────
                          _MenuButton(
                            icon: Icons.school_rounded,
                            label: t.btnTutorial,
                            color: AppTheme.kAccentPurple,
                            onPressed: () => _openTutorial(context, ref),
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
    );
  }

  // ─── Navigation helpers ──────────────────────────────────────────────────

  Future<void> _startNewGame(BuildContext context, WidgetRef ref) async {
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);

    // First game ever: show the interactive tutorial first (Requirement 11.5).
    final tutorial = ref.read(tutorialProvider.notifier);
    await tutorial.init();
    if (!context.mounted) return;
    if (!ref.read(tutorialProvider).isComplete) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const TutorialScreen()));
      if (!context.mounted) return;
    }

    // Let the player choose how strong the bot is.
    final strings = ref
        .read(localeServiceProvider)
        .value
        ?.of(ref.read(localeProvider));
    if (strings == null) return;
    final difficulty = await showDifficultyPicker(context, strings);
    if (difficulty == null || !context.mounted) return;
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);
    ref.read(newGameDifficultyProvider.notifier).set(difficulty);

    // Reset to a fresh game state by rebuilding the notifiers.
    ref.invalidate(gameProvider);
    ref.invalidate(selectedTerritoryProvider);
    ref.invalidate(armedAbilityProvider);
    ref.invalidate(gameFeedbackProvider);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  Future<void> _resumeGame(BuildContext context, WidgetRef ref) async {
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);
    final loaded = await ref.read(gameProvider.notifier).loadGame();
    if (!context.mounted) return;
    if (!loaded) {
      // Corrupted / missing save: stay on the menu (Requirement 12.3).
      ref.invalidate(_hasSaveProvider);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  void _openTutorial(BuildContext context, WidgetRef ref) {
    ref.read(audioServiceProvider).playSfx(AudioService.sfxButtonTap);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TutorialScreen()));
  }
}

// ─── Private widgets ─────────────────────────────────────────────────────────

/// Animated app title with a drop shadow and a playful scale effect.
class _AppTitle extends StatefulWidget {
  const _AppTitle({required this.title});

  final String title;

  @override
  State<_AppTitle> createState() => _AppTitleState();
}

class _AppTitleState extends State<_AppTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Text(
        widget.title,
        textAlign: TextAlign.center,
        style: AppTheme.displayStyle.copyWith(
          color: AppTheme.army1Primary,
          shadows: [
            Shadow(
              color: AppTheme.army1Primary.withAlpha(80),
              offset: const Offset(0, 4),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

/// TR / EN language toggle — currently selected locale is highlighted.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.currentLocale,
    required this.onLocaleSelected,
  });

  final Locale currentLocale;
  final void Function(Locale) onLocaleSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LocaleChip(
          label: 'TR',
          icon: Icons.language,
          selected: currentLocale == kLocaleTurkish,
          onTap: () => onLocaleSelected(kLocaleTurkish),
        ),
        const SizedBox(width: 12),
        _LocaleChip(
          label: 'EN',
          icon: Icons.language,
          selected: currentLocale == kLocaleEnglish,
          onTap: () => onLocaleSelected(kLocaleEnglish),
        ),
      ],
    );
  }
}

/// Individual locale chip in the language toggle.
class _LocaleChip extends StatelessWidget {
  const _LocaleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = selected ? AppTheme.army1Primary : AppTheme.kNeutralLight;
    final fgColor = selected ? AppTheme.kTextLight : AppTheme.kTextDark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.army1Primary.withAlpha(80),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.labelStyle.copyWith(color: fgColor, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary menu button with icon + text label (Requirement 11.3).
class _MenuButton extends StatelessWidget {
  const _MenuButton({
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
