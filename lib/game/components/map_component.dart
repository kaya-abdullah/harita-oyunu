/// Africa map Flame component for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
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
/// its real countries, each split between its cities, and turns taps ([tapAt]) into
/// [GameNotifier.onTerritoryTapped] calls.
///
/// Drawing everything in one component (instead of one component per city)
/// keeps the frame cheap on phones. Layers, bottom to top:
///   - the satellite picture (until it has loaded — and in tests that do not
///     wait for it — a drawn map with earthy country colours instead);
///   - owned land raised like a plateau ("oyunu 3D yap"): a dark cliff in
///     the army's colour under its edge, the land tinted in the army colour
///     on top (the land still shows through);
///   - bold country borders (no lines between the cities of a country —
///     "beyaz çizgileri kaldır");
///   - "walls": a dark line in each army's colour along its frontier;
///   - a dashed sea route to Madagascar;
///   - selection / neighbour / card-target outlines;
///   - every city: a little 3D building in its owner's colour (a tower on
///     gold mines, with a gold crown; a diamond on diamond mines), drawn
///     back to front, and above it a label with a little soldier and the
///     number of soldiers in the city.
///
/// The whole map is tilted by [TiltedMap] around the game widget, so the
/// buildings stand on a land seen from an angle.
///
/// The land layers only change when the game state does, so they are
/// recorded once into a [Picture] and replayed every frame.
class MapComponent extends PositionComponent with HasGameReference<WarGame> {
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
  static final List<Paint> _wallPaints = [
    for (final c in AppTheme.armyPrimaries)
      Paint()
        ..color = Color.lerp(c, const Color(0xFF000000), 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
  ];

  /// How far (map units) owned land stands above the rest.
  static const double cliffHeight = 5;

  /// Layers the cliff under raised land is drawn with.
  static const int cliffSteps = 4;

  // Cliff layers per army, darkest (lowest) last.
  static final List<List<Paint>> _cliffPaints = [
    for (final c in AppTheme.armyPrimaries)
      [
        for (var i = 1; i <= cliffSteps; i++)
          Paint()
            ..color = Color.lerp(
              c,
              const Color(0xFF000000),
              0.35 + 0.35 * i / cliffSteps,
            )!,
      ],
  ];

  static final Paint _satellitePaint = Paint()
    ..filterQuality = FilterQuality.medium;
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
    // Buildings back to front (the far ones are behind the near ones),
    // then every label on top.
    final label = math.min(maxLabelWorld, labelScreenPx / zoom);
    final shown =
        [
          for (final t in territories)
            if (visible == null || visible.contains(graph.getPosition(t.id))) t,
        ]..sort(
          (a, b) =>
              graph.getPosition(a.id).dy.compareTo(graph.getPosition(b.id).dy),
        );
    for (final t in shown) {
      _drawBuilding(canvas, t, graph.getPosition(t.id), label);
    }
    _drawFlag(canvas, _americaCentre, label * 2.6);
    for (final t in shown) {
      _drawLabel(canvas, t, graph.getPosition(t.id), label);
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

    // Each army's land, raised: a cliff of [cliffSteps] darker layers under
    // it, then the land itself (picture again, clipped) and the army tint.
    final armyLand = <ArmyId, Path>{};
    for (final t in territories) {
      final owner = t.ownerArmyId;
      if (owner == null) continue;
      (armyLand[owner] ??= Path()).addPath(_cityPaths[t.id], Offset.zero);
    }
    for (var step = cliffSteps; step >= 1; step--) {
      armyLand.forEach((owner, path) {
        canvas.drawPath(
          path.shift(Offset(0, cliffHeight * step / cliffSteps)),
          _cliffPaints[owner.index][step - 1],
        );
      });
    }
    if (satellite != null && armyLand.isNotEmpty) {
      final raised = Path();
      for (final path in armyLand.values) {
        raised.addPath(path, Offset.zero);
      }
      canvas
        ..save()
        ..clipPath(raised)
        ..drawImageRect(
          satellite,
          Rect.fromLTWH(
            0,
            0,
            satellite.width.toDouble(),
            satellite.height.toDouble(),
          ),
          graph.satelliteRect,
          _satellitePaint,
        )
        ..restore();
    } else if (armyLand.isNotEmpty) {
      armyLand.forEach((_, path) {
        canvas
          ..save()
          ..clipPath(path);
        _countries.forEach(
          (key, c) => canvas.drawPath(c, _countryPaints[key]!),
        );
        canvas.restore();
      });
    }
    final tints = satellite != null ? _armyTints : _armyPaints;
    armyLand.forEach(
      (owner, path) => canvas.drawPath(path, tints[owner.index]),
    );

    if (satellite != null) {
      _countries.forEach((_, path) => canvas.drawPath(path, _satBorderPaint));
    } else {
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

  /// Middle of America (the player's start country), where its flag
  /// stands.
  late final Offset _americaCentre = () {
    final ids = graph.playerStartCities;
    var sum = Offset.zero;
    for (final id in ids) {
      sum += graph.getPosition(id);
    }
    return sum / ids.length.toDouble();
  }();

  /// America's flag ("Amerika biz olalım") on a pole [h] tall standing on
  /// [p]: red and white stripes and a blue corner with white stars.
  void _drawFlag(Canvas canvas, Offset p, double h) {
    final poleTop = p.translate(0, -h);
    canvas
      ..drawOval(
        Rect.fromCenter(center: p, width: h * 0.25, height: h * 0.08),
        _groundShadow,
      )
      ..drawLine(
        p,
        poleTop,
        Paint()
          ..color = const Color(0xFFE0E0E0)
          ..strokeWidth = h * 0.04
          ..strokeCap = StrokeCap.round,
      );
    final w = h * 0.62;
    final fh = h * 0.4;
    final flag = Rect.fromLTWH(poleTop.dx, poleTop.dy, w, fh);
    canvas.drawRect(flag, Paint()..color = _white);
    final stripe = fh / 7;
    final red = Paint()..color = const Color(0xFFC62828);
    for (var i = 0; i < 7; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(flag.left, flag.top + i * stripe, w, stripe),
        red,
      );
    }
    final corner = Rect.fromLTWH(flag.left, flag.top, w * 0.42, stripe * 4);
    canvas.drawRect(corner, Paint()..color = const Color(0xFF1A237E));
    final star = Paint()..color = _white;
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 3; c++) {
        canvas.drawCircle(
          Offset(
            corner.left + corner.width * (c + 0.5) / 3,
            corner.top + corner.height * (r + 0.5) / 2,
          ),
          stripe * 0.35,
          star,
        );
      }
    }
    canvas.drawRect(
      flag,
      Paint()
        ..color = const Color(0xFF1B1B1B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.015,
    );
  }

  /// Height of a city's building, for a label [h] map units tall.
  static double buildingHeight(Territory t, double h) =>
      h * (t.hasGoldMine ? 1.5 : 0.95);

  /// One city as a little 3D building standing on [p] — a box with a lit
  /// roof and a shaded side in its owner's colour (light stone for nobody's
  /// city). Gold mines are a tall tower with a gold crown on the roof,
  /// diamond mines show a diamond beside it. [h] is the label height.
  void _drawBuilding(Canvas canvas, Territory t, Offset p, double h) {
    final owner = t.ownerArmyId;
    final base = owner == null
        ? const Color(0xFFE0DCD2)
        : AppTheme.armyPrimaries[owner.index];
    final w = h * 0.9;
    final tall = buildingHeight(t, h);
    final depth = h * 0.4;

    // Shadow on the ground.
    canvas.drawOval(
      Rect.fromCenter(
        center: p.translate(depth * 0.4, 0),
        width: w * 1.6,
        height: depth * 1.2,
      ),
      _groundShadow,
    );
    if (t.hasGoldMine) {
      _drawBox(
        canvas,
        p.translate(-w * 0.45, 0),
        w * 0.6,
        h * 0.6,
        depth,
        base,
      );
      _drawBox(canvas, p.translate(w * 0.5, 0), w * 0.6, h * 0.75, depth, base);
    }
    final roof = _drawBox(canvas, p, w, tall, depth, base);
    if (t.hasGoldMine) {
      _drawCrown(canvas, roof.translate(0, -h * 0.12), w * 0.42);
    }
    if (t.hasDiamondMine) {
      _drawGem(canvas, p.translate(w * 0.95, -h * 0.3), h * 0.55);
    }
  }

  /// A box [w] wide, [tall] high and [depth] deep with its front bottom
  /// edge centred on [p]: front face, a lit roof leaning back and a shaded
  /// right side. Returns the middle of the roof.
  Offset _drawBox(
    Canvas canvas,
    Offset p,
    double w,
    double tall,
    double depth,
    Color color,
  ) {
    final l = p.dx - w / 2;
    final r = p.dx + w / 2;
    final top = p.dy - tall;
    final back = Offset(depth * 0.55, -depth);
    final front = Rect.fromLTRB(l, top, r, p.dy);
    final roof = Path()
      ..moveTo(l, top)
      ..lineTo(r, top)
      ..lineTo(r + back.dx, top + back.dy)
      ..lineTo(l + back.dx, top + back.dy)
      ..close();
    final side = Path()
      ..moveTo(r, p.dy)
      ..lineTo(r, top)
      ..lineTo(r + back.dx, top + back.dy)
      ..lineTo(r + back.dx, p.dy + back.dy)
      ..close();
    final edge = Paint()
      ..color = const Color(0xFF1B1B1B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(side, Paint()..color = Color.lerp(color, _black, 0.45)!)
      ..drawRect(front, Paint()..color = Color.lerp(color, _black, 0.15)!)
      ..drawPath(roof, Paint()..color = Color.lerp(color, _white, 0.35)!);
    // Windows: two rows of lit squares on the front.
    final win = w * 0.16;
    for (var row = 0; row < (tall > w ? 3 : 2); row++) {
      for (final x in [l + w * 0.2, r - w * 0.2 - win]) {
        final y = top + tall * 0.18 + row * win * 1.9;
        if (y + win > p.dy - win * 0.5) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, win, win), _windowPaint);
      }
    }
    canvas
      ..drawPath(side, edge)
      ..drawRect(front, edge)
      ..drawPath(roof, edge);
    return Offset(p.dx + back.dx / 2, top + back.dy / 2);
  }

  static const Color _black = Color(0xFF000000);
  static const Color _white = Color(0xFFFFFFFF);
  static final Paint _windowPaint = Paint()..color = const Color(0xFFFFF59D);
  static final Paint _groundShadow = Paint()..color = const Color(0x66000000);

  /// The dark label above a city's building: a little soldier and the
  /// city's soldier count, rimmed in the owner's colour. [h] is the label
  /// height in map units.
  void _drawLabel(Canvas canvas, Territory t, Offset p, double h) {
    final owner = t.ownerArmyId;
    final text = _countText(t.unitCount);
    final scale = h / _labelFontPx;
    final textW = text.width * scale;
    final soldierW = h * 0.55;
    final padX = h * 0.22;
    final w = padX + soldierW + h * 0.12 + textW + padX;
    final top = p.dy - buildingHeight(t, h) - h * 0.55 - h;
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

  /// Handles a tap at [local] (map coordinates). Taps come from
  /// [MapGestureLayer] rather than Flame's tap events: Flame converts
  /// pointer positions with `RenderBox.globalToLocal`, which is wrong on the
  /// tilted 3D map, while the layer's pointer positions are exact.
  void tapAt(Vector2 local) {
    final id = cityAt(local);
    if (id == null) return;
    // Select / attack / move / deploy / fire armed ability, depending on
    // the current selection (see GameNotifier.onTerritoryTapped).
    ref.read(gameProvider.notifier).onTerritoryTapped(id);
  }
}
