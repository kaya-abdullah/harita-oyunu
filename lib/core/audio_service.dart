/// Audio playback service for Harita: Kendi İmparatorluğunu Kur.
///
/// Wraps `audioplayers` to provide non-fatal SFX and background music playback.
/// Any playback errors are silently swallowed — audio is purely presentational
/// and must never crash or block the game (Requirements 10.4, 10.5).
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Centralised audio service for in-game sounds and background music.
///
/// All public methods are fire-and-forget: failures are caught internally so
/// the caller never needs to handle audio errors.
class AudioService {
  // ─── SFX file name constants ─────────────────────────────────────────────

  /// Sound played when an attack is declared.
  static const sfxAttack = 'attack.mp3';

  /// Sound played when a special ability is activated.
  static const sfxAbility = 'ability.mp3';

  /// Sound played at the end of each turn.
  static const sfxTurnEnd = 'turn_end.mp3';

  /// Fanfare played when a player wins.
  static const sfxVictory = 'victory.mp3';

  /// Subtle click for UI button taps.
  static const sfxButtonTap = 'tap.mp3';

  /// Looping upbeat background music track.
  static const musicBackground = 'background.mp3';

  // ─── Private music player ────────────────────────────────────────────────

  /// Dedicated player kept alive for looping background music.
  /// Created lazily (inside a try) so a missing audio plugin — e.g. in widget
  /// tests — can never throw from the constructor.
  AudioPlayer? _musicPlayer;

  /// Global on/off switch; when false all playback calls are no-ops.
  bool enabled = true;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Plays a short sound effect from `assets/audio/[fileName]`.
  ///
  /// Creates a one-shot [AudioPlayer] per call so simultaneous SFX do not
  /// interrupt each other. Any error is silently discarded.
  Future<void> playSfx(String fileName) async {
    if (!enabled) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('audio/$fileName'));
      // Release the player once the clip finishes.
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (_) {
      // Audio is non-fatal — swallow all errors silently.
    }
  }

  /// Starts looping background music from `assets/audio/[fileName]`.
  ///
  /// Stops any currently playing music before starting the new track.
  /// Any error is silently discarded.
  Future<void> playMusic(String fileName) async {
    if (!enabled) return;
    try {
      final player = _musicPlayer ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('audio/$fileName'));
    } catch (_) {
      // Audio is non-fatal — swallow all errors silently.
    }
  }

  /// Stops the currently looping background music.
  ///
  /// Any error is silently discarded.
  Future<void> stopMusic() async {
    try {
      await _musicPlayer?.stop();
    } catch (_) {
      // Audio is non-fatal — swallow all errors silently.
    }
  }

  /// Releases all underlying [AudioPlayer] resources.
  ///
  /// Call this when the service is no longer needed (e.g. app dispose).
  Future<void> dispose() async {
    try {
      await _musicPlayer?.dispose();
    } catch (_) {
      // Ignore disposal errors.
    }
  }
}

/// Provides the singleton [AudioService] instance.
///
/// Scoped at the root [ProviderScope] so the same music player is reused
/// across screen navigations.
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  return service;
});
