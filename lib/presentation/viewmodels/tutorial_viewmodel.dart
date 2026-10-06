/// Tutorial state management (ViewModel layer) for Harita: Kendi İmparatorluğunu Kur.
///
/// Tracks the player's progress through the 7 onboarding steps and persists
/// completion status to Hive so returning players can skip the tutorial.
///
/// Requirements: 11.5
library;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─── TutorialStep ─────────────────────────────────────────────────────────────

/// The seven ordered tutorial steps, each mapped to a locale key.
///
/// | Step        | Locale key                  |
/// |-------------|-----------------------------|
/// | map         | tutorial_step_map           |
/// | territory   | tutorial_step_territory     |
/// | resources   | tutorial_step_resources     |
/// | abilities   | tutorial_step_abilities     |
/// | shop        | tutorial_step_shop          |
/// | endTurn     | tutorial_step_end_turn      |
/// | victory     | tutorial_step_victory       |
enum TutorialStep {
  map,
  territory,
  resources,
  abilities,
  shop,
  endTurn,
  victory;

  /// The locale string key for this step's description text.
  String get localeKey {
    switch (this) {
      case TutorialStep.map:
        return 'tutorial_step_map';
      case TutorialStep.territory:
        return 'tutorial_step_territory';
      case TutorialStep.resources:
        return 'tutorial_step_resources';
      case TutorialStep.abilities:
        return 'tutorial_step_abilities';
      case TutorialStep.shop:
        return 'tutorial_step_shop';
      case TutorialStep.endTurn:
        return 'tutorial_step_end_turn';
      case TutorialStep.victory:
        return 'tutorial_step_victory';
    }
  }

  /// The icon representing this step in the UI.
  IconData get icon {
    switch (this) {
      case TutorialStep.map:
        return Icons.public_rounded;
      case TutorialStep.territory:
        return Icons.grid_view_rounded;
      case TutorialStep.resources:
        return Icons.diamond_rounded;
      case TutorialStep.abilities:
        return Icons.local_fire_department_rounded;
      case TutorialStep.shop:
        return Icons.storefront_rounded;
      case TutorialStep.endTurn:
        return Icons.skip_next_rounded;
      case TutorialStep.victory:
        return Icons.military_tech_rounded;
    }
  }
}

// ─── TutorialState ────────────────────────────────────────────────────────────

/// Immutable snapshot of the tutorial's progression state.
class TutorialState {
  const TutorialState({
    required this.currentStepIndex,
    required this.isComplete,
  });

  /// Creates the initial state: first step, not complete.
  const TutorialState.initial() : currentStepIndex = 0, isComplete = false;

  /// Creates a state that is already marked complete (for returning players).
  const TutorialState.completed()
    : currentStepIndex = TutorialState._totalSteps - 1,
      isComplete = true;

  /// Total number of tutorial steps.
  static const int _totalSteps =
      7; // TutorialStep.values.length — hardcoded for const compatibility

  /// Zero-based index of the step currently displayed.
  final int currentStepIndex;

  /// `true` after the player taps "Finish" on the last step or "Skip".
  final bool isComplete;

  /// The [TutorialStep] value for [currentStepIndex].
  TutorialStep get currentStep => TutorialStep.values[currentStepIndex];

  /// Total number of steps in the tutorial.
  int get totalSteps => _totalSteps;

  /// `true` when [currentStepIndex] points to the last step.
  bool get isLastStep => currentStepIndex == _totalSteps - 1;

  // ─── copyWith ─────────────────────────────────────────────────────────────

  TutorialState copyWith({int? currentStepIndex, bool? isComplete}) {
    return TutorialState(
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TutorialState) return false;
    return currentStepIndex == other.currentStepIndex &&
        isComplete == other.isComplete;
  }

  @override
  int get hashCode => Object.hash(currentStepIndex, isComplete);

  @override
  String toString() =>
      'TutorialState(step: $currentStepIndex/$totalSteps, complete: $isComplete)';
}

// ─── Hive constants ───────────────────────────────────────────────────────────

const _kTutorialBoxName = 'tutorial_prefs';
const _kCompletedKey = 'completed';

// ─── TutorialNotifier ─────────────────────────────────────────────────────────

/// Manages tutorial progression and persists the completion flag to Hive.
///
/// ### Lifecycle
/// 1. [build] returns the default [TutorialState.initial].
/// 2. Call [init] immediately after the tutorial screen mounts; if Hive
///    records `completed == true` the state transitions to
///    [TutorialState.completed] so the screen pops automatically.
///
/// ### Actions
/// - [nextStep] — advances to the next step or marks complete on the last.
/// - [skipTutorial] — marks complete immediately regardless of current step.
class TutorialNotifier extends Notifier<TutorialState> {
  @override
  TutorialState build() => const TutorialState.initial();

  // ─── init ─────────────────────────────────────────────────────────────────

  /// Reads persistent completion state from Hive and updates [state].
  ///
  /// Should be called once when the tutorial screen is first displayed so
  /// returning players do not see the tutorial again unless they explicitly
  /// choose to replay it.
  Future<void> init() async {
    try {
      final box = await Hive.openBox<bool>(_kTutorialBoxName);
      final completed = box.get(_kCompletedKey, defaultValue: false) ?? false;
      if (completed) {
        state = const TutorialState.completed();
      }
    } catch (_) {
      // Persistence failure must never crash the app — remain at initial state.
    }
  }

  // ─── nextStep ─────────────────────────────────────────────────────────────

  /// Advances the tutorial to the next step.
  ///
  /// On the last step, calls [skipTutorial] to mark completion and persist.
  void nextStep() {
    if (state.isComplete) return;

    if (state.isLastStep) {
      skipTutorial();
      return;
    }

    state = state.copyWith(currentStepIndex: state.currentStepIndex + 1);
  }

  // ─── skipTutorial ─────────────────────────────────────────────────────────

  /// Marks the tutorial as complete and persists the flag to Hive.
  ///
  /// The UI observes [TutorialState.isComplete] and navigates away.
  void skipTutorial() {
    if (state.isComplete) return;
    state = state.copyWith(isComplete: true);
    _persistCompletion();
  }

  // ─── _persistCompletion ───────────────────────────────────────────────────

  Future<void> _persistCompletion() async {
    try {
      final box = await Hive.openBox<bool>(_kTutorialBoxName);
      await box.put(_kCompletedKey, true);
    } catch (_) {
      // Persistence failure must never crash the app.
    }
  }
}

// ─── tutorialProvider ─────────────────────────────────────────────────────────

/// Root [NotifierProvider] for [TutorialState].
///
/// Consumers watch this provider to rebuild whenever the step changes or the
/// tutorial completes.
final tutorialProvider = NotifierProvider<TutorialNotifier, TutorialState>(
  TutorialNotifier.new,
);
