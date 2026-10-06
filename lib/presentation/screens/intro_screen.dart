/// Intro screen for Harita: Kendi İmparatorluğunu Kur.
///
/// Played every time the app opens: on a white screen an atomic bomb falls
/// and hits, a blinding flash gives way to a real photograph of an atomic
/// test explosion (Operation Upshot-Knothole "Badger", 1953 — public domain)
/// that swells as the fireball grows, then dark smoke rolls over the screen
/// and clears to reveal the main menu (New Game, Resume, How to Play).
/// Tapping anywhere skips straight to the menu.
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
  static const Duration duration = Duration(milliseconds: 6000);

  /// The explosion photograph.
  static const String photoAsset = 'assets/images/nuke_badger.jpg';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the photo early so it is ready at the moment of the blast.
    precacheImage(const AssetImage(IntroScreen.photoAsset), context);
  }

  void _onTick() {
    if (!_boomPlayed && _controller.value >= IntroTimeline.soundStart) {
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
            opacity: _done ? 1 : IntroTimeline.menuOpacity(_controller.value),
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
              builder: (context, _) {
                final t = _controller.value;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (t < IntroTimeline.coverEnd)
                      const ColoredBox(color: Colors.white),
                    // The real explosion, growing like a fireball.
                    if (t >= IntroTimeline.impact && t < IntroTimeline.coverEnd)
                      Opacity(
                        opacity: IntroTimeline.photoOpacity(t),
                        child: Transform.translate(
                          offset: IntroTimeline.shake(t),
                          child: Transform.scale(
                            scale: IntroTimeline.photoScale(t),
                            alignment: const Alignment(0, -0.1),
                            child: Image.asset(
                              IntroScreen.photoAsset,
                              key: const Key('intro_photo'),
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, 0.2),
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    CustomPaint(painter: _IntroPainter(t)),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

// ─── Timeline ────────────────────────────────────────────────────────────────

/// Timing of the intro as fractions of [IntroScreen.duration].
abstract final class IntroTimeline {
  /// The bomb hits the ground.
  static const double impact = 0.18;

  /// The blast sound starts with a 1 s falling whistle, so it is started
  /// that much before [impact] for the boom to land on the flash.
  static const double soundStart = impact - 1.0 / 6.0;

  /// The white flash has faded and the photo is fully visible.
  static const double flashEnd = 0.28;

  /// Smoke starts rolling in.
  static const double smokeStart = 0.6;

  /// Smoke covers the whole screen; the menu is placed underneath.
  static const double coverEnd = 0.78;

  static double seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// Opacity of the menu under the overlay at progress [t].
  static double menuOpacity(double t) => t < coverEnd ? 0 : 1;

  /// The photo fades in under the flash.
  static double photoOpacity(double t) =>
      Curves.easeOut.transform(seg(t, impact, impact + 0.06));

  /// The photo starts close-up and pulls back as the cloud grows.
  static double photoScale(double t) =>
      1.3 - 0.3 * Curves.easeOutCubic.transform(seg(t, impact, coverEnd));

  /// Ground shake right after the blast.
  static Offset shake(double t) {
    if (t < impact || t > impact + 0.16) return Offset.zero;
    final k = 1 - seg(t, impact, impact + 0.16);
    return Offset(sin(t * 420) * 12 * k, cos(t * 510) * 8 * k);
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

/// Draws the falling bomb, the flash and the smoke at progress [t] (0 … 1).
class _IntroPainter extends CustomPainter {
  _IntroPainter(this.t);

  final double t;

  static final List<_Puff> _smokePuffs = _makePuffs(60, 3);

  static List<_Puff> _makePuffs(int n, int seed) {
    final rng = Random(seed);
    return [
      for (var i = 0; i < n; i++)
        _Puff(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          0.5 + rng.nextDouble() * 0.7,
          rng.nextDouble(),
        ),
    ];
  }

  /// A soft, blurred smoke puff.
  static void _puff(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45 + 1),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final unit = min(w, h);
    final ground = h * 0.8;
    const seg = IntroTimeline.seg;

    // ── The falling bomb ────────────────────────────────────────────────
    if (t < IntroTimeline.impact) {
      final fall = Curves.easeIn.transform(seg(t, 0, IntroTimeline.impact));
      final y = -unit * 0.3 + (ground + unit * 0.3) * fall;
      // Its shadow on the ground grows as it comes down.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2, ground),
          width: unit * 0.25 * fall,
          height: unit * 0.04 * fall,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25 * fall)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      _drawBomb(canvas, Offset(w / 2, y), unit * 0.055);
    }

    // ── Blinding flash at the impact ────────────────────────────────────
    final flash =
        seg(t, IntroTimeline.impact, IntroTimeline.impact + 0.015) *
        (1 - seg(t, IntroTimeline.impact + 0.02, IntroTimeline.flashEnd));
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 0.4),
            radius: 1.2,
            colors: [
              Colors.white.withValues(alpha: flash),
              const Color(0xFFFFF8E1).withValues(alpha: flash),
              const Color(0xFFFFE0B2).withValues(alpha: flash * 0.9),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    // ── Smoke rolls over the whole screen, then drifts away ─────────────
    final cover = Curves.easeIn.transform(
      seg(t, IntroTimeline.smokeStart, IntroTimeline.coverEnd),
    );
    final clear = Curves.easeIn.transform(seg(t, IntroTimeline.coverEnd, 1));
    if (cover > 0) {
      final diag = sqrt(w * w + h * h);
      for (final p in _smokePuffs) {
        final drift = 1 + clear * 1.8;
        final c = Offset(
          w / 2 + p.x * w * 0.6 * drift,
          h * 0.55 + p.y * h * 0.6 * drift - cover * h * 0.1,
        );
        final base = Color.lerp(
          const Color(0xFF3E2723),
          const Color(0xFF757575),
          p.shade,
        )!;
        // Big soft billows that thicken (rather than grow from dots).
        _puff(
          canvas,
          c,
          diag * 0.3 * p.r * (0.6 + 0.4 * cover),
          base.withValues(alpha: cover * (1 - clear)),
        );
      }
    }
  }

  /// A heavy, round atomic bomb ("Fat Man" shape) with its nose at [nose].
  void _drawBomb(Canvas canvas, Offset nose, double r) {
    final c = nose.translate(0, -r * 1.25);
    final body = Rect.fromCenter(center: c, width: r * 2.4, height: r * 2.6);
    final steel = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFF8D9A72), Color(0xFF4A5536), Color(0xFF1F2616)],
        stops: const [0, 0.45, 1],
      ).createShader(body);
    final dark = Paint()..color = const Color(0xFF1F2616);

    // Motion streaks above the bomb.
    final streak = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 2;
    for (var i = -2; i <= 2; i++) {
      final x = c.dx + i * r * 0.45;
      canvas.drawLine(
        Offset(x, c.dy - r * 3.2),
        Offset(x, c.dy - r * 6),
        streak,
      );
    }
    // Box tail with fins.
    final tail = Rect.fromCenter(
      center: c.translate(0, -r * 2),
      width: r * 1.8,
      height: r * 1.0,
    );
    canvas
      ..drawRect(
        Rect.fromCenter(
          center: c.translate(0, -r * 1.4),
          width: r * 0.8,
          height: r * 0.9,
        ),
        dark,
      )
      ..drawRect(tail, dark)
      ..drawRect(
        tail.deflate(r * 0.15),
        Paint()..color = const Color(0xFF3A4429),
      )
      // Body.
      ..drawOval(body, steel)
      // Highlight.
      ..drawOval(
        Rect.fromCenter(
          center: c.translate(-r * 0.5, -r * 0.4),
          width: r * 0.5,
          height: r * 1.1,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15),
      )
      // Seam and bolts.
      ..drawLine(
        Offset(body.left + r * 0.05, c.dy),
        Offset(body.right - r * 0.05, c.dy),
        Paint()
          ..color = const Color(0xFF151A0F)
          ..strokeWidth = 1.5,
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
