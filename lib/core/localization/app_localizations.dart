import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'locale_service.dart';

/// Supported locales for the application.
const Locale kLocaleTurkish = Locale('tr');
const Locale kLocaleEnglish = Locale('en');

/// All locales the app officially supports.
const List<Locale> kSupportedLocales = [kLocaleTurkish, kLocaleEnglish];

/// Factory that asynchronously loads the JSON locale bundles from
/// `assets/locales/` and returns a ready-to-use [LocaleService].
///
/// Call once at startup (e.g. in `main()` before `runApp`) and inject the
/// result into your Riverpod providers.
///
/// ```dart
/// final localeService = await AppLocalizations.load();
/// ```
class AppLocalizations {
  AppLocalizations._();

  /// Loads both locale bundles from assets and constructs a [LocaleService].
  ///
  /// Throws a [StateError] if either bundle asset cannot be loaded.
  static Future<LocaleService> load() async {
    final Map<String, Map<String, String>> bundles = {};

    for (final locale in kSupportedLocales) {
      final assetPath = 'assets/locales/${locale.languageCode}.json';
      try {
        final raw = await rootBundle.loadString(assetPath);
        final decoded = json.decode(raw) as Map<String, dynamic>;
        bundles[locale.languageCode] = decoded.map(
          (k, v) => MapEntry(k, v.toString()),
        );
      } catch (e) {
        throw StateError(
          'Failed to load locale bundle for "${locale.languageCode}" '
          'from "$assetPath": $e',
        );
      }
    }

    return LocaleService(bundles: bundles);
  }

  /// Creates a [LocaleService] directly from in-memory bundle maps.
  ///
  /// Useful for tests where you want to supply bundles without touching
  /// the asset system.
  static LocaleService fromBundles(Map<String, Map<String, String>> bundles) =>
      LocaleService(bundles: bundles);
}

/// Convenience extension on [LocaleService] that exposes named getters for
/// every well-known string key, so call sites avoid magic-string literals.
///
/// Usage:
/// ```dart
/// final t = localeService.of(currentLocale);
/// Text(t.appName);
/// Text(t.errorInsufficientDiamonds);
/// ```
extension LocaleServiceX on LocaleService {
  /// Returns a [_Strings] helper bound to [locale].
  AppStrings of(Locale locale) => AppStrings(this, locale);
}

/// Bound accessor returned by [LocaleServiceX.of].
///
/// Each getter calls `LocaleService.translate` so the three-level fallback
/// chain (requested locale → English → raw key) is always honoured.
class AppStrings {
  const AppStrings(this._service, this._locale);

  final LocaleService _service;
  final Locale _locale;

  String _t(String key, {Map<String, String>? p}) =>
      _service.translate(key, _locale, params: p);

  // ── App ──────────────────────────────────────────────────────────────────
  String get appName => _t('app_name');
  String get resourceName => _t('resource_name');

  // ── Ability names ────────────────────────────────────────────────────────
  String get abilityFireBomb => _t('ability_fire_bomb');
  String get abilityBombardment => _t('ability_bombardment');
  String get abilitySoldierSpell => _t('ability_soldier_spell');
  String get abilityMegaBomba => _t('ability_mega_bomba');

  /// e.g. `strings.abilityLocked(turn: '10')`
  String abilityLocked({required String turn}) =>
      _t('ability_locked', p: {'turn': turn});

  // ── Tooltips ─────────────────────────────────────────────────────────────
  String get tooltipFireBomb => _t('tooltip_fire_bomb');
  String get tooltipBombardment => _t('tooltip_bombardment');
  String get tooltipSoldierSpell => _t('tooltip_soldier_spell');
  String get tooltipMegaBomba => _t('tooltip_mega_bomba');

  // ── Errors ───────────────────────────────────────────────────────────────
  String get errorInsufficientDiamonds => _t('error_insufficient_diamonds');
  String get errorAbilityLocked => _t('error_ability_locked');

  /// e.g. `strings.errorCooldownActive(turns: '2')`
  String errorCooldownActive({required String turns}) =>
      _t('error_cooldown_active', p: {'turns': turns});

  String get errorInvalidAttack => _t('error_invalid_attack');
  String get errorNotYourTurn => _t('error_not_your_turn');

  // ── Victory ──────────────────────────────────────────────────────────────
  /// e.g. `strings.victoryTitle(army: 'Army 1')`
  String victoryTitle({required String army}) =>
      _t('victory_title', p: {'army': army});

  /// e.g. `strings.victoryTurns(turn: '37')`
  String victoryTurns({required String turn}) =>
      _t('victory_turns', p: {'turn': turn});

  String get victorySubtitle => _t('victory_subtitle');

  // ── Buttons ──────────────────────────────────────────────────────────────
  String get btnNewGame => _t('btn_new_game');
  String get btnResume => _t('btn_resume');
  String get btnTutorial => _t('btn_tutorial');
  String get btnEndTurn => _t('btn_end_turn');
  String get btnShop => _t('btn_shop');
  String get btnMainMenu => _t('btn_main_menu');
  String get btnNext => _t('btn_next');
  String get btnBack => _t('btn_back');
  String get btnConfirm => _t('btn_confirm');
  String get btnCancel => _t('btn_cancel');

  // ── Territory info ───────────────────────────────────────────────────────
  String get territoryOwnerLabel => _t('territory_owner_label');
  String get territoryUnitsLabel => _t('territory_units_label');
  String get territoryAdjacentLabel => _t('territory_adjacent_label');
  String get territoryOwnerNeutral => _t('territory_owner_neutral');

  // ── HUD ──────────────────────────────────────────────────────────────────
  String get turnLabel => _t('turn_label');
  String get activeArmyLabel => _t('active_army_label');
  String get diamondBalanceLabel => _t('diamond_balance_label');

  // ── Shop ─────────────────────────────────────────────────────────────────
  String get shopTitle => _t('shop_title');
  String get shopBuy => _t('shop_buy');
  String get shopReadOnly => _t('shop_read_only');
  String get shopCostLabel => _t('shop_cost_label');
  String get shopEmpty => _t('shop_empty');

  // ── Army names ───────────────────────────────────────────────────────────
  String get army1Name => _t('army_1_name');
  String get army2Name => _t('army_2_name');

  /// Display name of the army with [index] (0 = the player, 1 … 6 = bots),
  /// e.g. "Mavi Ordu".
  String armyName(int index) => _t('army_${index + 1}_name');
  String get armyNeutral => _t('army_neutral');

  // ── Tutorial ─────────────────────────────────────────────────────────────
  String get tutorialSkip => _t('tutorial_skip');
  String get tutorialNext => _t('tutorial_next');
  String get tutorialFinish => _t('tutorial_finish');
  String get tutorialStepMap => _t('tutorial_step_map');
  String get tutorialStepTerritory => _t('tutorial_step_territory');
  String get tutorialStepResources => _t('tutorial_step_resources');
  String get tutorialStepAbilities => _t('tutorial_step_abilities');
  String get tutorialStepShop => _t('tutorial_step_shop');
  String get tutorialStepEndTurn => _t('tutorial_step_end_turn');
  String get tutorialStepVictory => _t('tutorial_step_victory');

  // ── Gameplay feedback ────────────────────────────────────────────────────
  String get btnAttack => _t('btn_attack');
  String get hintSelectTerritory => _t('hint_select_territory');
  String get hintAttack => _t('hint_attack');
  String get errorAbilityNotReady => _t('error_ability_not_ready');
  String get errorInvalidTarget => _t('error_invalid_target');
  String get attackWon => _t('attack_won');
  String get attackLost => _t('attack_lost');
  String get aiThinking => _t('ai_thinking');

  /// e.g. `strings.abilitySelectTarget(ability: 'Fire Bomb')`
  String abilitySelectTarget({required String ability}) =>
      _t('ability_select_target', p: {'ability': ability});

  /// e.g. `strings.abilityUsed(ability: 'Fire Bomb')`
  String abilityUsed({required String ability}) =>
      _t('ability_used', p: {'ability': ability});

  String get cannotDeploy => _t('cannot_deploy');
  String get unitsMoved => _t('units_moved');
  String get shopItemDesc => _t('shop_item_desc');
  String get reserveLabel => _t('reserve_label');

  /// e.g. `strings.btnDeploy(count: '3')`
  String btnDeploy({required String count}) =>
      _t('btn_deploy', p: {'count': count});

  /// e.g. `strings.unitsDeployed(count: '3')`
  String unitsDeployed({required String count}) =>
      _t('units_deployed', p: {'count': count});

  /// e.g. `strings.diamondMineCaptured(count: '250')`
  String diamondMineCaptured({required String count}) =>
      _t('diamond_mine_captured', p: {'count': count});

  String get diamondMineLabel => _t('diamond_mine_label');

  /// e.g. `strings.goldMineCaptured(count: '150')`
  String goldMineCaptured({required String count}) =>
      _t('gold_mine_captured', p: {'count': count});
  String get goldMineLabel => _t('gold_mine_label');
  String get terrainLabel => _t('terrain_label');

  /// Name of a terrain, e.g. `strings.terrainName('rainforest')`.
  String terrainName(String terrain) => _t('terrain_$terrain');
  String get botCountTitle => _t('bot_count_title');
  String get btnStart => _t('btn_start');
  String get youLabel => _t('you_label');
  String get defeatTitle => _t('defeat_title');
  String defeatSubtitle(String army) =>
      _t('defeat_subtitle', p: {'army': army});

  // ── Bot difficulty ──────────────────────────────────────────────────────
  String get difficultyTitle => _t('difficulty_title');
  String get difficultyVeryEasy => _t('difficulty_very_easy');
  String get difficultyMedium => _t('difficulty_medium');
  String get difficultyHard => _t('difficulty_hard');
  String get difficultyVeryEasyDesc => _t('difficulty_very_easy_desc');
  String get difficultyMediumDesc => _t('difficulty_medium_desc');
  String get difficultyHardDesc => _t('difficulty_hard_desc');
  String get difficultyLabel => _t('difficulty_label');
  String get tilesLabel => _t('tiles_label');

  /// Looks up an arbitrary [key] (e.g. a shop item `nameKey`) with the
  /// standard fallback chain.
  String raw(String key) => _t(key);
}
