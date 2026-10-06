/// Africa map Flame component for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

// ─── MapComponent ─────────────────────────────────────────────────────────────

/// Renders Africa as a normal map — real coastline and country borders —
/// divided into many tiny square tiles ("minik kare"), and turns taps into
/// [GameNotifier.onTerritoryTapped] calls.
///
/// Drawing everything in one component (instead of one component per tile)
/// keeps the frame cheap on phones. Layers, bottom to top:
///   - a light shore band and the countries in earthy colours;
///   - owned tiles in their army colour, clipped to the coastline;
///   - country borders and the coast, then a faint tile grid;
///   - "walls": a dark line in each army's colour along its frontier;
///   - gold bars on the bases (gold mines), cyan diamond-mine markers;
///   - unit counts (only once zoomed in far enough to read them);
///   - selection / neighbour / ability-target frames;
///   - a dashed sea link to Madagascar.
class MapComponent extends PositionComponent
    with TapCallbacks, HasGameReference<WarGame> {
  MapComponent({required this.ref, TerritoryGraph? graph})
    : graph = graph ?? TerritoryGraph.bundled() {
    size = Vector2(this.graph.width, this.graph.height);
    for (final t in this.graph.territories) {
      final p = this.graph.positionOf(t.id);
      _cellToId[_cellKey(p.col, p.row)] = t.id;
    }
    _buildStaticLayers();
  }

  /// Riverpod widget reference used to read game state and send taps.
  final WidgetRef ref;

  /// Static map layout (tile grid, regions, adjacency, outlines).
  final TerritoryGraph graph;

  final Map<int, int> _cellToId = {};
  final Path _land = Path();
  final Path _grid = Path();
  final Map<String, Path> _countries = {};
  final List<(Offset, Offset)> _seaLinks = [];

  static int _cellKey(int col, int row) => row * 1000 + col;

  /// Unit counts are drawn only when a tile is at least this many screen
  /// pixels wide.
  static const double minReadableTilePx = 15;

  // ─── Paints ────────────────────────────────────────────────────────────────

  static final List<Paint> _armyPaints = [
    for (final c in AppTheme.armyPrimaries) Paint()..color = c.withAlpha(230),
  ];
  static final List<Paint> _wallPaints = [
    for (final c in AppTheme.armyPrimaries)
      Paint()
        ..color = Color.lerp(c, const Color(0xFF000000), 0.5)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.square,
  ];
  static final Paint _goldDark = Paint()..color = const Color(0xFF8D6E00);
  static final Paint _goldShine = Paint()..color = const Color(0xFFFFF59D);
  static final Paint _shorePaint = Paint()
    ..color = const Color(0xFFB3E5FC)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeJoin = StrokeJoin.round;
  static final Paint _gridPaint = Paint()
    ..color = const Color(0x1F000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  static final Paint _borderHalo = Paint()
    ..color = const Color(0x99FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round;
  static final Paint _borderPaint = Paint()
    ..color = const Color(0xB34E342E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..strokeJoin = StrokeJoin.round;
  static final Paint _seaLinkPaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _selectedPaint = Paint()
    ..color = const Color(0xFFFFD600)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final Paint _neighbourPaint = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _abilityTargetPaint = Paint()
    ..color = const Color(0xFFFF6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;
  static final Paint _baseFill = Paint()..color = const Color(0xFFFFC107);
  static final Paint _markerStroke = Paint()
    ..color = const Color(0xFF263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _mineFill = Paint()..color = AppTheme.kDiamond;
  static final Paint _mineShine = Paint()..color = const Color(0xFFE0F7FA);

  static final TextPaint _lightText = TextPaint(
    style: const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    ),
  );
  static final TextPaint _darkText = TextPaint(
    style: const TextStyle(
      color: Color(0xFF3E2723),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    ),
  );

  /// Earthy palette for neutral land, one colour per country.
  static const List<Color> _landPalette = [
    Color(0xFFE6D3A3),
    Color(0xFFD9C27E),
    Color(0xFFC9D79C),
    Color(0xFFE8C39E),
    Color(0xFFB9CF8E),
    Color(0xFFDCC9A0),
    Color(0xFFD4B483),
    Color(0xFFC5DDA8),
  ];
  final Map<String, Paint> _countryPaints = {};

  // ─── Static layers ─────────────────────────────────────────────────────────

  void _buildStaticLayers() {
    final keys = graph.outlines.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final path = Path();
      for (final ring in graph.outlines[keys[i]]!) {
        path.addPolygon(ring, true);
        _land.addPolygon(ring, true);
      }
      _countries[keys[i]] = path;
      _countryPaints[keys[i]] = Paint()
        ..color = _landPalette[i % _landPalette.length];
    }

    final s = graph.tileSize;
    for (final t in graph.territories) {
      final p = graph.positionOf(t.id);
      final x = p.col * s;
      final y = p.row * s;
      // Right and bottom edges; neighbours draw the others.
      _grid
        ..moveTo(x + s, y)
        ..lineTo(x + s, y + s)
        ..moveTo(x, y + s)
        ..lineTo(x + s, y + s);
      if (!_cellToId.containsKey(_cellKey(p.col - 1, p.row))) {
        _grid
          ..moveTo(x, y)
          ..lineTo(x, y + s);
      }
      if (!_cellToId.containsKey(_cellKey(p.col, p.row - 1))) {
        _grid
          ..moveTo(x, y)
          ..lineTo(x + s, y);
      }
      for (final adj in t.adjacentIds) {
        if (adj > t.id && graph.isSeaLink(t.id, adj)) {
          _seaLinks.add((p.offset, graph.positionOf(adj).offset));
        }
      }
    }
  }

  // ─── Rendering ─────────────────────────────────────────────────────────────

  Rect _tileRect(int id) {
    final p = graph.positionOf(id);
    final s = graph.tileSize;
    return Rect.fromLTWH(p.col * s, p.row * s, s, s);
  }

  @override
  void render(Canvas canvas) {
    final state = ref.read(gameProvider);
    final selectedId = ref.read(selectedTerritoryProvider);
    final armed = ref.read(armedAbilityProvider);
    final territories = state.territories;

    // Zoom level and visible area (both unknown before the game mounts).
    var tilePx = 0.0;
    Rect? visible;
    if (isMounted) {
      tilePx = graph.tileSize * game.camera.viewfinder.zoom;
      visible = game.camera.visibleWorldRect.inflate(graph.tileSize);
    }

    // ── Land ────────────────────────────────────────────────────────────
    canvas.drawPath(_land, _shorePaint);
    _countries.forEach((key, path) {
      canvas.drawPath(path, _countryPaints[key]!);
    });

    // Country borders lie under the armies, whose walls mark their land.
    _countries.forEach((_, path) => canvas.drawPath(path, _borderHalo));
    _countries.forEach((_, path) => canvas.drawPath(path, _borderPaint));

    canvas
      ..save()
      ..clipPath(_land);
    for (final t in territories) {
      final owner = t.ownerArmyId;
      if (owner == null) continue;
      canvas.drawRect(_tileRect(t.id), _armyPaints[owner.index]);
    }
    canvas.drawPath(_grid, _gridPaint);
    _drawWalls(canvas, territories);
    canvas.restore();
    for (final (a, b) in _seaLinks) {
      _drawDashed(canvas, a, b);
    }

    // ── Markers, numbers, frames ────────────────────────────────────────
    Territory? selected;
    if (selectedId != null && selectedId < territories.length) {
      selected = territories[selectedId];
    }
    final showNumbers = tilePx >= minReadableTilePx;
    final targeting = armed != null && armed != AbilityType.soldierSpell;

    for (final t in territories) {
      final rect = _tileRect(t.id);
      if (visible != null && !visible.overlaps(rect)) continue;

      if (t.hasGoldMine) {
        _drawGold(canvas, rect, big: t.type == TerritoryType.bigBase);
      }
      if (t.hasDiamondMine) _drawMine(canvas, rect);

      if (showNumbers && t.unitCount > 0) {
        (t.ownerArmyId == null ? _darkText : _lightText).render(
          canvas,
          '${t.unitCount}',
          Vector2(rect.center.dx, rect.center.dy + 1),
          anchor: Anchor.center,
        );
      }

      if (targeting &&
          t.ownerArmyId != ArmyId.army1 &&
          t.adjacentIds.any(
            (id) => territories[id].ownerArmyId == ArmyId.army1,
          )) {
        canvas.drawRect(rect.deflate(2), _abilityTargetPaint);
      } else if (selected != null && selected.adjacentIds.contains(t.id)) {
        canvas.drawRect(rect.deflate(1.5), _neighbourPaint);
      }
    }

    if (selected != null) {
      canvas.drawRect(_tileRect(selected.id).deflate(1), _selectedPaint);
    }
  }

  /// Frontier "walls": along every tile edge between different owners, a
  /// dark line in the colour of each army that owns a side, drawn just
  /// inside its own tile so neighbouring armies' walls sit side by side.
  void _drawWalls(Canvas canvas, List<Territory> territories) {
    final s = graph.tileSize;
    const inset = 1.3;
    final paths = <int, Path>{};
    void wall(ArmyId? owner, Offset a, Offset b) {
      if (owner == null) return;
      final path = paths.putIfAbsent(owner.index, Path.new);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }

    for (final t in territories) {
      final p = graph.positionOf(t.id);
      final x = p.col * s;
      final y = p.row * s;
      final right = _cellToId[_cellKey(p.col + 1, p.row)];
      final below = _cellToId[_cellKey(p.col, p.row + 1)];
      final left = _cellToId[_cellKey(p.col - 1, p.row)];
      final above = _cellToId[_cellKey(p.col, p.row - 1)];
      final o = t.ownerArmyId;
      if (o == null) continue;
      if (right == null || territories[right].ownerArmyId != o) {
        wall(o, Offset(x + s - inset, y), Offset(x + s - inset, y + s));
      }
      if (below == null || territories[below].ownerArmyId != o) {
        wall(o, Offset(x, y + s - inset), Offset(x + s, y + s - inset));
      }
      if (left == null || territories[left].ownerArmyId != o) {
        wall(o, Offset(x + inset, y), Offset(x + inset, y + s));
      }
      if (above == null || territories[above].ownerArmyId != o) {
        wall(o, Offset(x, y + inset), Offset(x + s, y + inset));
      }
    }
    paths.forEach((i, path) => canvas.drawPath(path, _wallPaints[i]));
  }

  /// Gold bars (a gold mine) in the top-left corner of [rect]; two bars on
  /// a big base.
  void _drawGold(Canvas canvas, Rect rect, {required bool big}) {
    final w = rect.width * (big ? 0.5 : 0.56);
    final h = w * 0.42;
    void bar(Offset topLeft) {
      final r = Rect.fromLTWH(topLeft.dx, topLeft.dy, w, h);
      final shape = Path()
        ..moveTo(r.left + w * 0.18, r.top)
        ..lineTo(r.right - w * 0.18, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..close();
      canvas
        ..drawPath(shape, _goldDark)
        ..drawPath(shape.shift(const Offset(0, -0.8)), _baseFill)
        ..drawRect(
          Rect.fromLTWH(r.left + w * 0.25, r.top + h * 0.15, w * 0.3, h * 0.2),
          _goldShine,
        )
        ..drawPath(shape, _markerStroke);
    }

    final origin = Offset(rect.left + 1.5, rect.top + 2.5);
    if (big) {
      bar(origin.translate(0, h * 0.9));
      bar(origin.translate(w * 0.5, h * 0.9));
      bar(origin.translate(w * 0.25, 0));
    } else {
      bar(origin);
    }
  }

  /// A small cut-diamond marker in the top-right corner of [rect].
  void _drawMine(Canvas canvas, Rect rect) {
    final w = rect.width * 0.36;
    final cx = rect.right - w / 2 - 1.5;
    final top = rect.top + 2.0;
    final gem = Path()
      ..moveTo(cx - w / 2, top + w * 0.3)
      ..lineTo(cx - w * 0.25, top)
      ..lineTo(cx + w * 0.25, top)
      ..lineTo(cx + w / 2, top + w * 0.3)
      ..lineTo(cx, top + w)
      ..close();
    canvas
      ..drawPath(gem, _mineFill)
      ..drawRect(
        Rect.fromLTWH(cx - w * 0.2, top + w * 0.08, w * 0.15, w * 0.15),
        _mineShine,
      )
      ..drawPath(gem, _markerStroke);
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b) {
    const dash = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      final end = d + dash < total ? d + dash : total;
      canvas.drawLine(a + dir * d, a + dir * end, _seaLinkPaint);
    }
  }

  // ─── Tap handling ──────────────────────────────────────────────────────────

  /// Returns the tile id under [local] (map coordinates), or `null` for sea.
  int? tileAt(Vector2 local) {
    if (local.x < 0 || local.y < 0) return null;
    final col = local.x ~/ graph.tileSize;
    final row = local.y ~/ graph.tileSize;
    return _cellToId[_cellKey(col, row)];
  }

  @override
  void onTapUp(TapUpEvent event) {
    final id = tileAt(event.localPosition);
    if (id == null) return;
    // Select / attack / move / deploy / fire armed ability, depending on
    // the current selection (see GameNotifier.onTerritoryTapped).
    ref.read(gameProvider.notifier).onTerritoryTapped(id);
  }
}
