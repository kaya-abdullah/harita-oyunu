/// Three-dimensional looking units for Harita: soldiers, tanks, bombers,
/// explosions and forest trees.
///
/// Everything is drawn with shading (light from the top left), soft ground
/// shadows and highlights, so the pieces look like little 3D models on the
/// map. The functions only use `dart:ui`, so both the Flame map and Flutter
/// widgets (the HUD, the shop) can draw them.
library;

import 'dart:math';
import 'dart:ui';

/// Lighter / darker variants of [c] for the lit and shaded faces.
Color _shade(Color c, double amount) => amount >= 0
    ? Color.lerp(c, const Color(0xFFFFFFFF), amount)!
    : Color.lerp(c, const Color(0xFF000000), -amount)!;

final Paint _shadowPaint = Paint()
  ..color = const Color(0x55000000)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

/// A soft oval shadow on the ground.
void _groundShadow(Canvas canvas, Offset c, double w, double h) {
  canvas.drawOval(
    Rect.fromCenter(center: c, width: w, height: h),
    _shadowPaint,
  );
}

// ─── Soldier ─────────────────────────────────────────────────────────────────

/// A soldier standing (or walking, with [step] 0…1) with his feet at
/// [feet]; [size] is his height. [color] is the army's colour (uniform).
void drawSoldier(
  Canvas canvas,
  Offset feet,
  double size,
  Color color, {
  double step = 0,
}) {
  final s = size;
  _groundShadow(canvas, feet.translate(s * 0.08, 0), s * 0.55, s * 0.16);

  final swing = sin(step * 2 * pi) * s * 0.09;
  final boot = Paint()..color = const Color(0xFF2B2B2B);
  final trouser = Paint()..color = _shade(color, -0.45);
  // Legs (one forward, one back while walking).
  for (final dx in [-1.0, 1.0]) {
    final x = feet.dx + dx * s * 0.08 + (dx < 0 ? swing : -swing);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - s * 0.06, feet.dy - s * 0.42, s * 0.12, s * 0.36),
          Radius.circular(s * 0.04),
        ),
        trouser,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - s * 0.07, feet.dy - s * 0.09, s * 0.16, s * 0.09),
          Radius.circular(s * 0.03),
        ),
        boot,
      );
  }

  // Body: a rounded box lit from the left.
  final body = Rect.fromLTWH(
    feet.dx - s * 0.17,
    feet.dy - s * 0.78,
    s * 0.34,
    s * 0.4,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(body, Radius.circular(s * 0.08)),
    Paint()
      ..shader = Gradient.linear(
        body.topLeft,
        body.topRight,
        [_shade(color, 0.35), color, _shade(color, -0.4)],
        [0, 0.45, 1],
      ),
  );
  // Belt.
  canvas.drawRect(
    Rect.fromLTWH(body.left, body.bottom - s * 0.08, body.width, s * 0.05),
    Paint()..color = const Color(0xFF3E2723),
  );

  // Rifle across the chest.
  final rifle = Paint()
    ..color = const Color(0xFF3B3B3B)
    ..strokeWidth = s * 0.06
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(feet.dx - s * 0.22, feet.dy - s * 0.42),
    Offset(feet.dx + s * 0.28, feet.dy - s * 0.86),
    rifle,
  );

  // Face and helmet (a shaded dome).
  final head = Offset(feet.dx, feet.dy - s * 0.88);
  canvas.drawCircle(head, s * 0.11, Paint()..color = const Color(0xFFE0B48A));
  final helmet = Rect.fromCircle(
    center: head.translate(0, -s * 0.04),
    radius: s * 0.15,
  );
  canvas.drawArc(
    helmet,
    pi,
    pi,
    true,
    Paint()
      ..shader = Gradient.radial(
        helmet.center.translate(-s * 0.06, -s * 0.06),
        s * 0.2,
        [_shade(color, 0.1), _shade(color, -0.55)],
      ),
  );
}

/// A squad of soldiers around [center] — up to [count] of them in two
/// ranks, each [size] tall.
void drawSquad(
  Canvas canvas,
  Offset center,
  double size,
  Color color, {
  int count = 3,
  double step = 0,
}) {
  final n = count.clamp(1, 5);
  for (var i = 0; i < n; i++) {
    final row = i.isEven ? 0.0 : 1.0;
    final dx = (i - (n - 1) / 2) * size * 0.42;
    drawSoldier(
      canvas,
      center.translate(dx, row * size * 0.22),
      size,
      color,
      step: step + i * 0.3,
    );
  }
}

// ─── Tank ────────────────────────────────────────────────────────────────────

/// A tank seen from above at an angle, centred on [center], [size] long,
/// with its gun pointing at [angle] (radians, 0 = right).
void drawTank(
  Canvas canvas,
  Offset center,
  double size,
  Color color, {
  double angle = 0,
}) {
  final s = size;
  _groundShadow(canvas, center.translate(s * 0.06, s * 0.2), s * 1.05, s * 0.5);

  canvas
    ..save()
    ..translate(center.dx, center.dy);
  final facingLeft = cos(angle) < 0;
  if (facingLeft) canvas.scale(-1, 1);

  // Tracks with road wheels.
  final track = RRect.fromRectAndRadius(
    Rect.fromLTWH(-s * 0.5, s * 0.02, s, s * 0.24),
    Radius.circular(s * 0.12),
  );
  canvas.drawRRect(track, Paint()..color = const Color(0xFF262626));
  final wheel = Paint()..color = const Color(0xFF5A5A5A);
  final hub = Paint()..color = const Color(0xFF8C8C8C);
  for (var i = 0; i < 5; i++) {
    final c = Offset(-s * 0.38 + i * s * 0.19, s * 0.14);
    canvas
      ..drawCircle(c, s * 0.075, wheel)
      ..drawCircle(c, s * 0.03, hub);
  }

  // Hull: lit top face and a darker side face.
  final side = Path()
    ..moveTo(-s * 0.48, s * 0.04)
    ..lineTo(s * 0.5, s * 0.04)
    ..lineTo(s * 0.44, -s * 0.1)
    ..lineTo(-s * 0.46, -s * 0.1)
    ..close();
  canvas.drawPath(side, Paint()..color = _shade(color, -0.35));
  final top = Path()
    ..moveTo(-s * 0.46, -s * 0.1)
    ..lineTo(s * 0.44, -s * 0.1)
    ..lineTo(s * 0.36, -s * 0.22)
    ..lineTo(-s * 0.4, -s * 0.22)
    ..close();
  canvas.drawPath(
    top,
    Paint()
      ..shader = Gradient.linear(Offset(0, -s * 0.22), Offset(0, -s * 0.1), [
        _shade(color, 0.3),
        _shade(color, 0.05),
      ]),
  );

  // Gun barrel (a shaded cylinder).
  final barrel = Rect.fromLTWH(s * 0.05, -s * 0.33, s * 0.55, s * 0.065);
  canvas.drawRRect(
    RRect.fromRectAndRadius(barrel, Radius.circular(s * 0.03)),
    Paint()
      ..shader = Gradient.linear(barrel.topCenter, barrel.bottomCenter, [
        const Color(0xFF9E9E9E),
        const Color(0xFF424242),
      ]),
  );
  canvas.drawRect(
    Rect.fromLTWH(s * 0.56, -s * 0.345, s * 0.07, s * 0.095),
    Paint()..color = const Color(0xFF303030),
  );

  // Turret: a lit dome.
  final turret = Rect.fromCenter(
    center: Offset(-s * 0.02, -s * 0.27),
    width: s * 0.44,
    height: s * 0.26,
  );
  canvas.drawOval(
    turret,
    Paint()
      ..shader = Gradient.radial(
        turret.center.translate(-s * 0.08, -s * 0.06),
        s * 0.26,
        [_shade(color, 0.45), color, _shade(color, -0.5)],
        [0, 0.5, 1],
      ),
  );
  canvas
    ..drawCircle(
      Offset(-s * 0.08, -s * 0.36),
      s * 0.04,
      Paint()..color = _shade(color, -0.6),
    )
    ..restore();
}

// ─── Bomber ──────────────────────────────────────────────────────────────────

/// A four-engine bomber seen from above, centred on [center], [size] from
/// wing tip to wing tip, flying towards [angle] (radians, 0 = right). Its
/// shadow falls [altitude] below it.
void drawBomber(
  Canvas canvas,
  Offset center,
  double size,
  Color color, {
  double angle = 0,
  double altitude = 0.35,
}) {
  final s = size;
  // Shadow on the ground, offset by the height.
  canvas
    ..save()
    ..translate(center.dx + s * altitude * 0.4, center.dy + s * altitude)
    ..rotate(angle);
  _planeShape(canvas, s, _shadowPaint, _shadowPaint, _shadowPaint);
  canvas
    ..restore()
    ..save()
    ..translate(center.dx, center.dy)
    ..rotate(angle);

  final metal = _shade(color, 0.15);
  final wingPaint = Paint()
    ..shader = Gradient.linear(
      Offset(0, -s * 0.5),
      Offset(0, s * 0.5),
      [_shade(metal, 0.35), metal, _shade(metal, -0.45)],
      [0, 0.45, 1],
    );
  final bodyPaint = Paint()
    ..shader = Gradient.linear(
      Offset(0, -s * 0.08),
      Offset(0, s * 0.08),
      [_shade(metal, 0.6), metal, _shade(metal, -0.55)],
      [0, 0.4, 1],
    );
  final engine = Paint()..color = _shade(color, -0.55);
  _planeShape(canvas, s, wingPaint, bodyPaint, engine);

  // Cockpit glass with a glint.
  canvas
    ..drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.4, 0),
        width: s * 0.1,
        height: s * 0.07,
      ),
      Paint()..color = const Color(0xFF263238),
    )
    ..drawCircle(
      Offset(s * 0.41, -s * 0.015),
      s * 0.012,
      Paint()..color = const Color(0xCCFFFFFF),
    )
    ..restore();
}

void _planeShape(Canvas canvas, double s, Paint wing, Paint body, Paint eng) {
  // Swept main wings.
  final wings = Path()
    ..moveTo(s * 0.12, 0)
    ..lineTo(-s * 0.08, -s * 0.5)
    ..lineTo(-s * 0.18, -s * 0.5)
    ..lineTo(-s * 0.1, 0)
    ..lineTo(-s * 0.18, s * 0.5)
    ..lineTo(-s * 0.08, s * 0.5)
    ..close();
  canvas.drawPath(wings, wing);
  // Tail plane.
  final tail = Path()
    ..moveTo(-s * 0.36, 0)
    ..lineTo(-s * 0.46, -s * 0.18)
    ..lineTo(-s * 0.5, -s * 0.18)
    ..lineTo(-s * 0.46, 0)
    ..lineTo(-s * 0.5, s * 0.18)
    ..lineTo(-s * 0.46, s * 0.18)
    ..close();
  canvas.drawPath(tail, wing);
  // Fuselage.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.13),
      Radius.circular(s * 0.065),
    ),
    body,
  );
  // Four engines.
  for (final y in [-0.33, -0.17, 0.17, 0.33]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-s * 0.02 + y.abs() * -0.2 * s, y * s),
          width: s * 0.14,
          height: s * 0.055,
        ),
        Radius.circular(s * 0.025),
      ),
      eng,
    );
  }
}

// ─── Explosions ──────────────────────────────────────────────────────────────

/// A fireball growing and fading at [center]; [t] runs 0…1, [radius] is its
/// largest size.
void drawExplosion(Canvas canvas, Offset center, double radius, double t) {
  final grow = Curves3d.easeOut(t.clamp(0, 1));
  final fade = (1 - t).clamp(0.0, 1.0);
  final r = radius * (0.25 + 0.75 * grow);
  // Smoke ring.
  canvas.drawCircle(
    center,
    r * 1.15,
    Paint()
      ..color = Color.fromARGB((120 * fade).round(), 40, 36, 33)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
  );
  // Fireball.
  canvas.drawCircle(
    center,
    r,
    Paint()
      ..shader = Gradient.radial(
        center.translate(-r * 0.2, -r * 0.2),
        r,
        [
          Color.fromARGB((255 * fade).round(), 255, 253, 231),
          Color.fromARGB((235 * fade).round(), 255, 179, 0),
          Color.fromARGB((200 * fade).round(), 230, 74, 25),
          Color.fromARGB(0, 120, 30, 10),
        ],
        [0, 0.35, 0.7, 1],
      ),
  );
}

/// The big Atom / Nuclear bomb blast: flash, fireball, shock ring and a
/// mushroom cloud rising at [center]; [t] runs 0…1.
void drawMushroom(Canvas canvas, Offset center, double radius, double t) {
  final p = t.clamp(0.0, 1.0);
  final fade = p < 0.7 ? 1.0 : (1 - p) / 0.3;
  // Shock ring.
  canvas.drawCircle(
    center,
    radius * (0.3 + 1.4 * p),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08
      ..color = Color.fromARGB((180 * (1 - p)).round(), 255, 255, 255),
  );
  final rise = Curves3d.easeOut(p);
  final stemTop = center.translate(0, -radius * 1.4 * rise);
  // Stem.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(
        center.dx - radius * 0.16,
        stemTop.dy,
        center.dx + radius * 0.16,
        center.dy,
      ),
      Radius.circular(radius * 0.1),
    ),
    Paint()
      ..shader = Gradient.linear(
        Offset(center.dx - radius * 0.16, 0),
        Offset(center.dx + radius * 0.16, 0),
        [
          Color.fromARGB((230 * fade).round(), 255, 213, 79),
          Color.fromARGB((230 * fade).round(), 191, 54, 12),
        ],
      ),
  );
  // Cap: a lit dome of fire and smoke.
  final cap = Rect.fromCenter(
    center: stemTop,
    width: radius * (0.6 + 1.0 * rise),
    height: radius * (0.4 + 0.55 * rise),
  );
  canvas.drawOval(
    cap,
    Paint()
      ..shader = Gradient.radial(
        cap.center.translate(-cap.width * 0.15, -cap.height * 0.2),
        cap.width * 0.6,
        [
          Color.fromARGB((255 * fade).round(), 255, 241, 118),
          Color.fromARGB((240 * fade).round(), 255, 112, 67),
          Color.fromARGB((220 * fade).round(), 93, 64, 55),
        ],
        [0, 0.45, 1],
      ),
  );
  // Fireball at the ground.
  drawExplosion(canvas, center, radius * 0.7, min(1, p * 1.4));
}

// ─── Forest ──────────────────────────────────────────────────────────────────

/// A round shaded tree with its trunk base at [base], [size] tall.
void drawTree(Canvas canvas, Offset base, double size) {
  final s = size;
  _groundShadow(canvas, base.translate(s * 0.12, 0), s * 0.7, s * 0.2);
  canvas.drawRect(
    Rect.fromLTWH(base.dx - s * 0.06, base.dy - s * 0.35, s * 0.12, s * 0.35),
    Paint()..color = const Color(0xFF5D4037),
  );
  final crown = base.translate(0, -s * 0.62);
  canvas.drawCircle(
    crown,
    s * 0.36,
    Paint()
      ..shader = Gradient.radial(
        crown.translate(-s * 0.12, -s * 0.12),
        s * 0.45,
        [
          const Color(0xFF81C784),
          const Color(0xFF2E7D32),
          const Color(0xFF1B5E20),
        ],
        [0, 0.55, 1],
      ),
  );
}

/// A small grove of [drawTree]s around [center].
void drawForest(Canvas canvas, Offset center, double size) {
  const spots = [
    Offset(-0.6, 0.1),
    Offset(0.55, 0.15),
    Offset(-0.05, -0.25),
    Offset(0.15, 0.45),
    Offset(-0.35, 0.55),
  ];
  for (final o in spots) {
    drawTree(canvas, center + o * size, size * (0.85 + (o.dx.abs() * 0.2)));
  }
}

/// Easing helpers (kept here so `dart:ui`-only code needs no Flutter).
abstract final class Curves3d {
  /// Fast start, gentle end.
  static double easeOut(double t) => 1 - pow(1 - t, 3).toDouble();
}
