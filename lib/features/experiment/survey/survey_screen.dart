// New Survey experiment (v60.7) — chibi-character sandbox.
//
// Per the spec: a 4-part minimum character (head, body, feet, eye)
// with optional shadow / weapon / decorations. This first slice
// ships ONLY the four mandatory parts + joystick walking + jumping.
// No combat, no weapons, no decorations, no shadow, no animations
// beyond walk-bob and jump arc.
//
// Architecture (everything lives in this single file for now —
// the spec calls for splitting into rig.dart / parts/* / etc., but
// keeping it together while we iterate is cheaper than premature
// extraction).
//
// Pipeline:
//   1. Joystick → ChibiCharacter.update(dt)
//   2. State advance (yaw smoothing, locomotion mode, jump arc)
//   3. FramePose computed (bobs, lifts, foot phases)
//   4. Skeleton snapshot built (Frame at every Slot)
//   5. Each Part.onUpdate(dt, skel) — per-frame state
//   6. Each Part.onBuild(BuildCtx) — emit (depth, draw) Ops
//   7. Sort Ops back-to-front, draw
//
// Adding a new visual = subclass a Part, override onBuild, register
// in Catalog. No render-pipeline plumbing.

import 'dart:math' as math;

import 'package:basecamp/theme/spacing.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =====================================================================
// V3 — pure 3D vector math
// =====================================================================

/// Immutable 3D vector. Used for everything from anchor positions
/// to part-local offsets to camera math. `const` ctor lets us
/// declare common offsets without per-frame allocation.
class V3 {
  const V3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  static const V3 zero = V3(0, 0, 0);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);

  double get length => math.sqrt(x * x + y * y + z * z);
}

V3 v3Lerp(V3 a, V3 b, double t) =>
    V3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

// =====================================================================
// Slot — every named anchor a part can attach to
// =====================================================================

enum Slot {
  // Ground
  ground,

  // Lower body
  footLeft,
  footRight,
  hipLeft,
  hipRight,
  hipFront,
  hipBack,
  beltCenter,
  tailBase,

  // Torso
  back,
  chestFront,
  shoulderLeft,
  shoulderRight,
  wingsLeft,
  wingsRight,

  // Neck
  neckFront,
  neckBack,

  // Head
  headBottom,
  headTop,
  headFront,
  headBack,
  headLeft,
  headRight,
  headTopLeft,
  headTopRight,

  // Above head
  hairTop,
  halo,

  // Hands
  handLeft,
  handRight,
}

// =====================================================================
// Frame — local 3D coordinate basis at an anchor
// =====================================================================

/// A right-handed (right, up, forward) basis at an origin.
/// Parts read frames to position themselves relative to a Slot.
class Frame {
  const Frame({
    required this.origin,
    required this.right,
    required this.up,
    required this.forward,
  });

  factory Frame.upright(V3 origin) => Frame(
        origin: origin,
        right: const V3(1, 0, 0),
        up: const V3(0, 1, 0),
        forward: const V3(0, 0, 1),
      );

  final V3 origin;
  final V3 right;
  final V3 up;
  final V3 forward;

  /// Convert a local-space vector to world space.
  V3 toWorld(V3 local) =>
      origin + right * local.x + up * local.y + forward * local.z;

  Frame translated(V3 delta) => Frame(
        origin: origin + delta,
        right: right,
        up: up,
        forward: forward,
      );
}

// =====================================================================
// FramePose — every per-frame scalar a part might read
// =====================================================================

class FramePose {
  const FramePose({
    required this.bodyCenterY,
    required this.walkBobY,
    required this.headBobY,
    required this.footLeftPhase,
    required this.footRightPhase,
    required this.globalLiftY,
    required this.t,
    required this.yaw,
    required this.pitch,
  });

  final double bodyCenterY;
  final double walkBobY;
  final double headBobY;

  /// 0..1 sin phase per foot. 0 = grounded, 1 = peak lift.
  final double footLeftPhase;
  final double footRightPhase;

  /// Vertical offset from a jump arc.
  final double globalLiftY;

  final double t; // current time, seconds since start
  final double yaw;
  final double pitch;
}

// =====================================================================
// Skeleton — published frame snapshot for one render pass
// =====================================================================

class Skeleton {
  Skeleton({
    required this.pose,
    required this.frames,
  })  : cy = math.cos(pose.yaw),
        sy = math.sin(pose.yaw),
        cp = math.cos(pose.pitch),
        sp = math.sin(pose.pitch);

  final FramePose pose;
  final Map<Slot, Frame> frames;

  // Cached camera basis — reused across every proj() call this
  // frame so we skip ~400 trig ops on a typical chibi.
  final double cy;
  final double sy;
  final double cp;
  final double sp;

  /// Project a world-space point to screen space.
  /// Fixed orthographic 3/4 view (FFT/Tactics-Ogre style):
  /// Y projects to screen-Y, X+Z combine to screen-X with X
  /// stretched and Z foreshortened. `depth` is +larger = closer
  /// for the back-to-front sort.
  Proj proj(V3 p) {
    final x1 = p.x * cy + p.z * sy;
    final y1 = p.y;
    final z1 = -p.x * sy + p.z * cy;
    return Proj(
      Offset(x1, -y1 * cp + z1 * sp),
      y1 * sp + z1 * cp,
    );
  }
}

class Proj {
  const Proj(this.offset, this.depth);
  final Offset offset;
  final double depth;
}

// =====================================================================
// Op — depth-tagged paint closure
// =====================================================================

class Op {
  Op(this.depth, this.draw);
  final double depth;
  final void Function() draw;
}

// =====================================================================
// BuildCtx — the only API a Part talks to
// =====================================================================

/// Helpers that emit depth-tagged Ops. Parts use these to draw —
/// never paint the canvas directly outside an op closure, otherwise
/// the back-to-front sort can't see the paint.
class BuildCtx {
  BuildCtx(this.skel, this.canvas, this.ops);

  final Skeleton skel;
  final Canvas canvas;
  final List<Op> ops;

  Frame at(Slot s) => skel.frames[s] ?? Frame.upright(V3.zero);
  FramePose get pose => skel.pose;
  Proj proj(V3 p) => skel.proj(p);

  void op(double depth, void Function() draw) =>
      ops.add(Op(depth, draw));

  /// Sphere → flat circle on screen. Radius scaled by simple depth
  /// fall-off so closer = bigger.
  void circle3D(V3 center, double r, Paint paint) {
    final p = proj(center);
    final scale = 1 + p.depth * 0.0015;
    op(p.depth, () => canvas.drawCircle(p.offset, r * scale, paint));
  }

  /// Rounded rod between two world points.
  void segment(V3 a, V3 b, double width, Paint paint) {
    final pa = proj(a);
    final pb = proj(b);
    final stroke = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    op((pa.depth + pb.depth) * 0.5, () {
      canvas.drawLine(pa.offset, pb.offset, stroke);
    });
  }

  /// Ground-plane oval (flat on the world XZ plane). Used for
  /// shadows. The pitch-sin squashes a circle into the perspective
  /// the rest of the rig uses.
  void horizontalDisk(V3 center, double r, Paint paint) {
    final p = proj(center);
    op(p.depth, () {
      canvas
        ..save()
        ..translate(p.offset.dx, p.offset.dy)
        ..scale(1, skel.sp)
        ..drawCircle(Offset.zero, r, paint)
        ..restore();
    });
  }
}

// =====================================================================
// Part — base class for everything that draws
// =====================================================================

abstract class Part {
  String get id;
  void onUpdate(double dt, Skeleton skel) {}
  void onBuild(BuildCtx ctx);
}

abstract class HeadPart extends Part {}

abstract class BodyPart extends Part {}

abstract class FootPart extends Part {}

abstract class EyePart extends Part {}

// =====================================================================
// Default concrete parts (the four required for a buildable chibi)
// =====================================================================

/// Skull radius shared between SphereHead + BunnyHead so part
/// geometry stays in lock-step with the rig's `headRadius`.
const double _kHeadRadius = 22;

class SphereHead extends HeadPart {
  @override
  String get id => 'head_sphere';

  static final _fillPaint = Paint()..color = const Color(0xFFF6EAD7);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void onBuild(BuildCtx ctx) {
    final f = ctx.at(Slot.headBottom);
    // Center the sphere in head space. headBottom is at headY -
    // headRadius, so lift by headRadius to land at headY.
    final center = f.toWorld(const V3(0, _kHeadRadius, 0));
    final p = ctx.proj(center);
    final scale = 1 + p.depth * 0.0015;
    ctx.op(p.depth, () {
      ctx.canvas
        ..drawCircle(p.offset, _kHeadRadius * scale, _fillPaint)
        ..drawCircle(p.offset, _kHeadRadius * scale, _outlinePaint);
    });
  }
}

/// Bunny-shaped head — a sphere skull with two long upright ears.
/// In the spec, ears are a Decoration layer; this part bakes them
/// directly into the head until the decoration system ships, so
/// the default loadout can be "bunny" with no extra plumbing.
///
/// Each ear is a tall oval with a pink inner oval (the inside of
/// the ear). They lean outward slightly + back, anchoring at the
/// `headTopLeft` / `headTopRight` slots so future cosmetic layers
/// (a hat, a halo) sit above them naturally.
class BunnyHead extends HeadPart {
  @override
  String get id => 'head_bunny';

  static final _furPaint = Paint()..color = const Color(0xFFF6EAD7);
  static final _innerEarPaint = Paint()..color = const Color(0xFFEFB7C2);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void onBuild(BuildCtx ctx) {
    final headBottom = ctx.at(Slot.headBottom);

    // 1) Skull — sphere centered at headY (= headBottom + radius).
    final skullCenter = headBottom.toWorld(const V3(0, _kHeadRadius, 0));
    final pSkull = ctx.proj(skullCenter);
    final skullScale = 1 + pSkull.depth * 0.0015;
    ctx.op(pSkull.depth, () {
      ctx.canvas
        ..drawCircle(pSkull.offset, _kHeadRadius * skullScale, _furPaint)
        ..drawCircle(
          pSkull.offset,
          _kHeadRadius * skullScale,
          _outlinePaint,
        );
    });

    // 2) Ears — one per side, anchored at the head-top corners.
    // The ear base sits a hair above the anchor, and the tip
    // lifts ~36 units up + leans outward by `tilt`.
    void drawEar(Slot anchor, double tilt) {
      final f = ctx.at(anchor);
      final base = f.toWorld(V3(tilt * 2, 0, 0));
      final tip = f.toWorld(V3(tilt * 8, 36, 0));
      final p = ctx.proj(base);
      final pTip = ctx.proj(tip);
      final scale = 1 + p.depth * 0.0015;
      // Ear depth slightly behind the skull so the skull's outline
      // overlaps the ear's bottom edge (reads as "ear behind face").
      final earDepth = p.depth - 0.4;
      ctx.op(earDepth, () {
        final mid = Offset(
          (p.offset.dx + pTip.offset.dx) / 2,
          (p.offset.dy + pTip.offset.dy) / 2,
        );
        final dx = pTip.offset.dx - p.offset.dx;
        final dy = pTip.offset.dy - p.offset.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        final angle = math.atan2(dy, dx) - math.pi / 2;
        ctx.canvas
          ..save()
          ..translate(mid.dx, mid.dy)
          ..rotate(angle)
          ..drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: 14 * scale,
              height: length,
            ),
            _furPaint,
          )
          ..drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: 14 * scale,
              height: length,
            ),
            _outlinePaint,
          )
          // Inner ear — a smaller pink oval, slightly toward the tip
          // side so it reads as "ear opening pointing forward".
          ..drawOval(
            Rect.fromCenter(
              center: const Offset(0, -2),
              width: 7 * scale,
              height: length * 0.7,
            ),
            _innerEarPaint,
          )
          ..restore();
      });
    }

    drawEar(Slot.headTopLeft, -1);
    drawEar(Slot.headTopRight, 1);

    // 3) Tiny pink nose dot, sitting on the face plane below the
    // eyes. Gives the face the unmistakable bunny read without
    // adding a separate Decoration part.
    final headFront = ctx.at(Slot.headFront);
    final nose = headFront.toWorld(const V3(0, -6, -2));
    final pNose = ctx.proj(nose);
    final noseScale = 1 + pNose.depth * 0.0015;
    ctx.op(pNose.depth + 0.6, () {
      ctx.canvas.drawOval(
        Rect.fromCenter(
          center: pNose.offset,
          width: 5 * noseScale,
          height: 4 * noseScale,
        ),
        _innerEarPaint,
      );
    });
  }
}

class CapsuleBody extends BodyPart {
  @override
  String get id => 'body_capsule';

  static final _fillPaint = Paint()..color = const Color(0xFF7A8C9A);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void onBuild(BuildCtx ctx) {
    final chest = ctx.at(Slot.chestFront);
    // Single rounded oval centered on the chest anchor — a chibi
    // body that reads as "small torso" rather than the previous
    // three-circle stack which looked like a snowman of the same
    // height as the head. Slot.back is reserved on the rig for
    // future cape / backpack parts; unused here.
    final p = ctx.proj(chest.origin);
    final scale = 1 + p.depth * 0.0015;
    ctx.op(p.depth - 0.01, () {
      final rect = Rect.fromCenter(
        center: p.offset,
        width: 32 * scale,
        height: 36 * scale,
      );
      ctx.canvas
        ..drawOval(rect, _fillPaint)
        ..drawOval(rect, _outlinePaint);
    });
  }
}

class Feet extends FootPart {
  @override
  String get id => 'feet_default';

  static final _fillPaint = Paint()..color = const Color(0xFF3A3A3A);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void onBuild(BuildCtx ctx) {
    void drawFoot(Slot slot, double phase) {
      final f = ctx.at(slot);
      // Lift the foot through the walk cycle.
      final lift = math.sin(phase * math.pi).clamp(0, 1) * 6.0;
      final center = f.toWorld(V3(0, 4 + lift, 0));
      final p = ctx.proj(center);
      final scale = 1 + p.depth * 0.0015;
      ctx.op(p.depth, () {
        ctx.canvas.drawOval(
          Rect.fromCenter(
            center: p.offset,
            width: 22 * scale,
            height: 14 * scale,
          ),
          _fillPaint,
        );
        ctx.canvas.drawOval(
          Rect.fromCenter(
            center: p.offset,
            width: 22 * scale,
            height: 14 * scale,
          ),
          _outlinePaint,
        );
      });
    }

    drawFoot(Slot.footLeft, ctx.pose.footLeftPhase);
    drawFoot(Slot.footRight, ctx.pose.footRightPhase);
  }
}

class CyclopsEye extends EyePart {
  @override
  String get id => 'eye_cyclops';

  static final _whitePaint = Paint()..color = const Color(0xFFFFFFFF);
  static final _pupilPaint = Paint()..color = const Color(0xFF1A1A1A);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void onBuild(BuildCtx ctx) {
    final f = ctx.at(Slot.headFront);
    // headFront is already at face-plane level (y=headY). Sit
    // slightly forward of it (z=-2) so we don't lose to depth
    // sorting against the skull surface.
    final center = f.toWorld(const V3(0, 0, -2));
    final p = ctx.proj(center);
    final scale = 1 + p.depth * 0.0015;
    ctx.op(p.depth + 0.5, () {
      // Eye white
      ctx.canvas
        ..drawOval(
          Rect.fromCenter(
            center: p.offset,
            width: 24 * scale,
            height: 18 * scale,
          ),
          _whitePaint,
        )
        ..drawOval(
          Rect.fromCenter(
            center: p.offset,
            width: 24 * scale,
            height: 18 * scale,
          ),
          _outlinePaint,
        )
        // Pupil
        ..drawCircle(p.offset, 5 * scale, _pupilPaint);
    });
  }
}

/// "Twin" eye — two ovals with pupils, the standard humanoid /
/// animal eye layout. Used by the bunny default and any future
/// loadout that wants normal-looking eyes instead of a single
/// cyclopean one.
class TwinEye extends EyePart {
  @override
  String get id => 'eye_twin';

  static final _whitePaint = Paint()..color = const Color(0xFFFFFFFF);
  static final _pupilPaint = Paint()..color = const Color(0xFF1A1A1A);
  static final _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void onBuild(BuildCtx ctx) {
    final f = ctx.at(Slot.headFront);

    void drawEye(double xOffset) {
      // headFront is at face-plane level; offset forward by z=-2 so
      // we don't lose to depth sorting against the skull.
      final center = f.toWorld(V3(xOffset, 2, -2));
      final p = ctx.proj(center);
      final scale = 1 + p.depth * 0.0015;
      ctx.op(p.depth + 0.5, () {
        ctx.canvas
          ..drawOval(
            Rect.fromCenter(
              center: p.offset,
              width: 11 * scale,
              height: 14 * scale,
            ),
            _whitePaint,
          )
          ..drawOval(
            Rect.fromCenter(
              center: p.offset,
              width: 11 * scale,
              height: 14 * scale,
            ),
            _outlinePaint,
          )
          // Pupil — slightly oval, vertical, sits center-low so the
          // eye reads as "looking forward" not "spaced out".
          ..drawOval(
            Rect.fromCenter(
              center: p.offset.translate(0, 1),
              width: 4.5 * scale,
              height: 6.5 * scale,
            ),
            _pupilPaint,
          );
      });
    }

    // Symmetric pair, ~8 units apart on the face plane.
    drawEye(-8);
    drawEye(8);
  }
}

// =====================================================================
// Loadout — the immutable parts bundle on a character
// =====================================================================

class Loadout {
  Loadout({
    required this.head,
    required this.body,
    required this.feet,
    required this.eye,
  }) : parts = List<Part>.unmodifiable(<Part>[feet, body, head, eye]);

  final HeadPart head;
  final BodyPart body;
  final FootPart feet;
  final EyePart eye;

  /// Pre-computed render-order list: feet → body → head → eye. Spec
  /// emphasizes "later entries draw over earlier ones"; depth sort
  /// inside the BuildCtx still handles cross-cluster ordering, but
  /// this is the build-call sequence. Cached as a field so the
  /// per-frame render loop doesn't allocate a fresh list every
  /// time it iterates.
  final List<Part> parts;
}

// =====================================================================
// Catalog — picker-facing list of available variants
// =====================================================================

class Variant<T extends Part> {
  const Variant(this.label, this.build);
  final String label;
  final T Function() build;
}

class Catalog {
  static const heads = <Variant<HeadPart>>[
    // Bunny first so it's the default in any picker / loadout
    // that auto-picks `Catalog.heads.first`.
    Variant('Bunny', BunnyHead.new),
    Variant('Sphere', SphereHead.new),
  ];
  static const bodies = <Variant<BodyPart>>[
    Variant('Capsule', CapsuleBody.new),
  ];
  static const feet = <Variant<FootPart>>[
    Variant('Default', Feet.new),
  ];
  static const eyes = <Variant<EyePart>>[
    // Twin first — normal humanoid/animal eye layout, the default
    // for the bunny build.
    Variant('Twin', TwinEye.new),
    Variant('Cyclops', CyclopsEye.new),
  ];
}

// =====================================================================
// ChibiCharacter — the actual Flame component
// =====================================================================

class ChibiCharacter extends PositionComponent {
  ChibiCharacter({
    required this.joystick,
    this.keyboardInput,
  }) : super(anchor: Anchor.center);

  final JoystickComponent joystick;

  /// Optional secondary input source — used on web/desktop where
  /// dragging a virtual joystick with the mouse is awkward. Null
  /// on platforms where it isn't wired (mobile-only); the chibi
  /// just falls back to the joystick.
  final KeyboardInput? keyboardInput;

  // Default loadout: bunny with normal twin eyes. Per the Catalog
  // ordering above, `Catalog.heads.first.build()` would also yield
  // BunnyHead — using the explicit constructors here keeps the
  // default discoverable from a quick read of this file.
  Loadout _loadout = Loadout(
    head: BunnyHead(),
    body: CapsuleBody(),
    feet: Feet(),
    eye: TwinEye(),
  );

  // World position in the simple 3D scene. y=0 = ground; y rises
  // when the character jumps. (The character's screen position
  // comes from PositionComponent.position, but world-space y is
  // tracked here for the jump arc.)
  double _worldY = 0;
  double _verticalVelocity = 0;
  bool _grounded = true;

  // Walk cycle phase advances with locomotion magnitude.
  double _walkPhase = 0;
  double _yaw = 0;
  double _t = 0;

  // Reused-across-frames render scratch buffers. Per the spec:
  // > The Op list is reused frame-to-frame (_ops.clear() instead
  // > of new List) to avoid per-frame List growth.
  // Same idea for the slot→Frame map: a bounded set (28 entries)
  // we mutate in place rather than re-allocate per render.
  final List<Op> _ops = <Op>[];
  final Map<Slot, Frame> _frames = <Slot, Frame>{};

  /// Jump impulse triggered from the UI button.
  void jump() {
    if (!_grounded) return;
    _verticalVelocity = 220;
    _grounded = false;
  }

  // Setter for the parts bundle. Wired through the picker UI in a
  // follow-up; currently only the default Loadout is used.
  // ignore: use_setters_to_change_properties
  void setLoadout(Loadout l) => _loadout = l;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;

    // Combine joystick + keyboard input into a single planar
    // delta. Joystick: Flame's `relativeDelta` already normalises
    // to [-1,1] per axis. Keyboard: the WASD/arrows controller
    // emits raw -1/0/+1 per axis. Sum them and clamp to a unit
    // disc so diagonal keyboard input doesn't move √2× faster.
    final kx = keyboardInput?.delta.x ?? 0;
    final ky = keyboardInput?.delta.y ?? 0;
    var dx = joystick.relativeDelta.x + kx;
    var dy = joystick.relativeDelta.y + ky;
    final raw = math.sqrt(dx * dx + dy * dy);
    if (raw > 1) {
      dx /= raw;
      dy /= raw;
    }
    final mag = raw > 1 ? 1.0 : raw;
    if (keyboardInput?.consumeJump() ?? false) {
      jump();
    }

    // Translate the character on screen — with a cap so it can't
    // leave the visible play area.
    const speed = 140.0;
    position += Vector2(dx, dy) * speed * dt;
    final size = findGame()?.size ?? Vector2(800, 600);
    position.x = position.x.clamp(40, size.x - 40);
    position.y = position.y.clamp(80, size.y - 60);

    // Yaw smoothly tracks the joystick direction.
    //
    // Sign convention here is fiddly: the rig's `headFront` sits
    // at world z=-22 (toward camera) when yaw=0, so yaw=0 = facing
    // camera. A positive yaw rotates the rig CCW from above, which
    // visually puts headFront on screen-LEFT — meaning the
    // character is showing its right shoulder. So:
    //   joystick right (dx>0) → want character facing screen-right
    //                            → world facing +X → yaw = -π/2
    //   joystick left (dx<0)  → want facing screen-left
    //                            → world facing -X → yaw = +π/2
    //   joystick up (dy<0)    → facing screen-up = world -Z = yaw 0
    //   joystick down (dy>0)  → facing screen-down = world +Z = yaw π
    // → targetYaw = atan2(-dx, -dy).
    if (mag > 0.05) {
      final targetYaw = math.atan2(-dx, -dy);
      var delta = targetYaw - _yaw;
      while (delta > math.pi) {
        delta -= math.pi * 2;
      }
      while (delta < -math.pi) {
        delta += math.pi * 2;
      }
      _yaw += delta * math.min(1, dt * 8);
    }

    // Walk cycle phase only advances when actually moving.
    _walkPhase = (_walkPhase + dt * 6 * mag) % 1.0;

    // Vertical (jump) integration.
    if (!_grounded) {
      _verticalVelocity -= 700 * dt; // gravity
      _worldY += _verticalVelocity * dt;
      if (_worldY <= 0) {
        _worldY = 0;
        _verticalVelocity = 0;
        _grounded = true;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Per-frame pose.
    final pose = FramePose(
      bodyCenterY: 50 + _worldY,
      walkBobY: math.sin(_walkPhase * math.pi * 2) * 1.5,
      headBobY: math.sin(_walkPhase * math.pi * 2 + 1) * 1.0,
      footLeftPhase: (_walkPhase + 0.5) % 1.0,
      footRightPhase: _walkPhase,
      globalLiftY: _worldY,
      t: _t,
      yaw: _yaw,
      pitch: 0.6, // ~34° camera tilt; static
    );

    // Build the rig — frames at every Slot. Chibi proportions:
    // small body, large head, head sits cleanly above body with no
    // overlap. Constants are in the same arbitrary unit space the
    // parts read; the projector handles screen scaling.
    //
    // Vertical stack (bottom → top):
    //   0–8     feet
    //   8–42    body capsule (center 25, half-height 17)
    //   42–86   head sphere (center 64, radius 22)
    //   86–125  bunny ears (when present)
    const headRadius = _kHeadRadius;
    const bodyHalfHeight = 17.0;
    final feetY = pose.globalLiftY;
    final bodyY = feetY + 25 + pose.walkBobY;
    final headY = feetY + 64 + pose.headBobY;
    // Reuse the long-lived `_frames` map across frames — bounded
    // 28 entries; clear+refill is cheaper than allocate-and-GC,
    // especially on lower-end Android where the new-gen GC takes
    // measurable pause time on every frame's worth of garbage.
    _frames
      ..clear()
      ..[Slot.ground] = Frame.upright(V3.zero)
      ..[Slot.footLeft] = Frame.upright(V3(-9, feetY, 0))
      ..[Slot.footRight] = Frame.upright(V3(9, feetY, 0))
      ..[Slot.hipLeft] = Frame.upright(V3(-12, bodyY - bodyHalfHeight, 0))
      ..[Slot.hipRight] = Frame.upright(V3(12, bodyY - bodyHalfHeight, 0))
      ..[Slot.hipFront] = Frame.upright(V3(0, bodyY - bodyHalfHeight, -8))
      ..[Slot.hipBack] = Frame.upright(V3(0, bodyY - bodyHalfHeight, 8))
      ..[Slot.beltCenter] = Frame.upright(V3(0, bodyY - 10, 0))
      ..[Slot.tailBase] = Frame.upright(V3(0, bodyY - 8, 10))
      ..[Slot.back] = Frame.upright(V3(0, bodyY + 4, 10))
      ..[Slot.chestFront] = Frame.upright(V3(0, bodyY, -10))
      ..[Slot.shoulderLeft] = Frame.upright(V3(-18, bodyY + 10, 0))
      ..[Slot.shoulderRight] = Frame.upright(V3(18, bodyY + 10, 0))
      ..[Slot.wingsLeft] = Frame.upright(V3(-12, bodyY + 8, 8))
      ..[Slot.wingsRight] = Frame.upright(V3(12, bodyY + 8, 8))
      ..[Slot.neckFront] = Frame.upright(V3(0, bodyY + 16, -6))
      ..[Slot.neckBack] = Frame.upright(V3(0, bodyY + 16, 6))
      // Head anchors — sphere center is at headY, radius 22.
      ..[Slot.headBottom] = Frame.upright(V3(0, headY - headRadius, 0))
      ..[Slot.headTop] = Frame.upright(V3(0, headY + headRadius, 0))
      ..[Slot.headFront] = Frame.upright(V3(0, headY, -headRadius))
      ..[Slot.headBack] = Frame.upright(V3(0, headY, headRadius))
      ..[Slot.headLeft] = Frame.upright(V3(-headRadius, headY, 0))
      ..[Slot.headRight] = Frame.upright(V3(headRadius, headY, 0))
      ..[Slot.headTopLeft] = Frame.upright(V3(-13, headY + 14, 0))
      ..[Slot.headTopRight] = Frame.upright(V3(13, headY + 14, 0))
      ..[Slot.hairTop] = Frame.upright(V3(0, headY + headRadius, 0))
      ..[Slot.halo] = Frame.upright(V3(0, headY + headRadius + 18, 0))
      ..[Slot.handLeft] = Frame.upright(V3(-22, bodyY - 6, 0))
      ..[Slot.handRight] = Frame.upright(V3(22, bodyY - 6, 0));

    // Reuse the ops list — `clear()` keeps the underlying buffer,
    // so subsequent frames don't trigger growable-list re-grow.
    // Per the spec: "_ops.clear() instead of new List".
    _ops.clear();
    final skel = Skeleton(pose: pose, frames: _frames);
    final ctx = BuildCtx(skel, canvas, _ops);

    // Per-frame state advance + ops emission. Iterating
    // `_loadout.parts` (a cached unmodifiable List, see Loadout)
    // avoids the previous getter-allocates-fresh-list pattern.
    final parts = _loadout.parts;
    for (var i = 0; i < parts.length; i++) {
      parts[i].onUpdate(0, skel);
    }
    for (var i = 0; i < parts.length; i++) {
      parts[i].onBuild(ctx);
    }

    _ops.sort((a, b) => a.depth.compareTo(b.depth));
    for (var i = 0; i < _ops.length; i++) {
      _ops[i].draw();
    }
  }
}

// =====================================================================
// Keyboard input — web/desktop alternative to the joystick
// =====================================================================

/// Tracks WASD / arrow-key state into a unit-vector delta plus a
/// one-shot jump flag. ChibiCharacter reads these alongside the
/// joystick — sums + clamps the two so a user pressing both at
/// once doesn't move twice as fast.
///
/// Long-lived (one instance per game), receives keyboard events
/// through `KeyboardHandler` (mixed in here, hosted on a game
/// that mixes in `HasKeyboardHandlerComponents`).
class KeyboardInput extends Component with KeyboardHandler {
  final Vector2 delta = Vector2.zero();
  bool _jumpQueued = false;

  /// Reads + resets the queued jump flag in one shot. Lets the
  /// chibi handle "user pressed Space" without us having to debounce
  /// repeated key-repeat events.
  bool consumeJump() {
    if (!_jumpQueued) return false;
    _jumpQueued = false;
    return true;
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Recompute the delta from the live `keysPressed` set — handles
    // chord changes (e.g. release one key while another is still
    // held) without leaking stuck-on movement.
    var x = 0;
    var y = 0;
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW)) {
      y -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS)) {
      y += 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA)) {
      x -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD)) {
      x += 1;
    }
    delta
      ..x = x.toDouble()
      ..y = y.toDouble();

    // Queue a jump on Space-press. Auto-repeat re-sends KeyDown
    // for held keys; the chibi's `_grounded` check ignores extras
    // anyway, but consume-on-read keeps the contract clean.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _jumpQueued = true;
      return true;
    }
    return delta.x != 0 || delta.y != 0;
  }
}

// =====================================================================
// Game host
// =====================================================================

class _SurveyGame extends FlameGame
    with HasGameReference, HasKeyboardHandlerComponents {
  late final JoystickComponent joystick;
  late final KeyboardInput keyboardInput;
  late final ChibiCharacter chibi;

  // External handle so the screen's "Jump" button can poke us.
  void requestJump() => chibi.jump();

  @override
  Color backgroundColor() => const Color(0xFFE8E5DD);

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final knobPaint = BasicPalette.darkGray.paint();
    final bgPaint = BasicPalette.gray.withAlpha(96).paint();
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 22, paint: knobPaint),
      background: CircleComponent(radius: 56, paint: bgPaint),
      margin: const EdgeInsets.only(left: 28, bottom: 28),
    );
    add(joystick);

    keyboardInput = KeyboardInput();
    add(keyboardInput);

    chibi = ChibiCharacter(
      joystick: joystick,
      keyboardInput: keyboardInput,
    )
      ..position = Vector2(size.x * 0.5, size.y * 0.55)
      ..size = Vector2(120, 160);
    add(chibi);
  }
}

// =====================================================================
// Survey screen
// =====================================================================

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  late final _SurveyGame _game = _SurveyGame();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Survey'),
        // Subtitle-style hint about what this is, in case the user
        // lands here without context.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chibi sandbox · joystick / WASD / arrows · jump = '
                'tap or space',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GameWidget<_SurveyGame>(game: _game),
          // Jump button — bottom-right, mirroring the joystick on
          // the bottom-left. Touch on web works the same as mobile.
          Positioned(
            right: 28,
            bottom: 28,
            child: FloatingActionButton(
              onPressed: _game.requestJump,
              tooltip: 'Jump',
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ],
      ),
    );
  }
}
