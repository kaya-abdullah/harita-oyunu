/// The game screen of Harita: Kendi İmparatorluğunu Kur.
///
/// The map with the Weapon Shop always open beside it, the HUD (turn,
/// diamonds, tanks, bombers, armies), the player's cards, the action
/// buttons (Kart Çek, Saldır, Uçak, Turu Bitir) and the city panel.
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
import 'package:harita/presentation/widgets/common/game_names.dart';
import 'package:harita/presentation/widgets/common/game_snack.dart';
import 'package:harita/presentation/widgets/hud/ability_panel.dart';
import 'package:harita/presentation/widgets/hud/resource_bar.dart';
import 'package:harita/presentation/widgets/hud/turn_indicator.dart';
import 'package:harita/presentation/widgets/map/territory_info_panel.dart';
import 'package:harita/presentation/widgets/shop/weapon_shop_panel.dart';

// ─── GameScreen ───────────────────────────────────────────────────────────────

/// The screen a game is played on.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final WarGame _warGame;

  bool _leaving = false;

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
    ref.read(armedToolProvider.notifier).set(null);
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

  void _drawCard() {
    _audio.playSfx(AudioService.sfxButtonTap);
    ref.read(gameProvider.notifier).drawCard();
  }

  void _attack() {
    _audio.playSfx(AudioService.sfxButtonTap);
    ref.read(gameProvider.notifier).showAttackHint();
  }

  void _bomber() {
    _audio.playSfx(AudioService.sfxButtonTap);
    ref.read(gameProvider.notifier).armBomber();
  }

  // ─── Feedback ────────────────────────────────────────────────────────────

  void _showFeedback(GameFeedback fb) {
    final t = _strings;
    if (t == null || !mounted) return;
    final v = fb.value;
    String msg;
    IconData icon;
    Color? color;
    String cardName(int? index) =>
        index == null ? '' : abilityDisplayName(AbilityType.values[index], t);
    switch (fb.kind) {
      case GameFeedbackKind.noCard:
        msg = t.errorNoCard;
        icon = Icons.style_rounded;
      case GameFeedbackKind.invalidAbilityTarget:
        msg = t.errorInvalidTarget;
        icon = Icons.block_rounded;
      case GameFeedbackKind.abilityArmed:
        final armed = ref.read(armedToolProvider);
        msg = t.abilitySelectTarget(
          ability: armed is ArmedCard ? abilityDisplayName(armed.type, t) : '',
        );
        icon = Icons.my_location_rounded;
      case GameFeedbackKind.abilityUsed:
        final type = v == null ? _lastArmed : AbilityType.values[v];
        _audio.playSfx(
          type == AbilityType.atomBomb || type == AbilityType.nuclearBomb
              ? AudioService.sfxNuke
              : AudioService.sfxAbility,
        );
        msg = t.abilityUsed(
          ability: type == null ? '' : abilityDisplayName(type, t),
        );
        icon = type == null ? Icons.bolt_rounded : abilityIcon(type);
      case GameFeedbackKind.cardDrawn:
        _audio.playSfx(AudioService.sfxAbility);
        msg = t.cardDrawn(card: cardName(v));
        icon = v == null
            ? Icons.style_rounded
            : abilityIcon(AbilityType.values[v]);
        color = v == null ? null : AppTheme.abilityColor(AbilityType.values[v]);
      case GameFeedbackKind.cardAlreadyDrawn:
        msg = t.cardAlreadyDrawn;
        icon = Icons.style_rounded;
      case GameFeedbackKind.bomberArmed:
        msg = t.bomberArmed;
        icon = Icons.flight_rounded;
      case GameFeedbackKind.bomberHit:
        _audio.playSfx(AudioService.sfxAttack);
        msg = t.bomberHit(count: '${v ?? 0}');
        icon = Icons.flight_rounded;
      case GameFeedbackKind.noBomber:
        msg = t.noBomber;
        icon = Icons.airplanemode_inactive_rounded;
      case GameFeedbackKind.invalidBomberTarget:
        msg = t.invalidBomberTarget;
        icon = Icons.block_rounded;
      case GameFeedbackKind.attackHint:
        msg = t.hintAttack;
        icon = Icons.pan_tool_alt_rounded;
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
        msg = v == 1 ? t.attackLostTank : t.attackLost;
        icon = Icons.shield_rounded;
      case GameFeedbackKind.unitsMoved:
        msg = t.unitsMoved;
        icon = Icons.directions_walk_rounded;
      case GameFeedbackKind.tributeTaken:
        _audio.playSfx(AudioService.sfxGold);
        msg = t.tributeTaken(count: '${v ?? 0}');
        icon = Icons.payments_rounded;
        color = AppTheme.kGold;
      case GameFeedbackKind.notYourTurn:
        msg = t.errorNotYourTurn;
        icon = Icons.hourglass_top_rounded;
      case GameFeedbackKind.insufficientDiamonds:
        msg = t.errorInsufficientDiamonds;
        icon = Icons.diamond_outlined;
      case GameFeedbackKind.purchased:
        _audio.playSfx(AudioService.sfxGold);
        msg = t.purchased;
        icon = Icons.shopping_bag_rounded;
      case GameFeedbackKind.nextPlayer:
        final state = ref.read(gameProvider);
        final id = ArmyId.values[v ?? 0];
        msg = t.nextPlayer(player: armyDisplayName(state, id, t));
        icon = Icons.swap_horiz_rounded;
        color = AppTheme.armyColor(id);
        _warGame.focusOnViewer();
    }
    showGameSnack(context, msg, icon: icon, color: color);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isVictoryProvider, (prev, next) {
      if (next && prev != true) _goToVictory();
    });
    ref.listen<ArmedTool?>(armedToolProvider, (_, next) {
      if (next is ArmedCard) _lastArmed = next.type;
    });
    ref.listen<GameFeedback?>(gameFeedbackProvider, (_, next) {
      if (next != null) _showFeedback(next);
    });

    final actions = _ActionButtonRow(
      onEndTurn: _endTurn,
      onDrawCard: _drawCard,
      onAttack: _attack,
      onBomber: _bomber,
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
          child: Row(
            children: [
              Expanded(
                child: ClipRect(child: GameWidget(game: game)),
              ),
              const SizedBox(width: 96, child: WeaponShopPanel(compact: true)),
            ],
          ),
        ),
        const AbilityPanel(),
        actions,
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.24,
          ),
          child: const SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: TerritoryInfoPanel(),
          ),
        ),
      ],
    );
  }
}

// ─── _SidePanelLayout ─────────────────────────────────────────────────────────

class _SidePanelLayout extends StatelessWidget {
  const _SidePanelLayout({required this.game, required this.actions});

  final WarGame game;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRect(child: GameWidget(game: game)),
        ),
        SizedBox(
          width: wide ? 230 : 104,
          child: WeaponShopPanel(compact: !wide),
        ),
        SizedBox(
          width: wide ? 340 : 300,
          child: ColoredBox(
            color: AppTheme.kBackground,
            child: SingleChildScrollView(
              primary: false,
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

class _ActionButtonRow extends ConsumerWidget {
  const _ActionButtonRow({
    required this.onEndTurn,
    required this.onDrawCard,
    required this.onAttack,
    required this.onBomber,
    required this.onHome,
  });

  final VoidCallback onEndTurn;
  final VoidCallback onDrawCard;
  final VoidCallback onAttack;
  final VoidCallback onBomber;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localeServiceAsync = ref.watch(localeServiceProvider);
    final state = ref.watch(gameProvider);
    final armed = ref.watch(armedToolProvider);
    final humanPlays =
        state.activeArmy.isHuman && state.phase == GamePhase.playing;
    final army = state.activeArmy;

    return localeServiceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (localeService) {
        final strings = localeService.of(locale);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: onHome,
                tooltip: strings.btnMainMenu,
                icon: const Icon(Icons.home_rounded, size: 24),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _HudButton(
                  key: const Key('btn_draw_card'),
                  icon: Icons.style_rounded,
                  label: strings.btnDrawCard,
                  color: AppTheme.kAccentPurple,
                  onPressed: humanPlays && !army.hasDrawnCard
                      ? onDrawCard
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _HudButton(
                  key: const Key('btn_attack'),
                  icon: Icons.pan_tool_alt_rounded,
                  label: strings.btnAttack,
                  color: AppTheme.army2Primary,
                  onPressed: humanPlays ? onAttack : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _HudButton(
                  key: const Key('btn_bomber'),
                  icon: Icons.flight_rounded,
                  label: '${strings.btnBomber} ${army.bombersReady}',
                  color: const Color(0xFF455A64),
                  highlighted: armed is ArmedBomber,
                  onPressed: humanPlays && army.bombersReady > 0
                      ? onBomber
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _HudButton(
                  key: const Key('btn_end_turn'),
                  icon: Icons.skip_next_rounded,
                  label: strings.btnEndTurn,
                  color: AppTheme.army1Primary,
                  onPressed: humanPlays ? onEndTurn : null,
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
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppTheme.kTextLight,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: highlighted
              ? const BorderSide(color: AppTheme.kWarning, width: 3)
              : BorderSide.none,
        ),
        elevation: 3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
