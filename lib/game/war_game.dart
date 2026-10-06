/// Root Flame game class for Harita: Kendi İmparatorluğunu Kur.
library;

import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/game/components/map_component.dart';

// ─── WarGame ─────────────────────────────────────────────────────────────────

/// The root [FlameGame] for Harita.
///
/// [WarGame] owns the Africa [MapComponent] and bridges the Flame rendering
/// pipeline with the Riverpod state layer via the injected [WidgetRef].
///
/// The camera fits the whole continent into the widget; players can pinch
/// to zoom in on the small tiles and drag to pan ([SeaBackdrop]).
class WarGame extends FlameGame {
  WarGame({required this.ref});

  /// Riverpod widget reference used to read / watch providers from within
  /// Flame components.
  final WidgetRef ref;

  /// The map of Africa.
  late MapComponent mapComponent;

  /// Extra zoom applied by the player on top of the fit-to-screen zoom.
  double userZoom = 1;

  /// Maximum extra zoom.
  static const double maxUserZoom = 8;

  static const double _margin = 8;

  double _fitZoom = 1;

  @override
  Color backgroundColor() => SeaBackdrop.seaColor;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    mapComponent = MapComponent(ref: ref);
    camera.viewfinder.anchor = Anchor.center;
    await world.addAll([SeaBackdrop(), mapComponent]);
    _applyCamera(recenter: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _applyCamera();
  }

  // ─── Camera ────────────────────────────────────────────────────────────────

  Vector2 get _mapSize => mapComponent.size;

  void _applyCamera({bool recenter = false}) {
    final view = size;
    if (view.x <= 0 || view.y <= 0) return;
    _fitZoom = min(
      view.x / (_mapSize.x + _margin * 2),
      view.y / (_mapSize.y + _margin * 2),
    );
    camera.viewfinder.zoom = _fitZoom * userZoom;
    if (recenter) camera.viewfinder.position = _mapSize / 2;
    _clampPosition();
  }

  /// Zooms by [factor] relative to the zoom at gesture start.
  void zoomTo(double newUserZoom) {
    userZoom = newUserZoom.clamp(1, maxUserZoom).toDouble();
    _applyCamera();
  }

  /// Pans the camera by [screenDelta] pixels.
  void panBy(Vector2 screenDelta) {
    camera.viewfinder.position -= screenDelta / camera.viewfinder.zoom;
    _clampPosition();
  }

  /// Keeps the map on screen: centred when it fits, otherwise its edges may
  /// not pass the screen edges.
  void _clampPosition() {
    final zoom = camera.viewfinder.zoom;
    final half = size / (2 * zoom);
    final pos = camera.viewfinder.position;
    double clampAxis(double v, double extent, double halfView) {
      if (halfView * 2 >= extent) return extent / 2;
      return v.clamp(halfView - _margin, extent - halfView + _margin);
    }

    camera.viewfinder.position = Vector2(
      clampAxis(pos.x, _mapSize.x, half.x),
      clampAxis(pos.y, _mapSize.y, half.y),
    );
  }
}

// ─── SeaBackdrop ─────────────────────────────────────────────────────────────

/// Large invisible hit area behind the map that receives pinch-zoom and
/// drag-to-pan gestures anywhere on the canvas. The sea itself is the game's
/// [WarGame.backgroundColor], which — unlike a huge painted rectangle — never
/// spills over the HUD widgets around the canvas.
class SeaBackdrop extends PositionComponent
    with ScaleCallbacks, HasGameReference<WarGame> {
  SeaBackdrop()
    : super(
        position: Vector2.all(-5000),
        size: Vector2.all(10000),
        priority: -1,
      );

  /// Ocean colour around Africa.
  static const Color seaColor = Color(0xFF4FC3F7);

  double _zoomAtStart = 1;

  @override
  void onScaleStart(ScaleStartEvent event) {
    super.onScaleStart(event);
    _zoomAtStart = game.userZoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateEvent event) {
    if (event.pointerCount > 1) game.zoomTo(_zoomAtStart * event.scale);
    game.panBy(event.focalPointDelta);
  }
}
