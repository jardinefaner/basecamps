// Editorial paper-craft helpers for the basket-survey thank-you
// card. These are the visual primitives the printable end-card
// uses — they have no relationship to the gameplay (faces /
// physics / drag-drop). Imported only by `thank_you_card.dart`.
//
//   * `PaperGrain`         — a fine speckle overlay so the
//                            parchment background reads as paper.
//   * `StampPanel`         — bordered panel with offset shadow
//                            border, the signature "ink-stamp"
//                            look from the design reference.
//   * `ThumbIconPainter`   — colored circle + rotated thumb. Used
//                            as decorative chips next to scores.
//   * `JarPainter`         — glass mason-jar silhouette. Optional
//                            decorative element; the actual basket
//                            snapshot in the card is the live
//                            `BasketWorldWidget` capture, not this.
//   * `BasketRibbonPainter`— gift ribbon + tied bow drawn ON TOP
//                            of the basket snapshot in the card.
//                            Makes the keepsake feel "wrapped"
//                            without changing the basket itself.

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════
// Thumb icon
// ═════════════════════════════════════════════════════════════════

/// Skin-toned palette — chosen warm enough to read on the
/// parchment background without competing with the choice
/// circles' accent colors.
class _ThumbSkin {
  const _ThumbSkin._();
  static const Color base = Color(0xFFE8B88A);
  static const Color shade = Color(0xFFD4956A);
  static const Color light = Color(0xFFF0CBA8);
  static const Color nail = Color(0xFFF5DEC8);
}

/// A circle with a thumb inside, rotated by [angleDegrees]
/// (0 = thumb pointing DOWN, 180 = pointing UP). Background
/// fill + outline color come from the choice's palette.
class ThumbIconPainter extends CustomPainter {
  const ThumbIconPainter({
    required this.angleDegrees,
    required this.color,
    required this.background,
    this.outlineWidth = 2.0,
  });

  final double angleDegrees;
  final Color color;
  final Color background;
  final double outlineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = math.min(w, h) / 2;
    final center = Offset(w / 2, h / 2);

    // Circle background + outline.
    canvas
      ..drawCircle(
        center,
        r - outlineWidth / 2,
        Paint()..color = background,
      )
      ..drawCircle(
        center,
        r - outlineWidth / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineWidth,
      );

    // Thumb rendering — drawn as if pointing DOWN, then rotated.
    // Coordinate system inside the rotated frame is anchored at
    // canvas centre, with +y pointing toward the wrist (the
    // direction of the thumb's "down" reference).
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angleDegrees * math.pi / 180);

    // The HTML reference has a 64×64 canvas; scale our local
    // drawing to the actual size.
    final s = (r * 2) / 64;

    final fistFill = Paint()..color = _ThumbSkin.base;
    final shadeStroke = Paint()
      ..color = _ThumbSkin.shade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 * s;

    // Wrist (the bit emerging from the "sleeve").
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-5 * s, -18 * s, 10 * s, 9 * s),
        Radius.circular(2.5 * s),
      ),
      Paint()..color = _ThumbSkin.shade,
    );

    // Fist body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-11 * s, -10 * s, 22 * s, 15 * s),
        Radius.circular(6 * s),
      ),
      fistFill,
    );

    // Three knuckle bumps along the bottom of the fist.
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: Offset(-6 * s, 5 * s),
          width: 7 * s,
          height: 5 * s,
        ),
        fistFill,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(1 * s, 5.5 * s),
          width: 7 * s,
          height: 5 * s,
        ),
        fistFill,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(8 * s, 5 * s),
          width: 6 * s,
          height: 5 * s,
        ),
        fistFill,
      );

    // Finger separator lines.
    canvas
      ..drawLine(Offset(-3 * s, -9 * s), Offset(-3 * s, 3 * s),
          Paint()
            ..color = _ThumbSkin.shade.withValues(alpha: 0.5)
            ..strokeWidth = 0.7 * s)
      ..drawLine(Offset(4 * s, -9 * s), Offset(4 * s, 3 * s),
          Paint()
            ..color = _ThumbSkin.shade.withValues(alpha: 0.5)
            ..strokeWidth = 0.7 * s);

    // Knuckle shines on top.
    final knuckleHi = Paint()
      ..color = _ThumbSkin.light.withValues(alpha: 0.6);
    canvas
      ..drawCircle(Offset(-6 * s, -6 * s), 1.2 * s, knuckleHi)
      ..drawCircle(Offset(1 * s, -6.5 * s), 1.2 * s, knuckleHi)
      ..drawCircle(Offset(8 * s, -6 * s), 1.2 * s, knuckleHi);

    // Thumb proper — sticks out to the right of the fist,
    // pointing down (toward +y in our rotated frame).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * s, -6 * s, 8 * s, 17 * s),
        Radius.circular(4 * s),
      ),
      fistFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * s, -6 * s, 8 * s, 17 * s),
        Radius.circular(4 * s),
      ),
      shadeStroke,
    );

    // Thumb nail.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(11.5 * s, 6 * s, 5 * s, 3.5 * s),
        Radius.circular(1.8 * s),
      ),
      Paint()..color = _ThumbSkin.nail,
    );

    // Thumb knuckle line.
    canvas.drawLine(
      Offset(14 * s, -2 * s),
      Offset(14 * s, 1 * s),
      Paint()
        ..color = _ThumbSkin.shade.withValues(alpha: 0.4)
        ..strokeWidth = 0.6 * s,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ThumbIconPainter old) =>
      old.angleDegrees != angleDegrees ||
      old.color != color ||
      old.background != background ||
      old.outlineWidth != outlineWidth;
}

/// A widget convenience around `ThumbIconPainter`. Sized via
/// the parent's BoxConstraints (or a wrapping SizedBox).
class ThumbIcon extends StatelessWidget {
  const ThumbIcon({
    required this.angleDegrees,
    required this.color,
    required this.background,
    super.key,
    this.size,
    this.outlineWidth = 2.0,
  });

  final double angleDegrees;
  final Color color;
  final Color background;
  final double? size;
  final double outlineWidth;

  @override
  Widget build(BuildContext context) {
    final painter = ThumbIconPainter(
      angleDegrees: angleDegrees,
      color: color,
      background: background,
      outlineWidth: outlineWidth,
    );
    if (size != null) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: painter),
      );
    }
    return CustomPaint(painter: painter);
  }
}

// ═════════════════════════════════════════════════════════════════
// Glass jar
// ═════════════════════════════════════════════════════════════════

/// Glass mason jar silhouette. Translucent fill + faint stroke
/// so orbs inside are visible. Lid + outer rim are stroked in
/// solid ink. Two diagonal highlight strokes on the left to read
/// as "glass".
///
/// The path mirrors the SVG in the HTML mockup; geometry is
/// declared in its own 190×270 design space and scaled to the
/// canvas size so the jar's rendered dimensions follow the
/// containing widget.
class JarPainter extends CustomPainter {
  const JarPainter({this.inkColor = const Color(0xFF1A1A1A)});

  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 190;
    final sy = size.height / 270;
    canvas
      ..save()
      ..scale(sx, sy);

    // Body silhouette: shoulders fall from the neck (y=56),
    // straight side to ~y=240, rounded base at y=258.
    final bodyPath = Path()
      ..moveTo(38, 56)
      ..lineTo(28, 240)
      ..quadraticBezierTo(28, 258, 48, 258)
      ..lineTo(142, 258)
      ..quadraticBezierTo(162, 258, 162, 240)
      ..lineTo(152, 56)
      ..close();
    canvas
      ..drawPath(
        bodyPath,
        Paint()..color = const Color(0xFFC8D2DC).withValues(alpha: 0.14),
      )
      ..drawPath(
        bodyPath,
        Paint()
          ..color = const Color(0xFF787E8C).withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

    // Neck collar (the recessed band below the screw lid).
    final neckRect = Rect.fromLTWH(48, 30, 94, 28);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(neckRect, const Radius.circular(4)),
        Paint()..color = const Color(0xFFC8D2DC).withValues(alpha: 0.12),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(neckRect, const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFF787E8C).withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

    // Screw lid — drawn in solid ink so it reads as the cap.
    final lidRect = Rect.fromLTWH(40, 20, 110, 13);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(lidRect, const Radius.circular(4)),
        Paint()
          ..color = inkColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      )
      // Lid mid-line — subtle horizontal at the centre of the cap.
      ..drawLine(
        const Offset(40, 26.5),
        const Offset(150, 26.5),
        Paint()
          ..color = inkColor.withValues(alpha: 0.25)
          ..strokeWidth = 0.8,
      )
      // Two diagonal highlights on the left side — ink-stamp glass.
      ..drawLine(
        const Offset(46, 74),
        const Offset(42, 176),
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        const Offset(52, 80),
        const Offset(49, 155),
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.20)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JarPainter old) =>
      old.inkColor != inkColor;
}

// ═════════════════════════════════════════════════════════════════
// Paper grain
// ═════════════════════════════════════════════════════════════════

/// Cheap, deterministic speckle overlay so the parchment surface
/// reads as paper rather than flat color. Painted once on widget
/// init and cached via the seed; the painter's `shouldRepaint`
/// returns false unless the seed changes.
class PaperGrainPainter extends CustomPainter {
  PaperGrainPainter({this.seed = 1, this.density = 1800, this.opacity = 0.06});

  final int seed;

  /// Number of speckles over the whole canvas. ~1800 reads as
  /// a soft grain at the typical app size.
  final int density;

  /// Speckle opacity (0..1). 0.06 is barely visible but adds
  /// the "real paper" feel.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..color = const Color(0xFF1A1A1A).withValues(
      alpha: opacity,
    );
    for (var i = 0; i < density; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.4 + rng.nextDouble() * 0.8;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PaperGrainPainter old) =>
      old.seed != seed ||
      old.density != density ||
      old.opacity != opacity;
}

/// Background widget that paints the paper grain over its child.
/// The grain sits ABOVE everything inside, with `IgnorePointer`
/// so it never absorbs taps.
class PaperGrain extends StatelessWidget {
  const PaperGrain({required this.child, super.key, this.seed = 1});
  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: PaperGrainPainter(seed: seed),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Stamp button — black box with offset double-shadow border
// ═════════════════════════════════════════════════════════════════

/// The signature button look from the HTML: a square panel with
/// a 2px black border and a second 2px border offset 4px down +
/// right behind it, like an ink-stamped sticker. The hover state
/// in CSS shifts the panel by 1px and the shadow by another 1px
/// for a "lift" effect; we replicate via AnimatedContainer.
class StampPanel extends StatelessWidget {
  const StampPanel({
    required this.child,
    super.key,
    this.selected = false,
    this.faded = false,
    this.onTap,
    this.shadowOffset = const Offset(4, 4),
  });

  final Widget child;
  final bool selected;
  final bool faded;
  final VoidCallback? onTap;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: faded ? 0.15 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: shadowOffset.dx,
            top: shadowOffset.dy,
            right: -shadowOffset.dx,
            bottom: -shadowOffset.dy,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF1A1A1A),
                  width: 2,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: faded ? null : onTap,
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF2EDE4),
                border: Border.all(
                  color: const Color(0xFF1A1A1A),
                  width: 2,
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Basket ribbon
// ═════════════════════════════════════════════════════════════════

/// Gift-ribbon overlay drawn on top of the basket snapshot in
/// the thank-you card. A horizontal teal band wraps across the
/// upper portion of the basket; a tied bow sits on the left side.
/// Soft gradient + a faint stitch line so it reads painterly
/// rather than vector-perfect.
///
/// The painter doesn't know anything about the basket below it —
/// it just paints a ribbon at a fixed proportional position. The
/// caller stacks this above the snapshot so the underlying
/// basket + marbles stay visible.
class BasketRibbonPainter extends CustomPainter {
  const BasketRibbonPainter({
    this.ribbonColor1 = const Color(0xFF5DCAA5),
    this.ribbonColor2 = const Color(0xFF3A9C7B),
  });

  /// Top + bottom of the ribbon's gradient. Defaults to a teal
  /// pair that pairs well with the parchment surface; can be
  /// retuned per-card if needed.
  final Color ribbonColor1;
  final Color ribbonColor2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Ribbon band — sits across the top quarter of the snapshot
    // so it reads as wrapped around the basket's upper edge.
    final bandHeight = h * 0.13;
    final bandTop = h * 0.18;
    final bandRect = Rect.fromLTWH(0, bandTop, w, bandHeight);

    final bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ribbonColor1, ribbonColor2],
      ).createShader(bandRect);
    canvas.drawRect(bandRect, bandPaint);

    // Faint stitching across the middle of the band.
    canvas.drawLine(
      Offset(0, bandRect.center.dy),
      Offset(w, bandRect.center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Bow on the left side of the band — two loops + a knot +
    // a pair of trailing tails.
    _paintBow(
      canvas,
      Offset(w * 0.30, bandRect.center.dy),
      bandHeight,
    );
  }

  void _paintBow(Canvas canvas, Offset c, double bandH) {
    final loopR = bandH * 0.85;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [ribbonColor1, ribbonColor2],
      ).createShader(Rect.fromCircle(center: c, radius: loopR * 1.4));

    // Left loop.
    final left = Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
        c.dx - loopR * 1.4, c.dy - loopR * 0.85,
        c.dx - loopR * 1.3, c.dy,
      )
      ..quadraticBezierTo(
        c.dx - loopR * 1.4, c.dy + loopR * 0.85,
        c.dx, c.dy,
      )
      ..close();
    // Right loop.
    final right = Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
        c.dx + loopR * 1.4, c.dy - loopR * 0.85,
        c.dx + loopR * 1.3, c.dy,
      )
      ..quadraticBezierTo(
        c.dx + loopR * 1.4, c.dy + loopR * 0.85,
        c.dx, c.dy,
      )
      ..close();
    canvas
      ..drawPath(left, paint)
      ..drawPath(right, paint)
      // Centre knot.
      ..drawCircle(c, loopR * 0.42, paint);

    // Two trailing tails dangling below.
    final tail1 = Path()
      ..moveTo(c.dx - loopR * 0.32, c.dy + loopR * 0.18)
      ..lineTo(c.dx - loopR * 0.55, c.dy + loopR * 1.6)
      ..lineTo(c.dx - loopR * 0.10, c.dy + loopR * 1.4)
      ..close();
    final tail2 = Path()
      ..moveTo(c.dx + loopR * 0.32, c.dy + loopR * 0.18)
      ..lineTo(c.dx + loopR * 0.55, c.dy + loopR * 1.6)
      ..lineTo(c.dx + loopR * 0.10, c.dy + loopR * 1.4)
      ..close();
    canvas
      ..drawPath(tail1, paint)
      ..drawPath(tail2, paint);
  }

  @override
  bool shouldRepaint(covariant BasketRibbonPainter old) =>
      old.ribbonColor1 != ribbonColor1 ||
      old.ribbonColor2 != ribbonColor2;
}
