/// Locale state management and persistence for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/localization/locale_service.dart';

const _kLocaleBoxName = 'locale_prefs';
const _kLocaleKey = 'selected_locale';
const _kDefaultLocale = kLocaleTurkish;

/// Riverpod [Notifier] that manages the currently selected [Locale].
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => _kDefaultLocale;

  /// Loads the previously saved locale from Hive and updates state.
  Future<void> init() async {
    final box = await Hive.openBox<String>(_kLocaleBoxName);
    final savedCode = box.get(_kLocaleKey);
    if (savedCode != null) {
      final resolved = _resolveLocale(savedCode);
      if (resolved != null) state = resolved;
    }
  }

  /// Switches the active locale to [locale] and persists the change.
  void setLocale(Locale locale) {
    if (!kSupportedLocales.contains(locale)) return;
    state = locale; // synchronous — satisfies < 200 ms requirement
    _persist(locale); // fire-and-forget persistence
  }

  Locale? _resolveLocale(String languageCode) {
    for (final locale in kSupportedLocales) {
      if (locale.languageCode == languageCode) return locale;
    }
    return null;
  }

  Future<void> _persist(Locale locale) async {
    try {
      final box = await Hive.openBox<String>(_kLocaleBoxName);
      await box.put(_kLocaleKey, locale.languageCode);
    } catch (_) {
      // Persistence failure must never crash the app.
    }
  }
}

/// Provides the active [Locale], managed by [LocaleNotifier].
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);

/// Provides a fully loaded [LocaleService] by reading JSON asset bundles.
final localeServiceProvider = FutureProvider<LocaleService>(
  (ref) => AppLocalizations.load(),
);
