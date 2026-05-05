// Basket world — physics + render loop for the basket-survey
// experiment. A single Ticker drives one `BasketWorld` that owns
// every marble (inside-the-basket + spillover), runs the per-frame
// step, and exposes the state to a CustomPainter.
//
// Why a custom mini-physics instead of Flame: the basket survey is
// a flat, focused interaction (drag → drop → settle); a full
// engine is overkill. The kiosk's marble jar already has full
// physics in Flame; here we want fast settle, predictable
// behaviour, and zero extra runtime cost.
//
// Three guarantees:
//   1. **Marbles never bounce forever.** Velocity damping + sleep
//      threshold + a hard cap on bounces (force-settle if a marble
//      bounces more than 12× within 1 second).
//   2. **Walls match the painter.** A single `BasketGeometry`
//      class defines the interior trapezoid; both physics and the
//      painter consume it.
//   3. **Variant cycling is per-marble.** Every 8–12s a marble
//      rotates to the next `MarbleVariant`, so the pile stays
//      visually alive — at any moment some are breathing, some
//      fidgeting, some emoting.

import 'dart:math' as math;
import 'dart:ui';

import 'package:basecamp/features/experiment/basket_survey/painted_face.dart';

/// Geometry of the basket in local 320×240 space. The painter +
/// the physics solver consume the same constants so the woven
/// walls visually align with the collision walls.
class BasketGeometry {
  const BasketGeometry._();

  /// Width / height of the world.
  static const double worldW = 320;
  static const double worldH = 240;

  /// Top opening (rim).
  static const double rimY = 50;
  static const double leftRimX = 54;
  static const double rightRimX = 266;

  /// Bottom of the basket (floor of the woven container).
  static const double basketFloorY = 218;
  static const double leftBaseX = 76;
  static const double rightBaseX = 244;

  /// Rounded base radius — corners curve up here.
  static const double baseCornerR = 14;

  /// World ground (where overspill marbles settle).
  static const double groundY = 232;

  /// Rim threshold — once a settled marble inside has its centre
  /// below this y, it's considered "in the pile" for capacity.
  static const double settledCutoffY = 130;

  /// Marble radius (must match the painter's r).
  static const double marbleR = 33;

  /// How many marbles fit comfortably inside before overspill.
  static const int basketCapacity = 6;

  /// Left wall of the basket as a line segment (rim → base).
  static const Offset leftWallTop = Offset(leftRimX, rimY);
  static const Offset leftWallBottom = Offset(leftBaseX, basketFloorY);

  /// Right wall of the basket as a line segment (rim → base).
  static const Offset rightWallTop = Offset(rightRimX, rimY);
  static const Offset rightWallBottom = Offset(rightBaseX, basketFloorY);
}

/// One marble in the world. Mutable; the world steps these in
/// place each frame.
class MarbleBody {
  MarbleBody({
    required this.mood,
    required this.position,
    required this.velocity,
    required this.seed,
    required this.variant,
    required this.tOffset,
    required this.zone,
  });

  final FaceMood mood;
  final int seed;
  final double tOffset;

  Offset position;
  Offset velocity;

  /// Which physics zone this marble lives in. Determines which
  /// walls it collides with.
  MarbleZone zone;

  MarbleVariant variant;

  /// 0 → no squash. Set to 1 the moment the marble settles; the
  /// painter scales y by `(1 - squash * 0.18)` so it briefly
  /// pancakes then springs back. Decays to 0 over ~200ms.
  double settleSquash = 0;

  /// True once the marble has stopped moving. Settled marbles
  /// skip the integrate / collide pipeline; they still draw +
  /// animate variants.
  bool settled = false;

  /// Frames in a row with |v| below the sleep threshold. Once
  /// this exceeds [BasketWorld._sleepFrames], the marble sleeps.
  int settleFrames = 0;

  /// Bounce counter for the hard-cap. Resets if the marble has
  /// gone [BasketWorld._bounceWindow] seconds without bouncing.
  int bounceCount = 0;
  double bounceClock = 0;

  /// Wall-clock seconds remaining until the next variant swap.
  /// Initialised to a random value in [8, 12]; counts down each
  /// frame; on hit, picks the next variant + resets.
  double variantTtl = 10;

  MarbleBody copyWith({MarbleVariant? variant}) {
    final out = MarbleBody(
      mood: mood,
      position: position,
      velocity: velocity,
      seed: seed,
      variant: variant ?? this.variant,
      tOffset: tOffset,
      zone: zone,
    );
    return out;
  }

  /// Default-construct a `variantTtl` so freshly-spawned marbles
  /// don't all swap at the same moment. Internally inserted by
  /// [BasketWorld.addMarble].
  static double initialVariantTtl(math.Random rng) =>
      8.0 + rng.nextDouble() * 4.0;
}

/// Which physics zone a marble lives in. The basket interior and
/// the world ground are simulated independently — a marble in the
/// basket only collides with marbles in the basket, not with
/// spillover, and vice versa.
enum MarbleZone { basket, ground }

/// The world. Owns marbles + integrates them. Stateless on its
/// own — the parent widget calls [step] every frame and asks
/// [snapshot] for a draw-ready list.
class BasketWorld {
  BasketWorld({int? seed}) : _rng = math.Random(seed ?? 0xBA53E7);

  final math.Random _rng;

  /// All marbles (basket + ground).
  final List<MarbleBody> marbles = <MarbleBody>[];

  /// Wall-clock seconds since the world started. Drives the face
  /// painter's `t` arg.
  double t = 0;

  /// Drop a fresh marble in. Spawn position depends on the
  /// current pile: while the basket has room, marbles enter
  /// through the rim; once full, they get lobbed to a slot
  /// outside the basket so the pile spreads around the floor.
  /// Returns the new body (caller can do something with it,
  /// e.g. play a sound).
  MarbleBody addMarble(FaceMood mood) {
    final basketHowFull =
        marbles.where((m) => m.zone == MarbleZone.basket).length;
    final overspill = basketHowFull >= BasketGeometry.basketCapacity;
    final body = overspill
        ? _spawnOverspill(mood)
        : _spawnInBasket(mood);
    marbles.add(body);
    return body;
  }

  MarbleBody _spawnInBasket(FaceMood mood) {
    // Spawn at the rim center with a downward velocity. Falls
    // under gravity, bounces, settles into the pile.
    return MarbleBody(
      mood: mood,
      position: Offset(BasketGeometry.worldW / 2, BasketGeometry.rimY - 6),
      velocity: Offset(
        (_rng.nextDouble() - 0.5) * 30, // small lateral jitter
        180 + _rng.nextDouble() * 80,
      ),
      seed: marbles.length,
      variant: MarbleVariant.values[_rng.nextInt(4)],
      tOffset: _rng.nextDouble() * 6.28,
      zone: MarbleZone.basket,
    )..variantTtl = MarbleBody.initialVariantTtl(_rng);
  }

  MarbleBody _spawnOverspill(FaceMood mood) {
    // Cycle through 4 spawn slots (front, right, left, front-far)
    // so the floor pile fans out instead of stacking on one spot.
    final overspillIndex = marbles
        .where((m) => m.zone == MarbleZone.ground)
        .length;
    final slot = overspillIndex % 4;
    // Lateral velocity so the marble arcs out from the basket
    // mouth — kid sees it leap out.
    final vx = switch (slot) {
      0 => (_rng.nextDouble() - 0.5) * 40,
      1 => 80 + _rng.nextDouble() * 40, // outward right
      2 => -(80 + _rng.nextDouble() * 40), // outward left
      _ => 60 + _rng.nextDouble() * 40,
    };
    return MarbleBody(
      mood: mood,
      position: Offset(BasketGeometry.worldW / 2, BasketGeometry.rimY - 6),
      velocity: Offset(vx, 120 + _rng.nextDouble() * 40),
      seed: marbles.length,
      variant: MarbleVariant.values[_rng.nextInt(4)],
      tOffset: _rng.nextDouble() * 6.28,
      zone: MarbleZone.ground,
    )
      ..variantTtl = MarbleBody.initialVariantTtl(_rng)
      // Mark "needs to leave the basket" so on the way out we
      // don't collide with rim walls. Solved by: ground-zone
      // marbles never collide with basket walls in `_collideWalls`.
      ;
  }

  /// Wipe the world. Called by the parent on session reset.
  void reset() {
    marbles.clear();
    t = 0;
  }

  // ——— Tunables ————————————————————————————————————————————————

  static const double _gravity = 1200; // px/s²
  static const double _restitution = 0.42;
  // Per-frame damping at 60fps. We adjust by `dt*60` so framerate
  // changes don't change settle speed (e.g. 30fps still settles).
  static const double _damping60 = 0.93;
  static const double _sleepThreshold = 8; // px/s
  static const int _sleepFrames = 6;
  static const int _maxBounces = 12;
  static const double _bounceWindow = 1.0; // seconds

  // ——— Step ————————————————————————————————————————————————————

  /// Advance the world by [dt] seconds.
  void step(double dt) {
    t += dt;
    // Frame-rate-independent damping multiplier.
    final damp = math.pow(_damping60, dt * 60).toDouble();

    // 1) Variant cycling — for every marble, settled or not.
    for (final m in marbles) {
      m.variantTtl -= dt;
      if (m.variantTtl <= 0) {
        m.variant = MarbleVariant
            .values[(m.variant.index + 1) % MarbleVariant.values.length];
        m.variantTtl = MarbleBody.initialVariantTtl(_rng);
      }
      if (m.settleSquash > 0) {
        m.settleSquash = math.max(0, m.settleSquash - dt * 5.5);
      }
      m.bounceClock += dt;
      if (m.bounceClock > _bounceWindow) {
        m.bounceCount = 0;
        m.bounceClock = 0;
      }
    }

    // 2) Integrate gravity + velocity for unsettled marbles.
    for (final m in marbles) {
      if (m.settled) continue;
      m.velocity = Offset(
        m.velocity.dx * damp,
        (m.velocity.dy + _gravity * dt) * damp,
      );
      m.position = m.position + m.velocity * dt;
      _collideWalls(m);
    }

    // 3) Pairwise collisions. Only collide marbles in the same
    //    zone — basket marbles don't push ground marbles.
    for (var i = 0; i < marbles.length; i++) {
      for (var j = i + 1; j < marbles.length; j++) {
        if (marbles[i].zone != marbles[j].zone) continue;
        _collidePair(marbles[i], marbles[j]);
      }
    }

    // 4) Sleep + hard cap. Settled marbles drop out of the
    //    integration pipeline.
    for (final m in marbles) {
      if (m.settled) continue;
      if (m.bounceCount >= _maxBounces) {
        _settle(m);
        continue;
      }
      if (m.velocity.distance < _sleepThreshold) {
        m.settleFrames += 1;
        if (m.settleFrames >= _sleepFrames) {
          _settle(m);
        }
      } else {
        m.settleFrames = 0;
      }
    }
  }

  void _settle(MarbleBody m) {
    m.settled = true;
    m.velocity = Offset.zero;
    // One-shot squash on settle: like a soft "thud" landing.
    m.settleSquash = 1.0;
  }

  /// Collide one marble against the world boundaries (basket
  /// walls + floor for basket-zone, ground for ground-zone).
  void _collideWalls(MarbleBody m) {
    const r = BasketGeometry.marbleR;
    if (m.zone == MarbleZone.basket) {
      // Basket interior: floor + 2 sloped walls. The rim is
      // open; marbles can still escape upward but gravity will
      // pull them back.
      // ——— Floor ———
      if (m.position.dy + r > BasketGeometry.basketFloorY) {
        m.position = Offset(m.position.dx, BasketGeometry.basketFloorY - r);
        if (m.velocity.dy > 0) {
          m.velocity = Offset(
            m.velocity.dx * 0.85,
            -m.velocity.dy * _restitution,
          );
          m.bounceCount += 1;
          m.bounceClock = 0;
        }
      }
      // ——— Walls (sloped lines, rim → base) ———
      _collideAgainstSegment(
        m,
        BasketGeometry.leftWallTop,
        BasketGeometry.leftWallBottom,
        // Inward normal points right + slightly up.
        normalAwayFromInteriorTowardLeft: true,
      );
      _collideAgainstSegment(
        m,
        BasketGeometry.rightWallTop,
        BasketGeometry.rightWallBottom,
        normalAwayFromInteriorTowardLeft: false,
      );
    } else {
      // Ground zone: marbles roll on the world floor; can leave
      // the screen sides (the world is wider than the basket
      // visually so a few pixels off doesn't matter).
      if (m.position.dy + r > BasketGeometry.groundY) {
        m.position = Offset(m.position.dx, BasketGeometry.groundY - r);
        if (m.velocity.dy > 0) {
          m.velocity = Offset(
            m.velocity.dx * 0.85,
            -m.velocity.dy * _restitution,
          );
          m.bounceCount += 1;
          m.bounceClock = 0;
        }
      }
      // Soft side walls so ground marbles don't roll forever
      // off the canvas.
      if (m.position.dx - r < 0) {
        m.position = Offset(r, m.position.dy);
        m.velocity = Offset(-m.velocity.dx * _restitution, m.velocity.dy);
      } else if (m.position.dx + r > BasketGeometry.worldW) {
        m.position = Offset(BasketGeometry.worldW - r, m.position.dy);
        m.velocity = Offset(-m.velocity.dx * _restitution, m.velocity.dy);
      }
    }
  }

  /// Collide a circle (marble) against a line segment. Pushes
  /// the circle outward along the inward-pointing normal and
  /// reflects velocity along it.
  void _collideAgainstSegment(
    MarbleBody m,
    Offset a,
    Offset b, {
    required bool normalAwayFromInteriorTowardLeft,
  }) {
    const r = BasketGeometry.marbleR;
    // Closest point on segment to circle centre.
    final ab = b - a;
    final ap = m.position - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final tt = ((ap.dx * ab.dx + ap.dy * ab.dy) / ab2).clamp(0.0, 1.0);
    final closest = a + ab * tt;
    final delta = m.position - closest;
    final dist = delta.distance;
    if (dist >= r) return;

    // Compute the inward normal (pointing from the wall into the
    // basket interior). For left wall, interior is to the right;
    // for right wall, interior is to the left.
    final wallNormalOutward = Offset(-ab.dy, ab.dx) /
        math.sqrt(ab2); // perpendicular, length 1
    final inward = normalAwayFromInteriorTowardLeft
        ? -wallNormalOutward
        : wallNormalOutward;

    // Push the marble out along the inward normal so it sits
    // exactly r away from the wall.
    final overlap = r - dist;
    m.position = m.position + inward * overlap;
    // Reflect velocity component along the normal.
    final vAlongN =
        m.velocity.dx * inward.dx + m.velocity.dy * inward.dy;
    if (vAlongN < 0) {
      m.velocity = m.velocity - inward * (vAlongN * (1 + _restitution));
      // Friction-ish damp on tangent.
      m.velocity = Offset(m.velocity.dx * 0.92, m.velocity.dy * 0.92);
      m.bounceCount += 1;
      m.bounceClock = 0;
    }
  }

  /// Pairwise marble collision. Standard equal-mass elastic
  /// resolution along the contact normal.
  void _collidePair(MarbleBody a, MarbleBody b) {
    const r2 = BasketGeometry.marbleR * 2;
    final delta = b.position - a.position;
    final dist = delta.distance;
    if (dist == 0 || dist >= r2) return;
    final overlap = r2 - dist;
    final n = Offset(delta.dx / dist, delta.dy / dist);
    // Positional separation: each takes half of the overlap.
    // If one is settled, only push the unsettled one.
    if (a.settled && !b.settled) {
      b.position = b.position + n * overlap;
    } else if (b.settled && !a.settled) {
      a.position = a.position - n * overlap;
    } else if (!a.settled && !b.settled) {
      a.position = a.position - n * (overlap / 2);
      b.position = b.position + n * (overlap / 2);
    } else {
      // Both settled but overlapping (shouldn't normally happen
      // — sleep check guards) — split them lazily.
      a.position = a.position - n * (overlap / 2);
      b.position = b.position + n * (overlap / 2);
      return;
    }

    // Velocity: project onto contact normal, swap that
    // component (equal-mass elastic), apply restitution.
    final vRel = (b.velocity - a.velocity);
    final vRelN = vRel.dx * n.dx + vRel.dy * n.dy;
    if (vRelN > 0) return; // already separating
    final impulse = n * (vRelN * (1 + _restitution));
    if (!a.settled) a.velocity = a.velocity + impulse;
    if (!b.settled) b.velocity = b.velocity - impulse;
    // Re-wake on hard impact: a settled neighbour gets a tiny
    // upward nudge so the pile registers the new arrival.
    if (a.settled && vRelN < -120) _wake(a, n * -1);
    if (b.settled && vRelN < -120) _wake(b, n);
  }

  void _wake(MarbleBody m, Offset bumpDir) {
    m.settled = false;
    m.settleFrames = 0;
    m.velocity = bumpDir * 30 + const Offset(0, -30);
  }
}
