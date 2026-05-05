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

  /// Top opening (rim) — the visual edge of the woven body.
  static const double rimY = 50;
  static const double leftRimX = 54;
  static const double rightRimX = 266;

  /// Bottom of the basket (floor of the woven container).
  static const double basketFloorY = 218;
  static const double leftBaseX = 76;
  static const double rightBaseX = 244;

  /// Rounded base radius — corners curve up here.
  static const double baseCornerR = 14;

  /// World ground (where overspill marbles settle). Aligned with
  /// `basketFloorY` so a marble overflowing the basket lands on
  /// the same visual floor level as the marbles inside it — the
  /// audit caught a 14px mismatch where overspill marbles
  /// floated above the basket's painted base.
  static const double groundY = basketFloorY;

  /// Rim threshold — once a settled marble inside has its centre
  /// below this y, it's considered "in the pile" for capacity.
  static const double settledCutoffY = 130;

  /// Marble radius (must match the painter's r).
  static const double marbleR = 33;

  /// How many marbles can pile up inside the basket before the
  /// next spawn redirects to overspill. The capacity is larger
  /// than what the visible body holds (~6) on purpose — marbles
  /// 7–10 pile ABOVE the rim, "spilling over the edge" of the
  /// basket. The [physicsWallTopY] extension (below) gives them
  /// lateral support so they don't just roll off. Marble #11
  /// onward goes to the overspill (ground) zone.
  static const int basketCapacity = 10;

  /// Y-coordinate of the **physics-only** wall top. The visible
  /// woven body still ends at [rimY]; we extend the collision
  /// walls up to here so marbles piling above the rim have
  /// something to lean against. Kids see marbles peeking over
  /// the basket edge naturally without rolling off the sides.
  static const double physicsWallTopY = 10;

  /// Left wall of the basket as a line segment. The visible
  /// woven body ends at [rimY] but the collision wall reaches
  /// up to [physicsWallTopY]. We linearly extrapolate the wall
  /// slope so the over-rim section keeps the same outward taper
  /// — a marble piling above is leaning against the same
  /// imaginary line, just higher.
  ///
  /// The wall opens outward going DOWN (from rim x=54 to base
  /// x=76, so the basket gets narrower toward the bottom):
  ///   |slope| = (leftBaseX - leftRimX) / (basketFloorY - rimY)
  ///           = (76 - 54) / (218 - 50) = 0.131
  ///   Going UP from the rim, the wall opens outward (smaller
  ///   x on the left). At physicsWallTopY = 10 (40px above rim):
  ///     x = leftRimX - |slope| * (rimY - physicsWallTopY)
  ///       = 54 - 0.131 * 40
  ///       ≈ 48.76
  static const Offset leftWallTop = Offset(48.76, physicsWallTopY);
  static const Offset leftWallBottom = Offset(leftBaseX, basketFloorY);

  /// Right wall (mirror).
  ///   x = rightRimX + |slope| * (rimY - physicsWallTopY)
  ///     = 266 + 0.131 * 40
  ///     ≈ 271.24
  static const Offset rightWallTop = Offset(271.24, physicsWallTopY);
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
    this.palette,
  });

  final FaceMood mood;
  final int seed;
  final double tOffset;

  /// Color override the marble was dropped with. Persists for
  /// the marble's lifetime so a face dropped wearing the green
  /// palette stays green — the per-question color rotation
  /// rotates the CHOICE row, not the marbles already in the
  /// basket.
  final FacePalette? palette;

  Offset position;
  Offset velocity;

  /// Rotation in radians. Marbles in flight spin freely; on a
  /// floor / wall contact, the tangent component of velocity
  /// converts to spin (real-ball physics — fast horizontal hit
  /// on a floor = backspin), and on a flat surface, rolling
  /// friction couples linear + angular velocity.
  double angle = 0;
  double angularVelocity = 0;

  /// Which physics zone this marble lives in. Determines which
  /// walls it collides with.
  MarbleZone zone;

  MarbleVariant variant;

  /// One-shot direction-aware squash from each collision. Set to
  /// `velocity along normal / 200` (capped at 0.6) on impact;
  /// decays to 0 over ~200ms. The painter pancakes the marble
  /// along [impactNormal]: floor hit = vertical squish, wall hit
  /// = horizontal squish, marble-on-marble = squish along the
  /// contact line.
  double impactSquash = 0;
  Offset impactNormal = const Offset(0, -1);

  /// Cartoon-physics flight stretch: when |v| > 200 px/s, the
  /// marble visually elongates along the velocity vector by up
  /// to 10%. Computed each frame from velocity; not stored —
  /// kept as a getter on the painter side.

  /// True once the marble has stopped moving. Settled marbles
  /// skip the integrate / collide pipeline; they still draw +
  /// animate variants.
  bool settled = false;

  /// Frames in a row with |v| AND |angularV| below threshold.
  /// Once this exceeds [BasketWorld._sleepFrames], the marble
  /// sleeps. Spinning marbles don't sleep — even if they're not
  /// translating, they're still alive on screen.
  int settleFrames = 0;

  /// Bounce counter for the hard-cap. Resets if the marble has
  /// gone [BasketWorld._bounceWindow] seconds without bouncing.
  int bounceCount = 0;
  double bounceClock = 0;

  /// Per-instance restitution. Drops slightly each bounce (×0.9)
  /// to model energy loss in the deformation, so the 4th bounce
  /// is much weaker than the 1st. Resets to default if the
  /// marble has gone a full second without bouncing (edge case
  /// where a wake-on-impact restarts physics).
  double restitution = 0.42;

  /// Per-marble time-scale (0.85..1.15). Multiplies the
  /// animation `t` so two marbles with the same variant + phase
  /// drift apart over time — kills "the whole pile is breathing
  /// in lockstep" creepiness.
  double timeScale = 1.0;

  /// Wall-clock seconds remaining until the next variant swap.
  /// Initialised to a random value in [4, 7]; counts down each
  /// frame; on hit, picks the next variant + fires a transition
  /// pulse.
  double variantTtl = 5;

  /// 0..1 — short transition pulse fired the moment a variant
  /// swap lands. The painter reads this and overlays a brief
  /// scale + halo brightness bump (~220ms) so the eye catches
  /// the moment a marble's animation flavour changes. Decays at
  /// ~4.5/sec.
  double variantTransitionT = 0;

  /// Look-at offset, in radians. When a settled neighbour is
  /// bumped by a hard arrival, we set this to a small angle (8–
  /// 12°) toward the arrival so the face turns to look. Decays
  /// to 0 over ~600ms (smooth easeOutCubic on the painter side).
  double lookAtT = 0;
  double lookAtAngle = 0;

  MarbleBody copyWith({MarbleVariant? variant}) {
    return MarbleBody(
      mood: mood,
      palette: palette, // preserve question-locked color override
      position: position,
      velocity: velocity,
      seed: seed,
      variant: variant ?? this.variant,
      tOffset: tOffset,
      zone: zone,
    );
  }

  /// Default-construct a `variantTtl` so freshly-spawned marbles
  /// don't all swap at the same moment. Internally inserted by
  /// [BasketWorld.addMarble].
  static double initialVariantTtl(math.Random rng) =>
      4.0 + rng.nextDouble() * 3.0;

  /// 0.85..1.15 random scale so two marbles with the same
  /// variant phase drift apart over time. Combined with the
  /// random tOffset, marbles with identical variants and seeds
  /// still feel distinct.
  static double initialTimeScale(math.Random rng) =>
      0.85 + rng.nextDouble() * 0.30;
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

  /// Drop a fresh marble in.
  ///
  /// [spawnAt] is the local 320×240 position the kid released
  /// the drag at — the marble starts there with a small downward
  /// velocity, so the drop reads as "the face fell from where I
  /// let go" rather than teleporting to the rim.
  ///
  /// [palette] is the body / ring / cheek override the choice
  /// was wearing this question. Persists for the marble's whole
  /// lifetime so the colors don't shift when the next question
  /// rotates the choice row.
  MarbleBody addMarble(
    FaceMood mood, {
    Offset? spawnAt,
    FacePalette? palette,
  }) {
    final basketHowFull =
        marbles.where((m) => m.zone == MarbleZone.basket).length;
    final overspill = basketHowFull >= BasketGeometry.basketCapacity;
    final body = overspill
        ? _spawnOverspill(mood, palette: palette)
        : _spawnInBasket(mood, spawnAt: spawnAt, palette: palette);
    marbles.add(body);
    return body;
  }

  MarbleBody _spawnInBasket(
    FaceMood mood, {
    Offset? spawnAt,
    FacePalette? palette,
  }) {
    // Spawn position is the drag-end x clamped into the rim, with
    // y always pinned just above the rim line so the marble FALLS
    // into the basket via gravity. The audit caught the bug where
    // a drop in the bottom corner clamped to the rim and looked
    // like the marble teleported across the screen — fix is to
    // ALWAYS spawn just above the rim regardless of where the
    // drag ended on the y axis. The drag's x is preserved so the
    // kid still sees "the marble drops where I let go" laterally.
    final spawn = spawnAt == null
        ? Offset(BasketGeometry.worldW / 2, BasketGeometry.rimY - 10)
        : Offset(
            spawnAt.dx.clamp(
              BasketGeometry.leftRimX + BasketGeometry.marbleR,
              BasketGeometry.rightRimX - BasketGeometry.marbleR,
            ),
            // y is always at the rim — no teleporting from the
            // bottom of the canvas up to the top.
            BasketGeometry.rimY - 10,
          );
    return MarbleBody(
      mood: mood,
      palette: palette,
      position: spawn,
      velocity: Offset(
        (_rng.nextDouble() - 0.5) * 30, // small lateral jitter
        140 + _rng.nextDouble() * 80,
      ),
      seed: marbles.length,
      variant: MarbleVariant.values[_rng.nextInt(4)],
      tOffset: _rng.nextDouble() * 6.28,
      zone: MarbleZone.basket,
    )
      ..variantTtl = MarbleBody.initialVariantTtl(_rng)
      ..timeScale = MarbleBody.initialTimeScale(_rng)
      ..angularVelocity = (_rng.nextDouble() - 0.5) * 4.0;
  }

  MarbleBody _spawnOverspill(FaceMood mood, {FacePalette? palette}) {
    // True random placement around the basket — no fixed cycling.
    // Pick one of three zones (left of basket, right of basket,
    // or front-center on the floor), then a random x within that
    // zone. Front-center is weighted slightly higher because the
    // camera is there and that's where the eye reads "around the
    // basket" most naturally. Marble-marble collision (already in
    // place) handles overlap, so even if two random spawns land
    // at the same x they get shoved apart on the way down — no
    // pyramid stacking on the same column.
    const r = BasketGeometry.marbleR;
    final zoneRoll = _rng.nextDouble();
    final double spawnX;
    final double vx;
    if (zoneRoll < 0.30) {
      // Left of basket: x ∈ [r, leftRimX - r * 0.5]. Lateral
      // velocity outward (negative) so the marble arcs away from
      // the rim before falling.
      spawnX = r + _rng.nextDouble() *
          (BasketGeometry.leftRimX - r * 1.5);
      vx = -40 - _rng.nextDouble() * 60;
    } else if (zoneRoll < 0.60) {
      // Right of basket: x ∈ [rightRimX + r * 0.5, worldW - r].
      spawnX = BasketGeometry.rightRimX + r * 0.5 +
          _rng.nextDouble() *
              (BasketGeometry.worldW - BasketGeometry.rightRimX - r * 1.5);
      vx = 40 + _rng.nextDouble() * 60;
    } else {
      // Front-center floor: x ∈ [60, 260]. Small lateral velocity
      // (±25 px/s) so consecutive front-zone spawns don't trace
      // identical paths.
      spawnX = 60.0 + _rng.nextDouble() * 200;
      vx = (_rng.nextDouble() - 0.5) * 50;
    }
    // Clamp the spawn x to inside the world's left/right walls so
    // we don't start an overspill marble already overlapping a
    // wall (caught by the audit — left-zone spawn at x=30 with
    // r=33 had spawnX-r=-3, briefly past the left wall).
    final clampedX = spawnX.clamp(r + 1, BasketGeometry.worldW - r - 1);
    return MarbleBody(
      mood: mood,
      palette: palette,
      position: Offset(clampedX, BasketGeometry.rimY - 8),
      velocity: Offset(vx, 100 + _rng.nextDouble() * 60),
      seed: marbles.length,
      variant: MarbleVariant.values[_rng.nextInt(4)],
      tOffset: _rng.nextDouble() * 6.28,
      zone: MarbleZone.ground,
    )
      ..variantTtl = MarbleBody.initialVariantTtl(_rng)
      ..timeScale = MarbleBody.initialTimeScale(_rng)
      ..angularVelocity = (_rng.nextDouble() - 0.5) * 6.0;
  }

  /// Wipe the world. Called by the parent on session reset.
  void reset() {
    marbles.clear();
    t = 0;
  }

  // ——— Tunables ————————————————————————————————————————————————

  static const double _gravity = 1200; // px/s²
  // Per-frame damping at 60fps. Adjusted by `dt*60` so framerate
  // changes don't change settle speed (30fps still settles).
  static const double _damping60 = 0.93;
  // Angular damping is more aggressive — spinning eats energy
  // quickly so we don't get a marble that translates fine but
  // spins forever.
  static const double _angDamping60 = 0.88;
  static const double _sleepThreshold = 8; // px/s
  static const double _angSleepThreshold = 0.6; // rad/s
  static const int _sleepFrames = 6;
  static const int _maxBounces = 12;
  static const double _bounceWindow = 1.0; // seconds
  // Energy stays in the marble after each bounce by this factor —
  // 4th bounce is much weaker than the 1st.
  static const double _bounceDecay = 0.85;

  // ——— Step ————————————————————————————————————————————————————

  /// Advance the world by [dt] seconds.
  void step(double dt) {
    t += dt;
    // Frame-rate-independent damping multiplier.
    final damp = math.pow(_damping60, dt * 60).toDouble();
    final angularDamp = math.pow(_angDamping60, dt * 60).toDouble();

    // 1) Per-marble bookkeeping — variant TTL, decays, clocks.
    for (final m in marbles) {
      // Variant cycling.
      m.variantTtl -= dt;
      if (m.variantTtl <= 0) {
        m.variant = MarbleVariant
            .values[(m.variant.index + 1) % MarbleVariant.values.length];
        m.variantTtl = MarbleBody.initialVariantTtl(_rng);
        // Fire a transition pulse so the eye catches the swap.
        m.variantTransitionT = 1.0;
      }
      // Decays.
      if (m.impactSquash > 0) {
        m.impactSquash = math.max(0, m.impactSquash - dt * 5.0);
      }
      if (m.variantTransitionT > 0) {
        m.variantTransitionT =
            math.max(0, m.variantTransitionT - dt * 4.5);
      }
      if (m.lookAtT > 0) {
        m.lookAtT = math.max(0, m.lookAtT - dt * 1.7); // ~600ms decay
      }
      // Bounce-window reset.
      m.bounceClock += dt;
      if (m.bounceClock > _bounceWindow) {
        m.bounceCount = 0;
        m.bounceClock = 0;
        m.restitution = 0.42; // restore default after quiet period
      }
    }

    // 2) Integrate gravity + velocity + spin for unsettled marbles.
    for (final m in marbles) {
      if (m.settled) continue;
      m.velocity = Offset(
        m.velocity.dx * damp,
        (m.velocity.dy + _gravity * dt) * damp,
      );
      m.position = m.position + m.velocity * dt;
      m.angularVelocity *= angularDamp;
      m.angle += m.angularVelocity * dt;
      _collideWalls(m);
    }

    // 3) Pairwise collisions — same-zone only (basket marbles
    //    don't push ground marbles).
    for (var i = 0; i < marbles.length; i++) {
      for (var j = i + 1; j < marbles.length; j++) {
        if (marbles[i].zone != marbles[j].zone) continue;
        _collidePair(marbles[i], marbles[j]);
      }
    }

    // 4) Sleep + hard cap. Three guards together:
    //    a) BOTH linear AND angular velocity below threshold —
    //       a spinning marble can't sleep.
    //    b) Marble is RESTING — touching a wall/floor/another
    //       settled marble. Without this check a marble at the
    //       apex of a small bounce (where vy crosses zero
    //       briefly) could sleep mid-air. Audit caught this.
    //    c) Hard cap on bounces: > _maxBounces in 1s → force-
    //       settle, but push out of any wall overlap first so
    //       we don't pin a marble through the basket wall.
    for (final m in marbles) {
      if (m.settled) continue;
      if (m.bounceCount >= _maxBounces) {
        _forceSettleSafely(m);
        continue;
      }
      final restingLinear = m.velocity.distance < _sleepThreshold;
      final restingAngular = m.angularVelocity.abs() < _angSleepThreshold;
      final hasContact = _isMarbleResting(m);
      if (restingLinear && restingAngular && hasContact) {
        m.settleFrames += 1;
        if (m.settleFrames >= _sleepFrames) {
          _settle(m);
        }
      } else {
        m.settleFrames = 0;
      }
    }
  }

  /// Hard-cap force-settle. Pushes the marble out of any wall
  /// overlap before settling so we don't pin a marble through
  /// the basket wall on its 13th bounce.
  void _forceSettleSafely(MarbleBody m) {
    // Run wall collision once more so any current overlap gets
    // resolved (position pushed out along the inward normal).
    _collideWalls(m);
    _settle(m);
  }

  void _settle(MarbleBody m) {
    m.settled = true;
    m.velocity = Offset.zero;
    m.angularVelocity = 0;
    // One-shot squash on settle along the gravity normal.
    m.impactSquash = 0.55;
    m.impactNormal = const Offset(0, -1);
  }

  /// `true` when [m] is touching a wall, floor, or another
  /// settled marble within radius distance. Used as a guard so
  /// the sleep check doesn't fire mid-air when velocity briefly
  /// crosses zero at the apex of a bounce.
  bool _isMarbleResting(MarbleBody m) {
    const r = BasketGeometry.marbleR;
    const epsilon = 2.0; // a couple px of slack
    if (m.zone == MarbleZone.basket) {
      // Touching basket floor?
      if (m.position.dy + r >= BasketGeometry.basketFloorY - epsilon) {
        return true;
      }
      // Touching either sloped wall?
      if (_distanceFromSegment(
            m.position,
            BasketGeometry.leftWallTop,
            BasketGeometry.leftWallBottom,
          ) <=
          r + epsilon) {
        return true;
      }
      if (_distanceFromSegment(
            m.position,
            BasketGeometry.rightWallTop,
            BasketGeometry.rightWallBottom,
          ) <=
          r + epsilon) {
        return true;
      }
    } else {
      // Ground zone — touching ground floor?
      if (m.position.dy + r >= BasketGeometry.groundY - epsilon) return true;
    }
    // Touching another settled marble in the same zone?
    for (final other in marbles) {
      if (identical(other, m) || !other.settled) continue;
      if (other.zone != m.zone) continue;
      final dx = other.position.dx - m.position.dx;
      final dy = other.position.dy - m.position.dy;
      final distSq = dx * dx + dy * dy;
      final r2 = (2 * r + epsilon) * (2 * r + epsilon);
      if (distSq <= r2) return true;
    }
    return false;
  }

  double _distanceFromSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final tt = ((ap.dx * ab.dx + ap.dy * ab.dy) / ab2).clamp(0.0, 1.0);
    final closest = a + ab * tt;
    return (p - closest).distance;
  }

  /// Collide one marble against the world boundaries (basket
  /// walls + floor for basket-zone, ground for ground-zone).
  /// On every contact:
  ///   * Position is pushed out along the inward normal so the
  ///     marble can't tunnel.
  ///   * Velocity reflects along the normal with the marble's
  ///     current `restitution` (which decays each bounce).
  ///   * Tangent component of velocity drives spin — fast
  ///     horizontal hit on a floor = backspin etc.
  ///   * `impactSquash` is set proportional to impact strength
  ///     so the painter pancakes the marble along the normal.
  void _collideWalls(MarbleBody m) {
    const r = BasketGeometry.marbleR;
    if (m.zone == MarbleZone.basket) {
      // ——— Floor ———
      if (m.position.dy + r > BasketGeometry.basketFloorY) {
        m.position = Offset(m.position.dx, BasketGeometry.basketFloorY - r);
        if (m.velocity.dy > 0) {
          _registerImpact(m, const Offset(0, -1));
          // Tangent (horizontal) velocity → spin.
          m.angularVelocity += m.velocity.dx * 0.04;
          m.velocity = Offset(
            m.velocity.dx * 0.85,
            -m.velocity.dy * m.restitution,
          );
        }
      }
      _collideAgainstSegment(
        m,
        BasketGeometry.leftWallTop,
        BasketGeometry.leftWallBottom,
        normalAwayFromInteriorTowardLeft: true,
      );
      _collideAgainstSegment(
        m,
        BasketGeometry.rightWallTop,
        BasketGeometry.rightWallBottom,
        normalAwayFromInteriorTowardLeft: false,
      );
    } else {
      // ——— Ground floor ———
      if (m.position.dy + r > BasketGeometry.groundY) {
        m.position = Offset(m.position.dx, BasketGeometry.groundY - r);
        if (m.velocity.dy > 0) {
          _registerImpact(m, const Offset(0, -1));
          m.angularVelocity += m.velocity.dx * 0.05;
          m.velocity = Offset(
            m.velocity.dx * 0.82,
            -m.velocity.dy * m.restitution,
          );
        }
      }
      // ——— Soft side walls so overspill doesn't roll off ———
      if (m.position.dx - r < 0) {
        m.position = Offset(r, m.position.dy);
        if (m.velocity.dx < 0) {
          _registerImpact(m, const Offset(1, 0));
          m.velocity = Offset(-m.velocity.dx * m.restitution, m.velocity.dy);
          m.angularVelocity -= m.velocity.dy * 0.04;
        }
      } else if (m.position.dx + r > BasketGeometry.worldW) {
        m.position = Offset(BasketGeometry.worldW - r, m.position.dy);
        if (m.velocity.dx > 0) {
          _registerImpact(m, const Offset(-1, 0));
          m.velocity = Offset(-m.velocity.dx * m.restitution, m.velocity.dy);
          m.angularVelocity += m.velocity.dy * 0.04;
        }
      }
    }
  }

  /// Centralised on-impact bookkeeping. Sets `impactSquash`
  /// proportional to the impact velocity along the inward normal
  /// (capped 0.6 so we don't pancake a marble flat), records the
  /// normal so the painter knows which axis to squash along, and
  /// decays the marble's restitution by [_bounceDecay] so each
  /// successive bounce is weaker.
  void _registerImpact(MarbleBody m, Offset inwardNormal) {
    final vAlong =
        -(m.velocity.dx * inwardNormal.dx + m.velocity.dy * inwardNormal.dy);
    if (vAlong < 30) return; // too soft to register
    final s = math.min(0.6, vAlong / 350);
    if (s > m.impactSquash) m.impactSquash = s;
    m.impactNormal = inwardNormal;
    m.bounceCount += 1;
    m.bounceClock = 0;
    m.restitution *= _bounceDecay;
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
      _registerImpact(m, inward);
      m.velocity = m.velocity - inward * (vAlongN * (1 + m.restitution));
      // Friction-ish damp on tangent.
      m.velocity = Offset(m.velocity.dx * 0.92, m.velocity.dy * 0.92);
      // Tangent velocity → spin. The tangent direction is
      // perpendicular to the inward normal.
      final tangent = Offset(-inward.dy, inward.dx);
      final vAlongT =
          m.velocity.dx * tangent.dx + m.velocity.dy * tangent.dy;
      m.angularVelocity += vAlongT * 0.05;
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
    // component (equal-mass elastic), apply averaged restitution.
    final vRel = b.velocity - a.velocity;
    final vRelN = vRel.dx * n.dx + vRel.dy * n.dy;
    if (vRelN > 0) return; // already separating
    final restitution = (a.restitution + b.restitution) / 2;
    final impulse = n * (vRelN * (1 + restitution));
    if (!a.settled) a.velocity = a.velocity + impulse;
    if (!b.settled) b.velocity = b.velocity - impulse;

    // Squash both marbles along the contact normal (proportional
    // to impact strength). Looks like a "kiss" between the two.
    // Audit fix: pairwise impacts now also feed `bounceCount` and
    // decay restitution — without this, two marbles can pair-
    // jitter forever without either tripping the hard cap.
    if (vRelN < -50) {
      final s = math.min(0.45, -vRelN / 350);
      if (s > a.impactSquash) {
        a.impactSquash = s;
        a.impactNormal = -n;
      }
      if (s > b.impactSquash) {
        b.impactSquash = s;
        b.impactNormal = n;
      }
      // Count this as a bounce on both marbles so the hard cap
      // can eventually trip if they keep ringing each other.
      if (!a.settled) {
        a.bounceCount += 1;
        a.bounceClock = 0;
        a.restitution *= _bounceDecay;
      }
      if (!b.settled) {
        b.bounceCount += 1;
        b.bounceClock = 0;
        b.restitution *= _bounceDecay;
      }
      // Friction at the contact point converts tangential motion
      // into spin — both marbles get a kick in opposite
      // directions.
      final tangent = Offset(-n.dy, n.dx);
      final vRelT = vRel.dx * tangent.dx + vRel.dy * tangent.dy;
      a.angularVelocity -= vRelT * 0.03;
      b.angularVelocity += vRelT * 0.03;
    }

    // Wake-on-arrival: a settled neighbour gets a tiny twist
    // toward the arriving marble (look-at) instead of a hard
    // physics bump. Reads as "oh, hi" rather than an earthquake.
    if (a.settled && vRelN < -100) _lookAtNudge(a, b);
    if (b.settled && vRelN < -100) _lookAtNudge(b, a);
  }

  /// A settled marble registers a hard arrival: turn its painted
  /// face slightly toward the arrival, decay back over ~600ms.
  /// Doesn't wake the marble — it stays settled, just tilts.
  void _lookAtNudge(MarbleBody settled, MarbleBody arrival) {
    final dx = arrival.position.dx - settled.position.dx;
    // Small angle (8–12°) toward the new arrival, sign-driven by
    // whether the arrival is to the left or right.
    final magnitude = 0.14 + _rng.nextDouble() * 0.07;
    settled.lookAtAngle = dx >= 0 ? magnitude : -magnitude;
    settled.lookAtT = 1.0;
  }
}
