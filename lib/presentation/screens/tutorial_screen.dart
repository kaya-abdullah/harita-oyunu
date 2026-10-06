/// Tutorial screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Guides new players through 7 onboarding steps. Each step displays:
///  - A large icon representing the topic
///  - A localized step description (≥ 16 sp)
///  - A step counter (e.g. "3 / 7")
///  - "Next" / "Skip" buttons, replaced by a "Let's Go!" finish button on the last step
///
/// Requirements: 11.5
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/localization/locale_service.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/viewmodels/tutorial_viewmodel.dart';

/// Interactive tutorial screen that walks the player through core game
/// mechanics before their first match.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  @override
  void initState() {
    super.initState();
    // Always start from step 1 when the screen is opened — the tutorial must
    // be replayable from the main menu even after it was completed once
    // (calling `init()` here would mark it complete and pop immediately).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(tutorialProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorialState = ref.watch(tutorialProvider);

    // Navigate away once the tutorial is marked complete.
    ref.listen<TutorialState>(tutorialProvider, (previous, next) {
      if (next.isComplete && mounted) {
        Navigator.of(context).pop();
      }
    });

    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.kBackground,
      body: localeServiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (localeService) => SafeArea(
          child: _TutorialBody(
            tutorialState: tutorialState,
            localeService: localeService,
            locale: locale,
            onNext: () => ref.read(tutorialProvider.notifier).nextStep(),
            onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          ),
        ),
      ),
    );
  }
}

// ─── _TutorialBody ────────────────────────────────────────────────────────────

class _TutorialBody extends StatelessWidget {
  const _TutorialBody({
    required this.tutorialState,
    required this.localeService,
    required this.locale,
    required this.onNext,
    required this.onSkip,
  });

  final TutorialState tutorialState;
  final LocaleService localeService;
  final dynamic locale; // Locale
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = localeService.of(locale);
    final step = tutorialState.currentStep;
    final stepDescription = localeService.translate(step.localeKey, locale);

    // Resolve button label strings
    final nextLabel = t.btnNext;
    final skipLabel = t.tutorialSkip;
    final finishLabel = t.tutorialFinish;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 600;
        final horizontalPadding = isTablet ? 80.0 : 24.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Step counter ──────────────────────────────────────────
              _StepCounter(
                current: tutorialState.currentStepIndex + 1,
                total: tutorialState.totalSteps,
              ),
              const SizedBox(height: 16),

              // ── Progress bar ──────────────────────────────────────────
              _ProgressBar(
                current: tutorialState.currentStepIndex + 1,
                total: tutorialState.totalSteps,
              ),
              const SizedBox(height: 12),

              // ── Card ──────────────────────────────────────────────────
              Expanded(
                child: _StepCard(icon: step.icon, description: stepDescription),
              ),
              const SizedBox(height: 12),

              // ── Action buttons ────────────────────────────────────────
              _ActionButtons(
                isLastStep: tutorialState.isLastStep,
                nextLabel: nextLabel,
                skipLabel: skipLabel,
                finishLabel: finishLabel,
                onNext: onNext,
                onSkip: onSkip,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

// ─── _StepCounter ─────────────────────────────────────────────────────────────

class _StepCounter extends StatelessWidget {
  const _StepCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$current / $total',
      textAlign: TextAlign.center,
      style: AppTheme.headingStyle.copyWith(
        color: AppTheme.army1Primary,
        fontSize: 22,
      ),
    );
  }
}

// ─── _ProgressBar ─────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: current / total,
        minHeight: 10,
        backgroundColor: AppTheme.kNeutralLight,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.army1Primary),
      ),
    );
  }
}

// ─── _StepCard ────────────────────────────────────────────────────────────────

/// Animated card that slides in when the step changes.
class _StepCard extends StatefulWidget {
  const _StepCard({required this.icon, required this.description});

  final IconData icon;
  final String description;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(_StepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon ||
        oldWidget.description != widget.description) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideIn,
        child: Card(
          color: AppTheme.kSurface,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppTheme.army1Light, width: 2),
          ),
          // Scrollable so long texts never overflow on short (landscape)
          // phone screens.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 32).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Icon ────────────────────────────────────────────────
                    Icon(widget.icon, size: 64, color: AppTheme.army1Primary),
                    const SizedBox(height: 16),

                    // ── Description text (≥ 16 sp per Req 11.1) ────────────
                    Text(
                      widget.description,
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyStyle.copyWith(
                        fontSize: 18,
                        height: 1.5,
                        color: AppTheme.kTextDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _ActionButtons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.isLastStep,
    required this.nextLabel,
    required this.skipLabel,
    required this.finishLabel,
    required this.onNext,
    required this.onSkip,
  });

  final bool isLastStep;
  final String nextLabel;
  final String skipLabel;
  final String finishLabel;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    if (isLastStep) {
      // Last step: only the "Let's Go!" finish button, full width.
      return ElevatedButton.icon(
        onPressed: onNext, // nextStep() calls skipTutorial() on last step
        icon: const Icon(Icons.flag_rounded, size: 24),
        label: Text(finishLabel),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.kAccentGreen,
          foregroundColor: AppTheme.kTextLight,
          textStyle: AppTheme.labelStyle.copyWith(fontSize: 20),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          shadowColor: AppTheme.kAccentGreen.withAlpha(100),
        ),
      );
    }

    // Intermediate steps: Skip (secondary) + Next (primary).
    return Row(
      children: [
        // Skip button — outlined style (lower visual weight).
        Expanded(
          child: OutlinedButton(
            onPressed: onSkip,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.kTextDark,
              textStyle: AppTheme.labelStyle.copyWith(fontSize: 18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: const BorderSide(color: AppTheme.kNeutralLight, width: 2),
            ),
            child: Text(skipLabel),
          ),
        ),
        const SizedBox(width: 16),

        // Next button — primary filled style.
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 24),
            label: Text(nextLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.army1Primary,
              foregroundColor: AppTheme.kTextLight,
              textStyle: AppTheme.labelStyle.copyWith(fontSize: 18),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
              shadowColor: AppTheme.army1Primary.withAlpha(100),
            ),
          ),
        ),
      ],
    );
  }
}
