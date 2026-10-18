/// The 3D view of the map ("oyunu 3D yap").
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Shows [child] (the game widget) as a land seen from an angle: it leans
/// back by [tilt] around its top edge with perspective, so the far
/// (northern) part of the map is smaller than the near part and the city
/// buildings stand on it. The top edge keeps the full width and the near
/// part reaches past the bottom, so the land fills the whole widget.
///
/// The game is first drawn flat into a picture the size of the widget, and
/// only that picture is tilted (an [ImageFilter.matrix]). Tilting the
/// drawing itself (a [Transform]) went wrong on phones when zoomed in far:
/// the map then reaches far past the screen, its near part ends up behind
/// the eye of the perspective, and the GPU dropped everything — the screen
/// showed only blue.
///
/// A filter does not move pointer positions, so [toCanvas] turns a point
/// on the screen into the game-canvas point shown there (and [toScreen]
/// back).
class TiltedMap extends StatelessWidget {
  const TiltedMap({super.key, required this.child});

  /// The game widget.
  final Widget child;

  /// How far the map leans back, in radians.
  static const double tilt = 0.6;

  /// How much nearer the bottom of the widget is than its top: things at
  /// the bottom look 1 / (1 − [depth]) times bigger than at the top, on
  /// every screen size.
  static const double depth = 0.3;

  /// The transform for a widget [size] big: leans back around the middle
  /// of its top edge.
  static Matrix4 transformFor(Size size) {
    final pivot = Offset(size.width / 2, 0);
    final perspective = depth / (math.sin(tilt) * size.height);
    return Matrix4.translationValues(pivot.dx, pivot.dy, 0)
      ..multiply(Matrix4.identity()..setEntry(3, 2, perspective))
      ..multiply(Matrix4.rotationX(-tilt))
      ..multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0));
  }

  /// Where the game-canvas point [canvas] shows on the screen (relative to
  /// this widget), for a widget [size] big.
  static Offset toScreen(Offset canvas, Size size) =>
      MatrixUtils.transformPoint(transformFor(size), canvas);

  /// The game-canvas point shown at [screen] (relative to this widget), for
  /// a widget [size] big — the exact inverse of [toScreen] on the flat
  /// canvas.
  static Offset toCanvas(Offset screen, Size size) {
    // Only points on the canvas plane (z = 0) are shown, so drop z and
    // invert what is left: a plain 2D perspective.
    final inverse = Matrix4.tryInvert(
      PointerEvent.removePerspectiveTransform(transformFor(size)),
    );
    if (inverse == null) return screen;
    return MatrixUtils.transformPoint(inverse, screen);
  }

  /// Colour behind the land (the deep sea), in case any of it shows.
  static const Color background = Color(0xFF061431);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ColoredBox(
          color: background,
          child: ImageFiltered(
            imageFilter: ImageFilter.matrix(
              transformFor(size).storage,
              filterQuality: FilterQuality.medium,
            ),
            // Keeps the flat picture to the widget's own size: zoomed in,
            // the map reaches far past it, and tilting all of that put
            // parts behind the eye and wiped the whole picture (the screen
            // went blue).
            child: ClipRect(child: child),
          ),
        );
      },
    );
  }
}
