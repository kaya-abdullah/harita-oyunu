/// Hive-backed implementation of [SaveRepository] for
/// Harita: Kendi İmparatorluğunu Kur.
library;

import 'package:hive_flutter/hive_flutter.dart';

import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/save_data.dart';

// ─── Abstract interface ───────────────────────────────────────────────────────

/// Contract for the persistence layer that saves and restores [GameState].
abstract class SaveRepository {
  /// Serialises [state] and writes it to persistent storage.
  Future<void> saveGameState(GameState state);

  /// Reads and deserialises the most-recently saved [GameState].
  ///
  /// Returns `null` if no save exists or if the save cannot be parsed.
  Future<GameState?> loadGameState();

  /// Removes the stored save from persistent storage.
  Future<void> deleteSave();

  /// Returns `true` if a save entry currently exists in storage.
  Future<bool> hasSave();
}

// ─── Concrete implementation ─────────────────────────────────────────────────

/// [SaveRepository] implementation backed by a Hive box.
///
/// The entire [GameState] is stored as a single [SaveData] object under the
/// key [_saveKey] inside the box named [_boxName].
///
/// **Requirement 12.1** — Game state is serialised and persisted after every
/// turn via [saveGameState].
///
/// **Requirement 12.2** — The saved state can be retrieved on the next launch
/// via [loadGameState] to offer a resume option.
///
/// **Requirement 12.3** — Any exception during deserialisation causes the
/// corrupted entry to be silently deleted; [loadGameState] then returns `null`
/// so the UI falls back to the main menu.
class HiveSaveRepository implements SaveRepository {
  /// Name of the Hive box used for game saves.
  static const String _boxName = 'game_save';

  /// Key under which the single [SaveData] entry is stored.
  static const String _saveKey = 'current_save';

  // ─── saveGameState ──────────────────────────────────────────────────────

  /// Serialises [state] to [SaveData] and writes it to the Hive box.
  ///
  /// Opens the box if it is not already open; Hive caches open boxes so
  /// repeated calls are inexpensive.
  @override
  Future<void> saveGameState(GameState state) async {
    final box = await Hive.openBox<SaveData>(_boxName);
    await box.put(_saveKey, SaveData.fromGameState(state));
  }

  // ─── loadGameState ──────────────────────────────────────────────────────

  /// Reads the stored [SaveData] and converts it back to a [GameState].
  ///
  /// Returns `null` when:
  ///   - no save entry exists, or
  ///   - any exception is thrown during deserialisation (corrupted save).
  ///
  /// In the corrupted-save case the entry is removed via [deleteSave] before
  /// returning, satisfying Requirement 12.3.
  @override
  Future<GameState?> loadGameState() async {
    try {
      final box = await Hive.openBox<SaveData>(_boxName);
      final raw = box.get(_saveKey);
      if (raw == null) return null;
      return raw.toGameState();
    } catch (_) {
      // Corrupted or schema-mismatched save — discard and let caller show menu.
      await deleteSave();
      return null;
    }
  }

  // ─── deleteSave ─────────────────────────────────────────────────────────

  /// Removes the [_saveKey] entry from the Hive box.
  ///
  /// No-op if the entry does not exist.
  @override
  Future<void> deleteSave() async {
    final box = await Hive.openBox<SaveData>(_boxName);
    await box.delete(_saveKey);
  }

  // ─── hasSave ────────────────────────────────────────────────────────────

  /// Returns `true` if a [SaveData] entry is stored under [_saveKey].
  ///
  /// Returns `false` on any error (e.g. Hive not initialized in tests).
  @override
  Future<bool> hasSave() async {
    try {
      final box = await Hive.openBox<SaveData>(_boxName);
      return box.containsKey(_saveKey);
    } catch (_) {
      return false;
    }
  }
}
