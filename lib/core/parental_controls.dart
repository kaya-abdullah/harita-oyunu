/// Parental-control utilities for Harita: Kendi İmparatorluğunu Kur.
///
/// Implements Requirements 13.1, 13.2, and 13.3:
///
///   13.1 — No advertisements are displayed during gameplay.
///   13.2 — Any navigation that would take the player outside the app MUST be
///           gated by a parental-confirmation dialog.
///   13.3 — Any real-money purchase transaction MUST require device-level
///           authentication (biometric / PIN) before proceeding.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// ADVERTISEMENT AUDIT (Requirement 13.1)
/// ─────────────────────────────────────────────────────────────────────────────
/// The following advertisement SDKs and packages are confirmed ABSENT from this
/// project (verified by searching all Dart source files and pubspec.yaml):
///
///   • google_mobile_ads    — not present
///   • admob_flutter        — not present
///   • flutter_facebook_ads — not present
///   • unity_ads            — not present
///   • applovin_max         — not present
///   • Any package whose name or import path contains "ad", "ads", or
///     "advertisement" in an advertisement-SDK context — not present
///
/// No Banner, Interstitial, Rewarded, or Native ad widgets exist anywhere in
/// the widget tree.  Compliance status: SATISFIED.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

import 'localization/app_localizations.dart';
import 'theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Requirement 13.2 — Parental confirmation before external navigation
// ─────────────────────────────────────────────────────────────────────────────

/// A simple dialog that asks a parent / guardian for confirmation before the
/// app navigates the child to an external URL or leaves the application.
///
/// Usage:
/// ```dart
/// final confirmed = await showParentalConfirmation(context);
/// if (confirmed) { /* proceed with external launch */ }
/// ```
///
/// The dialog is bilingual (TR / EN) using the active [localeProvider] from
/// Riverpod, but also accepts an optional [locale] override so it can be
/// shown without a Riverpod context (e.g. in platform callbacks).
class ParentalConfirmationDialog extends StatelessWidget {
  /// Creates a [ParentalConfirmationDialog].
  ///
  /// [locale] defaults to English when null.
  const ParentalConfirmationDialog({super.key, this.locale});

  /// Override the display locale.  When null the dialog falls back to English.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? kLocaleEnglish;
    final isTurkish = effectiveLocale == kLocaleTurkish;

    final title = isTurkish
        ? 'Ebeveyn Onayı Gerekiyor'
        : 'Parental Confirmation';
    final body = isTurkish
        ? 'Uygulamadan çıkmak istiyor musunuz?\nBu işlem çocuğunuzu uygulamanın dışına yönlendirecektir.'
        : 'Are you sure you want to leave the app?\nThis will navigate your child outside of the application.';
    final confirmLabel = isTurkish ? 'Onayla' : 'Confirm';
    final cancelLabel = isTurkish ? 'İptal' : 'Cancel';

    return AlertDialog(
      backgroundColor: AppTheme.kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(
            Icons.security_rounded,
            color: AppTheme.kWarning,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: AppTheme.headingStyle.copyWith(
                color: AppTheme.kTextDark,
                fontSize: 22,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        body,
        style: AppTheme.bodyStyle.copyWith(
          color: AppTheme.kTextDark,
          fontSize: 16,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        // Cancel — stays in the app
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.army1Primary,
            textStyle: AppTheme.labelStyle.copyWith(fontSize: 18),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: const BorderSide(color: AppTheme.army1Primary, width: 2),
          ),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: 8),
        // Confirm — parent approves leaving the app
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.kWarning,
            foregroundColor: AppTheme.kTextOnAmber,
            textStyle: AppTheme.labelStyle.copyWith(
              fontSize: 18,
              color: AppTheme.kTextOnAmber,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 3,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Shows a [ParentalConfirmationDialog] and returns `true` if the parent
/// confirmed, or `false` if they cancelled / dismissed the dialog.
///
/// This is the single entry-point that **every** potential external-URL launch
/// site in the codebase MUST call before invoking a platform URL launcher.
///
/// ```dart
/// Future<void> _openPrivacyPolicy(BuildContext context) async {
///   final confirmed = await showParentalConfirmation(context);
///   if (!confirmed) return;
///   // Only reached when parent explicitly confirms.
///   await launchUrl(Uri.parse('https://example.com/privacy'));
/// }
/// ```
///
/// Requirement 13.2 — no external link may bypass this gate.
Future<bool> showParentalConfirmation(
  BuildContext context, {
  Locale? locale,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // force an explicit choice
    builder: (_) => ParentalConfirmationDialog(locale: locale),
  );
  // null means the dialog was dismissed without a button press — treat as cancel
  return result ?? false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Requirement 13.3 — Device-level authentication before any purchase
// ─────────────────────────────────────────────────────────────────────────────

/// Guards any real-money in-app purchase transaction behind device-level
/// authentication (biometric / PIN).
///
/// **Current version status**: this game does not contain any real-money
/// in-app purchase flow.  The `authenticateBeforePurchase` method is provided
/// as a documented stub so that future developers cannot accidentally add a
/// purchase path that bypasses the authentication gate.
///
/// When real-money purchases are introduced:
///   1. Add the `local_auth` package to `pubspec.yaml`.
///   2. Replace the stub body below with the `local_auth` implementation.
///   3. Add the required platform permissions to `AndroidManifest.xml` and
///      `Info.plist` (USE_FINGERPRINT / NSFaceIDUsageDescription).
///
/// Example production implementation (do NOT add without the package):
/// ```dart
/// import 'package:local_auth/local_auth.dart';
///
/// static Future<bool> authenticateBeforePurchase(BuildContext context) async {
///   final auth = LocalAuthentication();
///   final canAuthenticate =
///       await auth.canCheckBiometrics || await auth.isDeviceSupported();
///   if (!canAuthenticate) return false;
///   return auth.authenticate(
///     localizedReason: 'Confirm this purchase',
///     options: const AuthenticationOptions(biometricOnly: false),
///   );
/// }
/// ```
class PurchaseGuard {
  // Private constructor — this class is a pure static utility namespace.
  PurchaseGuard._();

  /// Must be called before any real-money transaction.
  ///
  /// Requires device biometric / PIN authentication via the `local_auth`
  /// package (or equivalent platform mechanism).
  ///
  /// Returns `true` if the device owner authenticated successfully,
  /// `false` otherwise.
  ///
  /// **Stub behaviour** (current version): always returns `false` because no
  /// in-app purchases are enabled.  This ensures that any code path that
  /// mistakenly reaches this gate is blocked rather than silently permitted.
  ///
  /// Requirement 13.3 — device-level authentication required before purchase.
  static Future<bool> authenticateBeforePurchase(
    // ignore: avoid_unused_parameters
    BuildContext context,
  ) async {
    // ── Production: replace with local_auth call (see class-level doc) ──────
    // Stub: no purchases enabled in current version → always deny.
    return false;
  }
}
