/// Intro screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Played every time the app opens: on a white screen an atomic bomb falls
/// and hits, a fireball and a mushroom cloud rise, the smoke fills the
/// screen and then clears to reveal the main menu (New Game, Resume, How to
/// Play). Tapping anywhere skips straight to the menu.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:harita/core/audio_service.dart';
import 'package:harita/presentation/screens/main_menu_screen.dart';

/// Shows the bomb intro on top of the [MainMenuScreen].
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  /// Total length of the intro.
  static const Duration duration = Duration(milliseconds: 5200);

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _boomPlayed = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: IntroScreen.duration)
          ..addListener(_onTick)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _done = true);
            }
          })
          ..forward();
  }

  void _onTick() {
    if (!_boomPlayed && _controller.value >= _IntroPainter.impact - 0.04) {
      _boomPlayed = true;
      ref.read(audioServiceProvider).playSfx(AudioService.sfxNuke);
    }
  }

  void _skip() {
    if (_done) return;
    _controller.stop();
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The menu is underneath; it shows once the smoke clears.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Opacity(
            opacity: _done ? 1 : _IntroPainter.menuOpacity(_controller.value),
            child: child,
          ),
          child: const MainMenuScreen(),
        ),
        if (!_done)
          GestureDetector(
            key: const Key('intro_overlay'),
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) =>
                  CustomPaint(painter: _IntroPainter(_controller.value)),
            ),
          ),
      ],
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

/// Draws the intro at progress [t] (0 … 1).
class _IntroPainter extends CustomPainter {
  _IntroPainter(this.t);

  final double t;

  /// Progress at which the bomb hits the ground.
  static const double impact = 0.2;

  static const double _cloudEnd = 0.55;
  static const double _coverEnd = 0.75;

  /// Opacity of the menu under the overlay at progress [t].
  static double menuOpacity(double t) => t < _coverEnd ? 0 : 1;

  static final List<_Puff> _capPuffs = _makePuffs(26, 1);
  static final List<_Puff> _stemPuffs = _makePuffs(14, 2);
  static final List<_Puff> _coverPuffs = _makePuffs(34, 3);

  static List<_Puff> _makePuffs(int n, int seed) {
    final rng = Random(seed);
    return [
      for (var i = 0; i < n; i++)
        _Puff(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          0.6 + rng.nextDouble() * 0.6,
          rng.nextDouble(),
        ),
    ];
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// A soft, blurred smoke puff.
  static void _puff(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35 + 1),
    );
  }

  /// A glowing ball: white-hot centre fading out through [mid] and [edge].
  static void _glow(
    Canvas canvas,
    Offset c,
    double r,
    Color mid,
    Color edge,
    double alpha,
  ) {
    if (r <= 0 || alpha <= 0) return;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            mid.withValues(alpha: alpha),
            edge.withValues(alpha: alpha * 0.8),
            edge.withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 0.7, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ground = h * 0.74;
    final cx = w / 2;
    final unit = min(w, h);

    final reveal = _seg(t, _coverEnd, 1);
    if (t < _coverEnd) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }

    // Screen shake right after the impact.
    final shake = t > impact && t < impact + 0.15
        ? sin(t * 400) * 12 * (1 - _seg(t, impact, impact + 0.15))
        : 0.0;
    canvas
      ..save()
      ..translate(shake, shake * 0.6);

    final groundPaint = Paint()
      ..color = const Color(0xFFD7CCC8)
      ..strokeWidth = 3;

    if (t < impact) {
      // ── The falling bomb ───────────────────────────────────────────────
      final fall = Curves.easeIn.transform(_seg(t, 0, impact));
      final y = -unit * 0.2 + (ground + unit * 0.2) * fall;
      canvas.drawLine(Offset(0, ground), Offset(w, ground), groundPaint);
      _drawBomb(canvas, Offset(cx, y), unit * 0.06);
    } else if (t < _coverEnd) {
      // ── Fireball, shock wave, mushroom cloud ───────────────────────────
      final grow = Curves.easeOutCubic.transform(_seg(t, impact, _cloudEnd));
      final cool = _seg(t, impact + 0.04, _cloudEnd + 0.05);
      final hot = Color.lerp(
        const Color(0xFFFFEB3B),
        const Color(0xFFE65100),
        cool,
      )!;
      final smoke = Color.lerp(
        const Color(0xFF8D6E63),
        const Color(0xFF616161),
        cool,
      )!;
      canvas.drawLine(Offset(0, ground), Offset(w, ground), groundPaint);

      // Shock wave racing along the ground.
      final wave = _seg(t, impact, impact + 0.2);
      if (wave < 1) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, ground),
            width: w * 2.2 * wave,
            height: unit * 0.18 * wave,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 * (1 - wave) + 1
            ..color = const Color(0xFFFFCC80).withValues(alpha: 1 - wave)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }

      // Dust skirt at the base.
      for (final p in _stemPuffs) {
        _puff(
          canvas,
          Offset(cx + p.x * unit * 0.42 * grow, ground - unit * 0.03 * p.r),
          unit * 0.07 * p.r * (0.3 + grow),
          smoke.withValues(alpha: 0.75),
        );
      }

      // Stem: a column of rising smoke, glowing at the bottom.
      final capY = ground - unit * 0.62 * grow;
      for (var i = 0; i < 12; i++) {
        final f = i / 11;
        final y = ground - (ground - capY) * f;
        final r = unit * (0.075 - 0.03 * f) * (0.4 + grow * 0.6);
        _puff(
          canvas,
          Offset(cx + sin(i * 1.7) * unit * 0.01, y),
          r,
          Color.lerp(hot, smoke, 0.35 + 0.5 * f)!,
        );
      }

      // Cap: a wide, rolling cloud with a glowing underside.
      final capW = unit * 0.36 * grow;
      final capH = unit * 0.15 * grow;
      for (final p in _capPuffs) {
        final ring = p.y; // -1 … 1: back to front of the rolling cap
        final pos = Offset(cx + p.x * capW, capY + ring * capH * 0.55);
        final shade = Color.lerp(hot, smoke, (0.3 + 0.7 * p.shade) * cool)!;
        _puff(canvas, pos, unit * 0.1 * p.r * grow, shade);
      }
      // Fireball heart inside the cap, fading as it cools.
      _glow(
        canvas,
        Offset(cx, capY + capH * 0.2),
        unit * 0.24 * grow,
        hot,
        const Color(0xFFFF6F00),
        1 - cool * 0.85,
      );

      // Smoke rolls over the whole screen.
      final cover = Curves.easeIn.transform(
        _seg(t, _cloudEnd - 0.1, _coverEnd),
      );
      if (cover > 0) {
        final diag = sqrt(w * w + h * h);
        for (final p in _coverPuffs) {
          _puff(
            canvas,
            Offset(cx + p.x * w * 0.7, capY + p.y * h * 0.7),
            diag * 0.3 * p.r * cover,
            Color.lerp(
              const Color(0xFF616161),
              const Color(0xFF9E9E9E),
              p.shade,
            )!,
          );
        }
      }

      // Blinding flash at the impact.
      final flash = 1 - _seg(t, impact, impact + 0.07);
      if (flash > 0) {
        _glow(
          canvas,
          Offset(cx, ground),
          unit * (0.2 + 1.4 * (1 - flash)),
          const Color(0xFFFFF59D),
          const Color(0xFFFFB300),
          flash,
        );
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = Colors.white.withValues(alpha: flash * 0.85),
        );
      }
    }
    canvas.restore();

    // ── The smoke drifts away, revealing the menu ─────────────────────────
    if (t >= _coverEnd) {
      final fade = 1 - Curves.easeIn.transform(reveal);
      for (final p in _coverPuffs) {
        final drift = 1 + reveal * 1.5;
        _puff(
          canvas,
          Offset(w / 2 + p.x * w * 0.6 * drift, h / 2 + p.y * h * 0.6 * drift),
          unit * 0.45 * p.r,
          Color.lerp(
            const Color(0xFF757575),
            const Color(0xFFBDBDBD),
            p.shade,
          )!.withValues(alpha: fade),
        );
      }
    }
  }

  void _drawBomb(Canvas canvas, Offset nose, double r) {
    final body = Paint()..color = const Color(0xFF37474F);
    final dark = Paint()..color = const Color(0xFF263238);
    final stripe = Paint()..color = const Color(0xFFFFC107);
    final center = nose.translate(0, -r * 1.6);
    canvas
      // Tail fins.
      ..drawPath(
        Path()
          ..moveTo(center.dx - r, center.dy - r * 2.6)
          ..lineTo(center.dx + r, center.dy - r * 2.6)
          ..lineTo(center.dx + r * 0.4, center.dy - r * 1.2)
          ..lineTo(center.dx - r * 0.4, center.dy - r * 1.2)
          ..close(),
        dark,
      )
      // Body.
      ..drawOval(
        Rect.fromCenter(center: center, width: r * 2, height: r * 3.6),
        body,
      )
      ..drawRect(
        Rect.fromCenter(
          center: center.translate(0, -r * 0.6),
          width: r * 1.9,
          height: r * 0.35,
        ),
        stripe,
      );
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}

class _Puff {
  const _Puff(this.x, this.y, this.r, this.shade);

  final double x;
  final double y;
  final double r;
  final double shade;
}
