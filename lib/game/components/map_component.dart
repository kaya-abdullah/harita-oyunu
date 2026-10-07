/// Africa map Flame component for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/game_state.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/game/components/unit_painters.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

// ─── MapComponent ─────────────────────────────────────────────────────────────

/// Renders Africa as it looks from space (NASA's Blue Marble) divided into
/// city regions, and turns touches into game actions.
///
/// Layers, bottom to top:
///   - the satellite picture (until it has loaded — and in tests that do not
///     wait for it — a drawn map with earthy colours instead);
///   - thin white lines between all regions;
///   - every army's land: not filled, only a thick line in the army's colour
///     around it ("etrafında bir çizgi");
///   - the three forests, a dashed sea route to Madagascar;
///   - selection, neighbour and target highlights;
///   - the cities: a shaded ball in the owner's colour — bigger with more
///     soldiers (no numbers are written on the map; tap a city to see
///     them) — gold and diamond mines, and, zoomed in, 3D soldiers and the
///     army's tanks and bombers;
///   - the arrow while soldiers are dragged to a city;
///   - animations: marching soldiers and tanks, bombers, explosions.
///
/// Gestures: drag from one of your cities to a neighbour to send soldiers
/// there; drag elsewhere to pan, pinch to zoom; tap to select, attack or
/// play a card.
class MapComponent extends PositionComponent
    with
        TapCallbacks,
        DragCallbacks,
        ScaleCallbacks,
        HasGameReference<WarGame> {
  MapComponent({required this.ref, TerritoryGraph? graph})
    : graph = graph ?? TerritoryGraph.bundled() {
    size = Vector2(this.graph.width, this.graph.height);
    _buildStaticLayers();
  }

  /// Riverpod widget reference used to read game state and send actions.
  final WidgetRef ref;

  /// Static map layout (cities, regions, neighbours).
  final TerritoryGraph graph;

  final List<Path> _regions = [];
  final List<Rect> _regionBounds = [];
  final Path _land = Path();
  final Path _borders = Path();

  /// The satellite picture (`assets/images/africa_satellite.jpg`), once
  /// loaded.
  Image? _satellite;
  final Completer<void> _satelliteLoaded = Completer<void>();

  /// Completes when the satellite picture is ready to draw.
  Future<void> get satelliteReady => _satelliteLoaded.future;

  /// Whether the satellite picture is being drawn.
  bool get hasSatellite => _satellite != null;

  /// File of the satellite picture under `assets/images/`.
  static const String satelliteFile = 'africa_satellite.jpg';

  /// Largest radius of a city marker in world units (also the touch
  /// area of a city).
  static const double cityRadius = 10;

  /// Radius of a city marker: no numbers are written on the cities, so a
  /// city with more soldiers is drawn bigger.
  static double markerRadius(int soldiers) =>
      5.5 + 4.5 * (soldiers.clamp(0, 200) / 200);

  /// 3D soldiers, tanks and bombers appear once a city marker is at least
  /// this many screen pixels wide.
  static const double minFiguresCityPx = 16;

  // Army land outlines, rebuilt when cities change hands.
  List<ArmyId?> _ownersKey = const [];
  final Map<ArmyId, Path> _armyLand = {};

  // Drag of soldiers from a city.
  int? _dragSource;
  Offset? _dragPoint;
  double _zoomAtStart = 1;

  // Animation clock.
  double _clock = 0;
  final Map<BattleFx, double> _fxStart = {};

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Not awaited: the map is playable at once and the picture appears as
    // soon as it is decoded.
    game.images
        .load(satelliteFile)
        .then((image) {
          _satellite = image;
          if (!_satelliteLoaded.isCompleted) _satelliteLoaded.complete();
        })
        .catchError((Object _) {
          // Keep the drawn map if the picture cannot be loaded.
        });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
  }

  // ─── Paints ────────────────────────────────────────────────────────────────

  static final Paint _satellitePaint = Paint()
    ..filterQuality = FilterQuality.medium;
  static final Paint _landPaint = Paint()..color = const Color(0xFFD8C89A);
  static final Paint _shorePaint = Paint()
    ..color = const Color(0xFFB3E5FC)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeJoin = StrokeJoin.round;
  static final Paint _borderPaint = Paint()
    ..color = const Color(0x8CFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..strokeJoin = StrokeJoin.round;
  static final Paint _seaLinkPaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _selectedPaint = Paint()
    ..color = const Color(0xFFFFD600)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5
    ..strokeJoin = StrokeJoin.round;
  static final Paint _neighbourPaint = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round;
  static final Paint _targetPaint = Paint()
    ..color = const Color(0xFFFF6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeJoin = StrokeJoin.round;
  static final Paint _goodDropPaint = Paint()
    ..color = const Color(0x5500E676)
    ..style = PaintingStyle.fill;
  static final Paint _markerEdge = Paint()
    ..color = const Color(0xE6263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _goldRing = Paint()
    ..color = AppTheme.kGold
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6;
  static final Paint _mineFill = Paint()..color = AppTheme.kDiamond;
  static final Paint _mineShine = Paint()..color = const Color(0xFFE0F7FA);

  // ─── Static layers ─────────────────────────────────────────────────────────

  void _buildStaticLayers() {
    for (final rings in graph.outlines) {
      final path = Path();
      for (final ring in rings) {
        path.addPolygon(ring, true);
        _land.addPolygon(ring, true);
        _borders.addPolygon(ring, true);
      }
      _regions.add(path);
      _regionBounds.add(path.getBounds());
    }
  }

  /// Rebuilds each army's land outline when cities changed hands.
  void _refreshArmyLand(List<Territory> territories) {
    final key = [for (final t in territories) t.ownerArmyId];
    if (_listEquals(key, _ownersKey)) return;
    _ownersKey = key;
    _armyLand.clear();
    for (final t in territories) {
      final owner = t.ownerArmyId;
      if (owner == null) continue;
      final current = _armyLand[owner];
      _armyLand[owner] = current == null
          ? (Path()..addPath(_regions[t.id], Offset.zero))
          : Path.combine(PathOperation.union, current, _regions[t.id]);
    }
  }

  // ─── Rendering ─────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final state = ref.read(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final selectedId = ref.read(selectedTerritoryProvider);
    final armed = ref.read(armedToolProvider);
    final territories = state.territories;
    _refreshArmyLand(territories);

    final zoom = isMounted ? game.camera.viewfinder.zoom : 1.0;
    final cityPx = cityRadius * 2 * zoom;

    // ── Land ────────────────────────────────────────────────────────────
    final satellite = _satellite;
    if (satellite != null) {
      canvas.drawImageRect(
        satellite,
        Rect.fromLTWH(
          0,
          0,
          satellite.width.toDouble(),
          satellite.height.toDouble(),
        ),
        graph.satelliteRect,
        _satellitePaint,
      );
    } else {
      canvas
        ..drawPath(_land, _shorePaint)
        ..drawPath(_land, _landPaint);
    }
    canvas.drawPath(_borders, _borderPaint);

    // ── Army land: a line around it, nothing inside ─────────────────────
    _armyLand.forEach((army, path) {
      final color = AppTheme.armyColor(army);
      canvas
        ..save()
        ..clipPath(path)
        ..drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeJoin = StrokeJoin.round,
        )
        ..drawPath(
          path,
          Paint()
            ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..strokeJoin = StrokeJoin.round,
        )
        ..restore();
    });

    // ── Forests and the sea route ───────────────────────────────────────
    for (final t in territories) {
      if (!t.hasForest) continue;
      final c = graph.getPosition(t.id);
      drawForest(canvas, c.translate(cityRadius * 2.2, cityRadius * 1.4), 9);
    }
    for (final (a, b) in graph.seaLinks) {
      _drawDashed(canvas, graph.getPosition(a), graph.getPosition(b));
    }

    // ── Highlights ──────────────────────────────────────────────────────
    final me = state.activeArmyId;
    final humanActs = notifier.isHumanTurn;
    if (humanActs && armed != null) {
      for (final t in territories) {
        final ok = switch (armed) {
          ArmedCard(:final type) => isValidTarget(state, me, type, t),
          ArmedBomber() => t.ownerArmyId != me,
        };
        if (ok) canvas.drawPath(_regions[t.id], _targetPaint);
      }
    }
    final dragSource = _dragSource;
    final dragPoint = _dragPoint;
    if (dragSource != null && dragPoint != null) {
      final over = regionAt(dragPoint);
      if (over != null && notifier.canDispatch(dragSource, over)) {
        canvas.drawPath(_regions[over], _goodDropPaint);
      }
    }
    if (selectedId != null && selectedId < territories.length) {
      final selected = territories[selectedId];
      if (selected.ownerArmyId == me && humanActs) {
        for (final adj in selected.adjacentIds) {
          canvas.drawPath(_regions[adj], _neighbourPaint);
        }
      }
      canvas.drawPath(_regions[selectedId], _selectedPaint);
    }

    // ── Cities ──────────────────────────────────────────────────────────
    final visible = isMounted
        ? game.camera.visibleWorldRect.inflate(cityRadius * 4)
        : null;
    final showFigures = cityPx >= minFiguresCityPx;
    final step = _clock * 1.5;
    for (final t in territories) {
      final c = graph.getPosition(t.id);
      if (visible != null && !visible.contains(c)) continue;
      if (showFigures && t.ownerArmyId != null) {
        drawSquad(
          canvas,
          c.translate(0, cityRadius * 2.2),
          7,
          AppTheme.armyColor(t.ownerArmyId!),
          count: t.unitCount >= 100
              ? 3
              : t.unitCount >= 30
              ? 2
              : 1,
          step: step,
        );
      }
      _drawCity(canvas, t, c);
    }
    if (showFigures) _drawEquipment(canvas, state);

    // ── Drag arrow ──────────────────────────────────────────────────────
    if (dragSource != null && dragPoint != null) {
      _drawArrow(canvas, graph.getPosition(dragSource), dragPoint, me);
    }

    // ── Animations ──────────────────────────────────────────────────────
    _drawFx(canvas, ref.read(battleFxProvider));
  }

  void _drawCity(Canvas canvas, Territory t, Offset c) {
    final owner = t.ownerArmyId;
    final base = owner == null
        ? const Color(0xFF8D8D8D)
        : AppTheme.armyColor(owner);
    final r = markerRadius(t.unitCount);
    canvas
      ..drawCircle(
        c.translate(1.2, 1.8),
        r,
        Paint()..color = const Color(0x66000000),
      )
      ..drawCircle(
        c,
        r,
        Paint()
          ..shader = Gradient.radial(
            c.translate(-r * 0.35, -r * 0.4),
            r * 1.3,
            [
              Color.lerp(base, const Color(0xFFFFFFFF), 0.45)!,
              base,
              Color.lerp(base, const Color(0xFF000000), 0.45)!,
            ],
            [0, 0.5, 1],
          ),
      )
      ..drawCircle(c, r, _markerEdge);
    if (t.hasGoldMine) canvas.drawCircle(c, r + 1.6, _goldRing);
    if (t.hasDiamondMine) {
      _drawMine(canvas, c.translate(cityRadius * 0.85, -cityRadius * 0.85));
    }
  }

  /// Each army's tanks and bombers, parked by its strongest city.
  void _drawEquipment(Canvas canvas, GameState state) {
    final strongest = <ArmyId, Territory>{};
    for (final t in state.territories) {
      final o = t.ownerArmyId;
      if (o == null) continue;
      final best = strongest[o];
      if (best == null || t.unitCount > best.unitCount) strongest[o] = t;
    }
    strongest.forEach((id, city) {
      final army = state.armyOrNull(id);
      if (army == null) return;
      final c = graph.getPosition(city.id);
      final color = AppTheme.armyColor(id);
      if (army.tanks > 0) {
        drawTank(
          canvas,
          c.translate(-cityRadius * 2.4, cityRadius * 0.6),
          13,
          color,
        );
      }
      if (army.bombers > 0) {
        drawBomber(
          canvas,
          c.translate(cityRadius * 2.4, -cityRadius * 1.2),
          15,
          color,
          angle: -pi / 2,
          altitude: 0.15,
        );
      }
    });
  }

  void _drawMine(Canvas canvas, Offset c) {
    const w = 7.0;
    final gem = Path()
      ..moveTo(c.dx - w / 2, c.dy - w * 0.2)
      ..lineTo(c.dx - w * 0.25, c.dy - w / 2)
      ..lineTo(c.dx + w * 0.25, c.dy - w / 2)
      ..lineTo(c.dx + w / 2, c.dy - w * 0.2)
      ..lineTo(c.dx, c.dy + w / 2)
      ..close();
    canvas
      ..drawPath(gem, _mineFill)
      ..drawRect(
        Rect.fromLTWH(c.dx - w * 0.2, c.dy - w * 0.4, w * 0.15, w * 0.15),
        _mineShine,
      )
      ..drawPath(gem, _markerEdge);
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, ArmyId army) {
    final d = to - from;
    if (d.distance < 4) return;
    final color = AppTheme.armyColor(army);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(from, to, paint);
    final dir = d / d.distance;
    final normal = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(to.dx + dir.dx * 6, to.dy + dir.dy * 6)
      ..lineTo(
        to.dx - dir.dx * 6 + normal.dx * 7,
        to.dy - dir.dy * 6 + normal.dy * 7,
      )
      ..lineTo(
        to.dx - dir.dx * 6 - normal.dx * 7,
        to.dy - dir.dy * 6 - normal.dy * 7,
      )
      ..close();
    canvas.drawPath(head, Paint()..color = color);
    drawSquad(
      canvas,
      to.translate(0, 18),
      8,
      color,
      count: 3,
      step: _clock * 2,
    );
  }

  void _drawFx(Canvas canvas, List<BattleFx> effects) {
    _fxStart.removeWhere((fx, _) => !effects.contains(fx));
    for (final fx in effects) {
      final start = _fxStart.putIfAbsent(fx, () => _clock);
      final t = ((_clock - start) * 1000 / fx.durationMs).clamp(0.0, 1.0);
      final color = AppTheme.armyColor(fx.army);
      switch (fx.kind) {
        case BattleFxKind.march:
          final p = Offset.lerp(fx.from, fx.to, t)!;
          final dir = fx.to - fx.from;
          final angle = atan2(dir.dy, dir.dx);
          if (fx.withTank) {
            final back = dir.distance == 0 ? Offset.zero : dir / dir.distance;
            drawTank(canvas, p - back * 14, 14, color, angle: angle);
          }
          drawSquad(canvas, p, 9, color, count: 3, step: _clock * 3);
          if (t >= 0.85) {
            drawExplosion(canvas, fx.to, 16, (t - 0.85) / 0.15);
          }
        case BattleFxKind.bomber:
          final p = Offset.lerp(fx.from, fx.to, t)!;
          final dir = fx.to - fx.from;
          drawBomber(
            canvas,
            p.translate(0, -10),
            26,
            color,
            angle: dir.distance == 0 ? 0 : atan2(dir.dy, dir.dx),
          );
          if (t >= 0.8) {
            drawExplosion(canvas, fx.to, 18, (t - 0.8) / 0.2);
          }
        case BattleFxKind.blast:
          drawExplosion(canvas, fx.to, 20, t);
        case BattleFxKind.nuke:
          drawMushroom(canvas, fx.to, 40, t);
      }
    }
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b) {
    const dash = 5.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      final end = d + dash < total ? d + dash : total;
      canvas.drawLine(a + dir * d, a + dir * end, _seaLinkPaint);
    }
  }

  // ─── Hit testing ───────────────────────────────────────────────────────────

  /// The city whose region contains [p] (map coordinates), or whose marker
  /// is under [p]; `null` for the sea.
  int? regionAt(Offset p) {
    // The nearest city marker under the finger wins (markers of close
    // cities such as Casablanca and Rabat overlap).
    int? marker;
    var best = cityRadius;
    for (var i = 0; i < _regions.length; i++) {
      final d = (graph.getPosition(i) - p).distance;
      if (d <= best) {
        best = d;
        marker = i;
      }
    }
    if (marker != null) return marker;
    for (var i = 0; i < _regions.length; i++) {
      if (_regionBounds[i].contains(p) && _regions[i].contains(p)) return i;
    }
    return null;
  }

  /// Kept for tests and older callers: the city at [local].
  int? tileAt(Vector2 local) => regionAt(local.toOffset());

  // ─── Gestures ──────────────────────────────────────────────────────────────

  @override
  void onTapUp(TapUpEvent event) {
    final id = regionAt(event.localPosition.toOffset());
    if (id == null) return;
    ref.read(gameProvider.notifier).onTerritoryTapped(id);
  }

  /// One finger: drag soldiers out of an own city, or pan the map.
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragSource = null;
    _dragPoint = null;
    final notifier = ref.read(gameProvider.notifier);
    if (!notifier.isHumanTurn || ref.read(armedToolProvider) != null) return;
    final p = event.localPosition.toOffset();
    final id = regionAt(p);
    if (id == null) return;
    final state = ref.read(gameProvider);
    final city = state.territories[id];
    if (city.ownerArmyId == state.activeArmyId && city.unitCount >= 2) {
      _dragSource = id;
      _dragPoint = p;
      notifier.selectTerritory(id);
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_dragSource != null) {
      // Follow the finger from its real screen position (Flame's drag
      // deltas can jump when the gesture ends): screen → game canvas →
      // map (the map sits at the world origin).
      final global = event.raw.globalPosition;
      final canvas = game.convertGlobalToLocalCoordinate(
        Vector2(global.dx, global.dy),
      );
      _dragPoint = game.camera.globalToLocal(canvas).toOffset();
      return;
    }
    game.panBy(event.canvasDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final source = _dragSource;
    final point = _dragPoint;
    _dragSource = null;
    _dragPoint = null;
    if (source == null || point == null) return;
    final target = regionAt(point);
    if (target == null || target == source) return;
    ref.read(gameProvider.notifier).dispatchTroops(source, target);
  }

  /// Two fingers: pinch to zoom (and move the map).
  @override
  void onScaleStart(ScaleStartEvent event) {
    super.onScaleStart(event);
    _zoomAtStart = game.userZoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateEvent event) {
    if (event.pointerCount < 2) return;
    // A second finger: zoom instead of dragging soldiers.
    _dragSource = null;
    _dragPoint = null;
    game
      ..zoomTo(_zoomAtStart * event.scale)
      ..panBy(event.focalPointDelta);
  }

  /// Drops soldiers dragged from [source] on [target] (used by tests that
  /// cannot perform the gesture).
  void dragTroops(int source, int target) {
    ref.read(gameProvider.notifier).dispatchTroops(source, target);
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
