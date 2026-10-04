/// Africa tile-map Flame component for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

// ─── MapComponent ─────────────────────────────────────────────────────────────

/// Renders the whole Africa map as a grid of small square tiles ("minik
/// kare") and turns taps into [GameNotifier.onTerritoryTapped] calls.
///
/// Drawing all tiles in one component (instead of one component per tile)
/// keeps the frame cheap on phones. Visuals:
///   - neutral land: an earthy colour per country, owned land: army colour;
///   - thin dark lines along country borders, a thicker coastline;
///   - gold markers on bases (bigger for big bases);
///   - unit counts on occupied tiles;
///   - yellow ring on the selection, white rings on its neighbours, orange
///     rings on valid targets while an attack ability is armed;
///   - a dashed sea link to Madagascar.
class MapComponent extends PositionComponent with TapCallbacks {
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

  /// Static map layout (tile grid, regions, adjacency).
  final TerritoryGraph graph;

  final Map<int, int> _cellToId = {};
  final Path _grid = Path();
  final Path _borders = Path();
  final Path _coast = Path();
  final List<(Offset, Offset)> _seaLinks = [];
  final Map<String, Paint> _regionPaints = {};

  static int _cellKey(int col, int row) => row * 1000 + col;

  // ─── Paints ────────────────────────────────────────────────────────────────

  static final Paint _army1Paint = Paint()..color = const Color(0xFF1E88E5);
  static final Paint _army2Paint = Paint()..color = const Color(0xFFE53935);
  static final Paint _gridPaint = Paint()
    ..color = const Color(0x33000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final Paint _borderPaint = Paint()
    ..color = const Color(0xB33E2723)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  static final Paint _coastPaint = Paint()
    ..color = const Color(0xFF3E2723)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;
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
  static final Paint _baseStroke = Paint()
    ..color = const Color(0xFF4E3507)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

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

  /// Earthy pastel palette for neutral land, one colour per country.
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

  // ─── Static layers ─────────────────────────────────────────────────────────

  void _buildStaticLayers() {
    final s = graph.tileSize;
    final regions = <String>[];
    for (final t in graph.territories) {
      if (!regions.contains(t.name)) regions.add(t.name);
    }
    for (var i = 0; i < regions.length; i++) {
      _regionPaints[regions[i]] = Paint()
        ..color = _landPalette[i % _landPalette.length];
    }

    for (final t in graph.territories) {
      final p = graph.positionOf(t.id);
      final x = p.col * s;
      final y = p.row * s;
      // Right / bottom / left / top edges.
      final edges = [
        (p.col + 1, p.row, Offset(x + s, y), Offset(x + s, y + s)),
        (p.col, p.row + 1, Offset(x, y + s), Offset(x + s, y + s)),
        (p.col - 1, p.row, Offset(x, y), Offset(x, y + s)),
        (p.col, p.row - 1, Offset(x, y), Offset(x + s, y)),
      ];
      for (final (c, r, a, b) in edges) {
        final otherId = _cellToId[_cellKey(c, r)];
        if (otherId == null) {
          _coast
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy);
        } else if (otherId > t.id) {
          (graph.getById(otherId).name != t.name ? _borders : _grid)
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy);
        }
      }
      for (final adj in t.adjacentIds) {
        if (adj > t.id && graph.isSeaLink(t.id, adj)) {
          _seaLinks.add((p.offset, graph.positionOf(adj).offset));
        }
      }
    }
  }

  // ─── Rendering ─────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final state = ref.read(gameProvider);
    final selectedId = ref.read(selectedTerritoryProvider);
    final armed = ref.read(armedAbilityProvider);
    final s = graph.tileSize;
    final territories = state.territories;

    for (final (a, b) in _seaLinks) {
      _drawDashed(canvas, a, b);
    }

    Territory? selected;
    if (selectedId != null && selectedId < territories.length) {
      selected = territories[selectedId];
    }

    for (final t in territories) {
      final p = graph.positionOf(t.id);
      final rect = Rect.fromLTWH(p.col * s, p.row * s, s, s);
      final fill = switch (t.ownerArmyId) {
        ArmyId.army1 => _army1Paint,
        ArmyId.army2 => _army2Paint,
        null => _regionPaints[t.name] ?? _regionPaints.values.first,
      };
      canvas.drawRect(rect, fill);
    }

    canvas
      ..drawPath(_grid, _gridPaint)
      ..drawPath(_borders, _borderPaint)
      ..drawPath(_coast, _coastPaint);

    for (final t in territories) {
      final p = graph.positionOf(t.id);
      final rect = Rect.fromLTWH(p.col * s, p.row * s, s, s);

      if (t.type != TerritoryType.normal) {
        final r = t.type == TerritoryType.bigBase ? 5.0 : 3.8;
        final c = Offset(rect.left + r + 1.5, rect.top + r + 1.5);
        canvas
          ..drawCircle(c, r, _baseFill)
          ..drawCircle(c, r, _baseStroke);
      }

      if (t.unitCount > 0) {
        (t.ownerArmyId == null ? _darkText : _lightText).render(
          canvas,
          '${t.unitCount}',
          Vector2(rect.center.dx, rect.center.dy + 1),
          anchor: Anchor.center,
        );
      }

      if (armed != null &&
          armed != AbilityType.soldierSpell &&
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
      final p = graph.positionOf(selected.id);
      canvas.drawRect(
        Rect.fromLTWH(p.col * s, p.row * s, s, s).deflate(1),
        _selectedPaint,
      );
    }
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
