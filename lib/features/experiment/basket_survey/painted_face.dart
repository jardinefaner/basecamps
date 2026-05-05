// Painted face — Flutter widget wrapper around the **same**
// `FacePainter` the marble-jar kiosk uses. Reusing the painter
// (instead of redrawing the faces here) means the basket-survey
// experiment gets every per-face animation the kiosk has — angry
// brows + tears, sob pulses, looking around, sparkles, bouncing
// chomp — without keeping two copies in sync.
//
// The painter is time-driven (`t` in seconds). We feed it from a
// per-instance `AnimationController` running in repeat mode, so
// adjacent faces with different seeds breathe out of phase.

import 'dart:async';

import 'package:basecamp/features/experiment/survey/survey_screen.dart'
    show FaceMood, FacePainter, FacePalette, MarbleVariant;
import 'package:flutter/material.dart';

// Re-export the public face types so callers in this folder don't
// have to import the marble-jar screen directly.
export 'package:basecamp/features/experiment/survey/survey_screen.dart'
    show FaceMood, FacePalette, MarbleVariant, kFacePalettes;

/// 3-mode subset for BASECamp's default 3-point survey.
const List<FaceMood> kBasket3Choices = <FaceMood>[
  FaceMood.stronglyDisagree,
  FaceMood.notSure,
  FaceMood.stronglyAgree,
];

/// Full 5-mode list. Order: negative → positive (matches reading).
const List<FaceMood> kBasket5Choices = <FaceMood>[
  FaceMood.stronglyDisagree,
  FaceMood.disagree,
  FaceMood.notSure,
  FaceMood.agree,
  FaceMood.stronglyAgree,
];

/// Human-readable label for a mood. The kiosk doesn't print these
/// (the face IS the label) but the basket survey uses them for
/// accessibility tooltips on the draggables.
String basketFaceLabel(FaceMood m) => switch (m) {
      FaceMood.stronglyDisagree => 'No way',
      FaceMood.disagree => 'Not really',
      FaceMood.notSure => 'Kind of',
      FaceMood.agree => 'Yes',
      FaceMood.stronglyAgree => 'Yes!!',
    };

/// 3-point Likert mapping (0/1/2). Returns null for the F2/F4
/// designs that aren't part of the BASECamp 3-point default.
int? basketLikert3(FaceMood m) => switch (m) {
      FaceMood.stronglyDisagree => 0,
      FaceMood.notSure => 1,
      FaceMood.stronglyAgree => 2,
      _ => null,
    };

/// 5-point Likert (0..4). Always non-null.
int basketLikert5(FaceMood m) => switch (m) {
      FaceMood.stronglyDisagree => 0,
      FaceMood.disagree => 1,
      FaceMood.notSure => 2,
      FaceMood.agree => 3,
      FaceMood.stronglyAgree => 4,
    };

/// What state the face is in. Maps to one of the four
/// `MarbleVariant` animations — same animation set the kiosk
/// marbles cycle through.
enum BasketFaceState {
  /// Default cycling animation — what a face does just sitting in
  /// the choice row.
  idle,

  /// Picked up / being dragged. Bigger, livelier — uses the
  /// `emote` variant which is the most expressive of the four.
  held,

  /// Just landed in the basket. Visual still uses idle; callers
  /// can layer a squash on top via Transform.
  dropped,
}

MarbleVariant _variantFor(BasketFaceState s, int seed) {
  switch (s) {
    case BasketFaceState.idle:
      // Spread idle faces across the 4 variants (idle / breathing
      // / fidget / emote) by seed so a row doesn't lock-step.
      return MarbleVariant.values[seed.abs() % MarbleVariant.values.length];
    case BasketFaceState.held:
      return MarbleVariant.emote;
    case BasketFaceState.dropped:
      return MarbleVariant.idle;
  }
}

/// A painted face widget. Renders via the kiosk's `FacePainter`
/// running on a per-instance ticker so animations stay live.
class PaintedFace extends StatefulWidget {
  const PaintedFace({
    required this.mood,
    required this.size,
    super.key,
    this.state = BasketFaceState.idle,
    this.seed = 0,
    this.palette,
  });

  final FaceMood mood;
  final double size;
  final BasketFaceState state;

  /// Per-instance phase offset so adjacent faces don't lock-step.
  /// Pass the index in the row (or any small int).
  final int seed;

  /// Optional override for body / ring / cheek colors. The face's
  /// expression (eyes / mouth / brows / tears / sparkles) stays
  /// faithful to its mood — only the body fill rotates. Used by
  /// the basket-survey experiment to cycle colors per question.
  final FacePalette? palette;

  @override
  State<PaintedFace> createState() => _PaintedFaceState();
}

class _PaintedFaceState extends State<PaintedFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  /// Seconds elapsed since this face mounted. The kiosk's
  /// `FacePainter` reads `t` in seconds (its variants do `t/3`,
  /// `t/0.8`, etc.); we feed wall-clock seconds + a per-instance
  /// phase shift so adjacent faces don't move in sync.
  double get _t {
    // 60-second loop is plenty for the slowest variant (~3s period).
    return _ticker.value * 60.0 + widget.seed * 0.7;
  }

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
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
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _FaceCustomPainter(
            mood: widget.mood,
            variant: _variantFor(widget.state, widget.seed),
            t: _t,
            palette: widget.palette,
          ),
        );
      },
    );
  }
}

/// CustomPainter shim that delegates to the kiosk's FacePainter.
/// FacePainter is a plain class (not a CustomPainter); this thin
/// wrapper bridges it to Flutter's painting protocol.
class _FaceCustomPainter extends CustomPainter {
  _FaceCustomPainter({
    required this.mood,
    required this.variant,
    required this.t,
    this.palette,
  });

  final FaceMood mood;
  final MarbleVariant variant;
  final double t;
  final FacePalette? palette;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    FacePainter(
      mood: mood,
      variant: variant,
      t: t,
      palette: palette,
    ).paintAt(
      canvas,
      Offset(size.width / 2, size.height / 2),
      radius,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceCustomPainter old) =>
      old.t != t ||
      old.mood != mood ||
      old.variant != variant ||
      old.palette != palette;
}
