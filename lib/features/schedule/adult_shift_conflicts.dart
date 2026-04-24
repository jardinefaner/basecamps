import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';

/// Classifies why an assigned adult's shift clashes with a scheduled
/// activity — a break/lunch window overlap, off-shift bounds, or no
/// availability at all for that weekday.
enum ShiftConflictKind {
  /// Overlaps the adult's first break window.
  breakWindow,

  /// Overlaps the adult's second break window (v35 addition).
  break2Window,

  /// Overlaps the adult's lunch window.
  lunchWindow,

  /// Scheduled before the adult's availability starts or after it ends.
  offShift,

  /// Adult has no availability row for this weekday at all.
  noAvailabilityToday,
}

/// One shift-based conflict attached to a [ScheduleItem]. Collected
/// alongside the existing activity-vs-activity conflict info so the
/// Today screen can light up a red dot + render a matching section in
/// the conflict sheet.
class ShiftConflict {
  const ShiftConflict({
    required this.adultId,
    required this.kind,
    required this.reason,
  });

  final String adultId;
  final ShiftConflictKind kind;

  /// Human-readable message — "On break 10:30–10:45",
  /// "Outside Sarah's shift (9:00a–3:00p)", etc.
  final String reason;
}

/// For each item in [items] with an assigned adult, look up that
/// adult's availability for the given [isoWeekday] and flag
/// break/lunch overlaps, off-shift times, or a missing-shift day.
///
/// - Skips items with no [ScheduleItem.adultId].
/// - Skips full-day items entirely — they'd always overlap a shift and
///   don't participate in hour-by-hour availability math.
///
/// [availabilityByAdult] is "every availability row grouped by
/// adultId", typically
/// `ref.watch(allAvailabilityProvider).asData?.value` folded into a
/// map.
///
/// [adultsById] supplies adult names for human-readable reasons.
Map<String, List<ShiftConflict>> detectAdultShiftConflicts({
  required List<ScheduleItem> items,
  required Map<String, List<AdultAvailabilityData>> availabilityByAdult,
  required Map<String, Adult> adultsById,
  required int isoWeekday,
}) {
  final result = <String, List<ShiftConflict>>{};

  for (final item in items) {
    final adultId = item.adultId;
    if (adultId == null) continue;
    // Full-day activities (Tax Day, Teacher Appreciation, trips rolled
    // into the schedule as full-day entries) would always spill over
    // a shift and drown the user in redundant flags.
    if (item.isFullDay) continue;

    final adultName = adultsById[adultId]?.name ?? 'This adult';
    final rows = (availabilityByAdult[adultId] ?? const <AdultAvailabilityData>[])
        .where((r) => r.dayOfWeek == isoWeekday)
        .toList();

    if (rows.isEmpty) {
      (result[item.id] ??= <ShiftConflict>[]).add(
        ShiftConflict(
          adultId: adultId,
          kind: ShiftConflictKind.noAvailabilityToday,
          reason: '$adultName has no shift on this day',
        ),
      );
      continue;
    }

    // Shift bounds = earliest start ↔ latest end across every row
    // for this weekday. Split shifts (two rows) collapse to one
    // envelope; mid-day gap between rows is effectively treated as
    // "on shift" rather than "off shift" — the user can add a break
    // window if they want mid-day flagging.
    var earliestStart = _minutesFromHhmm(rows.first.startTime);
    var latestEnd = _minutesFromHhmm(rows.first.endTime);
    for (final r in rows.skip(1)) {
      final s = _minutesFromHhmm(r.startTime);
      final e = _minutesFromHhmm(r.endTime);
      if (s < earliestStart) earliestStart = s;
      if (e > latestEnd) latestEnd = e;
    }

    final offShift =
        item.startMinutes < earliestStart || item.endMinutes > latestEnd;
    if (offShift) {
      (result[item.id] ??= <ShiftConflict>[]).add(
        ShiftConflict(
          adultId: adultId,
          kind: ShiftConflictKind.offShift,
          reason: "Outside $adultName's shift "
              '(${_fmt(earliestStart)}–${_fmt(latestEnd)})',
        ),
      );
      // De-dupe: a break inside an already-off-shift item is
      // redundant. Move on to the next item.
      continue;
    }

    // On-shift → check the inner break / break2 / lunch windows.
    for (final r in rows) {
      _maybeAddWindowClash(
        result: result,
        item: item,
        adultId: adultId,
        adultName: adultName,
        startHhmm: r.breakStart,
        endHhmm: r.breakEnd,
        kind: ShiftConflictKind.breakWindow,
        label: 'break',
      );
      _maybeAddWindowClash(
        result: result,
        item: item,
        adultId: adultId,
        adultName: adultName,
        startHhmm: r.break2Start,
        endHhmm: r.break2End,
        kind: ShiftConflictKind.break2Window,
        label: 'afternoon break',
      );
      _maybeAddWindowClash(
        result: result,
        item: item,
        adultId: adultId,
        adultName: adultName,
        startHhmm: r.lunchStart,
        endHhmm: r.lunchEnd,
        kind: ShiftConflictKind.lunchWindow,
        label: 'lunch',
      );
    }
  }

  return result;
}

void _maybeAddWindowClash({
  required Map<String, List<ShiftConflict>> result,
  required ScheduleItem item,
  required String adultId,
  required String adultName,
  required String? startHhmm,
  required String? endHhmm,
  required ShiftConflictKind kind,
  required String label,
}) {
  if (startHhmm == null || endHhmm == null) return;
  final s = _minutesFromHhmm(startHhmm);
  final e = _minutesFromHhmm(endHhmm);
  if (s >= e) return; // Malformed row — skip silently.
  final overlaps = item.startMinutes < e && s < item.endMinutes;
  if (!overlaps) return;
  (result[item.id] ??= <ShiftConflict>[]).add(
    ShiftConflict(
      adultId: adultId,
      kind: kind,
      reason: "Overlaps $adultName's $label "
          '(${_fmt(s)}–${_fmt(e)})',
    ),
  );
}

int _minutesFromHhmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Compact "9a" / "10:30a" / "12p" form — matches the existing
/// conflict sheet's `_formatTime` style so reasons read the same
/// whether they came from the activity detector or the shift
/// detector.
String _fmt(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final period = h < 12 ? 'a' : 'p';
  final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return '$hour12$mm$period';
}
