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

import 'dart:async';
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
// Depth scale — fakes 3D by shrinking things higher on the screen
// =====================================================================

/// Map a screen-space Y to a "depth scale" for fake-3D shrinkage.
/// Top of the visible play area = farther away = smaller; bottom =
/// closer to camera = full size. Used by the chibi (Y-scale walking
/// feels like the character is really moving toward / away from the
/// camera) and by world props that want the same horizon read.
///
/// We use the playable strip [80 .. screenH-60] so the curve doesn't
/// hit its extremes for the parts of the screen the chibi can't
/// actually reach (above the plate / below the jar).
double depthScaleForY(double y, double screenH) {
  const farthest = 0.55;
  const closest = 1.0;
  const top = 80.0;
  final bottom = screenH - 60;
  if (bottom <= top) return closest;
  final t = ((y - top) / (bottom - top)).clamp(0.0, 1.0);
  return farthest + (closest - farthest) * t;
}

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
/// animal eye layout. v60.9: blinks every few seconds (driven by
/// `blinkPhaseAt(t)` reading `pose.t`); pupils drift gently with
/// a sine of t so the chibi feels alive at idle.
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
    // Animation: shared blink rhythm via pose.t. Two eyes blink
    // together (same seed). Pupil drift uses a slower sine so
    // they wander a bit.
    final blink = blinkPhaseAt(ctx.pose.t);
    final open = (1 - blink).clamp(0.05, 1.0);
    final pupil = math.sin(ctx.pose.t * 0.8) * 0.4;

    void drawEye(double xOffset) {
      // headFront is at face-plane level; offset forward by z=-2 so
      // we don't lose to depth sorting against the skull.
      final center = f.toWorld(V3(xOffset, 2, -2));
      final p = ctx.proj(center);
      final scale = 1 + p.depth * 0.0015;
      ctx.op(p.depth + 0.5, () {
        ctx.canvas
          // Eye white — vertical extent squashes by `open` for blink.
          ..drawOval(
            Rect.fromCenter(
              center: p.offset,
              width: 11 * scale,
              height: 14 * scale * open,
            ),
            _whitePaint,
          )
          ..drawOval(
            Rect.fromCenter(
              center: p.offset,
              width: 11 * scale,
              height: 14 * scale * open,
            ),
            _outlinePaint,
          );
        // Pupil — only render when the eye is open enough to host
        // it; otherwise it'd render as a smear behind a closed lid.
        if (open > 0.25) {
          ctx.canvas.drawOval(
            Rect.fromCenter(
              center: p.offset.translate(pupil * 2 * scale, 1),
              width: 4.5 * scale,
              height: 6.5 * scale * open,
            ),
            _pupilPaint,
          );
        }
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
    // leave the visible play area. Speed itself is depth-scaled in
    // the same direction the chibi visually shrinks, so walking
    // "into the distance" feels like real horizon-distance travel
    // (you cover less screen-pixels per second the smaller you are).
    final game = findGame();
    final size = game?.size ?? Vector2(800, 600);
    final depthScale = depthScaleForY(position.y, size.y);
    final speed = 140.0 * depthScale;
    position += Vector2(dx, dy) * speed * dt;

    // Walkable region: above the jar's top, below the plate's
    // bottom. The jar is the foreground prop the user can throw
    // marbles into — they can't walk into it.
    final game2 = (game is _SurveyGame) ? game : null;
    final jarTop = game2?.jar.position.y ?? size.y;
    position.x = position.x.clamp(40, size.x - 40);
    position.y = position.y.clamp(80, jarTop - 16);

    // Plate collision (v60.9). The question plate is rendered as
    // a Flutter overlay; we collide against its screen-space AABB
    // so the chibi can't walk through it. Push out along the
    // shortest-overlap axis so the chibi slides naturally around
    // edges instead of teleporting around the plate.
    final plate = game2?.plateBounds;
    if (plate != null) {
      // Chibi collision footprint — narrower than its render size
      // because the visible chibi only fills the lower ~half of
      // its component bounds (head extends up). Scale the
      // footprint with the same depth-scale we apply to the
      // visuals so a tiny far-away chibi has a tiny hitbox.
      final halfW = 26.0 * depthScale;
      final halfH = 50.0 * depthScale;
      final cx = position.x;
      final cy = position.y;
      final left = plate.left;
      final right = plate.right;
      final top = plate.top;
      final bottom = plate.bottom;
      final overlapX = (cx + halfW).clamp(left, right) -
          (cx - halfW).clamp(left, right);
      final overlapY = (cy + halfH).clamp(top, bottom) -
          (cy - halfH).clamp(top, bottom);
      if (overlapX > 0 && overlapY > 0) {
        // Push out along the smaller penetration axis.
        if (overlapX < overlapY) {
          if (cx < (left + right) / 2) {
            position.x = left - halfW;
          } else {
            position.x = right + halfW;
          }
        } else {
          if (cy < (top + bottom) / 2) {
            position.y = top - halfH;
          } else {
            position.y = bottom + halfH;
          }
        }
      }
    }

    // Apply the depth scale to the visual after position settles
    // so chibi at the top of the screen reads as "in the distance"
    // and at the bottom (near jar) reads as "in the foreground."
    // Re-read after the clamp/collisions in case Y was pushed.
    final finalScale = depthScaleForY(position.y, size.y);
    scale.setAll(finalScale);

    // Y-based render priority — pairs with `_MarbleNode`'s same
    // assignment so the chibi can pass behind a marble that's
    // closer to the camera (higher Y) and in front of one that's
    // farther (lower Y). Cheap fake-depth sort.
    priority = position.y.round();

    // Push the action context to the game on every move so the
    // FAB stays in sync with where we are.
    game2?.updateProximity();

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

    // Per-frame pose. Idle breathing micro-anim (v60.9): even when
    // _walkPhase isn't advancing (joystick at rest), the body
    // gently rises + falls and the head bobs slightly — the chibi
    // never goes fully static, so it reads as alive rather than a
    // dropped statue.
    final idleBob = math.sin(_t * 2.0) * 1.2;
    final idleHead = math.sin(_t * 2.0 + 1.4) * 0.8;
    final pose = FramePose(
      bodyCenterY: 50 + _worldY,
      walkBobY: math.sin(_walkPhase * math.pi * 2) * 1.5 + idleBob,
      headBobY: math.sin(_walkPhase * math.pi * 2 + 1) * 1.0 + idleHead,
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
// Animated face painter — used by marble buttons + falling marbles
// + the chibi's eyes
// =====================================================================

/// Mood of a face — drives the mouth shape.
enum FaceMood { sad, neutral, smiley }

/// Pure paint helper. v60.11 — chunky expressive faces inspired by
/// the "watercolor chibi marble" reference the user shared. Each
/// mood gets:
///   - per-mood eyebrows (smiley = arched up, neutral = flat,
///     sad = inner-up worried),
///   - large round eyes with a glossy highlight dot,
///   - a distinct mouth shape (smiley = wide curved grin with
///     tongue, neutral = small flat line, sad = open frown),
///   - mood-specific extras (smiley = blush dots; sad = tear).
///
/// All measurements are radius-relative so the same painter scales
/// from the 28px world marble up to whatever radius a future
/// "giant marble" or close-up needs.
class _FacePainter {
  const _FacePainter({
    required this.mood,
    this.blinkPhase = 0,
    this.pupilLeft = 0,
    this.pupilRight = 0,
  });

  final FaceMood mood;

  /// 0 = eyes fully open, 1 = fully closed.
  final double blinkPhase;

  /// Per-eye horizontal pupil drift in [-1, 1].
  final double pupilLeft;
  final double pupilRight;

  static final _eyeWhite = Paint()..color = const Color(0xFFFFFFFF);
  static final _eyeOutline = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _pupil = Paint()..color = const Color(0xFF1A1A1A);
  static final _mouthStroke = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _browStroke = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  static final _mouthFillSmiley = Paint()..color = const Color(0xFF7A2C3D);
  static final _mouthFillSad = Paint()..color = const Color(0xFF6D2C3E);
  static final _tongue = Paint()..color = const Color(0xFFE57A8D);
  static final _blush = Paint()..color = const Color(0x66E8758B);
  static final _tearFill = Paint()..color = const Color(0xFF6FC4F0);
  static final _tearOutline = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  void paintAt(Canvas canvas, Offset center, double radius) {
    canvas
      ..save()
      ..translate(center.dx, center.dy);

    final eyeY = -radius * 0.10;
    final eyeR = radius * 0.26;
    final eyeSpacing = radius * 0.36;
    final open = (1 - blinkPhase).clamp(0.05, 1.0);

    // ===== Eyebrows =====
    // Drawn first (above + behind the eyes). We draw a short stroke
    // and rotate it by `tilt` (CW positive — Flutter's +y is down,
    // so positive tilt makes the right end of the line go DOWN).
    //
    // For a brow, "inner end up" reads as worried. Left brow's
    // inner end is on its right side, so positive tilt makes inner
    // go DOWN (= angry/determined) and negative tilt makes inner
    // go UP (= worried). Right brow is mirrored.
    final browY = eyeY - eyeR * 0.95;
    final browLen = eyeR * 1.6;
    void drawBrow(double x, double tilt) {
      canvas
        ..save()
        ..translate(x, browY)
        ..rotate(tilt)
        ..drawLine(
          Offset(-browLen / 2, 0),
          Offset(browLen / 2, 0),
          _browStroke,
        )
        ..restore();
    }

    switch (mood) {
      case FaceMood.smiley:
        // Outer-down, inner-up = relaxed/cheerful arch.
        drawBrow(-eyeSpacing, -0.20);
        drawBrow(eyeSpacing, 0.20);
      case FaceMood.neutral:
        drawBrow(-eyeSpacing, 0.04);
        drawBrow(eyeSpacing, -0.04);
      case FaceMood.sad:
        // Inner-up worried angle.
        drawBrow(-eyeSpacing, -0.42);
        drawBrow(eyeSpacing, 0.42);
    }

    // ===== Eyes =====
    void drawEye(double x, double drift) {
      // Round body — slightly taller than wide for a chibi feel,
      // squashed by the blink curve.
      final rect = Rect.fromCenter(
        center: Offset(x, eyeY),
        width: eyeR * 1.6,
        height: eyeR * 2.1 * open,
      );
      canvas
        ..drawOval(rect, _eyeWhite)
        ..drawOval(rect, _eyeOutline);
      if (open > 0.25) {
        // Fat pupil — fills most of the eye, leaves room for the
        // glossy highlight on the upper-left.
        final pupilCenter = Offset(
          x + drift * eyeR * 0.45,
          eyeY + eyeR * 0.10,
        );
        // Highlight dot — gives the marble that "shiny watercolor"
        // read from the reference. Positioned upper-left of the
        // pupil, regardless of drift direction (a fixed light
        // source rather than a tracked-eye highlight).
        canvas
          ..drawCircle(pupilCenter, eyeR * 0.62 * open, _pupil)
          ..drawCircle(
            Offset(x - eyeR * 0.18, eyeY - eyeR * 0.20),
            eyeR * 0.22 * open,
            _eyeWhite,
          );
        // Sad mood gets a second smaller "wet" highlight bottom-
        // right of the pupil — sells the "watery eyes" read.
        if (mood == FaceMood.sad) {
          canvas.drawCircle(
            Offset(x + eyeR * 0.30, eyeY + eyeR * 0.32),
            eyeR * 0.12 * open,
            _eyeWhite,
          );
        }
      }
    }

    drawEye(-eyeSpacing, pupilLeft);
    drawEye(eyeSpacing, pupilRight);

    // ===== Mouth =====
    final mouthY = radius * 0.40;
    final mouthW = radius * 0.45;
    switch (mood) {
      case FaceMood.smiley:
        // Wide curved smile with the inside filled (pink) and a
        // tongue blob bottom-center. Reads as "open mouth grin"
        // from a glance. We clip to the bottom half of the mouth
        // ellipse so the upper edge stays a clean lip line.
        final mouthRect = Rect.fromCenter(
          center: Offset(0, mouthY),
          width: mouthW * 1.7,
          height: mouthW * 1.0,
        );
        canvas
          ..save()
          ..clipRect(Rect.fromLTRB(
            -mouthW, mouthY - 1, mouthW * 1.2, mouthY + mouthW,
          ))
          ..drawOval(mouthRect, _mouthFillSmiley)
          ..drawCircle(
            Offset(mouthW * 0.05, mouthY + mouthW * 0.30),
            mouthW * 0.32,
            _tongue,
          )
          ..restore()
          // Outline — bottom half of the ellipse + flat top lip.
          ..drawArc(mouthRect, 0, math.pi, false, _mouthStroke)
          ..drawLine(
            Offset(-mouthW * 0.85, mouthY),
            Offset(mouthW * 0.85, mouthY),
            _mouthStroke,
          )
          // Blush dots, tucked under each eye on the cheek.
          ..drawOval(
            Rect.fromCenter(
              center: Offset(-radius * 0.55, radius * 0.18),
              width: radius * 0.34,
              height: radius * 0.22,
            ),
            _blush,
          )
          ..drawOval(
            Rect.fromCenter(
              center: Offset(radius * 0.55, radius * 0.18),
              width: radius * 0.34,
              height: radius * 0.22,
            ),
            _blush,
          );
      case FaceMood.neutral:
        // Small flat-ish line, very slight wave so it doesn't read
        // as a hard frown.
        final p = Path()
          ..moveTo(-mouthW * 0.7, mouthY)
          ..quadraticBezierTo(
            -mouthW * 0.35,
            mouthY - 2,
            0,
            mouthY,
          )
          ..quadraticBezierTo(
            mouthW * 0.35,
            mouthY + 2,
            mouthW * 0.7,
            mouthY,
          );
        canvas.drawPath(p, _mouthStroke);
      case FaceMood.sad:
        // Open downturned mouth — small filled oval with a frown
        // line above it for the lip.
        final mouthRect = Rect.fromCenter(
          center: Offset(0, mouthY + radius * 0.05),
          width: mouthW * 1.05,
          height: mouthW * 0.7,
        );
        canvas
          ..drawOval(mouthRect, _mouthFillSad)
          ..drawOval(mouthRect, _mouthStroke);
        // Tear — sits just below the right eye.
        final tearTop = Offset(eyeSpacing + eyeR * 0.6, eyeY + eyeR * 0.95);
        final tearBottom = Offset(
          eyeSpacing + eyeR * 0.6,
          eyeY + eyeR * 1.95,
        );
        final tearPath = Path()
          ..moveTo(tearTop.dx, tearTop.dy)
          ..quadraticBezierTo(
            tearTop.dx + eyeR * 0.45,
            (tearTop.dy + tearBottom.dy) / 2,
            tearBottom.dx,
            tearBottom.dy,
          )
          ..quadraticBezierTo(
            tearTop.dx - eyeR * 0.45,
            (tearTop.dy + tearBottom.dy) / 2,
            tearTop.dx,
            tearTop.dy,
          )
          ..close();
        canvas
          ..drawPath(tearPath, _tearFill)
          ..drawPath(tearPath, _tearOutline)
          // Highlight on the tear so it reads as wet, not just a
          // blue blob.
          ..drawCircle(
            Offset(tearTop.dx - eyeR * 0.10, tearTop.dy + eyeR * 0.4),
            eyeR * 0.10,
            _eyeWhite,
          );
    }
    canvas.restore();
  }
}

/// Random-walk eye animator. Each instance picks a fresh
/// horizontal target every 1.5–4.5s and lerps toward it. Two
/// instances per face (left + right) so eyes drift independently;
/// the pair occasionally converges by chance, which reads as
/// "looking at each other." Stateful — instantiate once per face,
/// call `update(dt)` per frame, read `value`.
class _EyeDrift {
  _EyeDrift({int? seed})
      : _rng = math.Random(seed ?? math.Random().nextInt(1 << 31));

  final math.Random _rng;
  double _current = 0;
  double _target = 0;
  double _untilNext = 0;

  double get value => _current;

  void update(double dt) {
    _untilNext -= dt;
    if (_untilNext <= 0) {
      _target = (_rng.nextDouble() - 0.5) * 1.6; // -0.8..0.8
      _untilNext = 1.5 + _rng.nextDouble() * 3.0;
    }
    _current += (_target - _current) * math.min(1, dt * 4);
  }
}

/// Compute a blink phase (0 = open → 1 = closed → 0 = open) given
/// a continuous time source. Encapsulates the "blink every N
/// seconds for ~150ms" cycle so multiple consumers (chibi eye,
/// marble buttons, falling marbles) all share one rhythm shape.
///
/// `seed` lets sibling marbles blink slightly out-of-phase so a
/// row of three faces doesn't blink in lockstep. Pass any int.
double blinkPhaseAt(double t, {int seed = 0}) {
  // Period: 3.5–5.5s depending on seed. Each blink lasts 0.16s.
  final period = 3.5 + ((seed * 1733) % 1000) / 500.0; // 3.5..5.5
  final localT = (t + seed * 0.7) % period;
  if (localT > 0.16) return 0;
  // Triangle wave 0→1→0 over the 0.16s blink window.
  final p = localT / 0.16;
  return p < 0.5 ? p * 2 : (1 - p) * 2;
}

// =====================================================================
// Survey jar — clear container in the world that catches dropped
// face marbles
// =====================================================================

/// "Major jar" — a substantial clear container in the world. Per
/// the user's revised spec: bigger than the first pass, with a
/// proper 3D illusion. Drawn as a wide squat cylinder using two
/// ellipses (rim + base) and connecting walls, plus a vertical
/// highlight stripe for the glass feel.
///
/// Marble pile: stacks from the bottom up, left-to-right, in a
/// grid whose cell size is the marble diameter + a small gap.
/// New marbles claim a slot via `reserveSlot()` (which counts
/// every marble whether in flight or at rest, so concurrent drops
/// don't race for the same slot) and target that slot's settle
/// position.
class _Jar extends PositionComponent {
  _Jar({required Vector2 size}) : super(size: size, anchor: Anchor.topLeft);

  /// Marble radius — should match `_MarbleNode._radius` (the world
  /// marble's base render radius). Used to compute the slot grid
  /// inside the jar so dropped marbles sit cleanly in rows.
  /// Slightly under the render radius so they pack a hair tighter
  /// than visual size — a watercolor-style "jar full of marbles"
  /// reads better with a touch of overlap than spaced grid cells.
  static const double _marbleR = 22;

  /// How squashed the rim/base ellipses are vs a perfect circle.
  /// 0.25 = quite flat, gives the FFT-style 3/4 view tilt.
  static const double _rimFlatten = 0.25;

  static final _glassFill = Paint()..color = const Color(0x33C2DEEA);
  static final _backWallTint = Paint()..color = const Color(0x44A6C5D2);
  static final _glassOutline = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _glassHighlight = Paint()
    ..color = const Color(0x55FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _rimDark = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  /// Reserved slot count — each `reserveSlot` increments.
  int _reserved = 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = size.x;
    final h = size.y;
    final rimRy = w * _rimFlatten / 2;

    // 1) Back wall arc — bottom half of the rim ellipse, drawn
    // BEFORE the front so the front wall overlaps it. Gives a
    // depth read.
    final rimRect = Rect.fromCenter(
      center: Offset(w / 2, rimRy),
      width: w,
      height: rimRy * 2,
    );
    canvas.drawArc(rimRect, 0, math.pi, false, _rimDark);

    // 2) Body fill — rounded rectangle from rim center down to
    // base center.
    final bodyRect = RRect.fromLTRBAndCorners(
      0,
      rimRy,
      w,
      h - rimRy,
      bottomLeft: Radius.circular(rimRy),
      bottomRight: Radius.circular(rimRy),
    );
    canvas
      ..drawRRect(bodyRect, _glassFill)
      // Tint on the back-wall portion (top quarter inside the body)
      // for a hint of "depth through the glass".
      ..drawRect(
        Rect.fromLTRB(0, rimRy, w, rimRy + rimRy * 1.2),
        _backWallTint,
      );

    // 3) Side walls — two vertical lines from the rim corners to
    // the bottom of the body, where they round into the base curve.
    // 4) Base — bottom ellipse (split into two arcs).
    // 5) Rim — top ellipse, last so it sits over the body edges.
    // 6) Specular stripe — vertical highlight on the left wall.
    final baseRect = Rect.fromCenter(
      center: Offset(w / 2, h - rimRy),
      width: w,
      height: rimRy * 2,
    );
    canvas
      ..drawLine(Offset(0, rimRy), Offset(0, h - rimRy), _glassOutline)
      ..drawLine(Offset(w, rimRy), Offset(w, h - rimRy), _glassOutline)
      ..drawArc(baseRect, 0, math.pi, false, _glassOutline)
      ..drawArc(baseRect, math.pi, math.pi, false, _glassOutline)
      ..drawOval(rimRect, _glassOutline)
      ..drawLine(
        Offset(w * 0.15, rimRy + 6),
        Offset(w * 0.15, h - rimRy - 6),
        _glassHighlight,
      );
  }

  /// Claim the next slot in the marble grid + return the world-
  /// space position the marble should settle at.
  Vector2 reserveSlot() {
    final w = size.x;
    final h = size.y;
    final rimRy = w * _rimFlatten / 2;
    // Marble fillable region: from a hair below the rim down to
    // the inside of the base curve.
    final fillTop = rimRy + 6;
    final fillBottom = h - rimRy - 4;
    final perRow = math.max(
      1,
      (w / (_marbleR * 2 + 2)).floor(),
    );
    final slot = _reserved;
    _reserved += 1;
    final row = slot ~/ perRow;
    final col = slot % perRow;
    final cellW = w / perRow;
    final x = position.x + (col + 0.5) * cellW;
    final maxRows = math.max(
      1,
      ((fillBottom - fillTop) / (_marbleR * 2 + 2)).floor(),
    );
    final clampedRow = row.clamp(0, maxRows - 1);
    final y = position.y +
        fillBottom -
        _marbleR -
        clampedRow * (_marbleR * 2 + 2);
    return Vector2(x, y);
  }

  /// World-space top of the jar — used as the spawn Y for falling
  /// marbles so they appear to drop in from above.
  double get topY => position.y - 12;
}

// =====================================================================
// World marble nodes — pickable face emojis the chibi interacts with
// =====================================================================

/// Lifecycle of a face marble in the world.
///
/// idle    → sitting in its slot, gently bobbing, pickable on
///           proximity.
/// held    → currently carried by the chibi above its head.
/// flying  → projectile arc toward the jar; gravity-driven.
/// settled → landed in the jar, immovable from here on.
enum _MarbleState { idle, held, flying, settled }

/// One face emoji in the world. Replaces the earlier separate
/// `_FallingMarble` — same component handles the pickable rest
/// state, the held state, the throw arc, and the resting-in-jar
/// state. State transitions are explicit (`pickUp`, `releaseToRest`,
/// `throwTo`); the rest of the game just mutates `state` indirectly
/// through those.
class _MarbleNode extends PositionComponent {
  _MarbleNode({
    required this.slotIdx,
    required this.mood,
    required this.tint,
    required this.seed,
    required Vector2 spawnPos,
    required Vector2 restPos,
  })  : _restPos = restPos.clone(),
        super(anchor: Anchor.center) {
    position.setFrom(spawnPos);
  }

  /// Base render radius before depth-scaling. v60.11 — sized up to
  /// 28 so the chunkier expressive faces (eyebrows, blush, tear,
  /// open mouths) all read clearly even when the marble shrinks at
  /// the top of the screen.
  static const double _radius = 28;
  static const double _gravity = 1100;

  /// Which of the three face slots this marble belongs to (0..2).
  /// On settle, the game spawns a fresh marble for this slot at the
  /// same rest position.
  final int slotIdx;
  final FaceMood mood;
  final int seed;
  final Vector2 _restPos;

  /// Tint is mutable so the game can shuffle palette colors on the
  /// idle marbles when something lands in the jar.
  Color tint;

  late final _EyeDrift _eyeL = _EyeDrift(seed: seed * 31 + 1);
  late final _EyeDrift _eyeR = _EyeDrift(seed: seed * 31 + 2);

  _MarbleState state = _MarbleState.idle;

  /// True when the chibi is close enough to pick this up (or switch
  /// to it). Drives the soft halo + size pulse.
  bool highlighted = false;

  double _t = 0;
  double _vx = 0;
  double _vy = 0;
  double _settleY = 0;

  void pickUp() {
    state = _MarbleState.held;
    _vx = 0;
    _vy = 0;
    highlighted = false;
  }

  /// Drop back onto the world slot — used when the chibi switches
  /// from this marble to another. Snaps for now; could animate.
  void releaseToRest() {
    state = _MarbleState.idle;
    position.setFrom(_restPos);
    _vx = 0;
    _vy = 0;
  }

  /// Convert to a flying projectile that lands at (targetX,
  /// targetY). Solves for vy0 so the marble crests and falls into
  /// the jar mouth in a fixed flight time, regardless of distance.
  void throwTo(double targetX, double targetY) {
    state = _MarbleState.flying;
    _settleY = targetY;
    final dx = targetX - position.x;
    final dy = targetY - position.y;
    const flightTime = 0.7;
    _vx = dx / flightTime;
    _vy = (dy - 0.5 * _gravity * flightTime * flightTime) / flightTime;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _eyeL.update(dt);
    _eyeR.update(dt);

    final game = findGame();
    switch (state) {
      case _MarbleState.idle:
        // Subtle in-place bob keeps the marble alive; X stays glued
        // to the rest slot so a held-then-released marble snaps
        // back cleanly.
        position
          ..x = _restPos.x
          ..y = _restPos.y + math.sin(_t * 2 + seed) * 1.5;
      case _MarbleState.held:
        // Glide above the chibi's head. Use the chibi's depth-scale
        // so a tiny far-away chibi carries a tiny marble just above
        // its head, not a comically oversized one. Lifted higher
        // (90 vs old 70) to clear the bigger marble + ear hitbox.
        if (game is _SurveyGame) {
          final c = game.chibi;
          final cs = c.scale.x;
          position
            ..x = c.position.x
            ..y = c.position.y - 90 * cs + math.sin(_t * 4 + seed) * 1.5;
        }
      case _MarbleState.flying:
        _vy += _gravity * dt;
        position
          ..x += _vx * dt
          ..y += _vy * dt;
        if (position.y >= _settleY) {
          position.y = _settleY;
          state = _MarbleState.settled;
          if (game is _SurveyGame) game.onMarbleSettled(this);
        }
      case _MarbleState.settled:
        // Resting in the jar; nothing to do.
        break;
    }

    // Y-based render priority so marbles closer to the camera
    // (lower screen Y) draw over marbles farther away — and over
    // the chibi when the chibi is behind them. Cheap fake-depth
    // sort that doesn't need per-frame z-buffering.
    priority = position.y.round();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final pulse = (highlighted && state == _MarbleState.idle)
        ? 1 + math.sin(_t * 6) * 0.07
        : 1.0;
    final game = findGame();
    final h = game?.size.y ?? 600;
    final depth = depthScaleForY(position.y, h);
    final s = depth * pulse;
    final r = _radius * s;

    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final fill = Paint()..color = tint;
    final outline = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas
      ..drawCircle(Offset(0, r * 0.4), r * 0.85, shadow)
      ..drawCircle(Offset.zero, r, fill)
      ..drawCircle(Offset.zero, r, outline);

    final blink = blinkPhaseAt(_t, seed: seed);
    _FacePainter(
      mood: mood,
      blinkPhase: blink,
      pupilLeft: _eyeL.value,
      pupilRight: _eyeR.value,
    ).paintAt(canvas, Offset.zero, r);

    // Soft halo when pickable + highlighted — reads as "you can
    // grab me." Disabled in held / flying / settled states.
    if (highlighted && state == _MarbleState.idle) {
      final halo = Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset.zero, r + 5, halo);
    }
  }
}

// =====================================================================
// FAB action — what the floating action button does right now
// =====================================================================

/// What the FAB does on the next tap. Swaps based on chibi proximity
/// to marbles and to the jar; pushed into a `ValueNotifier` so the
/// Flutter UI can rebuild without polling.
enum _FabAction { jump, pickup, drop, switchMarble }

extension _FabActionUi on _FabAction {
  String get label {
    switch (this) {
      case _FabAction.jump:
        return 'Jump';
      case _FabAction.pickup:
        return 'Pick up';
      case _FabAction.drop:
        return 'Drop in jar';
      case _FabAction.switchMarble:
        return 'Switch';
    }
  }

  IconData get icon {
    switch (this) {
      case _FabAction.jump:
        return Icons.arrow_upward;
      case _FabAction.pickup:
        return Icons.back_hand_outlined;
      case _FabAction.drop:
        return Icons.south;
      case _FabAction.switchMarble:
        return Icons.swap_horiz;
    }
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
  late final _Jar jar;

  /// The three pickable marbles in the world (one per mood).
  /// Index = slot index = mood index in `_kFaceMoods`.
  late final List<_MarbleNode> _marbles;

  /// World-space "rest" position for each slot. Used to spawn
  /// fresh marbles after one is dropped into the jar.
  late final List<Vector2> _marbleRestPositions;

  /// Currently held marble, or null when nothing is being carried.
  _MarbleNode? heldMarble;

  /// Closest pickable (idle) marble within range, or null when the
  /// chibi isn't close to any. When holding a marble this points to
  /// a candidate to switch to.
  _MarbleNode? nearestMarble;

  /// True when the chibi is positioned where a held marble can be
  /// thrown into the jar.
  bool nearJar = false;

  /// Pickup proximity threshold in screen pixels. Tuned to feel
  /// "just standing next to" a marble — small enough that the chibi
  /// has to actually walk over to a slot, big enough that a
  /// distracted user with twitchy joystick still triggers cleanly.
  /// v60.11 — bumped to track the bigger 28px marbles.
  static const double _pickRange = 95;

  /// What the FAB does next. UI binds via ValueListenableBuilder.
  final ValueNotifier<_FabAction> fabAction = ValueNotifier(_FabAction.jump);

  /// Screen-space rect of the question plate. The plate is a
  /// Flutter overlay (Stack-positioned above the GameWidget) so
  /// it doesn't render through Flame, but we still want the chibi
  /// to *collide* with it — the user wants the plate to be
  /// immovable, "no one can move it." The chibi reads this rect
  /// in `update` and AABB-pushes itself out if it overlaps.
  ///
  /// Coordinates match the screen-space positioning the Flutter
  /// Stack uses (16px from each side, ~70dp tall plate). Updated
  /// by the screen on every layout via `setPlateBounds`.
  Rect? plateBounds;
  // Setter-style helper. The lint pushes us toward `set
  // plateBounds(...)` but this shape stays consistent with the
  // existing `setLoadout` helpers and is what the screen's
  // post-frame callback already calls.
  // ignore: use_setters_to_change_properties
  void setPlateBounds(Rect r) => plateBounds = r;

  /// Cycle of pastel marble fills the world marbles rotate through.
  /// Six entries so consecutive shuffles always pick a fresh-looking
  /// triple (we step by two from a moving anchor, so the three
  /// visible colors all change every shuffle).
  static const List<Color> _palette = <Color>[
    Color(0xFFB8D7F1), // soft blue
    Color(0xFFE6E6E6), // neutral gray
    Color(0xFFFFE89B), // warm yellow
    Color(0xFFEFB7C2), // pink
    Color(0xFFC8E6B7), // mint
    Color(0xFFD4B7E6), // lavender
  ];

  /// Returns the three colors currently shown by the world marbles,
  /// indexed by slot. Rotates through the palette on every settle.
  List<Color> _tintsForShuffle(int idx) {
    final base = idx % _palette.length;
    return <Color>[
      _palette[base],
      _palette[(base + 2) % _palette.length],
      _palette[(base + 4) % _palette.length],
    ];
  }

  int _shuffleIdx = 0;
  int _spawnCounter = 0;

  /// Recompute proximity state — what's the chibi nearest to, and
  /// what should the FAB do? Called from chibi.update(); cheap
  /// (3 distance checks + a couple of bbox checks).
  void updateProximity() {
    if (!isMounted) return;
    final chibiPos = chibi.position;

    // Nearest pickable (idle, non-held) marble within range.
    _MarbleNode? best;
    var bestDist = _pickRange;
    for (final m in _marbles) {
      if (m.state != _MarbleState.idle) continue;
      if (identical(m, heldMarble)) continue;
      final dx = m.position.x - chibiPos.x;
      final dy = m.position.y - chibiPos.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < bestDist) {
        bestDist = d;
        best = m;
      }
    }
    for (final m in _marbles) {
      m.highlighted = identical(m, best);
    }
    nearestMarble = best;

    // Near jar: chibi positioned over (or just above) the jar
    // mouth. The mouth is the rim ellipse at the top of the jar;
    // we approximate with a horizontal band starting ~80px above
    // the jar's top edge and extending to its top.
    final jarLeft = jar.position.x;
    final jarRight = jar.position.x + jar.size.x;
    final jarTopY = jar.position.y;
    final overJarHorizontally =
        chibiPos.x >= jarLeft - 30 && chibiPos.x <= jarRight + 30;
    final inDropBand =
        chibiPos.y >= jarTopY - 110 && chibiPos.y <= jarTopY + 30;
    nearJar = overJarHorizontally && inDropBand;

    // Decide FAB action.
    _FabAction next;
    if (heldMarble != null) {
      if (nearJar) {
        next = _FabAction.drop;
      } else if (best != null) {
        next = _FabAction.switchMarble;
      } else {
        next = _FabAction.jump;
      }
    } else {
      if (best != null) {
        next = _FabAction.pickup;
      } else {
        next = _FabAction.jump;
      }
    }
    if (fabAction.value != next) fabAction.value = next;
  }

  /// FAB tap dispatcher. Reads the current `fabAction` and acts.
  /// Re-runs proximity at the end so the icon updates immediately
  /// after the action resolves.
  void performFabAction() {
    switch (fabAction.value) {
      case _FabAction.jump:
        chibi.jump();
      case _FabAction.pickup:
        final n = nearestMarble;
        if (n != null) {
          heldMarble = n;
          n.pickUp();
          nearestMarble = null;
        }
      case _FabAction.switchMarble:
        final n = nearestMarble;
        final h = heldMarble;
        if (n != null && h != null) {
          h.releaseToRest();
          heldMarble = n;
          n.pickUp();
          nearestMarble = null;
        }
      case _FabAction.drop:
        final h = heldMarble;
        if (h != null) {
          // Reserve a slot inside the jar's marble grid; the marble
          // arcs there and the jar accepts it.
          final settle = jar.reserveSlot();
          h.throwTo(settle.x, settle.y);
          heldMarble = null;
        }
    }
    updateProximity();
  }

  /// Called by `_MarbleNode` the instant it lands inside the jar.
  /// 1. Rotate the palette anchor → recompute the visible triple.
  /// 2. Re-tint every still-idle marble (so the user sees the rest
  ///    of the world swap colors as a felt-time response).
  /// 3. Spawn a fresh marble in the now-empty slot so the world
  ///    keeps three pickable faces around.
  void onMarbleSettled(_MarbleNode m) {
    _shuffleIdx += 1;
    final newTints = _tintsForShuffle(_shuffleIdx);
    for (final other in _marbles) {
      if (other.state == _MarbleState.idle ||
          other.state == _MarbleState.held) {
        other.tint = newTints[other.slotIdx];
      }
    }
    // Spawn the replacement for this slot.
    final replacement = _MarbleNode(
      slotIdx: m.slotIdx,
      mood: m.mood,
      tint: newTints[m.slotIdx],
      seed: ++_spawnCounter * 7 + m.slotIdx,
      spawnPos: _marbleRestPositions[m.slotIdx],
      restPos: _marbleRestPositions[m.slotIdx],
    );
    _marbles[m.slotIdx] = replacement;
    // FlameGame.add returns a Future; fire-and-forget is correct
    // here — the new marble starts updating once its mount future
    // resolves on the next tick.
    // ignore: discarded_futures
    add(replacement);
  }

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

    // Major jar in the foreground — bigger than the first pass so
    // it reads as the closest prop in the scene, dominating the
    // lower half. ~45% width × 38% height; bottom edge near 95%
    // screen so it sits firmly on the ground line. Pairs with the
    // depth-scale curve: chibi shrinks toward the top, jar holds
    // its full size at the bottom = clear horizon read.
    final jarSize = Vector2(size.x * 0.45, size.y * 0.38);
    jar = _Jar(size: jarSize)
      ..position = Vector2(
        (size.x - jarSize.x) / 2,
        size.y * 0.95 - jarSize.y,
      );
    add(jar);

    // Chibi spawns mid-screen above the jar. Walks with depth
    // scaling — moves to top of screen → shrinks into the distance.
    chibi = ChibiCharacter(
      joystick: joystick,
      keyboardInput: keyboardInput,
    )
      ..position = Vector2(size.x * 0.7, size.y * 0.4)
      ..size = Vector2(120, 160);
    add(chibi);

    // Three world marbles, spread across the upper play area at
    // varying Y so they sit on different "depth bands" — left and
    // right slots a hair lower (closer) than the center slot. Far
    // enough apart that the chibi has to actually walk between
    // them rather than picking up two with one stop.
    final leftX = size.x * 0.18;
    final centerX = size.x * 0.5;
    final rightX = size.x * 0.82;
    final lowY = size.y * 0.30;
    final highY = size.y * 0.22;
    _marbleRestPositions = <Vector2>[
      Vector2(leftX, lowY), // sad
      Vector2(centerX, highY), // neutral (farther = higher Y)
      Vector2(rightX, lowY), // smiley
    ];
    final initialTints = _tintsForShuffle(0);
    _marbles = <_MarbleNode>[
      for (var i = 0; i < _kFaceMoods.length; i++)
        _MarbleNode(
          slotIdx: i,
          mood: _kFaceMoods[i],
          tint: initialTints[i],
          seed: 100 + i * 17,
          spawnPos: _marbleRestPositions[i],
          restPos: _marbleRestPositions[i],
        ),
    ];
    _marbles.forEach(add);
  }
}

// =====================================================================
// Question pool
// =====================================================================

/// A survey question. v60.9 — the answer marbles are always the
/// satisfaction scale (sad / neutral / smiley), so we don't carry
/// per-question emojis any more; we just rotate the question text.
/// Different question, same three marble faces.
class _SurveyQuestion {
  const _SurveyQuestion(this.question);
  final String question;
}

const _kSurveyQuestions = <_SurveyQuestion>[
  _SurveyQuestion('How are you feeling today?'),
  _SurveyQuestion('How was your morning?'),
  _SurveyQuestion('Energy level right now?'),
  _SurveyQuestion("How do you feel about today's plan?"),
  _SurveyQuestion('How was your last activity?'),
];

/// Fixed answer set — always sad / neutral / smiley, in that
/// reading order. The marble button row + the falling-marble
/// drop flow both consume this list directly.
const _kFaceMoods = <FaceMood>[
  FaceMood.sad,
  FaceMood.neutral,
  FaceMood.smiley,
];

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

  /// Random question chosen on screen mount. Stable for the
  /// session — flipping every frame would be jarring; users want
  /// to read once and answer.
  late final _SurveyQuestion _question =
      _kSurveyQuestions[math.Random().nextInt(_kSurveyQuestions.length)];

  /// Key on the question plate's outer Container. After every
  /// frame we read its bounds and push them down to the game so
  /// the chibi's collision check has a real screen-space rect to
  /// work with (Flutter does the layout; the game just consumes).
  final GlobalKey _plateKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Publish plate bounds once after first layout, then on every
    // build. The post-frame callback is the canonical "after
    // layout has settled" hook.
    WidgetsBinding.instance.addPostFrameCallback(_publishPlateBounds);
  }

  void _publishPlateBounds(Duration _) {
    if (!mounted) return;
    final ctx = _plateKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // The plate's overlay sits inside the Stack, which is laid out
    // edge-to-edge with the game canvas. localToGlobal gives screen-
    // space coords; the game's `size` is the same screen-space
    // (Flame's GameWidget fills its slot 1:1 with logical pixels),
    // so we can pass the rect through unmodified.
    final topLeft = box.localToGlobal(Offset.zero);
    final scaffoldRO = context.findRenderObject() as RenderBox?;
    final scaffoldOrigin =
        scaffoldRO?.localToGlobal(Offset.zero) ?? Offset.zero;
    final localTopLeft = topLeft - scaffoldOrigin;
    _game.setPlateBounds(localTopLeft & box.size);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Layout can shift on theme/size changes — re-publish.
    WidgetsBinding.instance.addPostFrameCallback(_publishPlateBounds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Re-measure every frame so rotation / window resize / safe-
    // area changes keep the plate's collision rect accurate. The
    // post-frame callback runs after this build commits.
    WidgetsBinding.instance.addPostFrameCallback(_publishPlateBounds);
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
          // Plate sits centered + narrow at the top so it reads as
          // "far in the distance" against the foreground jar. The
          // chibi shrinks as it walks toward the plate (depth
          // scale) — small plate up there reinforces the horizon
          // illusion. The marble tray is now in the world (Flame
          // _MarbleNode components) — no Flutter overlay tray.
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Container(
                    key: _plateKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _question.question,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Context-switching FAB — bottom-right, mirroring the
          // joystick. Icon + tooltip swap based on what the chibi
          // can do right now (jump / pick up / drop / switch).
          Positioned(
            right: 28,
            bottom: 28,
            child: ValueListenableBuilder<_FabAction>(
              valueListenable: _game.fabAction,
              builder: (context, action, _) => FloatingActionButton(
                onPressed: _game.performFabAction,
                tooltip: action.label,
                // Different background tint for held-marble actions
                // so the user gets a strong visual cue that "FAB is
                // doing something different now." Pickup/switch
                // tinted slightly warmer; drop tinted toward primary.
                backgroundColor: action == _FabAction.drop
                    ? theme.colorScheme.primary
                    : null,
                foregroundColor: action == _FabAction.drop
                    ? theme.colorScheme.onPrimary
                    : null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(action.icon, key: ValueKey(action)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// (The Flutter `_MarbleButton` + `_MarbleFacePainter` widgets used
// to live here. They're gone — the marbles are now world-space
// `_MarbleNode` components the chibi walks up to and picks up.)
