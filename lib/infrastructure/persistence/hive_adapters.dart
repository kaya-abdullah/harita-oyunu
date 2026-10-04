/// Hive adapter registration for Harita: Kendi İmparatorluğunu Kur.
///
/// Call [registerAdapters] exactly once during app startup, before opening
/// any Hive boxes.  The guard against re-registration makes it safe to call
/// from tests or hot-restart scenarios.
library;

import 'package:hive_flutter/hive_flutter.dart';

// save_data.g.dart is a `part of` save_data.dart; importing save_data.dart
// makes SaveDataAdapter available — no separate import of the generated file.
import 'package:harita/domain/models/save_data.dart';

/// Registers all generated Hive [TypeAdapter]s with the global Hive instance.
///
/// Uses [isAlreadyRegistered] guards so calling this function more than once
/// (e.g. during tests) does not throw a duplicate-registration error.
void registerAdapters() {
  if (!Hive.isAdapterRegistered(SaveDataAdapter().typeId)) {
    Hive.registerAdapter(SaveDataAdapter());
  }
}
