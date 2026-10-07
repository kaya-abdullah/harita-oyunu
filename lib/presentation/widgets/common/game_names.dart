/// Display names, icons and 3D unit glyphs shared by the game widgets.
library;

import 'package:flutter/material.dart';

import 'package:harita/core/localization/app_localizations.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/game/components/unit_painters.dart';

/// Localised name of a card.
String abilityDisplayName(AbilityType type, AppStrings strings) =>
    switch (type) {
      AbilityType.fireBomb => strings.abilityFireBomb,
      AbilityType.bombardment => strings.abilityBombardment,
      AbilityType.soldierSpell => strings.abilitySoldierSpell,
      AbilityType.megaBomba => strings.abilityMegaBomba,
      AbilityType.atomBomb => strings.abilityAtomBomb,
      AbilityType.nuclearBomb => strings.abilityNuclearBomb,
      AbilityType.tribute => strings.abilityTribute,
    };

/// What a card does, in one sentence.
String abilityTooltip(AbilityType type, AppStrings strings) => switch (type) {
  AbilityType.fireBomb => strings.tooltipFireBomb,
  AbilityType.bombardment => strings.tooltipBombardment,
  AbilityType.soldierSpell => strings.tooltipSoldierSpell,
  AbilityType.megaBomba => strings.tooltipMegaBomba,
  AbilityType.atomBomb => strings.tooltipAtomBomb,
  AbilityType.nuclearBomb => strings.tooltipNuclearBomb,
  AbilityType.tribute => strings.tooltipTribute,
};

/// Icon of a card.
IconData abilityIcon(AbilityType type) => switch (type) {
  AbilityType.fireBomb => Icons.local_fire_department_rounded,
  AbilityType.bombardment => Icons.flare_rounded,
  AbilityType.soldierSpell => Icons.groups_rounded,
  AbilityType.megaBomba => Icons.brightness_7_rounded,
  AbilityType.atomBomb => Icons.blur_on_rounded,
  AbilityType.nuclearBomb => Icons.dangerous_rounded,
  AbilityType.tribute => Icons.payments_rounded,
};

/// Name of army [id] in [state]: "Sen" for the only human, "Oyuncu 1/2"
/// when two people play, otherwise the army's colour name.
String armyDisplayName(GameState state, ArmyId id, AppStrings strings) {
  final humans = state.humanIds;
  if (humans.contains(id)) {
    return humans.length == 1
        ? strings.youLabel
        : strings.playerName(humans.indexOf(id) + 1);
  }
  return strings.armyName(id.index);
}

/// The kinds of 3D unit glyphs.
enum UnitGlyphKind { soldier, tank, bomber }

/// A small 3D-looking soldier, tank or bomber for the HUD and the shop.
class UnitGlyph extends StatelessWidget {
  const UnitGlyph({
    super.key,
    required this.kind,
    required this.color,
    this.size = 28,
  });

  /// Which unit.
  final UnitGlyphKind kind;

  /// Army colour.
  final Color color;

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _UnitGlyphPainter(kind, color)),
  );
}

class _UnitGlyphPainter extends CustomPainter {
  _UnitGlyphPainter(this.kind, this.color);

  final UnitGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    switch (kind) {
      case UnitGlyphKind.soldier:
        drawSoldier(canvas, c.translate(0, s * 0.45), s * 0.9, color);
      case UnitGlyphKind.tank:
        drawTank(canvas, c.translate(0, s * 0.05), s * 0.85, color);
      case UnitGlyphKind.bomber:
        drawBomber(
          canvas,
          c.translate(-s * 0.05, -s * 0.05),
          s * 0.9,
          color,
          angle: -0.6,
          altitude: 0.12,
        );
    }
  }

  @override
  bool shouldRepaint(_UnitGlyphPainter old) =>
      old.kind != kind || old.color != color;
}
