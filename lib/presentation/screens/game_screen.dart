/// Game screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Implements a responsive layout that switches between a stacked portrait
/// phone layout and a side-panel layout (tablets and landscape phones).
///
/// Also owns the screen-level reactions to game events:
///  - [gameFeedbackProvider] → localized SnackBar + sound effect;
///  - victory → fanfare + [VictoryScreen] (Requirement 9.2);
///  - Android back / home button → save and return to [MainMenuScreen].
///
/// Requirements: 1.2, 1.3, 1.4, 9.2, 10.5, 11.4
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/core/constants.dart';
import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/presentation/screens/main_menu_screen.dart';
import 'package:harita/presentation/screens/victory_screen.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';
import 'package:harita/presentation/viewmodels/locale_viewmodel.dart';
import 'package:harita/presentation/viewmodels/shop_viewmodel.dart';
import 'package:harita/presentation/widgets/common/game_snack.dart';
import 'package:harita/presentation/widgets/hud/ability_panel.dart';
import 'package:harita/presentation/widgets/hud/resource_bar.dart';
import 'package:harita/presentation/widgets/hud/turn_indicator.dart';
import 'package:harita/presentation/widgets/map/territory_info_panel.dart';
import 'package:harita/presentation/widgets/shop/weapon_shop_dialog.dart';

// ─── GameScreen ───────────────────────────────────────────────────────────────

/// Root game screen hosting the Flame canvas and all HUD widgets.
///
/// Uses [ConsumerStatefulWidget] so the [WarGame] instance is created once in
/// [initState] and preserved across rebuilds — creating it inline in [build]
/// would restart the Flame game on every state change.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final WarGame _warGame;

  /// Guards against navigating away twice (e.g. victory + back press).
  bool _leaving = false;

  /// Last ability the player armed — used to name it in the "used" message.
  AbilityType? _lastArmed;

  @override
  void initState() {
    super.initState();
    _warGame = WarGame(ref: ref);
    // A resumed save may already be finished — go straight to the result.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(isVictoryProvider)) _goToVictory();
    });
  }

  AppStrings? get _strings {
    final service = ref.read(localeServiceProvider).value;
    return service?.of(ref.read(localeProvider));
  }

  AudioService get _audio => ref.read(audioServiceProvider);

  // ─── Navigation ──────────────────────────────────────────────────────────

  void _goToVictory() {
    if (_leaving) return;
    _leaving = true;
    _audio.playSfx(AudioService.sfxVictory);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const VictoryScreen()),
    );
  }

  Future<void> _goToMenu() async {
    if (_leaving) return;
    _leaving = true;
    _audio.playSfx(AudioService.sfxButtonTap);
    ref.read(armedAbilityProvider.notifier).set(null);
    await ref.read(gameProvider.notifier).saveGame();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainMenuScreen()),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  void _endTurn() {
    _audio.playSfx(AudioService.sfxTurnEnd);
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    ref.read(gameProvider.notifier).endTurn();
  }

  void _openShop() {
    _audio.playSfx(AudioService.sfxButtonTap);
    // The human always plays Army 1; during the AI turn the shop opens in
    // read-only mode (Requirement 7.5).
    ref.read(shopProvider.notifier).openShop(ArmyId.army1);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WeaponShopDialog(),
    ).whenComplete(() {
      if (mounted) ref.read(shopProvider.notifier).closeShop();
    });
  }

  // ─── Feedback ────────────────────────────────────────────────────────────

  void _showFeedback(GameFeedback fb) {
    final t = _strings;
    if (t == null || !mounted) return;
    final v = fb.value;
    String msg;
    IconData icon;
    Color? color;
    switch (fb.kind) {
      case GameFeedbackKind.abilityLocked:
        msg = v != null && v > 0
            ? '${t.errorAbilityLocked} ${t.abilityLocked(turn: '$v')}'
            : t.errorAbilityLocked;
        icon = Icons.lock_rounded;
      case GameFeedbackKind.abilityCooldown:
        msg = t.errorCooldownActive(turns: '${v ?? 0}');
        icon = Icons.timer_rounded;
      case GameFeedbackKind.invalidAbilityTarget:
        msg = t.errorInvalidTarget;
        icon = Icons.block_rounded;
      case GameFeedbackKind.abilityArmed:
        final armed = ref.read(armedAbilityProvider);
        final name = armed == null ? '' : abilityDisplayName(armed, t);
        msg = t.abilitySelectTarget(ability: name);
        icon = Icons.my_location_rounded;
      case GameFeedbackKind.abilityUsed:
        _audio.playSfx(AudioService.sfxAbility);
        final used = _lastArmed;
        msg = t.abilityUsed(
          ability: used == null ? '' : abilityDisplayName(used, t),
        );
        icon = used == null ? Icons.bolt_rounded : abilityIcon(used);
      case GameFeedbackKind.invalidAttack:
        msg = t.errorInvalidAttack;
        icon = Icons.block_rounded;
      case GameFeedbackKind.territoryConquered:
        _audio.playSfx(AudioService.sfxAttack);
        msg = t.attackWon;
        icon = Icons.flag_rounded;
      case GameFeedbackKind.diamondMineCaptured:
        _audio.playSfx(AudioService.sfxDiamond);
        msg = t.diamondMineCaptured(count: '${v ?? 0}');
        icon = Icons.diamond_rounded;
        color = AppTheme.kDiamond;
      case GameFeedbackKind.goldMineCaptured:
        _audio.playSfx(AudioService.sfxGold);
        msg = t.goldMineCaptured(count: '${v ?? 0}');
        icon = Icons.paid_rounded;
        color = AppTheme.kGold;
      case GameFeedbackKind.attackRepelled:
        _audio.playSfx(AudioService.sfxAttack);
        msg = t.attackLost;
        icon = Icons.shield_rounded;
      case GameFeedbackKind.unitsMoved:
        msg = t.unitsMoved;
        icon = Icons.directions_walk_rounded;
      case GameFeedbackKind.unitsDeployed:
        msg = t.unitsDeployed(count: '${v ?? 0}');
        icon = Icons.groups_rounded;
      case GameFeedbackKind.cannotDeploy:
        msg = t.cannotDeploy;
        icon = Icons.block_rounded;
      case GameFeedbackKind.notYourTurn:
        msg = t.errorNotYourTurn;
        icon = Icons.hourglass_top_rounded;
      case GameFeedbackKind.insufficientDiamonds:
        msg = t.errorInsufficientDiamonds;
        icon = Icons.diamond_outlined;
    }
    showGameSnack(context, msg, icon: icon, color: color);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isVictoryProvider, (prev, next) {
      if (next && prev != true) _goToVictory();
    });
    ref.listen<AbilityType?>(armedAbilityProvider, (_, next) {
      if (next != null) _lastArmed = next;
    });
    ref.listen<GameFeedback?>(gameFeedbackProvider, (_, next) {
      if (next != null) _showFeedback(next);
    });

    final actions = _ActionButtonRow(
      onEndTurn: _endTurn,
      onShop: _openShop,
      onHome: _goToMenu,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToMenu();
      },
      child: Scaffold(
        backgroundColor: AppTheme.kBackground,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final useSidePanel =
                  constraints.maxWidth >= kPhoneBreakpoint ||
                  constraints.maxWidth > constraints.maxHeight;
              return useSidePanel
                  ? _SidePanelLayout(game: _warGame, actions: actions)
                  : _PortraitLayout(game: _warGame, actions: actions);
            },
          ),
        ),
      ),
    );
  }
}

// ─── _PortraitLayout ──────────────────────────────────────────────────────────

/// Portrait phone layout (width < 600 dp and taller than wide).
///
/// Structure (top → bottom): turn + resources, map canvas, abilities,
/// action buttons, scrollable territory info.
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({required this.game, required this.actions});

  final WarGame game;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TurnIndicator(),
        const ResourceBar(),
        Expanded(
          flex: 5,
          child: ClipRect(child: GameWidget(game: game)),
        ),
        const AbilityPanel(),
        actions,
        const Flexible(
          flex: 2,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TerritoryInfoPanel(),
          ),
        ),
      ],
    );
  }
}

// ─── _SidePanelLayout ─────────────────────────────────────────────────────────

/// Tablet / landscape layout: map on the left, scrollable HUD panel on the
/// right so nothing overflows on short landscape phone screens.
class _SidePanelLayout extends StatelessWidget {
  const _SidePanelLayout({required this.game, required this.actions});

  final WarGame game;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        Expanded(
          child: ClipRect(child: GameWidget(game: game)),
        ),
        SizedBox(
          width: width >= 900 ? 340 : 300,
          child: ColoredBox(
            color: AppTheme.kBackground,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TurnIndicator(),
                  const ResourceBar(),
                  const AbilityPanel(),
                  actions,
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: TerritoryInfoPanel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── _ActionButtonRow ─────────────────────────────────────────────────────────

/// Home, "End Turn" and "Shop" action buttons.
///
/// Both main buttons use [ElevatedButton.icon] with font size >= 16 sp
/// (Req 11.1) and high-contrast colour pairs from [AppTheme] (Req 11.2).
/// End Turn is disabled while the AI opponent is playing.
class _ActionButtonRow extends ConsumerWidget {
  const _ActionButtonRow({
    required this.onEndTurn,
    required this.onShop,
    required this.onHome,
  });

  final VoidCallback onEndTurn;
  final VoidCallback onShop;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);
    final gameState = ref.watch(gameProvider);
    final isPlayerTurn =
        gameState.activeArmyId == ArmyId.army1 &&
        gameState.phase == GamePhase.playing;

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Home / main menu
              IconButton.filledTonal(
                onPressed: onHome,
                tooltip: strings.btnMainMenu,
                icon: const Icon(Icons.home_rounded, size: 26),
              ),
              const SizedBox(width: 6),

              // End Turn button
              Expanded(
                child: _HudButton(
                  icon: Icons.skip_next_rounded,
                  label: strings.btnEndTurn,
                  color: AppTheme.army1Primary,
                  onPressed: isPlayerTurn ? onEndTurn : null,
                ),
              ),
              const SizedBox(width: 8),

              // Shop button
              Expanded(
                child: _HudButton(
                  icon: Icons.storefront_outlined,
                  label: strings.btnShop,
                  color: AppTheme.kAccentGreen,
                  onPressed: onShop,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppTheme.kTextLight,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
    );
  }
}
