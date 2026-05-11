// Painterly woven basket — the drop target for the basket-survey
// experiment. CustomPainter draws a hand-drawn-looking weave with
// wobbly horizontal "weft" courses crossing wobbly vertical "warp"
// stakes. Soft warm wood tones, slightly imperfect line weights so
// it reads as painted rather than vector-perfect.
//
// Two visual states drive the painter:
//   * `glow`  — true while a face is being dragged over the basket.
//                Adds a warm halo + lifts the rim a touch (a small
//                "I'm ready!" affordance). Best paired with an
//                AnimatedScale on the parent (1.0 → 1.05) for a
//                full breathing reaction.
//   * `recentDrop` — drives a subtle squash on the basket itself
//                  (set to true for ~250ms after a drop, then back
//                  to false). The painter does the actual squash
//                  via a vertical scale; the parent wraps in an
//                  AnimatedScale or AnimatedSwitcher.

import 'dart:math' as math;

import 'package:basecamp/features/experiment/basket_survey/basket_world.dart'
    show BasketGeometry;
import 'package:flutter/material.dart';

class BasketPainter extends CustomPainter {
  BasketPainter({
    required this.glow,
    this.recentDrop = false,
    this.seed = 0,
  });

  final bool glow;
  final bool recentDrop;
  final int seed;

  // ——— Palette (warm willow / rattan tones) ——————————————————
  static const Color _weaveBase = Color(0xFFB48656);
  static const Color _weaveDark = Color(0xFF8A562B);
  static const Color _weaveHi = Color(0xFFD9B67E);
  static const Color _shadow = Color(0xFF6B3F1B);
  static const Color _glowColor = Color(0xFF5DCAA5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // ignore: unused_local_variable
    final h = size.height; // referenced by some callers; kept for API.
    final rng = math.Random(seed); // stable per-instance jitter

    // Basket geometry: trapezoid — wider at top than bottom, with
    // a rounded base. Sourced from `BasketGeometry` so the painted
    // basket lines up exactly with the physics walls + floor —
    // marbles settle on the floor at the physics y, and the
    // painted basket bottom is at the same y. Without this we
    // get the "basket floating above the marble pile" bug:
    // bumping worldH for headroom shifted the relative ratios
    // and the painter drifted ~45px below physics.
    final basketLeft = w * 0.06;
    final basketRight = w * 0.94;
    const basketTop = BasketGeometry.rimY;
    const basketBottom = BasketGeometry.basketFloorY;
    final baseInset = w * 0.08;

    // ——— Warm halo behind the basket when active —————————————
    if (glow) {
      final glowPaint = Paint()
        ..color = _glowColor.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawOval(
        Rect.fromLTRB(
          basketLeft - 18,
          basketTop - 12,
          basketRight + 18,
          basketBottom + 12,
        ),
        glowPaint,
      );
    }

    // ——— Basket silhouette (filled, low contrast) — gives the ———
    // weave somewhere to land. Very pale wash so the weave reads
    // as the dominant surface.
    final silhouettePath = _basketSilhouette(
      Rect.fromLTRB(basketLeft, basketTop, basketRight, basketBottom),
      baseInset: baseInset,
    );
    canvas
      ..drawPath(
        silhouettePath,
        Paint()..color = _weaveBase.withValues(alpha: 0.18),
      )
      // ——— Vertical "warps" — the staves the weft weaves around ———
      // Drawn first so the weft can cross over them.
      ..save()
      ..clipPath(silhouettePath);
    final warpPaint = Paint()
      ..color = _weaveDark.withValues(alpha: 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const warpCount = 11;
    for (var i = 0; i < warpCount; i++) {
      final tx = i / (warpCount - 1);
      // Top + bottom x positions interpolate the trapezoid sides.
      final topX = basketLeft + (basketRight - basketLeft) * tx;
      final bottomX = basketLeft + baseInset +
          (basketRight - basketLeft - baseInset * 2) * tx;
      // Slight horizontal jitter — hand-drawn feel.
      final jitter = (rng.nextDouble() - 0.5) * 1.2;
      final p = Path()
        ..moveTo(topX + jitter, basketTop)
        ..quadraticBezierTo(
          (topX + bottomX) / 2 + jitter * 0.5,
          (basketTop + basketBottom) / 2,
          bottomX + jitter,
          basketBottom,
        );
      canvas.drawPath(p, warpPaint);
    }

    // ——— Horizontal "weft" — the visible weave courses ——————
    const weftCount = 9;
    for (var i = 0; i < weftCount; i++) {
      final ty = i / (weftCount - 1);
      final y = basketTop + (basketBottom - basketTop) * ty;
      // Trapezoid: row width tapers towards the base.
      final inset = baseInset * ty;
      final xStart = basketLeft + inset;
      final xEnd = basketRight - inset;
      _paintWeftCourse(
        canvas,
        rng,
        xStart: xStart,
        xEnd: xEnd,
        y: y,
        thick: 5.5 + ty * 0.6, // lower courses slightly thicker
      );
    }
    canvas.restore();

    // ——— Rim band — darker, slightly rounded; gives the basket ———
    // a visible top edge (the "lip" your eye lands on).
    final rimRect = Rect.fromLTWH(
      basketLeft - 4,
      basketTop - 8,
      (basketRight - basketLeft) + 8,
      14,
    );
    final rimPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_weaveDark, _shadow],
      ).createShader(rimRect);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(rimRect, const Radius.circular(8)),
        rimPaint,
      )
      // Highlight stripe across the rim — paint-stroke feel.
      ..drawLine(
        Offset(rimRect.left + 6, rimRect.top + 3),
        Offset(rimRect.right - 6, rimRect.top + 3),
        Paint()
          ..color = _weaveHi.withValues(alpha: 0.6)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      )
      // ——— Inner shadow at the rim — implies depth into the basket ——
      ..save()
      ..clipPath(silhouettePath);
    final innerShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _shadow.withValues(alpha: 0.45),
          _shadow.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromLTWH(
          basketLeft,
          basketTop,
          basketRight - basketLeft,
          (basketBottom - basketTop) * 0.30,
        ),
      );
    canvas
      ..drawRect(
        Rect.fromLTWH(
          basketLeft,
          basketTop,
          basketRight - basketLeft,
          (basketBottom - basketTop) * 0.30,
        ),
        innerShadow,
      )
      ..restore()
      // ——— Cast shadow under the basket — settles it on the surface ——
      ..drawOval(
        Rect.fromLTWH(
          basketLeft + baseInset - 4,
          basketBottom - 4,
          basketRight - basketLeft - baseInset * 2 + 8,
          12,
        ),
        Paint()
          ..color = _shadow.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
  }

  /// Trapezoid silhouette with rounded base — the basket outline.
  Path _basketSilhouette(Rect rect, {required double baseInset}) {
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - baseInset, rect.bottom - 14)
      ..arcToPoint(
        Offset(rect.right - baseInset - 14, rect.bottom),
        radius: const Radius.circular(14),
      )
      ..lineTo(rect.left + baseInset + 14, rect.bottom)
      ..arcToPoint(
        Offset(rect.left + baseInset, rect.bottom - 14),
        radius: const Radius.circular(14),
      )
      ..close();
  }

  /// Paint one horizontal weave course as a series of short
  /// alternating arches over invisible warps. The staggered
  /// arch direction reads as "in front / behind" the warps.
  void _paintWeftCourse(
    Canvas canvas,
    math.Random rng, {
    required double xStart,
    required double xEnd,
    required double y,
    required double thick,
  }) {
    const segments = 10;
    final dx = (xEnd - xStart) / segments;
    final base = Paint()
      ..color = _weaveBase
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final shadow = Paint()
      ..color = _shadow.withValues(alpha: 0.30)
      ..strokeWidth = thick * 0.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < segments; i++) {
      final x0 = xStart + dx * i;
      final x1 = x0 + dx;
      // Alternate arch direction: even segments arch up, odd down.
      final archUp = (i + (y * 0.1).round()).isEven;
      final mid = Offset((x0 + x1) / 2, y + (archUp ? -1.4 : 1.4));
      final jitter = (rng.nextDouble() - 0.5) * 0.6;
      final path = Path()
        ..moveTo(x0, y + jitter)
        ..quadraticBezierTo(mid.dx, mid.dy, x1, y + jitter);
      // Shadow first (behind the highlight), then the body stroke.
      canvas
        ..drawPath(path, shadow)
        ..drawPath(path, base);
    }
  }

  @override
  bool shouldRepaint(covariant BasketPainter old) =>
      old.glow != glow ||
      old.recentDrop != recentDrop ||
      old.seed != seed;
}
