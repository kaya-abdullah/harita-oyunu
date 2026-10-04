/// Bot difficulty levels for Harita: Kendi İmparatorluğunu Kur.
library;

/// How strong the AI opponent plays. Chosen when a new game starts.
enum AiDifficulty {
  /// "Çok Kolay" — a few timid moves per turn, no abilities or shopping.
  veryEasy,

  /// "Orta" — greedy expansion with occasional abilities.
  medium,

  /// "Zor" — plays every move well, hunts bases, uses every ability and
  /// receives extra soldiers each turn.
  hard,
}

/// Parses [name] back to an [AiDifficulty], defaulting to
/// [AiDifficulty.medium] for unknown or missing values.
AiDifficulty aiDifficultyFromName(String? name) => AiDifficulty.values
    .firstWhere((d) => d.name == name, orElse: () => AiDifficulty.medium);
