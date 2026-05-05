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
import 'dart:ui' as ui;

import 'package:basecamp/features/experiment/basket_survey/basket_painter.dart';
import 'package:basecamp/features/experiment/basket_survey/basket_world.dart';
import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';
import 'package:basecamp/features/experiment/survey/survey_screen.dart'
    show FacePainter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  /// has already added the marble to the world; the parent only
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

  @override
  Widget build(BuildContext context) {
    return DragTarget<FaceMood>(
      onWillAcceptWithDetails: (_) => widget.onWillAccept(),
      onLeave: (_) => widget.onLeave(),
      onAcceptWithDetails: (details) {
        _world.addMarble(details.data);
        widget.onAccept(details.data);
      },
      builder: (context, _, _) {
        return Center(
          child: AnimatedScale(
            scale: widget.glow ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: SizedBox(
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
    // Settle squash: vertical compress 0.85x → 1.0x as squash
    // decays from 1 to 0. easeOutBack feel via a spring-ish curve.
    if (m.settleSquash > 0) {
      final s = 1 - m.settleSquash * 0.18;
      canvas.scale(1 + (1 - s) * 0.5, s);
    }
    // Soft shadow under each marble — gives it weight + grounds
    // it visually. Lower marbles cast a slightly larger shadow.
    final shadow = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      const Offset(2, BasketGeometry.marbleR * 0.45),
      BasketGeometry.marbleR * 0.78,
      shadow,
    );
    FacePainter(
      mood: m.mood,
      variant: m.variant,
      t: world.t + m.tOffset,
    ).paintAt(canvas, Offset.zero, BasketGeometry.marbleR);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BasketWorldPainter old) =>
      true; // always — the world is ticking
}
