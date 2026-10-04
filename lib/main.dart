import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'infrastructure/persistence/hive_adapters.dart';

/// Application entry point.
///
/// Initialises Hive local storage before launching the Flutter widget tree.
///
/// ─────────────────────────────────────────────────────────────────────────
/// ADVERTISEMENT SDK COMPLIANCE (Requirement 13.1)
/// ─────────────────────────────────────────────────────────────────────────
/// No advertisement SDK is initialised here or anywhere else in this file.
/// Verified absent: google_mobile_ads, admob_flutter, flutter_facebook_ads,
/// unity_ads, applovin_max, and any other ad-network SDK.
///
/// The game is advertisement-free by design; this comment serves as an
/// explicit declaration for future maintainers.  Any PR that adds an ad SDK
/// initialisation call here MUST be reviewed for Requirement 13.1 compliance.
/// ─────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  // Required before any async operations that interact with Flutter bindings.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Hive with the default Flutter app documents directory.
  await Hive.initFlutter();

  // Register all generated Hive TypeAdapters before opening any boxes.
  registerAdapters();

  runApp(const HaritaApp());
}
