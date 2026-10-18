/// The 3D view of the map ("oyunu 3D yap").
library;

import 'package:flutter/widgets.dart';

/// Shows [child] (the game widget) as a land seen from an angle: it leans
/// back by [tilt] with perspective, so the far (northern) part of the map
/// gets smaller towards a sky on the horizon and the city buildings stand
/// on it.
///
/// Flutter maps pointer positions through the transform, so taps, drags
/// and pinches inside the child keep working in map coordinates.
class TiltedMap extends StatelessWidget {
  const TiltedMap({super.key, required this.child});

  /// The game widget.
  final Widget child;

  /// How far the map leans back, in radians.
  static const double tilt = 0.6;

  /// Strength of the perspective (how much faster far things shrink).
  static const double perspective = 0.0011;

  /// Enlargement that lets the leaning map still fill the screen sides.
  static const double fill = 1.3;

  /// The transform for a widget [size] big: leans back around its bottom
  /// middle, then grows by [fill] around the same point.
  static Matrix4 transformFor(Size size) {
    final pivot = Offset(size.width / 2, size.height);
    return Matrix4.translationValues(pivot.dx, pivot.dy, 0)
      ..multiply(Matrix4.identity()..setEntry(3, 2, perspective))
      ..multiply(Matrix4.rotationX(-tilt))
      ..multiply(Matrix4.diagonal3Values(fill, fill, 1))
      ..multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0));
  }

  /// Sky colours, from the top of the screen down to the horizon.
  static const List<Color> sky = [Color(0xFF0B2A5B), Color(0xFF6FA8DC)];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: sky,
            ),
          ),
          child: Transform(transform: transformFor(size), child: child),
        );
      },
    );
  }
}
