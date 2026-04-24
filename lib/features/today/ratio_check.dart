import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';

/// Ratio-check result for a single group at a single moment in time.
///
/// Holds counts rather than the raw lists that produced them so the UI
/// layer can render a compact chip without re-doing the math. Pure data
/// — no providers, no Drift — so it's trivially unit-testable.
///
/// Threshold is carried on the value so the UI and future settings
/// knob can agree on the same answer without re-plumbing a constant
/// through every call site. `8` is the current default (see
/// `_ratioFloor` in `group_today_card.dart`).
// TODO: promote `threshold` to `ProgramSettings` once the settings
// feature grows per-program ratio rules.
class GroupRatioNow {
  const GroupRatioNow({
    required this.groupId,
    required this.childrenInGroupNow,
    required this.adultsOnShiftForGroupNow,
    required this.threshold,
  });

  final String groupId;
  final int childrenInGroupNow;
  final int adultsOnShiftForGroupNow;
  final int threshold;

  /// "Under ratio" means more kids than the threshold allows per
  /// adult. With zero adults the rule collapses to "any kids present
  /// is a problem" — the only safe floor when nobody's on shift.
  bool get isUnderRatio {
    if (adultsOnShiftForGroupNow == 0) return childrenInGroupNow > 0;
    return (childrenInGroupNow / adultsOnShiftForGroupNow) > threshold;
  }

  /// Short display: "12:2 (6.0:1)" — kids:adults and the ratio. Zero-
  /// adults renders as "12 kids · no adult" since a ratio with a zero
  /// denominator reads as "/0" in headline chrome and confuses at a
  /// glance.
  String get display => adultsOnShiftForGroupNow == 0
      ? '$childrenInGroupNow kids · no adult'
      : '$childrenInGroupNow:$adultsOnShiftForGroupNow '
          '(${(childrenInGroupNow / adultsOnShiftForGroupNow).toStringAsFixed(1)}:1)';
}

/// Parses "HH:mm" into minutes-since-midnight. Small helper kept
/// private — the rest of the file uses it in several places.
int _parseHHmm(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// True when `nowMinutes` falls in the half-open span
/// `[start, end)` described by HH:mm strings. Null span means "no
/// such window" and always returns false.
bool _spanCoversNow({
  required String? start,
  required String? end,
  required int nowMinutes,
}) {
  if (start == null || end == null) return false;
  final s = _parseHHmm(start);
  final e = _parseHHmm(end);
  return nowMinutes >= s && nowMinutes < e;
}

/// Is this child physically present in the room right now?
///
/// * `null` expected arrival or pickup → treat as "all-day present"
///   (drop-in kids, kids with no standing times). Safer default for
///   ratio: counting a kid we can't timestamp is strictly more
///   cautious than silently dropping them.
/// * expected arrival `> now` → not here yet (pre-arrival). Excluded.
/// * expected pickup `<= now` → already gone. Excluded.
///
/// Override rules: the per-day `ChildScheduleOverride` beats the
/// standing times when present. A teacher logs "mom texted, running
/// late" and we use 9:30 instead of the standing 8:30.
bool _childPresentNow({
  required Child child,
  required ChildScheduleOverride? override,
  required int nowMinutes,
}) {
  final arrival =
      override?.expectedArrivalOverride ?? child.expectedArrival;
  final pickup = override?.expectedPickupOverride ?? child.expectedPickup;
  if (arrival != null) {
    if (nowMinutes < _parseHHmm(arrival)) return false;
  }
  if (pickup != null) {
    if (nowMinutes >= _parseHHmm(pickup)) return false;
  }
  return true;
}

/// Is an adult on break / break2 / lunch at `nowMinutes` given their
/// availability row for today? Any row that covers now with a populated
/// break window counts — an adult with two availability rows on the
/// same day (morning + afternoon splits) is on break if either row
/// says so.
bool _adultOnBreakNow({
  required List<AdultAvailabilityData> rowsForAdultToday,
  required int nowMinutes,
}) {
  for (final row in rowsForAdultToday) {
    if (_spanCoversNow(
      start: row.breakStart,
      end: row.breakEnd,
      nowMinutes: nowMinutes,
    )) {
      return true;
    }
    if (_spanCoversNow(
      start: row.break2Start,
      end: row.break2End,
      nowMinutes: nowMinutes,
    )) {
      return true;
    }
    if (_spanCoversNow(
      start: row.lunchStart,
      end: row.lunchEnd,
      nowMinutes: nowMinutes,
    )) {
      return true;
    }
  }
  return false;
}

/// Does `rowsForAdultToday` include any availability window that
/// covers `nowMinutes`? "On the clock at all right now" — the break
/// check above is a separate, additive filter.
bool _adultOnShiftNow({
  required List<AdultAvailabilityData> rowsForAdultToday,
  required int nowMinutes,
}) {
  for (final row in rowsForAdultToday) {
    final s = _parseHHmm(row.startTime);
    final e = _parseHHmm(row.endTime);
    if (nowMinutes >= s && nowMinutes < e) return true;
  }
  return false;
}

/// Is `adult` currently leading `groupId`? Two ways to qualify:
///   1. Static anchor: `anchoredGroupId == groupId` AND role is lead.
///   2. Per-day timeline block with `role == 'lead'` and
///      `groupId == groupId` covering the current minute.
///
/// Multi-lead groups naturally fall out — the caller iterates every
/// adult, so both leads get counted the same way.
bool _adultLeadsGroupNow({
  required Adult adult,
  required String groupId,
  required List<AdultDayBlock> adultBlocksToday,
  required int nowMinutes,
}) {
  final anchorMatches =
      AdultRole.fromDb(adult.adultRole) == AdultRole.lead &&
          adult.anchoredGroupId == groupId;
  if (anchorMatches) {
    // Static anchor is enough — no need to also require a timeline
    // block. A lead with no day-block overrides works the normal case.
    return true;
  }
  for (final block in adultBlocksToday) {
    if (block.adultId != adult.id) continue;
    if (block.groupId != groupId) continue;
    if (AdultBlockRole.fromDb(block.role) != AdultBlockRole.lead) continue;
    final s = _parseHHmm(block.startTime);
    final e = _parseHHmm(block.endTime);
    if (nowMinutes >= s && nowMinutes < e) return true;
  }
  return false;
}

/// Pure compute: produce a [GroupRatioNow] for the moment in `now`.
///
/// See header comments on [_childPresentNow] / [_adultLeadsGroupNow] /
/// [_adultOnBreakNow] for the individual rules. This top-level
/// function just composes them and counts what survives.
GroupRatioNow computeGroupRatioNow({
  required String groupId,
  required List<Child> childrenInGroup,
  required List<Adult> allAdults,
  required List<AdultAvailabilityData> allAvailability,
  required List<AdultDayBlock> todayBlocks,
  required DateTime now,
  Map<String, ChildScheduleOverride> overridesByChild =
      const <String, ChildScheduleOverride>{},
  int threshold = 8,
}) {
  final nowMinutes = now.hour * 60 + now.minute;
  final isoWeekday = now.weekday;

  var presentCount = 0;
  for (final child in childrenInGroup) {
    final override = overridesByChild[child.id];
    if (_childPresentNow(
      child: child,
      override: override,
      nowMinutes: nowMinutes,
    )) {
      presentCount++;
    }
  }

  // Index availability rows for *today* per adult so the per-adult
  // checks don't repeatedly scan the whole list.
  final availByAdultToday = <String, List<AdultAvailabilityData>>{};
  for (final row in allAvailability) {
    if (row.dayOfWeek != isoWeekday) continue;
    (availByAdultToday[row.adultId] ??= <AdultAvailabilityData>[])
        .add(row);
  }

  // Pre-filter blocks to today — the caller can hand us the full
  // week's blocks or just today's, either way we narrow here.
  final blocksToday = todayBlocks
      .where((b) => b.dayOfWeek == isoWeekday)
      .toList(growable: false);

  var adultCount = 0;
  for (final adult in allAdults) {
    final rows =
        availByAdultToday[adult.id] ?? const <AdultAvailabilityData>[];
    if (rows.isEmpty) continue;
    if (!_adultOnShiftNow(
      rowsForAdultToday: rows,
      nowMinutes: nowMinutes,
    )) {
      continue;
    }
    if (_adultOnBreakNow(
      rowsForAdultToday: rows,
      nowMinutes: nowMinutes,
    )) {
      continue;
    }
    if (!_adultLeadsGroupNow(
      adult: adult,
      groupId: groupId,
      adultBlocksToday: blocksToday,
      nowMinutes: nowMinutes,
    )) {
      continue;
    }
    adultCount++;
  }

  return GroupRatioNow(
    groupId: groupId,
    childrenInGroupNow: presentCount,
    adultsOnShiftForGroupNow: adultCount,
    threshold: threshold,
  );
}
