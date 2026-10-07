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

  // ── Cards ────────────────────────────────────────────────────────────────
  String get abilityFireBomb => _t('ability_fire_bomb');
  String get abilityBombardment => _t('ability_bombardment');
  String get abilitySoldierSpell => _t('ability_soldier_spell');
  String get abilityMegaBomba => _t('ability_mega_bomba');
  String get abilityAtomBomb => _t('ability_atom_bomb');
  String get abilityNuclearBomb => _t('ability_nuclear_bomb');
  String get abilityTribute => _t('ability_tribute');
  String get tooltipFireBomb => _t('tooltip_fire_bomb');
  String get tooltipBombardment => _t('tooltip_bombardment');
  String get tooltipSoldierSpell => _t('tooltip_soldier_spell');
  String get tooltipMegaBomba => _t('tooltip_mega_bomba');
  String get tooltipAtomBomb => _t('tooltip_atom_bomb');
  String get tooltipNuclearBomb => _t('tooltip_nuclear_bomb');
  String get tooltipTribute => _t('tooltip_tribute');
  String get cardsTitle => _t('cards_title');

  /// e.g. `strings.cardDrawn(card: 'Atom Bombası')`
  String cardDrawn({required String card}) =>
      _t('card_drawn', p: {'card': card});
  String get cardAlreadyDrawn => _t('card_already_drawn');

  /// e.g. `strings.abilitySelectTarget(ability: 'Fire Bomb')`
  String abilitySelectTarget({required String ability}) =>
      _t('ability_select_target', p: {'ability': ability});

  /// e.g. `strings.abilityUsed(ability: 'Fire Bomb')`
  String abilityUsed({required String ability}) =>
      _t('ability_used', p: {'ability': ability});

  /// e.g. `strings.tributeTaken(count: '200')`
  String tributeTaken({required String count}) =>
      _t('tribute_taken', p: {'count': count});

  // ── Bombers ──────────────────────────────────────────────────────────────
  String get bomberArmed => _t('bomber_armed');

  /// e.g. `strings.bomberHit(count: '15')`
  String bomberHit({required String count}) =>
      _t('bomber_hit', p: {'count': count});
  String get noBomber => _t('no_bomber');
  String get invalidBomberTarget => _t('invalid_bomber_target');

  // ── Errors ───────────────────────────────────────────────────────────────
  String get errorInsufficientDiamonds => _t('error_insufficient_diamonds');
  String get errorNoCard => _t('error_no_card');
  String get errorInvalidAttack => _t('error_invalid_attack');
  String get errorNotYourTurn => _t('error_not_your_turn');
  String get errorInvalidTarget => _t('error_invalid_target');

  // ── Victory ──────────────────────────────────────────────────────────────
  /// e.g. `strings.victoryTitle(army: 'Army 1')`
  String victoryTitle({required String army}) =>
      _t('victory_title', p: {'army': army});

  /// e.g. `strings.victoryTurns(turn: '37')`
  String victoryTurns({required String turn}) =>
      _t('victory_turns', p: {'turn': turn});

  String get victorySubtitle => _t('victory_subtitle');
  String get defeatTitle => _t('defeat_title');
  String defeatSubtitle(String army) =>
      _t('defeat_subtitle', p: {'army': army});

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
  String get btnAttack => _t('btn_attack');
  String get btnDrawCard => _t('btn_draw_card');
  String get btnBomber => _t('btn_bomber');
  String get btnStart => _t('btn_start');

  // ── City info ────────────────────────────────────────────────────────────
  String get territoryOwnerLabel => _t('territory_owner_label');
  String get territoryUnitsLabel => _t('territory_units_label');
  String get territoryAdjacentLabel => _t('territory_adjacent_label');
  String get territoryOwnerNeutral => _t('territory_owner_neutral');
  String get diamondMineLabel => _t('diamond_mine_label');
  String get goldMineLabel => _t('gold_mine_label');
  String get forestLabel => _t('forest_label');
  String get strengthLabel => _t('strength_label');

  /// e.g. `strings.diamondMineCaptured(count: '250')`
  String diamondMineCaptured({required String count}) =>
      _t('diamond_mine_captured', p: {'count': count});

  /// e.g. `strings.goldMineCaptured(count: '150')`
  String goldMineCaptured({required String count}) =>
      _t('gold_mine_captured', p: {'count': count});

  // ── HUD ──────────────────────────────────────────────────────────────────
  String get turnLabel => _t('turn_label');
  String get activeArmyLabel => _t('active_army_label');
  String get diamondBalanceLabel => _t('diamond_balance_label');
  String get citiesLabel => _t('cities_label');
  String get tanksLabel => _t('tanks_label');
  String get bombersLabel => _t('bombers_label');
  String get youLabel => _t('you_label');
  String get aiThinking => _t('ai_thinking');

  // ── Shop ─────────────────────────────────────────────────────────────────
  String get shopTitle => _t('shop_title');
  String get shopBuy => _t('shop_buy');
  String get shopReadOnly => _t('shop_read_only');
  String get shopTankDesc => _t('shop_tank_desc');
  String get shopBomberDesc => _t('shop_bomber_desc');
  String get purchased => _t('purchased');

  // ── Armies and players ───────────────────────────────────────────────────
  /// Display name of the army with [index] (0 … 11), e.g. "Mavi Ordu".
  String armyName(int index) => _t('army_${index + 1}_name');
  String get armyNeutral => _t('army_neutral');

  /// e.g. "Oyuncu 2".
  String playerName(int number) => _t('player_name', p: {'n': '$number'});

  /// e.g. `strings.nextPlayer(player: 'Oyuncu 2')`
  String nextPlayer({required String player}) =>
      _t('next_player', p: {'player': player});

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
  String get hintSelectTerritory => _t('hint_select_territory');
  String get hintAttack => _t('hint_attack');
  String get attackWon => _t('attack_won');
  String get attackLost => _t('attack_lost');
  String get attackLostTank => _t('attack_lost_tank');
  String get unitsMoved => _t('units_moved');

  // ── New game ─────────────────────────────────────────────────────────────
  String get botCountTitle => _t('bot_count_title');
  String get playersTitle => _t('players_title');
  String get playersOne => _t('players_one');
  String get playersTwo => _t('players_two');
  String get difficultyTitle => _t('difficulty_title');
  String get difficultyVeryEasy => _t('difficulty_very_easy');
  String get difficultyMedium => _t('difficulty_medium');
  String get difficultyHard => _t('difficulty_hard');
  String get difficultyVeryEasyDesc => _t('difficulty_very_easy_desc');
  String get difficultyMediumDesc => _t('difficulty_medium_desc');
  String get difficultyHardDesc => _t('difficulty_hard_desc');
  String get difficultyLabel => _t('difficulty_label');

  /// Language code of the bound locale (`tr` / `en`), e.g. for city names.
  String get languageCode => _locale.languageCode;

  /// Looks up an arbitrary [key] (e.g. a shop item `nameKey`) with the
  /// standard fallback chain.
  String raw(String key) => _t(key);
}
