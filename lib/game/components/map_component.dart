/// Africa map Flame component for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/theme/app_theme.dart';
import 'package:harita/domain/models/army.dart';
import 'package:harita/domain/models/special_ability.dart';
import 'package:harita/domain/services/ability_service.dart';
import 'package:harita/domain/models/territory.dart';
import 'package:harita/game/war_game.dart';
import 'package:harita/infrastructure/map/territory_graph.dart';
import 'package:harita/presentation/viewmodels/game_viewmodel.dart';

// ─── MapComponent ─────────────────────────────────────────────────────────────

/// Renders Africa as it really looks from space — NASA's Blue Marble
/// satellite picture (deserts, rain forests, savanna, ocean depths) — with
/// its real countries, each split between its cities, and turns taps into
/// [GameNotifier.onTerritoryTapped] calls.
///
/// Drawing everything in one component (instead of one component per city)
/// keeps the frame cheap on phones. Layers, bottom to top:
///   - the satellite picture (until it has loaded — and in tests that do not
///     wait for it — a drawn map with earthy country colours instead);
///   - owned city areas tinted in their army colour (the land still shows
///     through);
///   - thin lines between the cities of a country, bold country borders;
///   - "walls": a dark line in each army's colour along its frontier;
///   - a dashed sea route to Madagascar;
///   - selection / neighbour / card-target outlines;
///   - every city: a dot in its owner's colour (gold crown on gold mines,
///     a diamond on diamond mines) and a label above it with a little
///     soldier and the number of soldiers in the city.
///
/// The land layers only change when the game state does, so they are
/// recorded once into a [Picture] and replayed every frame.
class MapComponent extends PositionComponent
    with TapCallbacks, HasGameReference<WarGame> {
  MapComponent({required this.ref, TerritoryGraph? graph})
    : graph = graph ?? TerritoryGraph.bundled() {
    size = Vector2(this.graph.width, this.graph.height);
    _buildStaticLayers();
  }

  /// Riverpod widget reference used to read game state and send taps.
  final WidgetRef ref;

  /// Static map layout (cities, countries, adjacency, outlines).
  final TerritoryGraph graph;

  final Path _land = Path();
  final Map<String, Path> _countries = {};
  final List<Path> _cityPaths = [];
  final List<Rect> _cityBounds = [];
  final Path _cityLines = Path();

  /// Border lines touching each city (shared with a neighbour or coast).
  final List<List<CityBorder>> _bordersOf = [];
  final List<Path> _borderPaths = [];
  final Map<CityBorder, int> _borderIndex = {};
  final List<(Offset, Offset)> _seaLinks = [];

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

  // Cached land layer and what it was recorded for.
  Picture? _landPicture;
  List<Territory>? _landFor;
  bool _landWithSatellite = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Not awaited: the map is playable at once and the picture fades in
    // as soon as it is decoded.
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
  void onRemove() {
    _landPicture?.dispose();
    _landPicture = null;
    super.onRemove();
  }

  /// Height of a city's soldier label on screen, in pixels (it never gets
  /// bigger than [maxLabelWorld] map units, so labels shrink with the map
  /// when zoomed far out).
  static const double labelScreenPx = 15;

  /// Largest height of a soldier label in map units.
  static const double maxLabelWorld = 9;

  // ─── Paints ────────────────────────────────────────────────────────────────

  static final List<Paint> _armyPaints = [
    for (final c in AppTheme.armyPrimaries) Paint()..color = c.withAlpha(215),
  ];
  // Over the satellite picture the army colour is a tint, so forests and
  // deserts stay visible under conquered land.
  static final List<Paint> _armyTints = [
    for (final c in AppTheme.armyPrimaries) Paint()..color = c.withAlpha(140),
  ];
  static final List<Paint> _dotPaints = [
    for (final c in AppTheme.armyPrimaries) Paint()..color = c,
  ];
  static final List<Paint> _wallPaints = [
    for (final c in AppTheme.armyPrimaries)
      Paint()
        ..color = Color.lerp(c, const Color(0xFF000000), 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
  ];
  static final Paint _satellitePaint = Paint()
    ..filterQuality = FilterQuality.medium;
  static final Paint _satCityLinePaint = Paint()
    ..color = const Color(0x66FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  static final Paint _satBorderPaint = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..strokeJoin = StrokeJoin.round;
  static final Paint _shorePaint = Paint()
    ..color = const Color(0xFFB3E5FC)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeJoin = StrokeJoin.round;
  static final Paint _cityLinePaint = Paint()
    ..color = const Color(0x594E342E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  static final Paint _borderHalo = Paint()
    ..color = const Color(0x99FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round;
  static final Paint _borderPaint = Paint()
    ..color = const Color(0xCC4E342E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3
    ..strokeJoin = StrokeJoin.round;
  static final Paint _seaLinkPaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _selectedPaint = Paint()
    ..color = const Color(0xFFFFD600)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.2
    ..strokeJoin = StrokeJoin.round;
  static final Paint _selectedFill = Paint()..color = const Color(0x40FFD600);
  static final Paint _neighbourPaint = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round;
  static final Paint _abilityTargetPaint = Paint()
    ..color = const Color(0xFFFF6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeJoin = StrokeJoin.round;
  static final Paint _neutralDot = Paint()..color = const Color(0xFFECEFF1);
  static final Paint _dotRim = Paint()
    ..color = const Color(0xFF263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _labelBg = Paint()..color = const Color(0xD9101820);
  static final Paint _goldFill = Paint()..color = const Color(0xFFFFC107);
  static final Paint _goldDark = Paint()..color = const Color(0xFF8D6E00);
  static final Paint _mineFill = Paint()..color = AppTheme.kDiamond;
  static final Paint _mineShine = Paint()..color = const Color(0xFFE0F7FA);
  static final Paint _soldierPaint = Paint()..color = const Color(0xFFFFFFFF);
  static final Paint _helmetPaint = Paint()..color = const Color(0xFF9CCC65);

  /// Earthy palette for the drawn map, one colour per country.
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

    for (final rings in graph.cityOutlines) {
      final path = Path();
      for (final ring in rings) {
        path.addPolygon(ring, true);
      }
      _cityPaths.add(path);
      _cityBounds.add(path.getBounds());
      _bordersOf.add([]);
    }

    for (final border in graph.borders) {
      final path = Path()..addPolygon(border.points, false);
      _borderIndex[border] = _borderPaths.length;
      _borderPaths.add(path);
      _bordersOf[border.a].add(border);
      final b = border.b;
      if (b != null) {
        _bordersOf[b].add(border);
        if (graph.countryOf(border.a) == graph.countryOf(b)) {
          _cityLines.addPath(path, Offset.zero);
        }
      }
    }

    for (final (a, b) in graph.seaLinks) {
      _seaLinks.add((graph.getPosition(a), graph.getPosition(b)));
    }
  }

  // ─── Rendering ─────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final state = ref.read(gameProvider);
    final selectedId = ref.read(selectedTerritoryProvider);
    final armed = ref.read(armedAbilityProvider);
    final territories = state.territories;

    // Zoom level and visible area (both unknown before the game mounts).
    var zoom = 1.0;
    Rect? visible;
    if (isMounted) {
      zoom = game.camera.viewfinder.zoom;
      visible = game.camera.visibleWorldRect.inflate(20);
    }

    // ── Land (cached) ───────────────────────────────────────────────────
    final withSatellite = _satellite != null;
    if (_landPicture == null ||
        !identical(_landFor, territories) ||
        _landWithSatellite != withSatellite) {
      _landPicture?.dispose();
      final recorder = PictureRecorder();
      _drawLand(Canvas(recorder), territories);
      _landPicture = recorder.endRecording();
      _landFor = territories;
      _landWithSatellite = withSatellite;
    }
    canvas.drawPicture(_landPicture!);

    // ── Selection and card targets ──────────────────────────────────────
    Territory? selected;
    if (selectedId != null && selectedId < territories.length) {
      selected = territories[selectedId];
    }
    final targeting = armed != null && armed != AbilityType.soldierSpell;
    if (targeting) {
      for (final t in territories) {
        if (visible != null && !visible.overlaps(_cityBounds[t.id])) continue;
        if (isValidTarget(state, ArmyId.army1, armed, t)) {
          canvas.drawPath(_cityPaths[t.id], _abilityTargetPaint);
        }
      }
    } else if (selected != null) {
      for (final adj in selected.adjacentIds) {
        canvas.drawPath(_cityPaths[adj], _neighbourPaint);
      }
    }
    if (selected != null) {
      canvas
        ..drawPath(_cityPaths[selected.id], _selectedFill)
        ..drawPath(_cityPaths[selected.id], _selectedPaint);
    }

    // ── Cities and their soldiers ───────────────────────────────────────
    final label = math.min(maxLabelWorld, labelScreenPx / zoom);
    for (final t in territories) {
      final p = graph.getPosition(t.id);
      if (visible != null && !visible.contains(p)) continue;
      _drawCity(canvas, t, p, label);
    }
  }

  /// Records the land layer: picture or drawn countries, army tints,
  /// borders, walls and the sea route.
  void _drawLand(Canvas canvas, List<Territory> territories) {
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
      canvas.drawPath(_land, _shorePaint);
      _countries.forEach((key, path) {
        canvas.drawPath(path, _countryPaints[key]!);
      });
    }

    final tints = satellite != null ? _armyTints : _armyPaints;
    for (final t in territories) {
      final owner = t.ownerArmyId;
      if (owner == null) continue;
      canvas.drawPath(_cityPaths[t.id], tints[owner.index]);
    }

    if (satellite != null) {
      canvas.drawPath(_cityLines, _satCityLinePaint);
      _countries.forEach((_, path) => canvas.drawPath(path, _satBorderPaint));
    } else {
      canvas.drawPath(_cityLines, _cityLinePaint);
      _countries.forEach((_, path) => canvas.drawPath(path, _borderHalo));
      _countries.forEach((_, path) => canvas.drawPath(path, _borderPaint));
    }

    _drawWalls(canvas, territories);
    for (final (a, b) in _seaLinks) {
      _drawDashed(canvas, a, b);
    }
  }

  /// Frontier "walls": along every border between different owners (and
  /// along the coast), a dark line in the colour of the army on each side,
  /// kept inside its own city so neighbouring armies' walls sit side by
  /// side.
  void _drawWalls(Canvas canvas, List<Territory> territories) {
    for (final t in territories) {
      final owner = t.ownerArmyId;
      if (owner == null) continue;
      final frontier = Path();
      var any = false;
      for (final border in _bordersOf[t.id]) {
        final other = border.a == t.id ? border.b : border.a;
        if (other != null && territories[other].ownerArmyId == owner) {
          continue;
        }
        frontier.addPath(_borderPaths[_borderIndex[border]!], Offset.zero);
        any = true;
      }
      if (!any) continue;
      canvas
        ..save()
        ..clipPath(_cityPaths[t.id])
        ..drawPath(frontier, _wallPaints[owner.index])
        ..restore();
    }
  }

  /// One city: a dot in its owner's colour with mine markers, and above it
  /// a dark label with a little soldier and the city's soldier count.
  /// [h] is the label height in map units.
  void _drawCity(Canvas canvas, Territory t, Offset p, double h) {
    final r = h * 0.36;
    final owner = t.ownerArmyId;
    canvas
      ..drawCircle(p, r, owner == null ? _neutralDot : _dotPaints[owner.index])
      ..drawCircle(p, r, _dotRim);
    if (t.hasGoldMine) _drawCrown(canvas, p.translate(0, -r * 0.1), r * 0.8);
    if (t.hasDiamondMine) _drawGem(canvas, p.translate(r * 1.4, 0), r * 0.9);

    final text = _countText(t.unitCount);
    final scale = h / _labelFontPx;
    final textW = text.width * scale;
    final soldierW = h * 0.55;
    final padX = h * 0.22;
    final w = padX + soldierW + h * 0.12 + textW + padX;
    final top = p.dy - r - h * 0.15 - h;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(p.dx - w / 2, top, w, h),
      Radius.circular(h * 0.35),
    );
    canvas.drawRRect(box, _labelBg);
    if (owner != null) {
      canvas.drawRRect(
        box,
        Paint()
          ..color = AppTheme.armyPrimaries[owner.index]
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.1,
      );
    }
    _drawSoldier(
      canvas,
      Offset(box.left + padX + soldierW / 2, top + h / 2),
      h * 0.8,
    );
    canvas
      ..save()
      ..translate(box.left + padX + soldierW + h * 0.12, top + h * 0.06)
      ..scale(scale);
    text.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// Font size the count labels are laid out at (then scaled).
  static const double _labelFontPx = 20;

  final Map<int, TextPainter> _countTexts = {};

  TextPainter _countText(int count) => _countTexts.putIfAbsent(count, () {
    if (_countTexts.length > 600) _countTexts.clear();
    return TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: _labelFontPx,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  });

  /// A little soldier ("asker") [h] tall centred on [c]: helmet, head,
  /// body.
  void _drawSoldier(Canvas canvas, Offset c, double h) {
    final top = c.dy - h / 2;
    final body = Path()
      ..moveTo(c.dx - h * 0.26, c.dy + h / 2)
      ..lineTo(c.dx - h * 0.2, top + h * 0.5)
      ..quadraticBezierTo(c.dx, top + h * 0.42, c.dx + h * 0.2, top + h * 0.5)
      ..lineTo(c.dx + h * 0.26, c.dy + h / 2)
      ..close();
    canvas
      ..drawPath(body, _soldierPaint)
      ..drawCircle(Offset(c.dx, top + h * 0.3), h * 0.14, _soldierPaint)
      ..drawArc(
        Rect.fromCircle(center: Offset(c.dx, top + h * 0.27), radius: h * 0.2),
        math.pi,
        math.pi,
        true,
        _helmetPaint,
      );
  }

  /// A gold crown (gold mine) of half-width [s] centred on [c].
  void _drawCrown(Canvas canvas, Offset c, double s) {
    final crown = Path()
      ..moveTo(c.dx - s, c.dy + s * 0.5)
      ..lineTo(c.dx - s, c.dy - s * 0.4)
      ..lineTo(c.dx - s * 0.5, c.dy)
      ..lineTo(c.dx, c.dy - s * 0.7)
      ..lineTo(c.dx + s * 0.5, c.dy)
      ..lineTo(c.dx + s, c.dy - s * 0.4)
      ..lineTo(c.dx + s, c.dy + s * 0.5)
      ..close();
    canvas
      ..drawPath(crown.shift(Offset(0, s * 0.12)), _goldDark)
      ..drawPath(crown, _goldFill);
  }

  /// A small cut diamond (diamond mine) of width [w] centred on [c].
  void _drawGem(Canvas canvas, Offset c, double w) {
    final top = c.dy - w / 2;
    final gem = Path()
      ..moveTo(c.dx - w / 2, top + w * 0.3)
      ..lineTo(c.dx - w * 0.25, top)
      ..lineTo(c.dx + w * 0.25, top)
      ..lineTo(c.dx + w / 2, top + w * 0.3)
      ..lineTo(c.dx, top + w)
      ..close();
    canvas
      ..drawPath(gem, _mineFill)
      ..drawRect(
        Rect.fromLTWH(c.dx - w * 0.2, top + w * 0.08, w * 0.15, w * 0.15),
        _mineShine,
      )
      ..drawPath(gem, _dotRim);
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

  /// Returns the city whose area holds [local] (map coordinates) — or,
  /// for a tap just off the coast, the nearest city within reach — or
  /// `null` for open sea.
  int? cityAt(Vector2 local) {
    final p = Offset(local.x, local.y);
    for (var i = 0; i < _cityPaths.length; i++) {
      if (_cityBounds[i].contains(p) && _cityPaths[i].contains(p)) return i;
    }
    // Taps on a city label (drawn above the dot) count for that city.
    int? best;
    var bestD = 12.0;
    for (var i = 0; i < _cityPaths.length; i++) {
      final d = (graph.getPosition(i) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void onTapUp(TapUpEvent event) {
    final id = cityAt(event.localPosition);
    if (id == null) return;
    // Select / attack / move / deploy / fire armed ability, depending on
    // the current selection (see GameNotifier.onTerritoryTapped).
    ref.read(gameProvider.notifier).onTerritoryTapped(id);
  }
}
