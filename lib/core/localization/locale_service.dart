import 'dart:ui';

/// Provides locale-aware string lookup with a three-level fallback chain:
///   1. Requested locale bundle
///   2. English ('en') bundle
///   3. Raw key (returned as-is)
///
/// Supports parameter interpolation using `{paramName}` placeholders.
class LocaleService {
  /// The loaded locale bundles keyed by language code (e.g. 'tr', 'en').
  final Map<String, Map<String, String>> _bundles;

  /// Creates a [LocaleService] with the supplied locale bundles.
  ///
  /// The [bundles] map must contain at least an 'en' entry so the English
  /// fallback chain can function correctly.
  const LocaleService({required Map<String, Map<String, String>> bundles})
    : _bundles = bundles;

  /// Returns the localised string for [key] in [locale].
  ///
  /// Resolution order:
  ///   1. `_bundles[locale.languageCode][key]`
  ///   2. `_bundles['en'][key]`
  ///   3. [key] itself
  ///
  /// After resolving the template, any `{paramName}` placeholders found in
  /// the string are replaced with the values from [params].
  String translate(String key, Locale locale, {Map<String, String>? params}) {
    final requestedBundle = _bundles[locale.languageCode];
    final englishBundle = _bundles['en'];

    // 1. Try the requested locale.
    String? template = requestedBundle?[key];

    // 2. Fall back to English bundle.
    template ??= englishBundle?[key];

    // 3. Fall back to raw key.
    template ??= key;

    return _interpolate(template, params);
  }

  /// Replaces every `{paramName}` placeholder in [template] with the
  /// corresponding value from [params]. Returns [template] unchanged when
  /// [params] is null or empty.
  String _interpolate(String template, Map<String, String>? params) {
    if (params == null || params.isEmpty) return template;
    return params.entries.fold(
      template,
      (current, entry) => current.replaceAll('{${entry.key}}', entry.value),
    );
  }

  /// Returns true if the given [locale] has a registered bundle.
  bool supportsLocale(Locale locale) =>
      _bundles.containsKey(locale.languageCode);

  /// Returns all registered language codes (e.g. ['tr', 'en']).
  List<String> get supportedLanguageCodes => _bundles.keys.toList();
}
