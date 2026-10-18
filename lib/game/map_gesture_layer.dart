/// Pan and pinch-zoom for the Africa map.
library;

import 'package:flame/components.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:harita/game/war_game.dart';

/// Wraps the game widget and moves the map camera with raw pointer events:
/// one finger drags the map, two fingers pinch-zoom around the point between
/// them, and a mouse wheel zooms around the cursor.
///
/// A finger that goes down and up without moving further than [panSlop]
/// (and without a second finger) is a tap on the map — select, attack,
/// play a card — passed to [WarGame.tapAt]. The pointer positions a
/// [Listener] receives are exact even on the tilted 3D map. This does not depend on
/// Flame's scale events, which skip one-finger drags unless the game also
/// has drag listeners.
class MapGestureLayer extends StatefulWidget {
  const MapGestureLayer({super.key, required this.game, required this.child});

  /// The game whose camera moves.
  final WarGame game;

  /// The game widget.
  final Widget child;

  /// Distance in pixels a single finger moves before the map pans.
  static const double panSlop = 8;

  @override
  State<MapGestureLayer> createState() => _MapGestureLayerState();
}

class _MapGestureLayerState extends State<MapGestureLayer> {
  final Map<int, Offset> _pointers = {};
  Offset? _downAt;
  bool _panning = false;
  bool _maybeTap = false;
  double _pinchStartDistance = 0;
  double _pinchStartZoom = 1;

  WarGame get _game => widget.game;

  bool get _ready => _game.isLoaded;

  void _startPinch() {
    final (a, b) = _firstTwo();
    _pinchStartDistance = (a - b).distance;
    _pinchStartZoom = _game.userZoom;
  }

  (Offset, Offset) _firstTwo() {
    final it = _pointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return (a, it.current);
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _downAt = e.localPosition;
      _panning = false;
      _maybeTap = true;
    } else {
      _maybeTap = false;
      if (_pointers.length == 2) _startPinch();
    }
  }

  void _onMove(PointerMoveEvent e) {
    final old = _pointers[e.pointer];
    if (old == null || !_ready) return;
    if (_pointers.length == 1) {
      _pointers[e.pointer] = e.localPosition;
      final start = _downAt ?? old;
      if (!_panning &&
          (e.localPosition - start).distance > MapGestureLayer.panSlop) {
        _panning = true;
        _maybeTap = false;
      }
      if (_panning) {
        final d = e.localPosition - old;
        _game.panBy(Vector2(d.dx, d.dy));
      }
      return;
    }
    // Two (or more) fingers: zoom around the point between the first two,
    // and follow that point as it moves.
    final (a0, b0) = _firstTwo();
    final focalBefore = (a0 + b0) / 2;
    _pointers[e.pointer] = e.localPosition;
    final (a1, b1) = _firstTwo();
    final focal = (a1 + b1) / 2;
    final distance = (a1 - b1).distance;
    if (_pinchStartDistance > 0 && distance > 0) {
      _game.zoomAt(
        _pinchStartZoom * distance / _pinchStartDistance,
        Vector2(focal.dx, focal.dy),
      );
    }
    final d = focal - focalBefore;
    _game.panBy(Vector2(d.dx, d.dy));
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_maybeTap && e is PointerUpEvent && _pointers.isEmpty && _ready) {
      _game.tapAt(Vector2(e.localPosition.dx, e.localPosition.dy));
    }
    _maybeTap = false;
    if (_pointers.length >= 2) {
      _startPinch();
    } else if (_pointers.length == 1) {
      // Keep panning with the finger that stays, without a jump.
      _downAt = _pointers.values.first;
      _panning = true;
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_ready) return;
    final factor = e.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15;
    _game.zoomAt(
      _game.userZoom * factor,
      Vector2(e.localPosition.dx, e.localPosition.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      onPointerSignal: _onSignal,
      child: widget.child,
    );
  }
}
