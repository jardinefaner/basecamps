// Flutter widget that hosts a `BasketWorld` — drives its tick
// loop, dispatches drop events from the DragTarget, and renders
// everything (back marbles, woven basket, front marbles) via a
// single CustomPainter.
//
// One Ticker per widget instance. The ticker runs while there's
// at least one un-settled marble; when everything in the world
// has settled, we keep the ticker running anyway so the variant
// cycling + idle face animations stay live (the per-frame work is
// just `t += dt` + a few clamp ops, so we'd save microseconds and
// risk a frame-skipped animation start when a new marble drops).

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:basecamp/features/experiment/basket_survey/basket_painter.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_world.dart';
import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';
import 'package:basecamp/features/experiment/survey/survey_screen.dart'
    show FacePainter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Payload dragged from a face card to the basket. The basket
/// needs both the mood (for answer recording) and the palette
/// (so the marble inside the basket keeps the per-question color
/// it was wearing in the choice row).
class BasketDropPayload {
  const BasketDropPayload({required this.mood, this.palette});
  final FaceMood mood;
  final FacePalette? palette;
}

class BasketWorldWidget extends StatefulWidget {
  const BasketWorldWidget({
    required this.glow,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
    super.key,
  });

  final bool glow;
  final bool Function() onWillAccept;
  final VoidCallback onLeave;

  /// Fires when the kid drops a face onto the basket. The widget
  /// has already added the marble to the world (with the local
  /// drag-end position + the chosen palette); the parent only
  /// needs to record the answer + advance to the next question.
  final ValueChanged<FaceMood> onAccept;

  @override
  State<BasketWorldWidget> createState() => BasketWorldWidgetState();
}

class BasketWorldWidgetState extends State<BasketWorldWidget>
    with SingleTickerProviderStateMixin {
  final BasketWorld _world = BasketWorld();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0) {
      // Cap dt at 1/30s so a janky frame doesn't tunnel a marble
      // through a wall. Marbles travelling > ~40px/frame can
      // skip past wall thickness on a single integration step.
      final clampedDt = dt > 1 / 30 ? 1 / 30 : dt;
      _world.step(clampedDt);
    }
    if (mounted) setState(() {});
  }

  /// Reset the world. Called by the parent on session reset (next
  /// child taps in).
  void reset() {
    _world.reset();
    if (mounted) setState(() {});
  }

  /// `true` when every marble in the world has settled — used by
  /// the survey screen's snapshot poll so we don't freeze a frame
  /// with marbles mid-bounce.
  bool get isFullySettled =>
      _world.marbles.every((m) => m.settled);

  /// Direct access to the simulation. Used by the basket survey
  /// screen to imperatively spawn marbles outside the
  /// drag-and-drop path (e.g. from a multi-select activity tap).
  BasketWorld get world => _world;

  /// Key on the inner SizedBox so we can convert the drag-end
  /// global offset to the world's local coordinate space. (The
  /// AnimatedScale wrapping it also affects the transformation,
  /// but we read the SizedBox's render box BEFORE the scale so
  /// we get untransformed local coords — same coordinate space
  /// the painter uses.)
  final GlobalKey _worldBoxKey = GlobalKey();

  Offset _toLocal(Offset globalOffset) {
    final ctx = _worldBoxKey.currentContext;
    if (ctx == null) return Offset.zero;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(globalOffset);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<BasketDropPayload>(
      onWillAcceptWithDetails: (_) => widget.onWillAccept(),
      onLeave: (_) => widget.onLeave(),
      onAcceptWithDetails: (details) {
        final local = _toLocal(details.offset);
        _world.addMarble(
          details.data.mood,
          spawnAt: local,
          palette: details.data.palette,
        );
        widget.onAccept(details.data.mood);
      },
      builder: (context, _, _) {
        // FittedBox(BoxFit.contain) shrinks the 320×240 world to
        // fit whatever room the parent gives us — without it,
        // tall-but-narrow allocations (e.g. the bottom 200px slot
        // during open-ended) clip the basket floor + the overflow
        // marbles piling above the rim. globalToLocal in [_toLocal]
        // walks the transform stack, so drag mapping still lands
        // on the right physics coordinates after the scale.
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: widget.glow ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                key: _worldBoxKey,
                width: BasketGeometry.worldW,
                height: BasketGeometry.worldH,
                child: CustomPaint(
                  painter: _BasketWorldPainter(
                    world: _world,
                    glow: widget.glow,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Render order, back to front:
///   1. Back-row marbles inside the basket (drawn behind the weave).
///   2. Woven basket (translucent — back-row bleeds through).
///   3. Front-row marbles inside the basket (drawn in front of weave).
///   4. Ground / overspill marbles (drawn on top of everything).
///
/// "Back" vs "front" inside the basket is decided by y-position:
/// higher-up marbles read as further back, so we draw them first.
class _BasketWorldPainter extends CustomPainter {
  _BasketWorldPainter({required this.world, required this.glow});

  final BasketWorld world;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    // Marbles are split into three render lists.
    final backInside = <MarbleBody>[];
    final frontInside = <MarbleBody>[];
    final ground = <MarbleBody>[];
    const splitY = (BasketGeometry.rimY + BasketGeometry.basketFloorY) / 2;
    for (final m in world.marbles) {
      switch (m.zone) {
        case MarbleZone.basket:
          if (m.position.dy < splitY) {
            backInside.add(m);
          } else {
            frontInside.add(m);
          }
        case MarbleZone.ground:
          ground.add(m);
      }
    }

    // 1. Back-row inside marbles.
    for (final m in backInside) {
      _paintMarble(canvas, m);
    }

    // 2. Woven basket — translucent so back-row marbles bleed
    //    through the weave.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: 0.78),
    );
    BasketPainter(glow: glow).paint(canvas, size);
    canvas.restore();

    // 3. Front-row inside marbles.
    for (final m in frontInside) {
      _paintMarble(canvas, m);
    }

    // 4. Ground / overspill marbles — always draw on top.
    for (final m in ground) {
      _paintMarble(canvas, m);
    }
  }

  void _paintMarble(Canvas canvas, MarbleBody m) {
    canvas
      ..save()
      ..translate(m.position.dx, m.position.dy);

    // ——— Soft shadow ground anchor ——————————————————————————
    // Drawn before the marble's own transforms so it sits on
    // the floor regardless of squash/rotation.
    final shadow = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      const Offset(2, BasketGeometry.marbleR * 0.45),
      BasketGeometry.marbleR * 0.78,
      shadow,
    );

    // ——— Body rotation (spin) ———
    // For settled marbles, fold in the look-at tilt so the face
    // points slightly toward a recently-arrived neighbour.
    final lookAtEase = m.lookAtT == 0
        ? 0.0
        : Curves.easeOutCubic.transform(m.lookAtT);
    canvas.rotate(m.angle + m.lookAtAngle * lookAtEase);

    // ——— Direction-aware impact squash ———
    // The marble compresses along the inward-normal of whatever
    // surface it just hit; decays to neutral over ~200ms. We
    // apply it via an axis-aligned scale rotated to match the
    // normal so floor hits squash vertically and wall hits
    // squash horizontally.
    if (m.impactSquash > 0) {
      // Rotate into the impact-normal frame, scale x = swell,
      // y = compress so the marble pancakes against the surface,
      // then rotate back. Floor hits squash vertically, wall
      // hits squash horizontally, marble-marble hits squash
      // along the contact line.
      final normalAngle =
          math.atan2(m.impactNormal.dy, m.impactNormal.dx);
      final compress = 1 - m.impactSquash * 0.30;
      final swell = 1 + m.impactSquash * 0.18;
      canvas
        ..rotate(normalAngle)
        ..scale(swell, compress)
        ..rotate(-normalAngle);
    }

    // ——— Cartoon flight stretch ———
    // High velocity → marble visibly elongates along the
    // velocity vector by up to ~12%. Gives a sense of speed.
    if (!m.settled) {
      final speed = m.velocity.distance;
      if (speed > 200) {
        final stretch = math.min(0.12, (speed - 200) / 1600);
        final velAngle = math.atan2(m.velocity.dy, m.velocity.dx);
        canvas.rotate(velAngle);
        canvas.scale(1 + stretch, 1 - stretch * 0.5);
        canvas.rotate(-velAngle);
      }
    }

    // ——— Variant transition "pop" ———
    // Short scale pulse the moment the marble's variant cycles.
    // Eye-catches the swap. Decays to 0 over ~220ms.
    if (m.variantTransitionT > 0) {
      final pop = 1 + Curves.easeOut.transform(m.variantTransitionT) * 0.08;
      canvas.scale(pop, pop);
    }

    FacePainter(
      mood: m.mood,
      variant: m.variant,
      // Per-marble time-scale + phase offset so two marbles with
      // the same variant don't drift back into sync.
      t: world.t * m.timeScale + m.tOffset,
      palette: m.palette,
    ).paintAt(canvas, Offset.zero, BasketGeometry.marbleR);

    // ——— Variant transition halo ———
    // Faint white ring drawn outside the body to pulse on swap.
    if (m.variantTransitionT > 0) {
      final alpha =
          (Curves.easeOut.transform(m.variantTransitionT) * 0.55)
              .clamp(0.0, 1.0);
      final ring = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset.zero, BasketGeometry.marbleR + 4, ring);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BasketWorldPainter old) =>
      true; // always — the world is ticking
}
