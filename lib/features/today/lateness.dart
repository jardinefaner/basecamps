import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/attendance/attendance_repository.dart';

/// How many minutes past a child's expected arrival before the flag
/// fires. Gives a grace window so a bus getting stuck in traffic for
/// 8 minutes doesn't page the teacher. Hardcoded for now; if we add
/// a program-settings surface later this becomes a configurable knob
/// on that screen. Mirrored in `lateness_test.dart` — keep in sync.
const int latenessGraceMinutes = 15;

/// A single lateness flag rendered on Today. The strip groups these
/// by severity and renders the worst ones first.
///
/// Non-late children never produce one of these — the flag list only
/// surfaces kids who are actually problematic to look at.
class LatenessFlag {
  const LatenessFlag({
    required this.child,
    required this.expectedArrival,
    required this.minutesLate,
    this.note,
  });

  final Child child;

  /// The time the child was expected ("HH:mm"), for display in the
  /// flag row ("expected 8:30").
  final String expectedArrival;

  /// Minutes past `expectedArrival + grace` at the detection moment.
  /// UI uses this both for "22 min late" copy and for sort order.
  final int minutesLate;

  /// Free-form override note when present ("mom texted, running late
  /// — expect 9:30"). Shown under the bare "N min late" line so the
  /// teacher sees the explanation without tapping through.
  final String? note;
}

/// Computes the current lateness flags for [now] across [children]
/// given their [attendance] records and [overrides]. Pure function —
/// everything needed is passed in so it can be unit-tested without
/// standing up Drift or Riverpod.
///
/// A child earns a flag iff ALL of:
///   1. they have an expected arrival (standing OR overridden),
///   2. `now` is past `expectedArrival + graceMinutes`,
///   3. their [AttendanceStatus] for today is NOT
///      [AttendanceStatus.present] (if they're checked in, they
///      weren't late — or weren't late-enough-to-be-a-problem).
///
/// Absent children are NOT flagged: the teacher has already acted on
/// them (marked absent), so surfacing them as "late" would be noise.
List<LatenessFlag> computeLatenessFlags({
  required DateTime now,
  required List<Child> children,
  required Map<String, AttendanceRecord> attendance,
  required Map<String, ChildScheduleOverride> overrides,
  int graceMinutes = latenessGraceMinutes,
}) {
  final nowMinutes = now.hour * 60 + now.minute;
  final flags = <LatenessFlag>[];
  for (final child in children) {
    // Absent / present kids are resolved — skip.
    final status = attendance[child.id]?.status;
    if (status == AttendanceStatus.present) continue;
    if (status == AttendanceStatus.absent) continue;

    final ov = overrides[child.id];
    final expected = ov?.expectedArrivalOverride ?? child.expectedArrival;
    if (expected == null) continue;

    final expectedMin = _parseHHmm(expected);
    if (expectedMin == null) continue;
    final deadline = expectedMin + graceMinutes;
    if (nowMinutes < deadline) continue;

    flags.add(
      LatenessFlag(
        child: child,
        expectedArrival: expected,
        minutesLate: nowMinutes - deadline,
        note: ov?.note,
      ),
    );
  }
  // Most-late first — if 5 kids are late, the 40-minute one is the
  // one that needs attention, not the one who just crossed the line.
  flags.sort((a, b) => b.minutesLate.compareTo(a.minutesLate));
  return flags;
}

int? _parseHHmm(String s) {
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// Grace window before a not-yet-picked-up child trips the overdue
/// flag. Same knob as [latenessGraceMinutes] but independent — "late
/// pickup" and "late arrival" often have different tolerances in
/// practice (parents running 5 min late at pickup is routine; kids
/// at drop-off is more of a beat). Still hardcoded; see the note on
/// the arrival grace for when/where to make it configurable.
const int pickupGraceMinutes = 15;

/// A child still on-site past their expected pickup + grace. Mirrors
/// [LatenessFlag] in shape so the flags strip can render both lists
/// with the same row component.
class OverduePickupFlag {
  const OverduePickupFlag({
    required this.child,
    required this.expectedPickup,
    required this.minutesOverdue,
    this.note,
  });

  final Child child;
  final String expectedPickup;
  final int minutesOverdue;
  final String? note;
}

/// Computes overdue-pickup flags for [now] across [children] given
/// their [attendance] + [overrides]. Pure like [computeLatenessFlags];
/// everything is passed in so the overdue path is unit-testable.
///
/// A child earns a flag iff ALL of:
///   1. expected pickup (standing OR overridden) is set,
///   2. their attendance row is 'present' (they actually came today),
///   3. their pickup hasn't been recorded yet (`pickupTime == null`),
///   4. `now` is past `expectedPickup + graceMinutes`.
///
/// Kids with no row (never checked in) can't be overdue. Kids
/// already picked up (pickupTime non-null) fall out by rule 3, so
/// the strip empties naturally as parents arrive.
List<OverduePickupFlag> computeOverduePickupFlags({
  required DateTime now,
  required List<Child> children,
  required Map<String, AttendanceRecord> attendance,
  required Map<String, ChildScheduleOverride> overrides,
  int graceMinutes = pickupGraceMinutes,
}) {
  final nowMinutes = now.hour * 60 + now.minute;
  final flags = <OverduePickupFlag>[];
  for (final child in children) {
    final record = attendance[child.id];
    if (record == null) continue;
    if (record.status != AttendanceStatus.present) continue;
    if (record.pickupTime != null) continue;

    final ov = overrides[child.id];
    final expected = ov?.expectedPickupOverride ?? child.expectedPickup;
    if (expected == null) continue;

    final expectedMin = _parseHHmm(expected);
    if (expectedMin == null) continue;
    final deadline = expectedMin + graceMinutes;
    if (nowMinutes < deadline) continue;

    flags.add(
      OverduePickupFlag(
        child: child,
        expectedPickup: expected,
        minutesOverdue: nowMinutes - deadline,
        note: ov?.note,
      ),
    );
  }
  // Most-overdue first — the kid who's been waiting 40 min needs
  // attention before the one who just crossed the grace line.
  flags.sort((a, b) => b.minutesOverdue.compareTo(a.minutesOverdue));
  return flags;
}
