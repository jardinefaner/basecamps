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

import 'package:basecamp/features/surveys/canonical_questions.dart';
import 'package:basecamp/features/surveys/kiosk_exit_pin_modal.dart';
import 'package:basecamp/features/surveys/multi_select_overlay.dart';
import 'package:basecamp/features/surveys/open_ended_overlay.dart';
import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Screen-space velocity this frame (px/sec). Written each
  /// `update` from joystick + keyboard input so the game's
  /// chibi-marble collision pass can transfer momentum on contact.
  /// Zero when the chibi isn't being moved.
  Vector2 velocity = Vector2.zero();

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
    final stepVel = Vector2(dx, dy) * speed;
    velocity = stepVel;
    position += stepVel * dt;

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

/// 5-point Likert mood. Each value drives a unique face design
/// (palette + facial features + idle micro-animation).
///
/// Order matches the survey reading order from "most negative" to
/// "most positive" so the world marble layout (left → right) feels
/// natural.
enum FaceMood {
  stronglyDisagree, // F1 — red, shiver + tear + mouth contract
  disagree,         // F2 — coral, sway + brow droop
  notSure,          // F3 — amber, look L/R + blink
  agree,            // F4 — green, bob + cheek pulse + sparkle
  stronglyAgree,    // F5 — teal, bounce + chomp + 3 sparkles
}

/// Animation variant for a marble's continuous idle loop. Each
/// face has 4 distinct variants (per
/// `emoji_animation_variants_4x5_grid.html`); a marble picks one
/// at random when it spawns and plays it for its lifetime.
///
/// idle       — A: the base personality (shiver, sway, bob, etc.)
/// breathing  — B: slow organic scale pulse with subtler features
/// fidget     — C: nervous rapid energy
/// emote      — D: dramatic expression with extra particles
enum MarbleVariant { idle, breathing, fidget, emote }

/// Per-face color triple. Body = the flat circle fill; ring = a
/// slightly-darker shade of the body for the outline; ink = the
/// dark accent used for brows, eyes, mouth.
class _FacePalette {
  const _FacePalette({
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

/// Per-face palette table. Numbers come straight from the
/// emoji-character-animation spec (`emoji_character_animation_spec.html`).
const Map<FaceMood, _FacePalette> _kFacePalettes = <FaceMood, _FacePalette>{
  FaceMood.stronglyDisagree: _FacePalette(
    body: Color(0xFFFCEBEB),
    ring: Color(0xFFF09595),
    ink: Color(0xFFA32D2D),
    cheek: Color(0xFFF09595),
    tear: Color(0xFF85B7EB),
  ),
  FaceMood.disagree: _FacePalette(
    body: Color(0xFFFAECE7),
    ring: Color(0xFFF0997B),
    ink: Color(0xFF712B13),
    cheek: Color(0xFFF09595),
  ),
  FaceMood.notSure: _FacePalette(
    body: Color(0xFFFAEEDA),
    ring: Color(0xFFFAC775),
    ink: Color(0xFF854F0B),
    cheek: Color(0xFFFAC775),
  ),
  FaceMood.agree: _FacePalette(
    body: Color(0xFFEAF3DE),
    ring: Color(0xFF97C459),
    ink: Color(0xFF27500A),
    cheek: Color(0xFF97C459),
    sparkle: Color(0xFF97C459),
  ),
  FaceMood.stronglyAgree: _FacePalette(
    body: Color(0xFFE1F5EE),
    ring: Color(0xFF5DCAA5),
    ink: Color(0xFF085041),
    cheek: Color(0xFF5DCAA5),
    sparkle: Color(0xFF5DCAA5),
  ),
};

/// Painter for the 5-face Likert emoji set (per
/// `emoji_character_animation_spec.html`).
///
/// Each mood gets a unique flat-circle body in its palette colors
/// plus signature features (angry brows + tear for F1, happy-arc
/// closed eyes + open grin for F5, etc.). All measurements come
/// from the spec at body-radius 38; the painter scales them by
/// `radius / 38` so the same drawing code works for any marble
/// size (the world marbles use 28).
///
/// Animation is driven entirely by `t` (continuous time). Each
/// face paints its idle loop directly from t — no random pool, no
/// state machine. Tap reactions and other one-shots are applied
/// at the marble level (transform + scale), not inside the
/// painter.
class _FacePainter {
  const _FacePainter({
    required this.mood,
    this.variant = MarbleVariant.idle,
    this.t = 0,
  });

  final FaceMood mood;
  final MarbleVariant variant;
  final double t;

  void paintAt(Canvas canvas, Offset center, double radius) {
    final s = radius / 38;
    final palette = _kFacePalettes[mood]!;
    canvas
      ..save()
      ..translate(center.dx, center.dy);

    // Body: flat fill + paler ring outline.
    final bodyPaint = Paint()..color = palette.body;
    final ringPaint = Paint()
      ..color = palette.ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas
      ..drawCircle(Offset.zero, 38 * s, bodyPaint)
      ..drawCircle(Offset.zero, 38 * s, ringPaint);

    switch (mood) {
      case FaceMood.stronglyDisagree:
        _paintStronglyDisagree(canvas, s, palette);
      case FaceMood.disagree:
        _paintDisagree(canvas, s, palette);
      case FaceMood.notSure:
        _paintNotSure(canvas, s, palette);
      case FaceMood.agree:
        _paintAgree(canvas, s, palette);
      case FaceMood.stronglyAgree:
        _paintStronglyAgree(canvas, s, palette);
    }

    canvas.restore();
  }

  // ============================================================
  // F1: Strongly disagree — angry slanted brows, vertical-oval
  // pupils, soft pink cheeks. Variant-specific: idle does mouth
  // contract + 1 tear drip; breathing pulses tear opacity + brow
  // bobs; fidget squashes eyes rapidly; emote sobs with 2 tears.
  // ============================================================
  void _paintStronglyDisagree(Canvas canvas, double s, _FacePalette p) {
    final ink = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = p.ink;
    final hi = Paint()..color = p.body;

    // Per-variant tunings (defaults = idle).
    var mouthScaleX = 1.0;
    var mouthScaleY = 1.0;
    var eyeScaleY = 1.0;
    var browDy = 0.0;
    var browRot = 0.0;
    switch (variant) {
      case MarbleVariant.idle:
        final mc = ((t / 3) % 1) * math.pi * 2;
        mouthScaleX = 1 + math.sin(mc) * -0.075;
      case MarbleVariant.breathing:
        final c = (t / 4) % 1;
        browDy = math.sin(c * math.pi * 2) * 2;
        browRot = math.sin(c * math.pi * 2) * -3 * math.pi / 180;
      case MarbleVariant.fidget:
        final c = (t / 0.8) % 1;
        eyeScaleY = 1 - math.sin(c * math.pi * 2).abs() * 0.15;
      case MarbleVariant.emote:
        final c = (t / 1.5) % 1;
        final pulse = math.sin(c * math.pi * 2).abs();
        mouthScaleX = 1 + pulse * 0.15;
        mouthScaleY = 1 - pulse * 0.15;
    }

    // Brows: angry slant, with optional translate/rotate.
    // Eyes: vertical ovals + white highlight, optional Y squash.
    // Mouth — U-frown with optional sob scale.
    canvas
      ..save()
      ..translate(0, browDy)
      ..rotate(browRot)
      ..drawLine(Offset(-18 * s, -14 * s), Offset(-8 * s, -8 * s), ink)
      ..drawLine(Offset(18 * s, -14 * s), Offset(8 * s, -8 * s), ink)
      ..restore()
      ..save()
      ..scale(1, eyeScaleY)
      ..drawOval(
        Rect.fromCenter(
          center: Offset(-12 * s, 0),
          width: 8 * s,
          height: 10 * s,
        ),
        fill,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(12 * s, 0),
          width: 8 * s,
          height: 10 * s,
        ),
        fill,
      )
      ..drawCircle(Offset(-10 * s, -2 * s), 1.5 * s, hi)
      ..drawCircle(Offset(14 * s, -2 * s), 1.5 * s, hi)
      ..restore()
      ..save()
      ..translate(0, 16 * s)
      ..scale(mouthScaleX, mouthScaleY);
    final mouthPath = Path()
      ..moveTo(-14 * s, 0)
      ..quadraticBezierTo(0, -10 * s, 14 * s, 0);
    canvas
      ..drawPath(mouthPath, ink)
      ..restore();

    // Variant-specific tears.
    if (p.tear != null) {
      final tearColor = p.tear!;
      switch (variant) {
        case MarbleVariant.idle:
          // 2s drip: y 0→6, opacity 0.7→0.3 then reset.
          final c = (t / 2) % 1;
          double dy = 0;
          double opacity = 0;
          if (c < 0.60) {
            dy = (c / 0.60) * 6 * s;
            opacity = 0.7 - (c / 0.60) * 0.4;
          } else if (c < 0.80) {
            opacity = 0;
          } else {
            opacity = (c - 0.80) / 0.20 * 0.7;
          }
          if (opacity > 0.01) _drawF1Tear(canvas, s, 16, 4, dy, tearColor, opacity);
        case MarbleVariant.breathing:
          // 3s pulse: opacity 0.6 → 0.3 + scale 1 → 0.7 mid, then fade.
          final c = (t / 3) % 1;
          double opacity = 0;
          double scale = 1;
          double dy = 0;
          if (c < 0.50) {
            opacity = 0.6 - (c / 0.50) * 0.3;
            scale = 1 - (c / 0.50) * 0.3;
            dy = (c / 0.50) * 5 * s;
          } else if (c < 0.80) {
            opacity = 0;
          } else {
            opacity = (c - 0.80) / 0.20 * 0.6;
          }
          if (opacity > 0.01) {
            _drawF1Tear(canvas, s * scale, 16, 4, dy, tearColor, opacity);
          }
        case MarbleVariant.fidget:
          break; // no tear
        case MarbleVariant.emote:
          // Two tears falling on staggered 2s loops.
          for (var i = 0; i < 2; i++) {
            final c = ((t + i * 0.6) / 2) % 1;
            final dx = (i == 0 ? -4 : 3) * s * c;
            final dy = (i == 0 ? 18 : 16) * s * c;
            final opacity = (i == 0 ? 0.6 : 0.5) * (1 - c);
            final cx = i == 0 ? -15 * s : 15 * s;
            if (opacity > 0.01) {
              final tearPath = Path()
                ..moveTo(cx + dx, 6 * s + dy)
                ..quadraticBezierTo(
                  cx + dx + s,
                  10 * s + dy,
                  cx + dx,
                  14 * s + dy,
                )
                ..quadraticBezierTo(
                  cx + dx - s,
                  12 * s + dy,
                  cx + dx - s,
                  10 * s + dy,
                )
                ..close();
              canvas.drawPath(
                tearPath,
                Paint()..color = tearColor.withValues(alpha: opacity),
              );
            }
          }
      }
    }

    // Cheeks (slightly bigger on emote).
    final cheekRx = (variant == MarbleVariant.emote ? 14 : 12) * s;
    final cheekRy = (variant == MarbleVariant.emote ? 10 : 8) * s;
    final cheekAlpha = variant == MarbleVariant.emote ? 0.4 : 0.3;
    final cheek = Paint()..color = p.cheek.withValues(alpha: cheekAlpha);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: Offset(-22 * s, 8 * s),
          width: cheekRx,
          height: cheekRy,
        ),
        cheek,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(22 * s, 8 * s),
          width: cheekRx,
          height: cheekRy,
        ),
        cheek,
      );
  }

  /// Single F1 tear shape — used by both idle (1 tear) and
  /// breathing (1 pulsing tear) variants.
  void _drawF1Tear(Canvas canvas, double s, double cx, double cy,
      double dy, Color color, double opacity) {
    final path = Path()
      ..moveTo(cx * s, cy * s + dy)
      ..quadraticBezierTo(
        (cx + 2) * s,
        (cy + 6) * s + dy,
        cx * s,
        (cy + 10) * s + dy,
      )
      ..quadraticBezierTo(
        (cx - 2) * s,
        (cy + 12) * s + dy,
        (cx - 3) * s,
        (cy + 10) * s + dy,
      )
      ..quadraticBezierTo(
        (cx - 4) * s,
        (cy + 6) * s + dy,
        (cx - 3) * s,
        (cy + 2) * s + dy,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  // ============================================================
  // F2: Disagree — drooped brows, round pupils, gentle frown,
  // faint cheeks. Variants: idle bobs brows with sway; breathing
  // sneaks a midcycle blink; fidget wanders eyes Y + tiny lip
  // morph; emote sheds a sweat drop.
  // ============================================================
  void _paintDisagree(Canvas canvas, double s, _FacePalette p) {
    final ink = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = p.ink;
    final hi = Paint()..color = p.body;

    // Per-variant tunings.
    var browLY = 0.0;
    var browRY = 0.0;
    var eyeDy = 0.0;
    var eyeScaleY = 1.0;
    var lipDip = 8.0; // Y of mouth bottom curve apex; smaller = deeper.
    switch (variant) {
      case MarbleVariant.idle:
        final c = ((t / 3.5) % 1) * math.pi * 2;
        browLY = math.sin(c) * 1.5;
        browRY = math.sin(c) * 1.0;
      case MarbleVariant.breathing:
        // Eye blink at midcycle of 5s loop: closed scaleY 0.1 for
        // a brief moment around 50%.
        final c = (t / 5) % 1;
        if (c >= 0.48 && c <= 0.52) {
          final p = (c - 0.48) / 0.04;
          eyeScaleY = 1 - (p < 0.5 ? p * 2 : (1 - p) * 2) * 0.9;
        }
      case MarbleVariant.fidget:
        // Eyes wander Y (2.5s): 0 → +2 → -1 → +1 → 0
        final c = (t / 2.5) % 1;
        if (c < 0.25) {
          eyeDy = (c / 0.25) * 2;
        } else if (c < 0.50) {
          eyeDy = 2 - ((c - 0.25) / 0.25) * 3;
        } else if (c < 0.75) {
          eyeDy = -1 + ((c - 0.50) / 0.25) * 2;
        } else {
          eyeDy = 1 - ((c - 0.75) / 0.25);
        }
        // Lip dip subtly varies — picks slightly higher dip ~85-95%.
        final lc = (t / 3) % 1;
        if (lc >= 0.85 && lc <= 0.95) {
          lipDip = 9;
        }
      case MarbleVariant.emote:
        break; // body rocking; sweat handled below
    }

    // Brows.
    canvas
      ..drawLine(
        Offset(-18 * s, -12 * s + browLY),
        Offset(-8 * s, -10 * s + browLY),
        ink,
      )
      ..drawLine(
        Offset(18 * s, -12 * s + browRY),
        Offset(8 * s, -10 * s + browRY),
        ink,
      );

    // Eyes (with optional Y wander + blink scaleY).
    // ignore: cascade_invocations
    canvas
      ..save()
      ..translate(0, eyeDy * s);
    if (eyeScaleY < 0.99) {
      canvas
        ..save()
        ..scale(1, eyeScaleY)
        ..drawCircle(Offset(-12 * s, 0), 4 * s, fill)
        ..drawCircle(Offset(12 * s, 0), 4 * s, fill)
        ..restore()
        ..drawCircle(Offset(-10.5 * s, -1.5 * s), 1.5 * s, hi)
        ..drawCircle(Offset(13.5 * s, -1.5 * s), 1.5 * s, hi);
    } else {
      canvas
        ..drawCircle(Offset(-12 * s, 0), 4 * s, fill)
        ..drawCircle(Offset(12 * s, 0), 4 * s, fill)
        ..drawCircle(Offset(-10.5 * s, -1.5 * s), 1.5 * s, hi)
        ..drawCircle(Offset(13.5 * s, -1.5 * s), 1.5 * s, hi);
    }
    canvas.restore();

    // Mouth: gentle frown.
    final mouthPath = Path()
      ..moveTo(-10 * s, 14 * s)
      ..quadraticBezierTo(0, lipDip * s, 10 * s, 14 * s);
    canvas.drawPath(mouthPath, ink);

    // Cheeks.
    final cheek = Paint()..color = p.cheek.withValues(alpha: 0.2);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: Offset(-22 * s, 8 * s),
          width: 12 * s,
          height: 8 * s,
        ),
        cheek,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(22 * s, 8 * s),
          width: 12 * s,
          height: 8 * s,
        ),
        cheek,
      );

    // Emote: sweat drop falling from upper-right (3s loop).
    if (variant == MarbleVariant.emote) {
      final c = (t / 3) % 1;
      var opacity = 0.0;
      var dy = -2.0;
      var dx = 0.0;
      if (c < 0.80) {
        opacity = 0.5 * (1 - c / 0.80 * 0.6); // 0.5 → 0.2
        dy = -2 + c / 0.80 * 12;
        dx = c / 0.80 * 2;
      } else {
        opacity = 0;
      }
      if (opacity > 0.01) {
        final sweat = Path()
          ..moveTo(20 * s + dx * s, -14 * s + dy * s)
          ..quadraticBezierTo(
            22 * s + dx * s,
            -10 * s + dy * s,
            20 * s + dx * s,
            -6 * s + dy * s,
          )
          ..quadraticBezierTo(
            18 * s + dx * s,
            -4 * s + dy * s,
            17 * s + dx * s,
            -6 * s + dy * s,
          )
          ..quadraticBezierTo(
            16 * s + dx * s,
            -10 * s + dy * s,
            17 * s + dx * s,
            -12 * s + dy * s,
          )
          ..close();
        canvas.drawPath(
          sweat,
          Paint()
            ..color = const Color(0xFF85B7EB).withValues(alpha: opacity),
        );
      }
    }
  }

  // ============================================================
  // F3: Not sure — flat horizontal brows, round pupils, flat
  // mouth. Variants: idle = look L/R + center-reset blink (4s);
  // breathing = mouth purse (lip scaleX shrinks at 35% of 6s);
  // fidget = rapid eye dart; emote = brow lift + puff cloud.
  // ============================================================
  void _paintNotSure(Canvas canvas, double s, _FacePalette p) {
    final ink = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = p.ink;
    final hi = Paint()..color = p.body;

    var lookX = 0.0;
    var blinkOpen = 1.0;
    var browDy = 0.0;
    var mouthScaleX = 1.0;
    switch (variant) {
      case MarbleVariant.idle:
        final c = (t / 4) % 1;
        if (c >= 0.25 && c <= 0.40) {
          lookX = -3 * s;
        } else if (c >= 0.45 && c <= 0.60) {
          lookX = 3 * s;
        }
        if (c >= 0.42 && c < 0.48) {
          final lt = (c - 0.42) / 0.06;
          blinkOpen = 1 - (lt < 0.5 ? lt * 2 : (1 - lt) * 2);
        }
      case MarbleVariant.breathing:
        // Mouth purse: scaleX shrinks to 0.6 around 35% of 6s.
        final c = (t / 6) % 1;
        if (c >= 0.30 && c <= 0.40) {
          final lt = (c - 0.30) / 0.10;
          final dip = lt < 0.5 ? lt * 2 : (1 - lt) * 2;
          mouthScaleX = 1 - dip * 0.4;
        }
      case MarbleVariant.fidget:
        // Eyes dart rapidly — alternating L/R every 0.75s.
        final c = (t / 1.5) % 1;
        lookX = (c < 0.5 ? -4 : 4) * s;
      case MarbleVariant.emote:
        // Brow lift around 50-60% of 3s loop.
        final c = (t / 3) % 1;
        if (c >= 0.45 && c <= 0.60) {
          final lt = (c - 0.45) / 0.15;
          browDy = -3 * (lt < 0.5 ? lt * 2 : (1 - lt) * 2);
        }
    }

    // Flat horizontal brows.
    canvas
      ..drawLine(
        Offset(-18 * s, -12 * s + browDy),
        Offset(-6 * s, -12 * s + browDy),
        ink,
      )
      ..drawLine(
        Offset(18 * s, -12 * s + browDy),
        Offset(6 * s, -12 * s + browDy),
        ink,
      );

    final eyeR = 4 * s;
    Rect eyeRect(double cx) => Rect.fromCenter(
          center: Offset(cx + lookX, 0),
          width: eyeR * 2,
          height: eyeR * 2 * blinkOpen,
        );
    canvas
      ..drawOval(eyeRect(-12 * s), fill)
      ..drawOval(eyeRect(12 * s), fill);
    if (blinkOpen > 0.4) {
      canvas
        ..drawCircle(
          Offset(-10.5 * s + lookX, -1.5 * s),
          1.5 * s * blinkOpen,
          hi,
        )
        ..drawCircle(
          Offset(13.5 * s + lookX, -1.5 * s),
          1.5 * s * blinkOpen,
          hi,
        );
    }

    // Flat mouth (with optional purse).
    canvas
      ..save()
      ..translate(0, 14 * s)
      ..scale(mouthScaleX, 1)
      ..drawLine(Offset(-8 * s, 0), Offset(8 * s, 0), ink)
      ..restore();

    // Emote-only: puff cloud appears 60-80% of 4s loop.
    if (variant == MarbleVariant.emote) {
      final c = (t / 4) % 1;
      if (c >= 0.60 && c <= 0.80) {
        final lt = (c - 0.60) / 0.20;
        final opacity = (lt < 0.25 ? lt * 4 : (1 - lt) * 1.33).clamp(0.0, 0.45);
        final scale = 0.5 + lt * 1.0;
        final puffDy = -lt * 4 * s;
        canvas.drawCircle(
          Offset(24 * s, 12 * s + puffDy),
          4 * s * scale,
          Paint()..color = p.ring.withValues(alpha: opacity),
        );
      }
    }
  }

  // ============================================================
  // F4: Agree — outward-up brows, round pupils, smile, cheek
  // pulse, sparkle. Variants: idle = pulsing cheeks + sparkle;
  // breathing = bigger cheek pulse synced to body; fidget =
  // sparkle spinning; emote = floating heart.
  // ============================================================
  void _paintAgree(Canvas canvas, double s, _FacePalette p) {
    final ink = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = p.ink;
    final hi = Paint()..color = p.body;

    // Brows + eyes.
    canvas
      ..drawLine(Offset(-18 * s, -14 * s), Offset(-8 * s, -16 * s), ink)
      ..drawLine(Offset(18 * s, -14 * s), Offset(8 * s, -16 * s), ink)
      ..drawCircle(Offset(-12 * s, 0), 4 * s, fill)
      ..drawCircle(Offset(12 * s, 0), 4 * s, fill)
      ..drawCircle(Offset(-10.5 * s, -1.5 * s), 1.5 * s, hi)
      ..drawCircle(Offset(13.5 * s, -1.5 * s), 1.5 * s, hi);

    // Mouth: smile.
    final mouthPath = Path()
      ..moveTo(-10 * s, 12 * s)
      ..quadraticBezierTo(0, 20 * s, 10 * s, 12 * s);
    canvas.drawPath(mouthPath, ink);

    // Cheeks: per-variant alpha + size.
    var cheekAlpha = 0.25;
    var cheekRx = 14.0;
    switch (variant) {
      case MarbleVariant.idle:
        final c = (t / 2) % 1;
        cheekAlpha = 0.25 + math.sin(c * math.pi * 2) * 0.075;
      case MarbleVariant.breathing:
        // Sync to body breath (3s) — bigger pulse.
        final c = (t / 3) % 1;
        final pulse = math.sin(c * math.pi * 2);
        cheekAlpha = 0.275 + pulse * 0.125; // 0.15 → 0.40
        cheekRx = 14 + pulse * 1; // 13 → 15 px
      case MarbleVariant.fidget:
        cheekAlpha = 0.3;
      case MarbleVariant.emote:
        cheekAlpha = 0.3;
    }
    final cheek = Paint()..color = p.cheek.withValues(alpha: cheekAlpha);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: Offset(-22 * s, 8 * s),
          width: cheekRx * s,
          height: 8 * s,
        ),
        cheek,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(22 * s, 8 * s),
          width: cheekRx * s,
          height: 8 * s,
        ),
        cheek,
      );

    if (p.sparkle != null) {
      final sparkleColor = p.sparkle!;
      switch (variant) {
        case MarbleVariant.idle:
          // Single sparkle pulses 1.8s.
          final c = (t / 1.8) % 1;
          final alpha = math.sin(c * math.pi);
          if (alpha > 0.02) {
            final paint = Paint()
              ..color = sparkleColor.withValues(alpha: alpha * 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round;
            canvas
              ..save()
              ..translate(-30 * s, -22 * s)
              ..scale(alpha, alpha)
              ..drawLine(Offset(0, -4 * s), Offset(0, 4 * s), paint)
              ..drawLine(Offset(-4 * s, 0), Offset(4 * s, 0), paint)
              ..restore();
          }
        case MarbleVariant.breathing:
          break; // body+cheek breath does the work
        case MarbleVariant.fidget:
          // Sparkle scale + rotate alternate (0.6s).
          final c = (t / 0.6) % 1;
          final paint = Paint()
            ..color = sparkleColor.withValues(alpha: 0.7 * c)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;
          canvas
            ..save()
            ..translate(-28 * s, -20 * s)
            ..scale(c, c)
            ..rotate(c * 20 * math.pi / 180)
            ..drawLine(Offset(0, -4 * s), Offset(0, 4 * s), paint)
            ..drawLine(Offset(-4 * s, 0), Offset(4 * s, 0), paint)
            ..restore();
        case MarbleVariant.emote:
          // Floating heart: spawns near upper-left, drifts up-left
          // and fades on a 1.5s loop.
          final c = (t / 1.5) % 1;
          final scale = c < 0.30 ? c / 0.30 : 1.0;
          final dx = -c * 6 * s;
          final dy = -c * 14 * s;
          final alpha = (c < 0.30 ? c / 0.30 * 0.7 : 0.7 * (1 - c)).clamp(
            0.0,
            0.7,
          );
          if (alpha > 0.02) {
            final heart = Path()
              ..moveTo(-22 * s + dx, -22 * s + dy)
              ..cubicTo(
                -22 * s + dx,
                -28 * s + dy,
                -16 * s + dx,
                -30 * s + dy,
                -16 * s + dx,
                -24 * s + dy,
              )
              ..cubicTo(
                -16 * s + dx,
                -30 * s + dy,
                -10 * s + dx,
                -28 * s + dy,
                -10 * s + dx,
                -22 * s + dy,
              )
              ..cubicTo(
                -10 * s + dx,
                -18 * s + dy,
                -16 * s + dx,
                -14 * s + dy,
                -16 * s + dx,
                -12 * s + dy,
              )
              ..cubicTo(
                -16 * s + dx,
                -14 * s + dy,
                -22 * s + dx,
                -18 * s + dy,
                -22 * s + dx,
                -22 * s + dy,
              )
              ..close();
            canvas
              ..save()
              ..translate(-16 * s + dx, -22 * s + dy)
              ..scale(scale, scale)
              ..translate(16 * s - dx, 22 * s - dy)
              ..drawPath(
                heart,
                Paint()..color = sparkleColor.withValues(alpha: alpha),
              )
              ..restore();
          }
      }
    }
  }

  // ============================================================
  // F5: Strongly agree — happy-arched brows, ^_^ closed-curve
  // eyes, open grin with teeth + tongue + chomp, big cheeks, 3
  // staggered sparkles orbiting.
  // ============================================================
  void _paintStronglyAgree(Canvas canvas, double s, _FacePalette p) {
    final ink = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = p.ink;

    // Arched brows.
    final browL = Path()
      ..moveTo(-18 * s, -16 * s)
      ..quadraticBezierTo(-12 * s, -22 * s, -6 * s, -16 * s);
    final browR = Path()
      ..moveTo(6 * s, -16 * s)
      ..quadraticBezierTo(12 * s, -22 * s, 18 * s, -16 * s);
    canvas
      ..drawPath(browL, ink)
      ..drawPath(browR, ink);

    // ^_^ closed-curve eyes.
    final eyeL = Path()
      ..moveTo(-16 * s, -4 * s)
      ..quadraticBezierTo(-12 * s, -8 * s, -8 * s, -4 * s);
    final eyeR = Path()
      ..moveTo(8 * s, -4 * s)
      ..quadraticBezierTo(12 * s, -8 * s, 16 * s, -4 * s);
    canvas
      ..drawPath(eyeL, ink)
      ..drawPath(eyeR, ink);

    // Mouth chomp on 0.8s loop: scaleY 1 → 0.8 → 1.
    final chompT = (t / 0.8) % 1;
    final mouthScaleY = 1 - math.sin(chompT * math.pi * 2).abs() * 0.1;

    // Open grin with teeth + tongue.
    canvas
      ..save()
      ..scale(1, mouthScaleY);
    final grin = Path()
      ..moveTo(-14 * s, 8 * s)
      ..quadraticBezierTo(0, 22 * s, 14 * s, 8 * s)
      ..close();
    canvas.drawPath(grin, fill);
    // Teeth strip.
    final teethRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-9 * s, 8 * s, 18 * s, 5 * s),
      Radius.circular(2 * s),
    );
    canvas
      ..drawRRect(
        teethRect,
        Paint()..color = p.body.withValues(alpha: 0.7),
      )
      // Tongue blob.
      ..drawOval(
        Rect.fromCenter(
          center: Offset(0, 18 * s),
          width: 12 * s,
          height: 7 * s,
        ),
        Paint()..color = p.ring,
      )
      // Grin outline last so it sits above the teeth + tongue.
      ..drawPath(grin, ink)
      ..restore();

    // Big cheeks at 35%.
    final cheek = Paint()
      ..color = p.cheek.withValues(alpha: 0.35);
    canvas
      ..drawOval(
        Rect.fromCenter(center: Offset(-24 * s, 4 * s), width: 14 * s, height: 10 * s),
        cheek,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(24 * s, 4 * s), width: 14 * s, height: 10 * s),
        cheek,
      );

    // Variant-specific sparkle/glow behavior.
    if (p.sparkle != null) {
      final spark = p.sparkle!;
      switch (variant) {
        case MarbleVariant.idle:
          // 3 sparkles staggered on 1s loops at offsets 0/0.3/0.6.
          _drawSparkleCross(canvas, Offset(-32 * s, -26 * s), s, spark,
              t % 1, 2, 0.8);
          _drawSparkleCross(canvas, Offset(34 * s, -28 * s), s, spark,
              (t + 0.3) % 1, 1.5, 0.7);
          _drawSparkleDot(
              canvas, Offset(28 * s, 20 * s), s, spark, (t + 0.6) % 1, 0.6);
        case MarbleVariant.breathing:
          // Glow halo behind the body — pulses radius + opacity (2s).
          // Drawn here on top, but with low alpha + maskFilter so it
          // reads as a backlit aura rather than a foreground disk.
          final c = (t / 2) % 1;
          final pulse = math.sin(c * math.pi * 2);
          final radius = 40 + pulse * 4;
          final alpha = 0.13 + pulse * 0.05; // 0.08..0.18
          canvas.drawCircle(
            Offset.zero,
            radius * s,
            Paint()
              ..color = spark.withValues(alpha: alpha)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
          );
        case MarbleVariant.fidget:
          // 3 sparkles SPINNING — each rotates around its own
          // origin at a different rate.
          for (var i = 0; i < 3; i++) {
            final period = 0.4 + i * 0.1;
            final angle = (t / period) * math.pi * 2 * (i.isEven ? 1 : -1);
            final positions = [
              Offset(-32 * s, -26 * s),
              Offset(34 * s, -28 * s),
              Offset(28 * s, 22 * s),
            ];
            final alpha = 0.5 + 0.5 * math.sin((t / period) * math.pi * 2);
            canvas
              ..save()
              ..translate(positions[i].dx, positions[i].dy)
              ..rotate(angle)
              ..drawCircle(
                Offset.zero,
                (3 - i * 0.5) * s,
                Paint()..color = spark.withValues(alpha: alpha),
              )
              ..restore();
          }
        case MarbleVariant.emote:
          // 8 sun rays around the body, rotating slowly. Plus a
          // small sparkle particle ring around outer edge.
          final rayAngle = (t / 1.5) * math.pi * 2;
          final rayPaint = Paint()
            ..color = spark.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;
          canvas
            ..save()
            ..rotate(rayAngle);
          for (var i = 0; i < 8; i++) {
            final theta = i * math.pi / 4;
            final r1 = 42 * s;
            final r2 = 46 * s;
            canvas.drawLine(
              Offset(math.cos(theta) * r1, math.sin(theta) * r1),
              Offset(math.cos(theta) * r2, math.sin(theta) * r2),
              rayPaint,
            );
          }
          canvas.restore();
      }
    }
  }

  void _drawSparkleCross(
    Canvas canvas,
    Offset center,
    double s,
    Color color,
    double cycle,
    double strokeWidth,
    double maxOpacity,
  ) {
    final alpha = math.sin(cycle * math.pi);
    if (alpha < 0.02) return;
    final paint = Paint()
      ..color = color.withValues(alpha: alpha * maxOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(alpha, alpha)
      ..drawLine(Offset(0, -4 * s), Offset(0, 4 * s), paint)
      ..drawLine(Offset(-4 * s, 0), Offset(4 * s, 0), paint)
      ..restore();
  }

  void _drawSparkleDot(
    Canvas canvas,
    Offset center,
    double s,
    Color color,
    double cycle,
    double maxOpacity,
  ) {
    final alpha = math.sin(cycle * math.pi);
    if (alpha < 0.02) return;
    final paint = Paint()..color = color.withValues(alpha: alpha * maxOpacity);
    canvas.drawCircle(center, 2 * s * alpha, paint);
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

// =====================================================================
// Micro-animations — one-shot mood-flavored emotes layered onto
// the marble's idle baseline (blink + pupil drift).
// =====================================================================

/// Mod bag: one frame's worth of overrides the marble applies on
/// top of its baseline pose. Defaults are "no effect" so a marble
/// in `idle` micro-anim state renders identically to before the
/// system existed.
class _MicroAnimMods {
  /// Body translate.
  double tx = 0;
  double ty = 0;

  /// Body rotation (radians).
  double rot = 0;

  /// Body extra scale, multiplied into the existing base/squash.
  double sx = 1;
  double sy = 1;

}

/// Per-face continuous body-idle animator. Reads `_t` from the
/// marble each frame and emits a `_MicroAnimMods` describing the
/// body-level offsets (tx, ty, rot, sx, sy). Face-feature anims
/// (eye drift, blink, tear drip, sparkle, mouth contract / chomp)
/// live inside `_FacePainter` and read `t` directly.
///
/// Each face has a stable signature loop straight from the spec:
///   F1 stronglyDisagree — slow shiver (2.5s loop, ±2px, ±1°)
///   F2 disagree         — slow tilt sway (3s loop, ±3°)
///   F3 notSure          — body is still; only eyes move
///   F4 agree            — gentle vertical bob (2s loop, -3px)
///   F5 stronglyAgree    — bouncy wiggle (1.2s loop, -5px + ±4°)
class _MicroAnimController {
  _MicroAnimController({
    required this.mood,
    this.variant = MarbleVariant.idle,
  });

  final FaceMood mood;
  final MarbleVariant variant;

  void update(double dt) {
    // No state — output is a pure function of the marble's `_t`.
  }

  _MicroAnimMods compute(double t) {
    switch (variant) {
      case MarbleVariant.idle:
        return _idleBody(t);
      case MarbleVariant.breathing:
        return _breathingBody(t);
      case MarbleVariant.fidget:
        return _fidgetBody(t);
      case MarbleVariant.emote:
        return _emoteBody(t);
    }
  }

  // ============================================================
  // Variant A: idle — base personality (the spec's row 1)
  // ============================================================
  _MicroAnimMods _idleBody(double t) {
    final m = _MicroAnimMods();
    const deg = math.pi / 180;
    switch (mood) {
      case FaceMood.stronglyDisagree:
        final c = (t / 2.5) % 1;
        if (c < 0.15) {
          final p = c / 0.15;
          m
            ..tx = -3 * p
            ..rot = -2 * deg * p;
        } else if (c < 0.30) {
          final p = (c - 0.15) / 0.15;
          m
            ..tx = -3 + 6 * p
            ..rot = -2 * deg + 4 * deg * p;
        } else if (c < 0.50) {
          final p = (c - 0.30) / 0.20;
          m
            ..tx = 3 - 4 * p
            ..rot = 2 * deg * (1 - p);
        } else if (c < 0.70) {
          final p = (c - 0.50) / 0.20;
          m
            ..tx = -1 + p
            ..rot = 0;
        }
      case FaceMood.disagree:
        final c = (t / 3.5) % 1;
        m.rot = -math.sin(c * math.pi * 2).abs() * 4 * deg;
      case FaceMood.notSure:
        break;
      case FaceMood.agree:
        final c = (t / 2) % 1;
        m.ty = -math.sin(c * math.pi * 2).abs() * 4;
      case FaceMood.stronglyAgree:
        final c = (t / 1.2) % 1;
        if (c < 0.25) {
          final p = c / 0.25;
          m
            ..ty = -6 * p
            ..rot = -5 * deg * p;
        } else if (c < 0.75) {
          final p = (c - 0.25) / 0.5;
          m
            ..ty = -6
            ..rot = (-5 + 10 * p) * deg;
        } else {
          final p = (c - 0.75) / 0.25;
          m
            ..ty = -6 * (1 - p)
            ..rot = 5 * deg * (1 - p);
        }
    }
    return m;
  }

  // ============================================================
  // Variant B: breathing — slow organic scale pulse
  // ============================================================
  _MicroAnimMods _breathingBody(double t) {
    final m = _MicroAnimMods();
    switch (mood) {
      case FaceMood.stronglyDisagree:
        // Shrink to 0.94 mid-cycle (4s).
        final c = (t / 4) % 1;
        final s = 1 - math.sin(c * math.pi * 2).abs() * 0.06;
        m
          ..sx = s
          ..sy = s;
      case FaceMood.disagree:
        // Shrink + tiny y bob (5s).
        final c = (t / 5) % 1;
        final s = 1 - math.sin(c * math.pi * 2).abs() * 0.03;
        m
          ..sx = s
          ..sy = s
          ..ty = math.sin(c * math.pi * 2).abs() * 2;
      case FaceMood.notSure:
        // Expand to 1.03 (4s).
        final c = (t / 4) % 1;
        final s = 1 + math.sin(c * math.pi * 2).abs() * 0.03;
        m
          ..sx = s
          ..sy = s;
      case FaceMood.agree:
        // Swell to 1.05 (3s).
        final c = (t / 3) % 1;
        final s = 1 + math.sin(c * math.pi * 2).abs() * 0.05;
        m
          ..sx = s
          ..sy = s;
      case FaceMood.stronglyAgree:
        // Radiate: 1 → 1.08 → 0.97 (2s).
        final c = (t / 2) % 1;
        double s;
        if (c < 0.30) {
          s = 1 + (c / 0.30) * 0.08;
        } else if (c < 0.60) {
          s = 1.08 - ((c - 0.30) / 0.30) * 0.11;
        } else {
          s = 0.97 + ((c - 0.60) / 0.40) * 0.03;
        }
        m
          ..sx = s
          ..sy = s;
    }
    return m;
  }

  // ============================================================
  // Variant C: fidget — nervous rapid energy
  // ============================================================
  _MicroAnimMods _fidgetBody(double t) {
    final m = _MicroAnimMods();
    const deg = math.pi / 180;
    switch (mood) {
      case FaceMood.stronglyDisagree:
        // Rapid tremble (1.8s): rotation rocks -3..3..-2..2..0
        final c = (t / 1.8) % 1;
        if (c < 0.10) {
          m.rot = -3 * deg * (c / 0.10);
        } else if (c < 0.20) {
          final p = (c - 0.10) / 0.10;
          m.rot = (-3 + 6 * p) * deg;
        } else if (c < 0.30) {
          final p = (c - 0.20) / 0.10;
          m.rot = (3 - 5 * p) * deg;
        } else if (c < 0.40) {
          final p = (c - 0.30) / 0.10;
          m.rot = (-2 + 4 * p) * deg;
        } else if (c < 0.50) {
          final p = (c - 0.40) / 0.10;
          m.rot = 2 * deg * (1 - p);
        }
      case FaceMood.disagree:
        // Eyes wander (no body anim — handled in painter).
        break;
      case FaceMood.notSure:
        // Head shuffle X (2s).
        final c = (t / 2) % 1;
        m.tx = math.sin(c * math.pi * 2) * 2;
      case FaceMood.agree:
        // Jitter hop + rotate (1s).
        final c = (t / 1) % 1;
        if (c < 0.33) {
          final p = c / 0.33;
          m
            ..ty = -3 * p
            ..rot = 2 * deg * p;
        } else if (c < 0.66) {
          final p = (c - 0.33) / 0.33;
          m
            ..ty = -3 + 1 * p
            ..rot = (2 - 4 * p) * deg;
        } else {
          final p = (c - 0.66) / 0.34;
          m
            ..ty = -2 * (1 - p)
            ..rot = -2 * deg * (1 - p);
        }
      case FaceMood.stronglyAgree:
        // Hyper bounce (0.6s loop): -8px + 6° + 1.05 scale at peak.
        final c = (t / 0.6) % 1;
        final peak = math.sin(c * math.pi).abs();
        m
          ..ty = -8 * peak
          ..rot = 6 * deg * peak
          ..sx = 1 + 0.05 * peak
          ..sy = 1 + 0.05 * peak;
    }
    return m;
  }

  // ============================================================
  // Variant D: emote — dramatic expression
  // ============================================================
  _MicroAnimMods _emoteBody(double t) {
    final m = _MicroAnimMods();
    const deg = math.pi / 180;
    switch (mood) {
      case FaceMood.stronglyDisagree:
        // Subtle bob — 70-80% of cycle dips 3px (3s loop).
        final c = (t / 3) % 1;
        if (c >= 0.70 && c < 0.80) {
          final p = (c - 0.70) / 0.10;
          m.ty = 3 * (p < 0.5 ? p * 2 : (1 - p) * 2);
        }
      case FaceMood.disagree:
        // Big sway (4s): -6° → 0° → +3° → 0
        final c = (t / 4) % 1;
        if (c < 0.50) {
          m.rot = math.sin(c / 0.50 * math.pi) * -6 * deg;
        } else {
          m.rot = math.sin((c - 0.50) / 0.50 * math.pi) * 3 * deg;
        }
      case FaceMood.notSure:
        // No body anim — brow lift in painter.
        break;
      case FaceMood.agree:
        // Vertical bob with scale (1.5s).
        final c = (t / 1.5) % 1;
        final peak = math.sin(c * math.pi * 2).abs();
        m
          ..ty = -3 * peak
          ..sx = 1 + 0.04 * peak
          ..sy = 1 + 0.04 * peak;
      case FaceMood.stronglyAgree:
        // Rotation rocking (0.8s): -8° → +8° with slight scale.
        final c = (t / 0.8) % 1;
        m
          ..rot = math.sin(c * math.pi * 2) * 8 * deg
          ..sx = 1.02
          ..sy = 1.02;
    }
    return m;
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
/// Mason jar — clear glass with a threaded screw-top neck, a
/// shoulder curve down to the cylinder body, and a rounded base.
/// Drawn in two passes so marbles can sit visually INSIDE the jar
/// (between the back wall and the front glass):
///
///   _Jar          — priority -1000, paints the back parts:
///                   back-of-base, back-of-rim, back-of-shoulder,
///                   back-wall tint. Drawn first.
///   marbles       — priority = position.y, sorted between.
///   _JarFront     — priority +1000000, paints the front parts on
///                   top of the marbles: front body wall (with the
///                   tinted-glass overlay), side walls, front-of-
///                   base curve, threaded neck (front), front-of-
///                   rim arc, specular highlight stripe.
///
/// `_rimFlatten` (the ratio of rim ellipse height to width) is
/// shared so the marble's `_resolveJarWalls` can use the same
/// geometry to bounce off the inside.
///
/// All drawing uses geometry helpers on `_Jar` (so `_JarFront` can
/// pull the same numbers without duplicating constants).
class _Jar extends PositionComponent {
  _Jar({required Vector2 size}) : super(size: size, anchor: Anchor.topLeft) {
    priority = -1000; // back parts always draw before marbles
  }

  /// How squashed the rim/base ellipses are vs a perfect circle.
  /// 0.20 reads as a clean cylinder seen from slightly above —
  /// deep enough to give 3/4-view depth but shallow enough that
  /// the rim doesn't eat the body. (0.32 from the previous pass
  /// made the body cavity too short to hold even one full marble.)
  static const double _rimFlatten = 0.20;

  /// Glass wall thickness. The visible outer outline draws at the
  /// component's full extent; the interior cylinder marbles bounce
  /// off is inset by this much per side. The faint inner outline
  /// draws at the interior edge so the user reads "thick glass."
  static const double _glassThickness = 6;

  // ——— Mason-jar profile ——————————————————————————————————————
  // All in local coords (origin at top-left of the component box).
  // Body width = component width; neck is ~15% narrower than body
  // (subtle — a real mason jar's threaded neck barely tapers in).
  double get bodyW => size.x;
  double get neckW => size.x * 0.85;

  /// Rim ellipse half-height (the rim spans Y in [0, 2*rimRy]).
  double get rimRy => bodyW * _rimFlatten / 2;

  /// Total height of the threaded screw neck (compact band of
  /// ridges right below the rim).
  double get threadH => rimRy * 0.6;

  /// Bottom Y of the threaded neck.
  double get neckBottomY => 2 * rimRy + threadH;

  /// Where the shoulder curve lands on the body width. Steeper
  /// than before so the body section gets the bulk of the height.
  double get shoulderEndY => neckBottomY + rimRy * 0.6;

  /// Bottom of the base ellipse.
  double get baseRy => rimRy * 0.95;

  /// Centerline X.
  double get cx => bodyW / 2;

  // ——— Interior cylinder (where marbles actually live) —————————
  // Inset from the visible outer wall by `_glassThickness` per side
  // so the front/back outlines float beyond the marble container,
  // giving the read of solid glass.
  double get interiorR => bodyW / 2 - _glassThickness;
  double get interiorRimRy => rimRy - _glassThickness * _rimFlatten;
  double get interiorBaseRy => baseRy - _glassThickness * _rimFlatten;

  /// Vertical screen-Y of the interior floor (where the marble pile
  /// sits in 3D). Slightly above the visible base so the floor
  /// reads as sitting on top of glass thickness.
  double get interiorFloorScreenY =>
      position.y + size.y - baseRy + _glassThickness * 0.4;

  /// Top of the body cylinder section in screen-Y. Marbles falling
  /// from the throw arc transition into 3D physics at this Y.
  double get interiorBodyTopScreenY =>
      position.y + shoulderEndY + _glassThickness;

  /// Total interior body height in jar-local Y (floor at 0, top of
  /// cylinder at this value). Used for overflow detection.
  double get interiorBodyHeight =>
      (size.y - baseRy) - shoulderEndY - _glassThickness * 0.4;

  Rect get topRimRect => Rect.fromCenter(
        center: Offset(cx, rimRy),
        width: neckW,
        height: rimRy * 2,
      );
  Rect get interiorTopRimRect => Rect.fromCenter(
        center: Offset(cx, rimRy),
        width: neckW - _glassThickness * 2,
        height: (rimRy - _glassThickness * _rimFlatten) * 2,
      );
  Rect get neckBottomRect => Rect.fromCenter(
        center: Offset(cx, neckBottomY),
        width: neckW,
        height: rimRy * 1.4,
      );
  Rect get baseRect => Rect.fromCenter(
        center: Offset(cx, size.y - baseRy),
        width: bodyW,
        height: baseRy * 2,
      );

  // ——— Paints (shared) ————————————————————————————————————————
  static final _outline = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  static final _outlineThin = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  static final _glassTint = Paint()..color = const Color(0x22C2DEEA);
  static final _glassFront = Paint()..color = const Color(0x33D5E8F0);
  static final _backWallTint = Paint()..color = const Color(0x33778899);
  static final _innerShadow = Paint()
    ..color = const Color(0x33000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  static final _highlightSoft = Paint()
    ..color = const Color(0x55FFFFFF)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  static final _highlightSharp = Paint()
    ..color = const Color(0x99FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _threadShade = Paint()..color = const Color(0x33000000);

  /// Faint dark line for the inner edge of the glass — sits just
  /// inside the outer wall outline so the user reads two edges
  /// (outer + inner) and the gap between as glass thickness.
  static final _innerEdge = Paint()
    ..color = const Color(0x551A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  /// Path of the jar's interior silhouette in local coords. Used
  /// by `_JarFront` to clip the tinted-glass overlay so it only
  /// dims marbles inside the jar (not the area outside its bounds).
  Path interiorPath() {
    final p = Path();
    final rimY = rimRy;
    final neckY = neckBottomY;
    final shoulderY = shoulderEndY;
    final bodyBottomY = size.y - baseRy;
    final neckHalf = neckW / 2;
    final bodyHalf = bodyW / 2;
    // Start at top-left of rim, trace down-left side, curve around
    // base, back up the right side, close at top-right of rim.
    p
      ..moveTo(cx - neckHalf, rimY)
      // Down the neck (vertical).
      ..lineTo(cx - neckHalf, neckY)
      // Shoulder curve out to body width.
      ..quadraticBezierTo(
        cx - neckHalf,
        shoulderY,
        cx - bodyHalf,
        shoulderY,
      )
      // Down the body.
      ..lineTo(cx - bodyHalf, bodyBottomY)
      // Across the bottom (the base ellipse's lower half).
      ..arcTo(baseRect, math.pi, math.pi, false)
      // Up the right body.
      ..lineTo(cx + bodyHalf, shoulderY)
      // Right shoulder curve in to neck.
      ..quadraticBezierTo(
        cx + neckHalf,
        shoulderY,
        cx + neckHalf,
        neckY,
      )
      // Up the right neck to the rim.
      ..lineTo(cx + neckHalf, rimY)
      ..close();
    return p;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // === BACK PASS ===
    // Outer back-of-base + back-of-rim outlines, plus the inner
    // back-of-rim outline (a touch thinner) drawn just inside the
    // outer one — together they sell glass thickness on the back
    // side. Then the smoky back-wall tint clipped to the interior
    // silhouette gives the "looking through to a back wall" read.
    final innerRim = interiorTopRimRect;
    canvas
      ..drawArc(baseRect, math.pi, math.pi, false, _outline)
      ..drawArc(topRimRect, math.pi, math.pi, false, _outlineThin)
      ..drawArc(innerRim, math.pi, math.pi, false, _innerEdge)
      ..save()
      ..clipPath(interiorPath())
      ..drawRect(
        Rect.fromLTRB(0, rimRy, size.x, neckBottomY + rimRy * 1.6),
        _backWallTint,
      )
      ..drawPath(interiorPath(), _innerShadow)
      ..restore();
  }

  /// World-space top of the jar — the rim's top edge in screen
  /// coords. Marbles aim here when thrown.
  double get topY => position.y;
}

/// Front pass for the mason jar. Sits at extreme priority so it
/// always draws AFTER every marble — that's how the front glass
/// occludes the marbles inside.
class _JarFront extends PositionComponent {
  _JarFront({required this.jar})
      : super(
          size: jar.size,
          position: jar.position,
          priority: 1000000,
        );

  final _Jar jar;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final cx = jar.cx;
    final bodyW = jar.bodyW;
    final neckW = jar.neckW;
    final rimRy = jar.rimRy;
    final neckBottomY = jar.neckBottomY;
    final shoulderEndY = jar.shoulderEndY;
    final baseRy = jar.baseRy;
    final h = jar.size.y;
    final neckHalf = neckW / 2;
    final bodyHalf = bodyW / 2;

    // Front silhouette outline (clipped front of the body): traces
    // the same interior path as the back's clip, drawn as outline.
    final frontOutlinePath = Path()
      ..moveTo(cx - neckHalf, rimRy)
      ..lineTo(cx - neckHalf, neckBottomY)
      ..quadraticBezierTo(
        cx - neckHalf,
        shoulderEndY,
        cx - bodyHalf,
        shoulderEndY,
      )
      ..lineTo(cx - bodyHalf, h - baseRy)
      ..arcTo(jar.baseRect, math.pi, math.pi, false)
      ..lineTo(cx + bodyHalf, shoulderEndY)
      ..quadraticBezierTo(
        cx + neckHalf,
        shoulderEndY,
        cx + neckHalf,
        neckBottomY,
      )
      ..lineTo(cx + neckHalf, rimRy);

    // ——— Tinted-glass overlay over the marbles ———
    // Clipped to the interior shape so only the inside of the jar
    // is dimmed; outside stays the world bg.
    canvas
      ..save()
      ..clipPath(jar.interiorPath())
      ..drawRect(
        Rect.fromLTRB(0, 0, jar.size.x, jar.size.y),
        _Jar._glassTint,
      )
      // Front-glass milky cast — concentrated on the lower-front
      // of the body (where the curved glass would pick up most of
      // the ambient light).
      ..drawRect(
        Rect.fromLTRB(0, shoulderEndY, jar.size.x, h - baseRy),
        _Jar._glassFront,
      )
      // Inner edge stroke — traces the interior silhouette so the
      // user sees BOTH outer and inner outlines and the gap reads
      // as solid glass thickness.
      ..drawPath(jar.interiorPath(), _Jar._innerEdge)
      ..restore()
      // ——— Front-of-base, body outline, threaded neck, rim ———
      ..drawArc(jar.baseRect, 0, math.pi, false, _Jar._outline)
      ..drawPath(frontOutlinePath, _Jar._outline);

    // Threaded neck: two horizontal ridge ellipses between the top
    // rim and the neck-bottom ellipse, each with a soft shade band
    // underneath (sells the screw-thread relief).
    const threadCount = 2;
    for (var i = 0; i < threadCount; i++) {
      final t = (i + 1) / (threadCount + 1);
      final y = rimRy * 2 + (neckBottomY - rimRy * 2) * t;
      final ridge = Rect.fromCenter(
        center: Offset(cx, y),
        width: neckW * (0.96 + 0.04 * math.sin(t * math.pi)),
        height: rimRy * 0.55,
      );
      canvas
        ..drawArc(
          ridge.translate(0, 1.5),
          0,
          math.pi,
          false,
          _Jar._threadShade,
        )
        ..drawOval(ridge, _Jar._outlineThin);
    }

    // Neck-bottom + top rim. Outer rim ellipse + a subtle inner rim
    // ellipse just inside it so the opening reads as glass-walled.
    canvas
      ..drawOval(jar.neckBottomRect, _Jar._outlineThin)
      ..drawArc(jar.topRimRect, 0, math.pi, false, _Jar._outline)
      ..drawOval(jar.topRimRect, _Jar._outlineThin)
      ..drawArc(jar.interiorTopRimRect, 0, math.pi, false, _Jar._innerEdge);

    // ——— Specular highlights ———
    // Soft stripe down the left side of the cylinder + a sharp
    // narrow accent line — together they sell curved glass lit
    // from above-left. Plus a faint top-rim arc highlight.
    final specRect = Rect.fromLTRB(
      cx - bodyHalf + 6,
      shoulderEndY + 4,
      cx - bodyHalf + 22,
      h - baseRy - 4,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(specRect, const Radius.circular(8)),
        _Jar._highlightSoft,
      )
      ..drawLine(
        Offset(cx - bodyHalf + 14, shoulderEndY + 12),
        Offset(cx - bodyHalf + 14, h - baseRy - 14),
        _Jar._highlightSharp,
      )
      ..drawArc(
        jar.topRimRect.deflate(2),
        math.pi * 1.1,
        math.pi * 0.7,
        false,
        _Jar._highlightSharp,
      );
  }
}

// =====================================================================
// World marble nodes — pickable face emojis the chibi interacts with
// =====================================================================

/// Lifecycle of a face marble.
///
/// idle     → in the world, springs around its rest slot, dodges
///            the chibi, gently nudges other idle siblings.
/// held     → carried above the chibi's head.
/// flying   → projectile arc en route to the jar's mouth (or to a
///            spillover target if the jar's full).
/// inJar    → inside the cylinder, in 3D. Has (jarX, jarY, jarZ)
///            with gravity acting on jarY only and lateral motion
///            in the (X, Z) plane. Walls + floor + 3D pairwise
///            collisions. Renders via a (X, Y, Z)→screen projection.
/// spilled  → overflow. Sits forever on the table around the jar,
///            collides with chibi + other loose marbles, but isn't
///            pickable. Decoration that records every drop.
enum _MarbleState { idle, held, flying, inJar, spilled }

/// One face emoji in the world. Same component handles every
/// lifecycle state — pickable, held, flying, bouncing in the jar.
/// State transitions go through explicit methods (`pickUp`,
/// `releaseToRest`, `throwToJar`); the rest of the game pokes the
/// `state` enum indirectly through those.
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
  /// 28 so the chunkier expressive faces all read clearly even when
  /// the marble shrinks at the top of the screen.
  static const double _radius = 28;
  static const double _gravity = 1100;

  /// Cap on idle-state velocity. v60.13 — raised from 180 so
  /// kicked marbles can roll a real distance before damping pulls
  /// them back. Hard contact with the chibi (handled in
  /// `_resolveWorldCollisions`) is the primary motion source now;
  /// the soft force-field at this radius just nudges nearby
  /// marbles a little so they react before the hit lands.
  static const double _idleVMax = 360;

  /// Hitbox half-width approximation for the chibi (matches the
  /// plate-collision constant in ChibiCharacter). The world
  /// collision pass uses this to push idle marbles out of overlap.
  static const double _chibiHalfW = 26;
  static const double _chibiHalfH = 50;

  /// Which of the three face slots this marble belongs to (0..2).
  /// On entry to the jar, the game spawns a fresh marble for this
  /// slot at the same rest position.
  final int slotIdx;
  final FaceMood mood;
  final int seed;
  final Vector2 _restPos;

  /// Animation variant — idle / breathing / fidget / emote. Picked
  /// at construction (seeded from `seed`) and stable for the life
  /// of this marble. Replacement marbles spawned after a jar drop
  /// re-roll this so the world feels varied across plays.
  late final MarbleVariant variant = MarbleVariant
      .values[math.Random(seed * 53 + 7).nextInt(MarbleVariant.values.length)];

  /// Tint is mutable so the game can shuffle palette colors on the
  /// idle marbles when something lands in the jar.
  Color tint;

  /// One shared eye-drift driver for both eyes. v60.14 — the older
  /// design had two independent drifts (one per eye) which read as
  /// "wonky / scary" when one eye drifted while the other stayed.
  /// Real eyes track together; both pupils now read the same value.
  late final _EyeDrift _eyeDrift = _EyeDrift(seed: seed * 31 + 1);
  late final _MicroAnimController _microAnim =
      _MicroAnimController(mood: mood, variant: variant);

  _MarbleState state = _MarbleState.idle;

  /// True when the chibi is close enough to pick this up (or switch
  /// to it). Drives the soft halo + size pulse.
  bool highlighted = false;

  double _t = 0;

  /// Velocity. Used by every dynamic state (idle avoidance, flying
  /// arc, in-jar physics). Library-private so the game can read +
  /// write during pairwise collision passes.
  double vx = 0;
  double vy = 0;

  /// Squash-and-stretch animation phase, 0..1. Starts at 1 on
  /// impact (jar entry, wall bounce, marble-on-marble collision)
  /// and decays — `render` reads this to scale the marble's local
  /// canvas with a damped wobble. Library-private so the game can
  /// trigger a squash from the collision pass.
  double squash = 0;

  /// One-shot guard so we only fire `onMarbleEnteredJar` once per
  /// throw, even if the marble crosses the rim line on multiple
  /// frames (it can re-enter from below if the jar gets crowded).
  bool _enteredJar = false;

  /// Where the throw arc lands and the post-flight state begins.
  /// Set by `throwToJar`; read by the flying-state branch.
  /// `_postFlightState` is `inJar` for normal throws and `spilled`
  /// for overflow throws.
  _MarbleState _postFlightState = _MarbleState.inJar;

  void pickUp() {
    state = _MarbleState.held;
    vx = 0;
    vy = 0;
    highlighted = false;
  }

  /// Drop back onto the world slot — used when the chibi switches
  /// from this marble to another. Snaps for now; could animate.
  void releaseToRest() {
    state = _MarbleState.idle;
    position.setFrom(_restPos);
    vx = 0;
    vy = 0;
  }

  /// Convert to a flying projectile aimed at the jar's mouth.
  /// 2D drop: aim at a point just inside the rim with a small
  /// random X jitter (the jar is narrow enough that the marble
  /// will basically stack vertically once inside; jitter just
  /// keeps adjacent throws from landing at the exact same X).
  ///
  /// Overflow check (geometric): if the highest in-jar marble in
  /// this column is within ~2r of the rim, this throw can't fit
  /// — re-target to a spillover trajectory landing on the table
  /// next to the jar.
  void throwToJar(_SurveyGame game) {
    state = _MarbleState.flying;
    _enteredJar = false;
    final jar = game.jar;
    final chibi = game.chibi;
    final cx = jar.position.x + jar.cx;
    final mouthY = jar.position.y + jar.rimRy;
    // Available lateral play inside the rim minus marble radius.
    final spread = math.max<double>(jar.neckW / 2 - _radius, 0);
    final aimX = cx + (math.Random().nextDouble() * 2 - 1) * spread * 0.6;

    // Overflow: would the new marble's center land above the rim?
    final pileTopY = game.pileTopAt(aimX);
    final rimThreshold = jar.position.y + jar.rimRy * 0.6;
    final overflow = (pileTopY - _radius * 2) < rimThreshold;

    if (overflow) {
      _postFlightState = _MarbleState.spilled;
      final outsideX = chibi.position.x < cx
          ? jar.position.x - 24
          : jar.position.x + jar.size.x + 24;
      final outsideY = jar.position.y + jar.size.y - jar.baseRy * 0.4;
      _aimArc(outsideX, outsideY, 0.78);
    } else {
      _postFlightState = _MarbleState.inJar;
      _aimArc(aimX, mouthY, 0.78);
    }
  }

  /// Throw-arc velocity solver: given a target (x, y) and a fixed
  /// flight time, compute (vx, vy) so gravity + initial velocity
  /// land exactly there.
  void _aimArc(double targetX, double targetY, double flightTime) {
    final dx = targetX - position.x;
    final dy = targetY - position.y;
    vx = dx / flightTime;
    vy = (dy - 0.5 * _gravity * flightTime * flightTime) / flightTime;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _eyeDrift.update(dt);
    // Body-level idle anims run continuously based on `_t`. The
    // controller is stateless now (per-face spec); call update for
    // API symmetry but it's effectively a no-op.
    if (state == _MarbleState.idle || state == _MarbleState.held) {
      _microAnim.update(dt);
    }
    if (squash > 0) {
      squash = math.max(0, squash - dt * 3.0);
    }

    final game = findGame();
    switch (state) {
      case _MarbleState.idle:
        _updateIdle(dt, game);
      case _MarbleState.held:
        _updateHeld(game);
      case _MarbleState.flying:
        vy += _gravity * dt;
        position
          ..x += vx * dt
          ..y += vy * dt;
        if (game is _SurveyGame && !_enteredJar) {
          final jar = game.jar;
          final triggerY = jar.position.y + jar.rimRy * 0.6;
          if (position.y >= triggerY) {
            // Side-entry guard: at the moment the marble crosses
            // the rim Y line, check whether its screen-X is
            // actually inside the rim's mouth. If it isn't, the
            // throw missed (the chibi was too far to the side and
            // the arc went around the jar) — redirect to spilled
            // instead of teleporting through the side wall.
            final rimLeft = jar.position.x + (jar.bodyW - jar.neckW) / 2;
            final rimRight = jar.position.x +
                (jar.bodyW - jar.neckW) / 2 +
                jar.neckW;
            final insideRim =
                position.x > rimLeft && position.x < rimRight;
            _enteredJar = true;
            squash = 0.45;
            if (_postFlightState == _MarbleState.inJar && insideRim) {
              // 2D pipeline: keep the screen-space velocity. Gravity
              // continues from here, the cylinder walls + the floor
              // catch the marble naturally.
              state = _MarbleState.inJar;
              game.onMarbleEnteredJar(this);
            } else {
              // Either the throw missed the rim (insideRim=false)
              // or the jar was full (postFlightState=spilled).
              // Either way, the marble lands on the table.
              state = _MarbleState.spilled;
              game.onMarbleEnteredJar(this);
            }
          }
        }
      case _MarbleState.inJar:
        if (game is _SurveyGame) _updateInJar(dt, game.jar);
      case _MarbleState.spilled:
        _updateSpilled(dt, game);
    }

    // Y-based render priority so marbles closer to the camera
    // (lower screen Y) draw over marbles farther away — and over
    // the chibi when the chibi is behind them. Cheap fake-depth
    // sort that doesn't need per-frame z-buffering.
    priority = position.y.round();
  }

  /// Idle physics: pure damping + a velocity cap. No spring.
  /// v60.16 — real-marble fantasy. A marble at rest stays at rest
  /// until something hits it; a kicked marble rolls and slows from
  /// friction, settling wherever it ends up. The pickup logic
  /// already finds the nearest one of any mood, so gameplay still
  /// works — you walk to wherever the marble actually is.
  ///
  /// All other interactions (chibi kick, marble-marble bounce,
  /// walls, plate, jar-exterior) live in `_resolveWorldCollisions`.
  void _updateIdle(double dt, FlameGame? game) {
    if (game is! _SurveyGame) return;
    // Friction-style damping. ~0.6/sec linear-ish drag — kicked
    // marbles roll a real distance and grind to a stop in a few
    // seconds, no rubber-band spring pulling them home.
    final damp = math.pow(0.55, dt).toDouble();
    vx *= damp;
    vy *= damp;
    final v2 = vx * vx + vy * vy;
    if (v2 > _idleVMax * _idleVMax) {
      final v = math.sqrt(v2);
      vx = vx / v * _idleVMax;
      vy = vy / v * _idleVMax;
    }
    position
      ..x += vx * dt
      ..y += vy * dt;
  }

  void _updateHeld(FlameGame? game) {
    if (game is! _SurveyGame) return;
    final c = game.chibi;
    final cs = c.scale.x;
    position
      ..x = c.position.x
      ..y = c.position.y - 90 * cs + math.sin(_t * 4 + seed) * 1.5;
  }

  /// 2D in-jar physics (screen-space). Gravity pulls down, walls
  /// catch the marble left/right, the floor catches it at the
  /// bottom. Marble center sits at `floorY = visible_base_top -
  /// radius` when at rest so the marble visually sits ON the floor
  /// rather than centered on it.
  ///
  /// Pairwise marble-marble collision is handled by the game in
  /// `_resolveJarCollisions` (2D circle-circle). `clampToJar` is
  /// idempotent so it can be called twice per frame (after
  /// integration, then again after pairwise) without weird drift.
  ///
  /// Bouncier than before: restitution 0.65 on walls + floor, no
  /// stick-to-wall threshold. A marble dropped in keeps bouncing
  /// until friction grinds it to rest — about 6 collisions for a
  /// hard drop (0.65^6 ≈ 7.5% of initial velocity left).
  void _updateInJar(double dt, _Jar jar) {
    vy += _gravity * dt;
    final drag = math.pow(0.6, dt).toDouble();
    vx *= drag;
    position
      ..x += vx * dt
      ..y += vy * dt;
    clampToJar(jar);
  }

  /// Wall + floor clamp in screen space. Idempotent.
  void clampToJar(_Jar jar) {
    const restitution = 0.65;
    final cx = jar.position.x + jar.cx;
    final innerR = jar.interiorR;
    final left = cx - innerR + _radius;
    final right = cx + innerR - _radius;
    // Floor: just inside the bottom of the visible base ellipse,
    // shifted up by marble radius so the marble's BOTTOM sits on
    // the floor (not its center). Eliminates the "drawn through
    // the bottom" bug.
    final floorY = jar.position.y +
        jar.size.y -
        jar.baseRy * 0.4 -
        _Jar._glassThickness -
        _radius;

    if (position.x < left) {
      position.x = left;
      if (vx < 0) {
        if (-vx > 80) squash = math.max(squash, 0.4);
        vx = -vx * restitution;
      }
    }
    if (position.x > right) {
      position.x = right;
      if (vx > 0) {
        if (vx > 80) squash = math.max(squash, 0.4);
        vx = -vx * restitution;
      }
    }
    if (position.y > floorY) {
      position.y = floorY;
      if (vy > 0) {
        if (vy > 80) squash = math.max(squash, 0.5);
        vy = -vy * restitution;
        // Light floor friction so a marble landing flat eventually
        // stops sliding.
        vx *= 0.85;
      }
    }
  }

  /// Spilled-state physics. Marble has overflowed the jar and is
  /// now a loose object on the table around it. Falls under gravity
  /// in screen space, bounces off the table (ground line) with
  /// lateral friction, and accumulates around the jar.
  ///
  /// Wall + plate + jar-exterior bounces are handled by the game's
  /// `_resolveWorldCollisions` pass alongside idle marbles, so
  /// chibi-marble + marble-marble collisions Just Work for spilled
  /// marbles too. This branch is just the local integration.
  void _updateSpilled(double dt, FlameGame? game) {
    if (game is! _SurveyGame) return;
    final jar = game.jar;
    // Gravity in screen-Y.
    vy += _gravity * 0.55 * dt;
    final drag = math.pow(0.5, dt).toDouble();
    vx *= drag;
    position
      ..x += vx * dt
      ..y += vy * dt;
    // Ground line — table around the jar's base. Use the visible
    // base ellipse's bottom plus a hair so spilled marbles look
    // like they're sitting *just* outside the jar's footprint.
    final groundY =
        jar.position.y + jar.size.y - jar.baseRy * 0.4 - _radius;
    if (position.y > groundY) {
      position.y = groundY;
      if (vy > 0) {
        if (vy > 100) squash = math.max(squash, 0.45);
        vy = -vy * 0.3;
        vx *= 0.7;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final mods = _microAnim.compute(_t);
    final pulse = (highlighted && state == _MarbleState.idle)
        ? 1 + math.sin(_t * 6) * 0.07
        : 1.0;
    final game = findGame();
    final h = game?.size.y ?? 600;
    final depth = depthScaleForY(position.y, h);
    final baseScale = depth * pulse;
    final r = _radius * baseScale;

    // Combine impact-squash with micro-anim scale. The micro-anim
    // mods are layered on top of (not in place of) the squash so a
    // marble bouncing in the jar still squashes correctly.
    final wobble = math.sin(squash * math.pi * 2.5) * squash * 0.22;
    final sx = baseScale * (1 + wobble) * mods.sx;
    final sy = baseScale * (1 - wobble) * mods.sy;

    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Shadow at full radius (no squash) — keeps contact grounded.
    // Then save/translate/rotate/scale for the body+face, paint
    // via `_FacePainter`, and restore.
    canvas
      ..drawCircle(
        Offset(mods.tx, mods.ty + r * 0.4),
        r * 0.85,
        shadow,
      )
      ..save()
      ..translate(mods.tx, mods.ty)
      ..rotate(mods.rot)
      ..scale(sx, sy);
    _FacePainter(mood: mood, variant: variant, t: _t)
        .paintAt(canvas, Offset.zero, _radius);
    canvas.restore();

    // Soft halo when pickable + highlighted — drawn outside all
    // transforms so it stays a clean circle even mid-impact /
    // mid-emote.
    if (highlighted && state == _MarbleState.idle) {
      final halo = Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(mods.tx, mods.ty), r + 5, halo);
    }
  }
}

// =====================================================================
// Celebration trigger — what fires when a marble lands in the jar
// =====================================================================

/// One pulse of celebration. The Flutter overlay listens to a
/// `ValueNotifier<_CelebrationEvent?>`; on every change it spawns
/// a fresh batch of face-emoji particles. `seq` exists so the
/// listener can detect repeat fires of the same mood (otherwise
/// the notifier would consider equal-by-value events as no change).
class _CelebrationEvent {
  const _CelebrationEvent({
    required this.mood,
    required this.tint,
    required this.seq,
  });

  final FaceMood mood;
  final Color tint;
  final int seq;
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
  _SurveyGame({this.moods, this.onAnswered});

  /// Override the set of mood marbles spawned in the world. When
  /// null, falls back to `_kFaceMoods` (the full 5-face sandbox
  /// catalog). Kiosk mode passes a 3-mood list (sd / ns / sa) so
  /// the world matches BASECamp's 3-point Likert scale.
  final List<FaceMood>? moods;

  /// Called whenever a marble enters the jar — the kiosk listens
  /// to record a SurveyResponse + advance to the next question.
  /// Null in sandbox mode where there's no survey to advance.
  final void Function(FaceMood mood)? onAnswered;

  late final JoystickComponent joystick;
  late final KeyboardInput keyboardInput;
  late final ChibiCharacter chibi;
  late final _Jar jar;

  /// The pickable marbles currently in the world. Length = the
  /// length of `moods` (or 5 if `moods` is null).
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

  /// Pickup proximity threshold in screen pixels. v60.12 — pushed
  /// to 150 so the chibi doesn't have to stand on top of a marble
  /// to grab it; "close enough" is enough. Pairs with the marble's
  /// chibi-avoidance (radius 75): the marble starts rolling away
  /// at 75 but stays grabbable out to 150.
  static const double _pickRange = 150;

  /// What the FAB does next. UI binds via ValueListenableBuilder.
  final ValueNotifier<_FabAction> fabAction = ValueNotifier(_FabAction.jump);

  /// Fires every time a marble lands in the jar — the Flutter
  /// celebration overlay listens and bursts a stream of face
  /// emojis across the screen. The seq counter changes on every
  /// fire so the listener detects re-fires even when the same mood
  /// is dropped twice in a row.
  final ValueNotifier<_CelebrationEvent?> celebrationTrigger =
      ValueNotifier(null);
  int _celebrationSeq = 0;

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

  // v60.17 — palette shuffling on jar landing was removed when the
  // 5-face Likert spec made colors part of each face's identity.
  // Each marble's tint comes from `_kFacePalettes[mood].body` and
  // never changes; replacement marbles spawn with the same palette.

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
          // Hand the marble to its own throw routine — it picks
          // an aim point inside the jar mouth and computes the
          // arc velocity. From that moment, physics takes over.
          h.throwToJar(this);
          heldMarble = null;
        }
    }
    updateProximity();
  }

  /// Called by `_MarbleNode` the instant it crosses into the jar
  /// mouth. Three things happen, in order:
  ///   1. Color palette rotates → visible triple recomputed.
  ///   2. Every still-idle marble re-tints (the user sees the rest
  ///      of the world swap colors — felt-time response).
  ///   3. A fresh marble for the now-empty slot spawns at the rest
  ///      position so the world keeps three pickable faces around.
  ///   4. Celebration overlay fires (mood + tint + seq).
  ///
  /// The newly-arrived marble (`m`) keeps living — it's now in
  /// `inJar` state and bouncing among siblings via `_resolveCollisions`.
  void onMarbleEnteredJar(_MarbleNode m) {
    // Spawn a replacement marble for this slot with the SAME mood
    // (colors are now identity, not random). The new marble takes
    // its tint straight from the mood's palette.
    final replacement = _MarbleNode(
      slotIdx: m.slotIdx,
      mood: m.mood,
      tint: _kFacePalettes[m.mood]!.body,
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

    // Celebration trigger — Flutter overlay reads mood + tint and
    // bursts a stream of face emojis.
    _celebrationSeq += 1;
    celebrationTrigger.value = _CelebrationEvent(
      mood: m.mood,
      tint: m.tint,
      seq: _celebrationSeq,
    );

    // Kiosk mode: notify the survey controller so it can record
    // the response + advance to the next question. No-op in
    // sandbox mode.
    onAnswered?.call(m.mood);
  }

  /// Lowest screen-Y (= visually highest) of any in-jar marble in
  /// a column near `targetX`. Used by `throwToJar` to detect when
  /// the pile has reached the rim. Returns +infinity if no marbles
  /// in the column (i.e. there's nothing stacked there yet).
  double pileTopAt(double targetX) {
    var minY = double.infinity;
    const r = _MarbleNode._radius;
    const reach = r * 1.6;
    for (final c in children) {
      if (c is! _MarbleNode || c.state != _MarbleState.inJar) continue;
      if ((c.position.x - targetX).abs() > reach) continue;
      if (c.position.y < minY) minY = c.position.y;
    }
    return minY;
  }

  /// 2D pairwise circle-circle collision for in-jar marbles. After
  /// every marble integrates its own gravity + walls in
  /// `_updateInJar`, we sweep pairs once per frame, resolve any
  /// overlaps with positional separation, and exchange momentum
  /// along the contact normal with restitution.
  ///
  /// Re-clamps each marble after pairwise so a marble pushed past
  /// the wall by a neighbor doesn't stay outside the cylinder for
  /// a frame.
  void _resolveJarCollisions() {
    final inJar = <_MarbleNode>[];
    for (final c in children) {
      if (c is _MarbleNode && c.state == _MarbleState.inJar) {
        inJar.add(c);
      }
    }
    const r = _MarbleNode._radius;
    const minDist = r * 2;
    const minDist2 = minDist * minDist;
    for (var i = 0; i < inJar.length; i++) {
      final a = inJar[i];
      for (var j = i + 1; j < inJar.length; j++) {
        final b = inJar[j];
        final dx = b.position.x - a.position.x;
        final dy = b.position.y - a.position.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minDist2 || d2 < 1e-6) continue;
        final d = math.sqrt(d2);
        final overlap = minDist - d;
        final nx = dx / d;
        final ny = dy / d;
        a.position
          ..x -= nx * overlap * 0.5
          ..y -= ny * overlap * 0.5;
        b.position
          ..x += nx * overlap * 0.5
          ..y += ny * overlap * 0.5;
        final rvx = b.vx - a.vx;
        final rvy = b.vy - a.vy;
        final velAlongNormal = rvx * nx + rvy * ny;
        if (velAlongNormal < 0) {
          const restitution = 0.65;
          final impulse = -(1 + restitution) * velAlongNormal / 2;
          a
            ..vx -= impulse * nx
            ..vy -= impulse * ny;
          b
            ..vx += impulse * nx
            ..vy += impulse * ny;
          if (-velAlongNormal > 80) {
            a.squash = math.max(a.squash, 0.4);
            b.squash = math.max(b.squash, 0.4);
          }
        }
      }
    }
    // Re-clamp after pairwise — a neighbor may have pushed someone
    // out of the cylinder; pull them back before the next frame.
    for (final m in inJar) {
      m.clampToJar(jar);
    }
  }

  /// Physics pass for marbles still out in the world (idle state).
  /// Runs after every idle marble has integrated its spring.
  ///
  /// Resolves, in order:
  ///   1. World-bounds bounce (off the playable rectangle).
  ///   2. Plate-AABB bounce (the immovable question plate).
  ///   3. Jar-exterior bounce (treat the jar as a no-go obstacle
  ///      from the outside — keeps idle marbles above the rim
  ///      instead of letting them slide down the side and tunnel
  ///      into the body).
  ///   4. Pairwise marble-marble collision with momentum exchange.
  ///   5. Chibi-marble collision: positional separation + an
  ///      impulse that adds the chibi's current velocity to the
  ///      marble (proportional to how head-on the contact is). A
  ///      head-on bump kicks the marble; a glancing brush nudges
  ///      it.
  ///
  /// Held marbles are excluded from every step (they're in the
  /// chibi's hand). Marbles that are flying / inJar follow their
  /// own paths and are handled by `_resolveJarCollisions`.
  void _resolveWorldCollisions() {
    // "Loose" marbles = both idle (can be picked up) and spilled
    // (decoration, but still physical objects). Both participate
    // in walls + plate + jar-exterior + pairwise + chibi-kick.
    final idle = <_MarbleNode>[];
    for (final c in children) {
      if (c is _MarbleNode &&
          (c.state == _MarbleState.idle ||
              c.state == _MarbleState.spilled)) {
        idle.add(c);
      }
    }
    if (idle.isEmpty) return;

    const r = _MarbleNode._radius;

    // ==== World bounds ====
    // Idle marbles live in the upper play area — clamp them above
    // the jar's top so they don't slide down past it. Spilled
    // marbles live BELOW that line (around the jar's base) so they
    // skip the upper-bound check; they only get the screen-edge
    // clamp + their own ground line in `_updateSpilled`.
    const playLeft = r;
    final playRight = size.x - r;
    const playTop = 60.0;
    final playBottom = jar.position.y - r;
    final screenBottom = size.y - r;
    for (final m in idle) {
      if (m.position.x < playLeft) {
        m.position.x = playLeft;
        if (m.vx < 0) m.vx = -m.vx * 0.55;
      } else if (m.position.x > playRight) {
        m.position.x = playRight;
        if (m.vx > 0) m.vx = -m.vx * 0.55;
      }
      if (m.state == _MarbleState.idle) {
        if (m.position.y < playTop) {
          m.position.y = playTop;
          if (m.vy < 0) m.vy = -m.vy * 0.55;
        } else if (m.position.y > playBottom) {
          m.position.y = playBottom;
          if (m.vy > 0) m.vy = -m.vy * 0.55;
        }
      } else {
        // spilled — only the bottom-of-screen clamp.
        if (m.position.y > screenBottom) {
          m.position.y = screenBottom;
          if (m.vy > 0) m.vy = -m.vy * 0.3;
        }
      }
    }

    // ==== Plate AABB ====
    final plate = plateBounds;
    if (plate != null) {
      for (final m in idle) {
        final cx = m.position.x;
        final cy = m.position.y;
        final overlapX = (cx + r).clamp(plate.left, plate.right) -
            (cx - r).clamp(plate.left, plate.right);
        final overlapY = (cy + r).clamp(plate.top, plate.bottom) -
            (cy - r).clamp(plate.top, plate.bottom);
        if (overlapX > 0 && overlapY > 0) {
          if (overlapX < overlapY) {
            // Push along X.
            if (cx < (plate.left + plate.right) / 2) {
              m.position.x = plate.left - r;
              if (m.vx > 0) m.vx = -m.vx * 0.55;
            } else {
              m.position.x = plate.right + r;
              if (m.vx < 0) m.vx = -m.vx * 0.55;
            }
          } else {
            // Push along Y.
            if (cy < (plate.top + plate.bottom) / 2) {
              m.position.y = plate.top - r;
              if (m.vy > 0) m.vy = -m.vy * 0.55;
            } else {
              m.position.y = plate.bottom + r;
              if (m.vy < 0) m.vy = -m.vy * 0.55;
            }
          }
          m.squash = math.max(m.squash, 0.3);
        }
      }
    }

    // ==== Jar-exterior bounce ====
    // Idle marbles can't roll over the rim ceiling. Spilled
    // marbles can't tunnel into the body silhouette from the
    // sides (they sit BESIDE the jar, not behind/in front).
    final rimRect = jar.topRimRect.translate(jar.position.x, jar.position.y);
    final jarLeft = jar.position.x;
    final jarRight = jar.position.x + jar.size.x;
    final jarBodyTopY = jar.position.y + jar.shoulderEndY;
    for (final m in idle) {
      if (m.state == _MarbleState.idle) {
        // Rim ceiling for idle marbles above the jar.
        if (m.position.x < rimRect.left - r) continue;
        if (m.position.x > rimRect.right + r) continue;
        final rimTopY = rimRect.top - r;
        if (m.position.y > rimTopY) {
          m.position.y = rimTopY;
          if (m.vy > 0) m.vy = -m.vy * 0.45;
          m.squash = math.max(m.squash, 0.3);
        }
      } else {
        // Spilled marbles bounce off the jar's body sides — keeps
        // them out of the cylinder footprint at table level.
        if (m.position.y < jarBodyTopY) continue;
        if (m.position.x > jarLeft - r &&
            m.position.x < jarLeft + r * 0.5) {
          m.position.x = jarLeft - r;
          if (m.vx > 0) m.vx = -m.vx * 0.4;
        } else if (m.position.x < jarRight + r &&
            m.position.x > jarRight - r * 0.5) {
          m.position.x = jarRight + r;
          if (m.vx < 0) m.vx = -m.vx * 0.4;
        }
      }
    }

    // ==== Marble-marble pairwise collision ====
    const minDist = r * 2;
    for (var i = 0; i < idle.length; i++) {
      final a = idle[i];
      for (var j = i + 1; j < idle.length; j++) {
        final b = idle[j];
        final dx = b.position.x - a.position.x;
        final dy = b.position.y - a.position.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minDist * minDist || d2 < 1e-6) continue;
        final d = math.sqrt(d2);
        final overlap = minDist - d;
        final nx = dx / d;
        final ny = dy / d;
        a.position
          ..x -= nx * overlap * 0.5
          ..y -= ny * overlap * 0.5;
        b.position
          ..x += nx * overlap * 0.5
          ..y += ny * overlap * 0.5;
        final rvx = b.vx - a.vx;
        final rvy = b.vy - a.vy;
        final velAlongNormal = rvx * nx + rvy * ny;
        if (velAlongNormal < 0) {
          const restitution = 0.55;
          final impulse = -(1 + restitution) * velAlongNormal / 2;
          a
            ..vx -= impulse * nx
            ..vy -= impulse * ny;
          b
            ..vx += impulse * nx
            ..vy += impulse * ny;
          if (-velAlongNormal > 60) {
            a.squash = math.max(a.squash, 0.35);
            b.squash = math.max(b.squash, 0.35);
          }
        }
      }
    }

    // ==== Chibi-marble collision (kick) ====
    // Treat the chibi as a screen-space rectangle (matches the
    // existing plate-collision footprint). On overlap, push the
    // marble out and add the chibi's velocity to it — head-on
    // hits transfer the most momentum, glancing brushes nudge.
    final chibiPos = chibi.position;
    final chibiScale = chibi.scale.x;
    final hw = _MarbleNode._chibiHalfW * chibiScale;
    final hh = _MarbleNode._chibiHalfH * chibiScale;
    final chibiLeft = chibiPos.x - hw;
    final chibiRight = chibiPos.x + hw;
    final chibiTop = chibiPos.y - hh;
    final chibiBottom = chibiPos.y + hh;
    final chibiVel = chibi.velocity;
    for (final m in idle) {
      // Closest point on the chibi rect to the marble center.
      final closestX = m.position.x.clamp(chibiLeft, chibiRight);
      final closestY = m.position.y.clamp(chibiTop, chibiBottom);
      final dx = m.position.x - closestX;
      final dy = m.position.y - closestY;
      final d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      // Overlap. Compute push-out normal: marble center → closest
      // point, but if the marble center is INSIDE the rect we
      // pick the smaller-overlap axis.
      double nx;
      double ny;
      double sep;
      if (d2 > 1e-6) {
        final d = math.sqrt(d2);
        nx = dx / d;
        ny = dy / d;
        sep = r - d;
      } else {
        // Center inside the rect — push out along smallest axis.
        final dxL = m.position.x - chibiLeft;
        final dxR = chibiRight - m.position.x;
        final dyT = m.position.y - chibiTop;
        final dyB = chibiBottom - m.position.y;
        final minH = math.min(dxL, dxR);
        final minV = math.min(dyT, dyB);
        if (minH < minV) {
          nx = (dxL < dxR) ? -1.0 : 1.0;
          ny = 0;
          sep = minH + r;
        } else {
          nx = 0;
          ny = (dyT < dyB) ? -1.0 : 1.0;
          sep = minV + r;
        }
      }
      m.position
        ..x += nx * sep
        ..y += ny * sep;

      // Kick: project chibi velocity onto the contact normal
      // (only the closing component) and add it (×kick gain) to
      // the marble. A standing-still chibi imparts nothing; a
      // sprinting head-on hit imparts maximum energy.
      final velAlongNormal = chibiVel.x * nx + chibiVel.y * ny;
      if (velAlongNormal > 0) {
        const kickGain = 1.8;
        m
          ..vx += nx * velAlongNormal * kickGain
          ..vy += ny * velAlongNormal * kickGain;
        if (velAlongNormal > 80) {
          m.squash = math.max(m.squash, 0.5);
        }
      } else {
        // Even if the chibi is stationary, when there's overlap
        // the marble should pop away a touch — pretend the
        // chibi gave it a 60px/s tap so it doesn't stick.
        m
          ..vx += nx * 60
          ..vy += ny * 60;
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _resolveWorldCollisions();
    _resolveJarCollisions();
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

    // Mason jar — narrow + tall test-tube proportions. Width
    // clamped to ~1.5× the marble diameter so marbles stack
    // mostly vertically (one per row), and aspect 1:3 makes the
    // body the dominant section so the pile climbs visibly.
    final jarW = (size.x * 0.18).clamp(100.0, 140.0);
    final jarH = jarW * 3.0;
    final jarSize = Vector2(jarW, jarH);
    jar = _Jar(size: jarSize)
      ..position = Vector2(
        (size.x - jarSize.x) / 2,
        size.y * 0.96 - jarSize.y,
      );
    add(jar);
    // Front-of-jar pass — extreme priority so it always renders
    // AFTER every marble. The marbles sit "inside the jar" because
    // this front layer's tinted glass + outline overlays them.
    add(_JarFront(jar: jar));

    // Chibi spawns mid-screen above the jar. Walks with depth
    // scaling — moves to top of screen → shrinks into the distance.
    chibi = ChibiCharacter(
      joystick: joystick,
      keyboardInput: keyboardInput,
    )
      ..position = Vector2(size.x * 0.7, size.y * 0.4)
      ..size = Vector2(120, 160);
    add(chibi);

    // Three world marbles, anchored RELATIVE to the jar's top
    // (instead of as a percentage of screen height). With the jar
    // pinned to the bottom 60-70% of screen, a fixed offset above
    // its rim keeps the rest slots in roughly the same spot
    // regardless of screen size. Lateral spread tied to the screen
    // width so the slots breathe across wide windows.
    // 5 marbles spread across the upper play area — Likert reading
    // order from most negative (left) to most positive (right). All
    // sit JUST BELOW THE QUESTION PLATE (not near the jar lid) so
    // they're the first thing the user sees + reaches.
    // Mood set: kiosk mode supplies 3 (BASECamp 3-point Likert);
    // sandbox falls back to all 5 faces.
    final activeMoods = moods ?? _kFaceMoods;
    final centerX = size.x / 2;
    final spread = math.min<double>(size.x * 0.40, 320);
    const restY = 130.0; // ~80px under the plate, accounting for safe-area.
    _marbleRestPositions = <Vector2>[
      for (var i = 0; i < activeMoods.length; i++)
        Vector2(
          activeMoods.length == 1
              ? centerX
              : centerX -
                  spread +
                  (i / (activeMoods.length - 1)) * spread * 2,
          restY,
        ),
    ];
    _marbles = <_MarbleNode>[
      for (var i = 0; i < activeMoods.length; i++)
        _MarbleNode(
          slotIdx: i,
          mood: activeMoods[i],
          // Tint comes from the mood's spec palette (not a shared
          // shuffle pool any more).
          tint: _kFacePalettes[activeMoods[i]]!.body,
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

/// 5-point Likert answer set in reading order — most negative
/// to most positive. Each marble in the world picks the next
/// mood from this list, one slot per face.
const _kFaceMoods = <FaceMood>[
  FaceMood.stronglyDisagree,
  FaceMood.disagree,
  FaceMood.notSure,
  FaceMood.agree,
  FaceMood.stronglyAgree,
];

// =====================================================================
// Survey screen
// =====================================================================

class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key, this.surveyId});

  /// When non-null, the screen runs in **kiosk mode** — loads the
  /// survey config, opens a session, and writes a Response per
  /// marble drop, advancing through the question list. When null,
  /// it runs in **sandbox mode** — the original chibi-marble
  /// playground with random questions and no persistence.
  final String? surveyId;

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

/// Maps the 5 painted face designs (F1-F5) onto BASECamp's
/// 3-point Likert answer codes (0 = disagree, 1 = kind of agree,
/// 2 = agree). The kiosk only spawns these three; the F2 (disagree)
/// and F4 (agree) designs from the spec are unused by BASECamp.
const Map<FaceMood, int> _kKioskMoodToValue = <FaceMood, int>{
  FaceMood.stronglyDisagree: 0,
  FaceMood.notSure: 1,
  FaceMood.stronglyAgree: 2,
};

const List<FaceMood> _kKioskMoods = <FaceMood>[
  FaceMood.stronglyDisagree,
  FaceMood.notSure,
  FaceMood.stronglyAgree,
];

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  late final _SurveyGame _game;

  /// Key on the question plate's outer Container. After every
  /// frame we read its bounds and push them down to the game so
  /// the chibi's collision check has a real screen-space rect to
  /// work with (Flutter does the layout; the game just consumes).
  final GlobalKey _plateKey = GlobalKey();

  // ——— Kiosk-mode state (null in sandbox mode) ———
  SurveyConfig? _survey;
  String? _sessionId;
  int _questionIndex = 0;
  int _childCount = 0;
  DateTime _questionStartedAt = DateTime.now();
  bool _showingAllDone = false;

  /// Timestamps of the most recent taps on the AppBar title.
  /// Three taps within 800ms → triple-tap; opens the PIN modal.
  /// Stored as a small ring buffer so we don't accumulate forever.
  final List<DateTime> _titleTapTimes = <DateTime>[];

  /// Random question used in sandbox mode only. Computed lazily
  /// the first time `_currentPrompt` reads it.
  late final _SurveyQuestion _sandboxQuestion =
      _kSurveyQuestions[math.Random().nextInt(_kSurveyQuestions.length)];

  bool get _isKiosk => widget.surveyId != null;

  /// What the question plate should display right now.
  String get _currentPrompt {
    if (!_isKiosk) return _sandboxQuestion.question;
    final survey = _survey;
    if (survey == null) return 'Loading…';
    if (_showingAllDone) return 'All done — thank you! 🎉';
    final q = survey.questions[_questionIndex];
    return q.prompt;
  }

  @override
  void initState() {
    super.initState();
    _game = _SurveyGame(
      moods: _isKiosk ? _kKioskMoods : null,
      onAnswered: _isKiosk ? _onMoodAnswered : null,
    );
    // Publish plate bounds once after first layout, then on every
    // build. The post-frame callback is the canonical "after
    // layout has settled" hook.
    WidgetsBinding.instance.addPostFrameCallback(_publishPlateBounds);
    if (_isKiosk) {
      unawaited(_initializeKiosk());
    }
  }

  Future<void> _initializeKiosk() async {
    final repo = ref.read(surveyRepositoryProvider);
    final survey = await repo.getById(widget.surveyId!);
    if (!mounted || survey == null) return;
    final sessionId = await repo.startSession(survey.id);
    if (!mounted) return;
    setState(() {
      _survey = survey;
      _sessionId = sessionId;
      _questionStartedAt = DateTime.now();
    });
    _playCurrentQuestionAudio();
  }

  /// Play (or re-play) the current question's prompt aloud, if
  /// audio mode allows. Silent for non-mood placeholders + the
  /// All-done overlay; the painter overlays already convey state.
  void _playCurrentQuestionAudio() {
    final survey = _survey;
    if (survey == null) return;
    if (survey.audioMode == SurveyAudioMode.silent) return;
    if (_showingAllDone) return;
    if (_questionIndex >= survey.questions.length) return;
    final q = survey.questions[_questionIndex];
    if (q.type != SurveyQuestionType.mood) return;
    final audio = ref.read(surveyAudioServiceProvider);
    // Fire-and-forget: audio failure is silent by design.
    unawaited(audio.playQuestion(survey.voice, q.prompt));
  }

  @override
  void dispose() {
    // If the teacher exits mid-flow, mark the session abandoned.
    final sessionId = _sessionId;
    if (sessionId != null && _isKiosk) {
      // Best-effort cleanup; if the app is being torn down the
      // write may not flush.
      unawaited(
        ref.read(surveyRepositoryProvider).endSession(
              sessionId,
              completed: false,
            ),
      );
    }
    super.dispose();
  }

  /// Called by `_SurveyGame.onAnswered` when a marble crosses the
  /// jar mouth in kiosk mode. Records the response, advances the
  /// question index, and (if we just answered the last question)
  /// fires the "All done!" beat.
  Future<void> _onMoodAnswered(FaceMood mood) async {
    final survey = _survey;
    final sessionId = _sessionId;
    if (survey == null || sessionId == null) return;
    final question = survey.questions[_questionIndex];
    if (question.type != SurveyQuestionType.mood) {
      // Shouldn't happen — non-mood questions skip the marble
      // world. Ignore the drop instead of polluting responses.
      return;
    }
    final moodValue = _kKioskMoodToValue[mood];
    if (moodValue == null) return; // F2/F4 designs aren't kiosk-spawned
    final reactionMs =
        DateTime.now().difference(_questionStartedAt).inMilliseconds;
    await ref.read(surveyRepositoryProvider).recordMoodAnswer(
          surveyId: survey.id,
          sessionId: sessionId,
          questionId: question.id,
          moodValue: moodValue,
          reactionTimeMs: reactionMs,
          isPractice: question.isPractice,
        );
    if (!mounted) return;
    // Maybe play a "you did it" nudge (10% probability, with the
    // service's own cooldown). Best-effort; silent by design when
    // audio mode is questions_only / silent.
    unawaited(
      ref.read(surveyAudioServiceProvider).maybePlayNudge(
            voice: survey.voice,
            audioMode: survey.audioMode,
            category: SurveyNudgeCategory.drop,
          ),
    );
    _advance();
  }

  /// Called when the kid commits a multi-select activity answer.
  /// Empty list = "skipped via commit" — same effect as Skip,
  /// recorded with no selections so the results sheet can tell
  /// "the kid saw the question" apart from "the kid never reached
  /// it" (the latter has no row at all).
  Future<void> _onMultiSelectCommit(List<String> selectedIds) async {
    final survey = _survey;
    final sessionId = _sessionId;
    if (survey == null || sessionId == null) return;
    final question = survey.questions[_questionIndex];
    final durationMs =
        DateTime.now().difference(_questionStartedAt).inMilliseconds;
    await ref.read(surveyRepositoryProvider).recordMultiSelectAnswer(
          surveyId: survey.id,
          sessionId: sessionId,
          questionId: question.id,
          selectedOptionIds: selectedIds,
          durationMs: durationMs,
          isPractice: question.isPractice,
        );
    if (!mounted) return;
    _advance();
  }

  /// Called by the open-ended overlay once the kid taps stop.
  /// Live STT means the transcription is already final by the
  /// time we get here — write it directly, no follow-up update
  /// needed. Audio file isn't kept (live streaming flow).
  Future<void> _onOpenEndedCommit(
    String transcription,
    int durationMs,
  ) async {
    final survey = _survey;
    final sessionId = _sessionId;
    if (survey == null || sessionId == null) return;
    final question = survey.questions[_questionIndex];
    await ref.read(surveyRepositoryProvider).recordOpenEndedAnswer(
          surveyId: survey.id,
          sessionId: sessionId,
          questionId: question.id,
          transcription: transcription,
          durationMs: durationMs,
          isPractice: question.isPractice,
        );
    if (!mounted) return;
    _advance();
  }

  /// Move to the next question, or trigger the end-of-survey beat
  /// if we just finished the last one.
  void _advance() {
    final survey = _survey;
    if (survey == null) return;
    if (_questionIndex + 1 >= survey.questions.length) {
      _onSurveyComplete();
    } else {
      setState(() {
        _questionIndex += 1;
        _questionStartedAt = DateTime.now();
      });
      _playCurrentQuestionAudio();
    }
  }

  /// "All done!" close beat. Closes the session as completed,
  /// shows the celebration overlay for ~3s, then resets the
  /// kiosk for the next child.
  void _onSurveyComplete() {
    final sessionId = _sessionId;
    final survey = _survey;
    if (sessionId == null || survey == null) return;
    setState(() {
      _showingAllDone = true;
      _childCount += 1;
    });
    // Close this child's session. Best effort — UI reset is the
    // user-visible signal that things are progressing.
    unawaited(
      ref.read(surveyRepositoryProvider).endSession(
            sessionId,
            completed: true,
          ),
    );
    Future.delayed(const Duration(seconds: 3), _resetForNextChild);
  }

  /// Triple-tap on the AppBar title is the only way out of the
  /// kiosk. Three taps within 800ms → opens the PIN modal. The
  /// ring buffer keeps memory bounded; we only ever look at the
  /// last 3 timestamps.
  void _onTitleTap() {
    if (!_isKiosk) return;
    final now = DateTime.now();
    _titleTapTimes.add(now);
    while (_titleTapTimes.length > 3) {
      _titleTapTimes.removeAt(0);
    }
    if (_titleTapTimes.length < 3) return;
    final span =
        _titleTapTimes.last.difference(_titleTapTimes.first).inMilliseconds;
    if (span > 800) return;
    _titleTapTimes.clear();
    unawaited(_handleExitTap());
  }

  Future<void> _handleExitTap() async {
    final survey = _survey;
    if (survey == null) return;
    // Pause any audio so the modal isn't fighting a question read.
    final audio = ref.read(surveyAudioServiceProvider);
    await audio.stop();
    if (!mounted) return;
    final ok = await KioskExitPinModal.show(context, survey);
    if (!mounted) return;
    if (ok) {
      // dispose() closes the session as `completed: false` —
      // exactly what we want for "teacher exited mid-flow."
      Navigator.of(context).pop();
    }
  }

  /// Reset state for the next child to walk up.
  Future<void> _resetForNextChild() async {
    if (!mounted) return;
    final survey = _survey;
    if (survey == null) return;
    final repo = ref.read(surveyRepositoryProvider);
    final newSessionId = await repo.startSession(survey.id);
    if (!mounted) return;
    setState(() {
      _sessionId = newSessionId;
      _questionIndex = 0;
      _questionStartedAt = DateTime.now();
      _showingAllDone = false;
    });
    _playCurrentQuestionAudio();
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
    final scaffold = Scaffold(
      appBar: AppBar(
        // Kiosk mode: title is site + classroom and is tappable
        // (3 taps within 800ms → PIN modal). The system back
        // button is also hidden because PopScope blocks it.
        automaticallyImplyLeading: !_isKiosk,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTitleTap,
          child: _isKiosk
              ? _kioskTitle(theme)
              : const Text('New Survey'),
        ),
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
                _isKiosk
                    ? 'Child ${_childCount + 1} · '
                        'Question ${_questionIndex + 1} of '
                        '${_survey?.questions.length ?? '…'}'
                    : 'Chibi sandbox · joystick / WASD / arrows · '
                        'jump = tap or space',
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
          // Celebration burst — fullscreen face-emoji particles
          // when a marble lands in the jar. Sits ABOVE the game
          // (so emojis fly over the chibi) but BELOW the plate +
          // FAB (so they don't occlude UI). IgnorePointer is
          // baked into the overlay so it never absorbs taps.
          Positioned.fill(
            child: _CelebrationOverlay(trigger: _game.celebrationTrigger),
          ),
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
                      _currentPrompt,
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
          // Kiosk-only overlays (no-op in sandbox mode).
          if (_isKiosk) ..._buildKioskOverlays(theme),
        ],
      ),
    );
    // Kiosk mode: PopScope blocks the system back gesture so a
    // child can't accidentally exit. The only way out is the
    // teacher's PIN-gated triple-tap on the title. Sandbox mode
    // pops normally.
    if (!_isKiosk) return scaffold;
    return PopScope(canPop: false, child: scaffold);
  }

  /// Title widget for kiosk mode — site name on top with the
  /// classroom underneath. Tap-target stays full-width so a
  /// teacher can land taps confidently.
  Widget _kioskTitle(ThemeData theme) {
    final survey = _survey;
    if (survey == null) {
      return const Text('Loading…');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          survey.siteName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          survey.classroom,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Overlays drawn on top of the game in kiosk mode:
  ///
  ///   * For non-Likert questions (multi-select / open-ended), a
  ///     full-screen "Coming in next slice — tap to skip"
  ///     placeholder. Slice 3 / 3.5 will replace these with real
  ///     question UIs.
  ///   * After the last question is answered, an "All done!"
  ///     celebration that sits for 3s then auto-resets to the
  ///     next child.
  List<Widget> _buildKioskOverlays(ThemeData theme) {
    final survey = _survey;
    if (survey == null) {
      return <Widget>[
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0xCCFFFFFF),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_showingAllDone) {
      return <Widget>[
        Positioned.fill(
          child: ColoredBox(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'All done!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Thank you. Pass it along to the next friend.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      '$_childCount response${_childCount == 1 ? '' : 's'} so far',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }
    // Non-Likert question? Show a placeholder skip card. The kiosk
    // currently only handles `mood` questions; multi-select +
    // open-ended ships in slice 3.5.
    final q = survey.questions[_questionIndex];
    if (q.type == SurveyQuestionType.multiSelect) {
      return <Widget>[
        Positioned.fill(
          child: MultiSelectQuestionOverlay(
            // Re-key on the question id so switching from question
            // N to N+1 (both multiSelect) tears down + rebuilds
            // the overlay, clearing the selection set + re-reading
            // the new prompt.
            key: ValueKey('ms_${q.id}'),
            question: q,
            voice: survey.voice,
            audioMode: survey.audioMode,
            onCommit: _onMultiSelectCommit,
            onSkip: _advance,
          ),
        ),
      ];
    }
    if (q.type == SurveyQuestionType.openEnded) {
      return <Widget>[
        Positioned.fill(
          child: OpenEndedQuestionOverlay(
            key: ValueKey('oe_${q.id}'),
            question: q,
            voice: survey.voice,
            audioMode: survey.audioMode,
            onCommit: _onOpenEndedCommit,
            onSkip: _advance,
          ),
        ),
      ];
    }
    return const <Widget>[];
  }
}

// (The Flutter `_MarbleButton` + `_MarbleFacePainter` widgets used
// to live here. They're gone — the marbles are now world-space
// `_MarbleNode` components the chibi walks up to and picks up.)

// =====================================================================
// Celebration overlay — fullscreen face-emoji particle burst
// =====================================================================

/// Fullscreen "you picked one!" feedback. Listens to a
/// `ValueNotifier<_CelebrationEvent?>` from the game; on every
/// fire it bursts ~30 face emojis (matching the dropped mood +
/// tint) up from the bottom of the screen. They float, spin a
/// touch, and fade — no layout impact, no input absorption (sits
/// inside an `IgnorePointer`).
///
/// Rendered via a single `CustomPaint` over the whole Stack — the
/// particles are not Flame components so they overlay the chibi
/// world cleanly without joining the Flame priority sort.
class _CelebrationOverlay extends StatefulWidget {
  const _CelebrationOverlay({required this.trigger});

  final ValueNotifier<_CelebrationEvent?> trigger;

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  final List<_CelebrationParticle> _particles = <_CelebrationParticle>[];
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _lastSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_onTrigger);
    _ticker = createTicker(_tick);
    // Ticker.start() returns a Future that completes when the
    // ticker is stopped. We dispose() in dispose(), so this is a
    // safe fire-and-forget.
    // ignore: discarded_futures
    _ticker.start();
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_onTrigger);
    _ticker.dispose();
    super.dispose();
  }

  void _onTrigger() {
    final ev = widget.trigger.value;
    if (ev == null || ev.seq == _lastSeq) return;
    _lastSeq = ev.seq;
    final size = MediaQuery.of(context).size;
    final rng = math.Random(ev.seq * 977);
    setState(() {
      for (var i = 0; i < 28; i++) {
        // Spawn from across the bottom edge with random horizontal
        // velocity, strong upward kick, and a per-particle lifespan.
        // `spawnDelay` staggers them so the burst rolls out across
        // ~200ms instead of all spawning on frame 1 (more "stream"
        // less "wall of confetti").
        _particles.add(_CelebrationParticle(
          mood: ev.mood,
          tint: ev.tint,
          x: rng.nextDouble() * size.width,
          y: size.height + 40,
          vx: (rng.nextDouble() - 0.5) * 200,
          vy: -(260 + rng.nextDouble() * 280),
          life: 1.6 + rng.nextDouble() * 0.8,
          radius: 18 + rng.nextDouble() * 16,
          spin: (rng.nextDouble() - 0.5) * 4,
          spawnDelay: i * 0.025,
          phaseSeed: rng.nextInt(1 << 20),
        ));
      }
    });
  }

  void _tick(Duration elapsed) {
    final raw = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_particles.isEmpty) return;
    // Cap dt so a tab-resume doesn't fast-forward physics by 5s.
    final dt = raw.clamp(0.0, 0.05);
    setState(() {
      for (final p in _particles) {
        p.age += dt;
        if (p.age < p.spawnDelay) continue;
        // Light gravity; particles still fall, but slower than the
        // marbles so they linger on screen for a celebratory moment.
        p
          ..x += p.vx * dt
          ..y += p.vy * dt
          ..vy += 240 * dt
          ..rotation += p.spin * dt;
      }
      _particles.removeWhere((p) => p.age - p.spawnDelay > p.life);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _CelebrationPainter(particles: _particles),
      ),
    );
  }
}

class _CelebrationParticle {
  _CelebrationParticle({
    required this.mood,
    required this.tint,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.radius,
    required this.spin,
    required this.spawnDelay,
    required this.phaseSeed,
  });

  final FaceMood mood;
  final Color tint;
  double x;
  double y;
  double vx;
  double vy;
  final double life;
  final double radius;
  final double spin;
  final double spawnDelay;
  final int phaseSeed;
  double age = 0;
  double rotation = 0;
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({required this.particles});

  final List<_CelebrationParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.age < p.spawnDelay) continue;
      final t = p.age - p.spawnDelay;
      // Fade-in over the first 0.15s, fade-out over the last 0.4s.
      final fadeIn = (t / 0.15).clamp(0.0, 1.0);
      final remaining = p.life - t;
      final fadeOut = (remaining / 0.4).clamp(0.0, 1.0);
      final alpha = (fadeIn * fadeOut).clamp(0.0, 1.0);
      // Pop-and-shrink scale: 1.15 at peak, down to 0.7 at end of
      // life. Keeps the burst feeling springy.
      final scaleT = (t / p.life).clamp(0.0, 1.0);
      final scale = 1.15 - 0.45 * scaleT;
      canvas
        ..save()
        ..translate(p.x, p.y)
        ..rotate(p.rotation)
        ..scale(scale, scale);

      // Alpha-aware fills/strokes — repaint per-particle since the
      // alpha varies.
      final fill = Paint()
        ..color = p.tint.withValues(alpha: alpha);
      final outlineA = Paint()
        ..color = const Color(0xFF1A1A1A).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas
        ..drawCircle(Offset.zero, p.radius, fill)
        ..drawCircle(Offset.zero, p.radius, outlineA);
      // Face. The shared painter doesn't accept an alpha override,
      // so we apply one via a saveLayer when the particle is
      // mid-fade. Cheap enough at ~30 particles.
      if (alpha < 0.99) {
        final paint = Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: alpha),
            BlendMode.modulate,
          );
        canvas.saveLayer(
          Rect.fromCircle(center: Offset.zero, radius: p.radius * 1.2),
          paint,
        );
      }
      // Each particle reuses the per-face painter — its own t means
      // the burst face animates independently of the world marble.
      _FacePainter(mood: p.mood, t: t).paintAt(canvas, Offset.zero, p.radius);
      if (alpha < 0.99) canvas.restore();

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter old) => true;
}
