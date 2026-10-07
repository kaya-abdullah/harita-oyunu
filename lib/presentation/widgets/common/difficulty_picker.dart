/// New-game picker: how many bots play and how strong they are.
library;

import 'package:flutter/material.dart';

import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/ai_difficulty.dart';
import 'package:harita/domain/models/army.dart';

/// Localised name of [d].
String difficultyName(AiDifficulty d, AppStrings t) => switch (d) {
  AiDifficulty.veryEasy => t.difficultyVeryEasy,
  AiDifficulty.medium => t.difficultyMedium,
  AiDifficulty.hard => t.difficultyHard,
};

/// Icon shown for each difficulty.
IconData difficultyIcon(AiDifficulty d) => switch (d) {
  AiDifficulty.veryEasy => Icons.signal_cellular_alt_1_bar_rounded,
  AiDifficulty.medium => Icons.signal_cellular_alt_2_bar_rounded,
  AiDifficulty.hard => Icons.signal_cellular_alt_rounded,
};

String _description(AiDifficulty d, AppStrings t) => switch (d) {
  AiDifficulty.veryEasy => t.difficultyVeryEasyDesc,
  AiDifficulty.medium => t.difficultyMediumDesc,
  AiDifficulty.hard => t.difficultyHardDesc,
};

Color _color(AiDifficulty d) => switch (d) {
  AiDifficulty.veryEasy => AppTheme.kAccentGreen,
  AiDifficulty.medium => AppTheme.army1Primary,
  AiDifficulty.hard => AppTheme.army2Primary,
};

/// The choices made in the new-game picker.
typedef NewGameChoice = ({AiDifficulty difficulty, int bots, int humans});

/// Shows the new-game picker: first the number of bots (1 … [kMaxBots],
/// starting at [initialBots]), then "Çok Kolay / Orta / Zor" as three big
/// buttons. Tapping a difficulty starts the game. Returns `null` if the
/// dialog was dismissed.
Future<NewGameChoice?> showNewGamePicker(
  BuildContext context,
  AppStrings strings, {
  NewGameChoice? initial,
}) {
  var bots = (initial?.bots ?? 5).clamp(1, kMaxBots);
  var humans = (initial?.humans ?? 1).clamp(1, kMaxHumans);
  return showDialog<NewGameChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AppTheme.kBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          strings.btnNewGame,
          textAlign: TextAlign.center,
          style: AppTheme.labelStyle.copyWith(color: AppTheme.kTextDark),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Players on this phone ─────────────────────────────────
              Text(
                strings.playersTitle,
                textAlign: TextAlign.center,
                style: AppTheme.labelStyle.copyWith(
                  color: AppTheme.kTextDark,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var n = 1; n <= kMaxHumans; n++) ...[
                    if (n > 1) const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceButton(
                        key: Key('humans_$n'),
                        label: n == 1 ? strings.playersOne : strings.playersTwo,
                        selected: n == humans,
                        onTap: () => setState(() => humans = n),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                strings.botCountTitle,
                textAlign: TextAlign.center,
                style: AppTheme.labelStyle.copyWith(
                  color: AppTheme.kTextDark,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              // ── Bot count ─────────────────────────────────────────────
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var n = 1; n <= kMaxBots; n++)
                    _BotCountButton(
                      key: Key('bots_$n'),
                      count: n,
                      selected: n == bots,
                      onTap: () => setState(() => bots = n),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // The colours of the armies that will play.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final id in ArmyId.values.take(bots + humans))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: AppTheme.armyColor(id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Difficulty ────────────────────────────────────────────
              Text(
                strings.difficultyTitle,
                textAlign: TextAlign.center,
                style: AppTheme.labelStyle.copyWith(
                  color: AppTheme.kTextDark,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              for (final d in AiDifficulty.values) ...[
                _DifficultyButton(
                  key: Key('difficulty_${d.name}'),
                  icon: difficultyIcon(d),
                  title: difficultyName(d, strings),
                  description: _description(d, strings),
                  color: _color(d),
                  onTap: () => Navigator.of(
                    ctx,
                  ).pop((difficulty: d, bots: bots, humans: humans)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.army1Primary : AppTheme.kNeutralLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: selected ? AppTheme.kTextLight : AppTheme.kTextDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotCountButton extends StatelessWidget {
  const _BotCountButton({
    super.key,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.army2Primary : AppTheme.kNeutralLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: selected ? AppTheme.kTextLight : AppTheme.kTextDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 32, color: AppTheme.kTextLight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.kTextLight,
                      ),
                    ),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.kTextLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
