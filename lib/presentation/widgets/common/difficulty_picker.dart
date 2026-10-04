/// Bot difficulty picker shown when a new game starts.
library;

import 'package:flutter/material.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/ai_difficulty.dart';

/// Emoji shown for each difficulty.
String difficultyEmoji(AiDifficulty d) => switch (d) {
  AiDifficulty.veryEasy => '🐣',
  AiDifficulty.medium => '🙂',
  AiDifficulty.hard => '😈',
};

/// Localised name of [d].
String difficultyName(AiDifficulty d, AppStrings t) => switch (d) {
  AiDifficulty.veryEasy => t.difficultyVeryEasy,
  AiDifficulty.medium => t.difficultyMedium,
  AiDifficulty.hard => t.difficultyHard,
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

/// Shows "Çok Kolay / Orta / Zor" as three big buttons and returns the
/// chosen difficulty, or `null` if the dialog was dismissed.
Future<AiDifficulty?> showDifficultyPicker(
  BuildContext context,
  AppStrings strings,
) {
  return showDialog<AiDifficulty>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.kBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        strings.difficultyTitle,
        textAlign: TextAlign.center,
        style: AppTheme.labelStyle.copyWith(color: AppTheme.kTextDark),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in AiDifficulty.values) ...[
              _DifficultyButton(
                key: Key('difficulty_${d.name}'),
                emoji: difficultyEmoji(d),
                title: difficultyName(d, strings),
                description: _description(d, strings),
                color: _color(d),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final String emoji;
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
              Text(emoji, style: const TextStyle(fontSize: 34)),
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
