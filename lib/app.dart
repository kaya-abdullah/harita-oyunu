/// Root application widget for Harita: Kendi İmparatorluğunu Kur.
///
/// Wires together:
///  - Riverpod [ProviderScope] for the entire provider tree.
///  - [AppTheme.lightTheme] applied to [MaterialApp] (Requirement 10.1, 11.1, 11.2).
///  - Locale initialisation from Hive on first build (Requirement 2.3).
///  - [IntroScreen] (bomb intro over the main menu) as the initial route
///    (Requirement 12.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/presentation/screens/intro_screen.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';

/// Root application widget.
///
/// Wraps the [MaterialApp] in a Riverpod [ProviderScope] so that all
/// descendants have access to the provider tree.
class HaritaApp extends StatelessWidget {
  const HaritaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: _AppRoot());
  }
}

/// Inner root widget that reads Riverpod providers.
///
/// Uses [ConsumerStatefulWidget] so that [LocaleNotifier.init] can be called
/// exactly once from [initState] — ensuring the saved locale is loaded from
/// Hive before the first frame is painted.
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot>
    with WidgetsBindingObserver {
  late final AudioService _audio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Upbeat looping background music for the whole app (Requirement 10.5).
    _audio = ref.read(audioServiceProvider);
    _audio.playMusic(AudioService.musicBackground);
    // Load the previously saved locale from Hive asynchronously.
    // This is fire-and-forget: state updates when the Future completes and
    // the widget rebuilds with the correct locale automatically.
    ref.read(localeProvider.notifier).init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Stops the music while the app is in the background and resumes it when
  /// the child comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _audio.playMusic(AudioService.musicBackground);
    } else if (state == AppLifecycleState.paused) {
      _audio.stopMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch locale so MaterialApp rebuilds when the language is switched.
    ref.watch(localeProvider);

    return MaterialApp(
      title: 'Harita: Kendi İmparatorluğunu Kur',
      debugShowCheckedModeBanner: false,
      // Apply theme with WCAG-compliant contrast and
      // minimum 16 sp font sizes (Requirements 10.1, 11.1, 11.2).
      theme: AppTheme.lightTheme,
      // The atomic-bomb intro plays first, then reveals the main menu.
      home: const IntroScreen(),
    );
  }
}
