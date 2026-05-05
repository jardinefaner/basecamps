// Painted face — a self-contained Flutter widget that renders one
// of the 5 BASECamp survey face designs (F1–F5) with a subtle
// idle animation. Built specifically for the basket-survey
// experiment so it can drag-and-drop without dragging Flame in.
//
// The 5-face palette + design language matches the marble kiosk
// (`lib/features/experiment/survey/survey_screen.dart`); the
// animations here are a stripped-down "essence" version — soft
// idle breathing + per-mood signature gesture (shiver / sway /
// look / bob / bounce). The kiosk's full animation system stays
// where it is; this file is intentionally short.
//
// The widget plays nicely with `Draggable` — pass `state: held`
// during the drag (slight tilt + scale up) and `state: dropped`
// when accepted (squash + fade).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mood identity, mirrored from the kiosk's `FaceMood` so callers
/// from outside this experiment can reuse this widget without
/// reaching into the marble-jar private types.
enum BasketFaceMood {
  stronglyDisagree, // F1 — red, shiver + tear
  disagree,         // F2 — coral, sway + brow droop
  notSure,          // F3 — amber, look L/R + blink
  agree,            // F4 — green, bob + sparkle
  stronglyAgree;    // F5 — teal, bounce + chomp + 3 sparkles

  /// Human-readable label. Kept compact so it fits under a face
  /// card without breaking layout. The basket survey shows it
  /// only on a long-press accessibility tooltip; the face itself
  /// is the primary signal.
  String get label => switch (this) {
        BasketFaceMood.stronglyDisagree => 'No way',
        BasketFaceMood.disagree => 'Not really',
        BasketFaceMood.notSure => 'Kind of',
        BasketFaceMood.agree => 'Yes',
        BasketFaceMood.stronglyAgree => 'Yes!!',
      };

  /// 3-point Likert mapping (0/1/2). Returns null for the F2/F4
  /// designs that aren't part of the BASECamp 3-point default.
  /// CSV exports key on this; missing values mean the question
  /// was rendered in 5-mode and the BASECamp scale doesn't apply.
  int? get likert3 => switch (this) {
        BasketFaceMood.stronglyDisagree => 0,
        BasketFaceMood.notSure => 1,
        BasketFaceMood.stronglyAgree => 2,
        _ => null,
      };

  /// Numeric for 5-point Likert — 0 (strongly disagree) … 4
  /// (strongly agree). Always non-null.
  int get likert5 => switch (this) {
        BasketFaceMood.stronglyDisagree => 0,
        BasketFaceMood.disagree => 1,
        BasketFaceMood.notSure => 2,
        BasketFaceMood.agree => 3,
        BasketFaceMood.stronglyAgree => 4,
      };
}

/// Per-face palette. Body = flat fill; ring = darker outline;
/// ink = brows / eyes / mouth; cheek = blush dots. Tear + sparkle
/// are mood-specific accents. Numbers come from the marble kiosk.
class BasketFacePalette {
  const BasketFacePalette({
    required this.body,
    required this.ring,
    required this.ink,
    required this.cheek,
    this.tear,
    this.sparkle,
  });
  final Color body;
  final Color ring;
  final Color ink;
  final Color cheek;
  final Color? tear;
  final Color? sparkle;
}

const Map<BasketFaceMood, BasketFacePalette> kBasketFacePalettes =
    <BasketFaceMood, BasketFacePalette>{
  BasketFaceMood.stronglyDisagree: BasketFacePalette(
    body: Color(0xFFFCEBEB),
    ring: Color(0xFFF09595),
    ink: Color(0xFFA32D2D),
    cheek: Color(0xFFF09595),
    tear: Color(0xFF85B7EB),
  ),
  BasketFaceMood.disagree: BasketFacePalette(
    body: Color(0xFFFAECE7),
    ring: Color(0xFFF0997B),
    ink: Color(0xFF712B13),
    cheek: Color(0xFFF09595),
  ),
  BasketFaceMood.notSure: BasketFacePalette(
    body: Color(0xFFFAEEDA),
    ring: Color(0xFFFAC775),
    ink: Color(0xFF854F0B),
    cheek: Color(0xFFFAC775),
  ),
  BasketFaceMood.agree: BasketFacePalette(
    body: Color(0xFFEAF3DE),
    ring: Color(0xFF97C459),
    ink: Color(0xFF27500A),
    cheek: Color(0xFF97C459),
    sparkle: Color(0xFF97C459),
  ),
  BasketFaceMood.stronglyAgree: BasketFacePalette(
    body: Color(0xFFE1F5EE),
    ring: Color(0xFF5DCAA5),
    ink: Color(0xFF085041),
    cheek: Color(0xFF5DCAA5),
    sparkle: Color(0xFF5DCAA5),
  ),
};

/// 3-mode subset for BASECamp's default 3-point survey: SD / NS / SA.
const List<BasketFaceMood> kBasket3Choices = <BasketFaceMood>[
  BasketFaceMood.stronglyDisagree,
  BasketFaceMood.notSure,
  BasketFaceMood.stronglyAgree,
];

/// Full 5-mode list: SD / D / NS / A / SA. Order is left → right
/// negative → positive so the kid's eye sweep matches reading.
const List<BasketFaceMood> kBasket5Choices = <BasketFaceMood>[
  BasketFaceMood.stronglyDisagree,
  BasketFaceMood.disagree,
  BasketFaceMood.notSure,
  BasketFaceMood.agree,
  BasketFaceMood.stronglyAgree,
];

/// What state the face is in. Drives subtle motion on top of the
/// idle loop. `idle` is the default; `held` is "user is dragging
/// it"; `dropped` is "it just landed in the basket."
enum BasketFaceState { idle, held, dropped }

/// A painted face widget you can drop into any layout. Includes
/// its own idle ticker so each face breathes/sways independently.
/// Sized via the [size] argument (the face fills the box; you
/// place it in a SizedBox to control footprint).
class PaintedFace extends StatefulWidget {
  const PaintedFace({
    required this.mood,
    required this.size,
    super.key,
    this.state = BasketFaceState.idle,
    this.seed = 0,
  });

  final BasketFaceMood mood;
  final double size;
  final BasketFaceState state;

  /// Per-instance phase offset so adjacent faces don't lock-step.
  /// Pass the index in the row (or any small int).
  final int seed;

  @override
  State<PaintedFace> createState() => _PaintedFaceState();
}

class _PaintedFaceState extends State<PaintedFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    unawaited(_ticker.repeat());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        // Continuous phase 0..1 looping; offset per-instance so a
        // row of faces feels organic rather than synchronised.
        final t = (_ticker.value + widget.seed * 0.13) % 1.0;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _PaintedFacePainter(
            mood: widget.mood,
            t: t,
            state: widget.state,
          ),
        );
      },
    );
  }
}

class _PaintedFacePainter extends CustomPainter {
  _PaintedFacePainter({
    required this.mood,
    required this.t,
    required this.state,
  });

  final BasketFaceMood mood;
  final double t; // 0..1 looping idle phase
  final BasketFaceState state;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = kBasketFacePalettes[mood]!;
    final w = size.width;
    final s = w / 80; // base scale: design assumes 80×80 face

    // Pivot to canvas centre — easier to think in (-40..+40).
    canvas.translate(w / 2, w / 2);

    // ——— State-driven outer transform ————————————————————
    final heldTilt = state == BasketFaceState.held ? 0.06 : 0.0;
    final droppedSquash = state == BasketFaceState.dropped ? 0.85 : 1.0;
    if (heldTilt != 0) canvas.rotate(heldTilt);
    canvas.scale(droppedSquash, droppedSquash);

    // ——— Idle "breathing" — soft scale pulse ————————————
    final breathe = 1.0 + math.sin(t * 2 * math.pi) * 0.018;
    canvas.scale(breathe, breathe);

    // ——— Per-mood signature motion (one extra DOF on top) ———
    _applyMoodMotion(canvas, t);

    // ——— Body + ring ———————————————————————————————————————
    final bodyPaint = Paint()..color = palette.body;
    final ringPaint = Paint()
      ..color = palette.ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4 * s;
    canvas
      ..drawCircle(Offset.zero, 36 * s, bodyPaint)
      ..drawCircle(Offset.zero, 36 * s, ringPaint)
      // ——— Subtle highlight (top-left) — gives it a paint feel ———
      ..drawCircle(
        Offset(-12 * s, -14 * s),
        9 * s,
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );

    // ——— Features: brows + eyes + mouth + cheeks ——————————
    _paintFeatures(canvas, s, palette);
  }

  void _applyMoodMotion(Canvas canvas, double t) {
    final phase = t * 2 * math.pi;
    switch (mood) {
      case BasketFaceMood.stronglyDisagree:
        // Tiny shiver: rapid x-jitter, very small.
        canvas.translate(math.sin(phase * 6) * 0.6, 0);
      case BasketFaceMood.disagree:
        // Slow side sway.
        canvas.translate(math.sin(phase) * 1.2, 0);
      case BasketFaceMood.notSure:
        // Looking around handled in eye paint, body just hovers.
        canvas.translate(0, math.sin(phase) * 0.4);
      case BasketFaceMood.agree:
        // Gentle bob.
        canvas.translate(0, math.sin(phase * 1.4) * 1.0);
      case BasketFaceMood.stronglyAgree:
        // Bouncy: bigger bob + slight scale pulse.
        final pop = 1.0 + math.sin(phase * 2) * 0.025;
        canvas
          ..translate(0, math.sin(phase * 2) * 1.6)
          ..scale(pop, pop);
    }
  }

  /// Dispatches feature painting per mood. Each branch is short
  /// enough that we can keep them inline rather than splitting
  /// into 5 helper classes.
  void _paintFeatures(Canvas canvas, double s, BasketFacePalette palette) {
    final ink = Paint()
      ..color = palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * s
      ..strokeCap = StrokeCap.round;
    final cheek = Paint()..color = palette.cheek.withValues(alpha: 0.55);

    // Cheeks — same on every face (relative position).
    canvas
      ..drawCircle(Offset(-16 * s, 6 * s), 4 * s, cheek)
      ..drawCircle(Offset(16 * s, 6 * s), 4 * s, cheek);

    switch (mood) {
      case BasketFaceMood.stronglyDisagree:
        _paintEyesClosedDown(canvas, s, ink);
        _paintMouthFrown(canvas, s, ink);
        _paintTear(canvas, s, palette);
        _paintBrowsFurrowed(canvas, s, ink);
      case BasketFaceMood.disagree:
        _paintEyesOpenSlight(canvas, s, ink);
        _paintMouthSlightFrown(canvas, s, ink);
        _paintBrowsDroop(canvas, s, ink);
      case BasketFaceMood.notSure:
        _paintEyesLookSide(canvas, s, ink, t);
        _paintMouthFlat(canvas, s, ink);
        _paintBrowsFlat(canvas, s, ink);
      case BasketFaceMood.agree:
        _paintEyesHappy(canvas, s, ink);
        _paintMouthSmile(canvas, s, ink);
        _paintBrowsLifted(canvas, s, ink);
        _paintSparkles(canvas, s, palette, count: 1);
      case BasketFaceMood.stronglyAgree:
        _paintEyesHappy(canvas, s, ink);
        _paintMouthBigSmile(canvas, s, ink);
        _paintBrowsLifted(canvas, s, ink);
        _paintSparkles(canvas, s, palette, count: 3);
    }
  }

  // ——— Eye painters ——————————————————————————————————————

  void _paintEyesClosedDown(Canvas canvas, double s, Paint ink) {
    // Curve down at the corners — sad closed eyes.
    final left = Path()
      ..moveTo(-16 * s, -4 * s)
      ..quadraticBezierTo(-12 * s, -1 * s, -8 * s, -4 * s);
    final right = Path()
      ..moveTo(8 * s, -4 * s)
      ..quadraticBezierTo(12 * s, -1 * s, 16 * s, -4 * s);
    canvas
      ..drawPath(left, ink)
      ..drawPath(right, ink);
  }

  void _paintEyesOpenSlight(Canvas canvas, double s, Paint ink) {
    final fill = Paint()..color = ink.color;
    canvas
      ..drawCircle(Offset(-12 * s, -3 * s), 2.4 * s, fill)
      ..drawCircle(Offset(12 * s, -3 * s), 2.4 * s, fill);
  }

  void _paintEyesLookSide(Canvas canvas, double s, Paint ink, double t) {
    // Shift left, then right, in a slow oscillation.
    final dx = math.sin(t * 2 * math.pi) * 1.6;
    final fill = Paint()..color = ink.color;
    canvas
      ..drawCircle(Offset(-12 * s + dx, -3 * s), 2.6 * s, fill)
      ..drawCircle(Offset(12 * s + dx, -3 * s), 2.6 * s, fill);
  }

  void _paintEyesHappy(Canvas canvas, double s, Paint ink) {
    // Smiling crescents — concave-up arcs.
    final left = Path()
      ..moveTo(-16 * s, -2 * s)
      ..quadraticBezierTo(-12 * s, -7 * s, -8 * s, -2 * s);
    final right = Path()
      ..moveTo(8 * s, -2 * s)
      ..quadraticBezierTo(12 * s, -7 * s, 16 * s, -2 * s);
    canvas
      ..drawPath(left, ink)
      ..drawPath(right, ink);
  }

  // ——— Mouth painters ————————————————————————————————————

  void _paintMouthFrown(Canvas canvas, double s, Paint ink) {
    final p = Path()
      ..moveTo(-9 * s, 14 * s)
      ..quadraticBezierTo(0, 8 * s, 9 * s, 14 * s);
    canvas.drawPath(p, ink);
  }

  void _paintMouthSlightFrown(Canvas canvas, double s, Paint ink) {
    final p = Path()
      ..moveTo(-7 * s, 12 * s)
      ..quadraticBezierTo(0, 9.5 * s, 7 * s, 12 * s);
    canvas.drawPath(p, ink);
  }

  void _paintMouthFlat(Canvas canvas, double s, Paint ink) {
    canvas.drawLine(Offset(-7 * s, 11 * s), Offset(7 * s, 11 * s), ink);
  }

  void _paintMouthSmile(Canvas canvas, double s, Paint ink) {
    final p = Path()
      ..moveTo(-8 * s, 9 * s)
      ..quadraticBezierTo(0, 15 * s, 8 * s, 9 * s);
    canvas.drawPath(p, ink);
  }

  void _paintMouthBigSmile(Canvas canvas, double s, Paint ink) {
    // Filled big smile — rounded arch.
    final p = Path()
      ..moveTo(-11 * s, 8 * s)
      ..quadraticBezierTo(0, 18 * s, 11 * s, 8 * s)
      ..quadraticBezierTo(0, 12 * s, -11 * s, 8 * s)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = ink.color
        ..style = PaintingStyle.fill,
    );
  }

  // ——— Brow painters —————————————————————————————————————

  void _paintBrowsFurrowed(Canvas canvas, double s, Paint ink) {
    final l = Path()
      ..moveTo(-18 * s, -12 * s)
      ..lineTo(-7 * s, -10 * s);
    final r = Path()
      ..moveTo(7 * s, -10 * s)
      ..lineTo(18 * s, -12 * s);
    canvas
      ..drawPath(l, ink)
      ..drawPath(r, ink);
  }

  void _paintBrowsDroop(Canvas canvas, double s, Paint ink) {
    final l = Path()
      ..moveTo(-18 * s, -10 * s)
      ..lineTo(-7 * s, -12 * s);
    final r = Path()
      ..moveTo(7 * s, -12 * s)
      ..lineTo(18 * s, -10 * s);
    canvas
      ..drawPath(l, ink)
      ..drawPath(r, ink);
  }

  void _paintBrowsFlat(Canvas canvas, double s, Paint ink) {
    canvas
      ..drawLine(Offset(-17 * s, -11 * s), Offset(-7 * s, -11 * s), ink)
      ..drawLine(Offset(7 * s, -11 * s), Offset(17 * s, -11 * s), ink);
  }

  void _paintBrowsLifted(Canvas canvas, double s, Paint ink) {
    final l = Path()
      ..moveTo(-17 * s, -11 * s)
      ..quadraticBezierTo(-12 * s, -14 * s, -7 * s, -11 * s);
    final r = Path()
      ..moveTo(7 * s, -11 * s)
      ..quadraticBezierTo(12 * s, -14 * s, 17 * s, -11 * s);
    canvas
      ..drawPath(l, ink)
      ..drawPath(r, ink);
  }

  // ——— Accents ———————————————————————————————————————————

  void _paintTear(Canvas canvas, double s, BasketFacePalette palette) {
    final tear = palette.tear ?? const Color(0xFF85B7EB);
    final p = Path()
      ..moveTo(-10 * s, -2 * s)
      ..quadraticBezierTo(-13 * s, 4 * s, -10 * s, 7 * s)
      ..quadraticBezierTo(-7 * s, 4 * s, -10 * s, -2 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = tear);
  }

  void _paintSparkles(
    Canvas canvas,
    double s,
    BasketFacePalette palette, {
    required int count,
  }) {
    final spark = palette.sparkle ?? const Color(0xFFFFD66B);
    final paint = Paint()..color = spark;
    final positions = <Offset>[
      Offset(-22 * s, -14 * s),
      Offset(22 * s, -10 * s),
      Offset(0, -22 * s),
    ];
    for (var i = 0; i < count && i < positions.length; i++) {
      _drawSpark(canvas, positions[i], 3.6 * s, paint);
    }
  }

  void _drawSpark(Canvas canvas, Offset c, double r, Paint paint) {
    // Four-point sparkle: two thin rhombuses crossed.
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.32, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.32, c.dy)
      ..close()
      ..moveTo(c.dx - r, c.dy)
      ..lineTo(c.dx, c.dy + r * 0.32)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy - r * 0.32)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant _PaintedFacePainter old) =>
      old.mood != mood || old.t != t || old.state != state;
}
