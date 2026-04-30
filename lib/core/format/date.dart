/// Shared date helpers. The audit found 12+ open-coded
/// `DateTime(d.year, d.month, d.day)` strips, plus 5 different
/// `DateFormat.MMMd()` "Apr 1 – Apr 5" range patterns and 4
/// "yMMMd().add_jm()" timestamp patterns. This file is the one
/// source of truth.
library;

import 'package:intl/intl.dart';

extension DateOnly on DateTime {
  /// Strip time-of-day to local midnight. Used everywhere we
  /// compare or store calendar-day values without a time
  /// component (the `attendance.date`, `schedule_entries.date`,
  /// `themes.start_date`, etc. columns all encode this).
  ///
  /// Replaces inline `DateTime(d.year, d.month, d.day)` that was
  /// scattered across the schedule resolver, attendance pass,
  /// today screen, calendar synthesizer, and several wizards.
  DateTime get dayOnly => DateTime(year, month, day);
}

/// True iff [a] and [b] fall on the same calendar day in local
/// time. Doesn't care about hours, minutes, or timezone offset
/// inside the same TZ. Handles null on either side as "not the
/// same day."
bool isSameCalendarDate(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// `Apr 1 – Apr 5` style range label. Used by themes, programs,
/// curriculum, schedule editor, and several places that show a
/// week / theme span. Same-day spans collapse to a single date
/// (`Apr 1`) instead of `Apr 1 – Apr 1`.
String formatDateRange(DateTime start, DateTime end) {
  final fmt = DateFormat.MMMd();
  if (isSameCalendarDate(start, end)) return fmt.format(start);
  return '${fmt.format(start)} – ${fmt.format(end)}';
}

/// `Apr 28, 2026 9:30 PM` style timestamp. Used for observation
/// cards, sync status, and form submission lists. The previous
/// open-coded form was `DateFormat.yMMMd().add_jm().format(t)`
/// — this wraps it so the entire pipeline shares the same
/// rendering rules.
String formatTimestamp(DateTime t) =>
    DateFormat.yMMMd().add_jm().format(t);

/// Short timestamp without the year — `Apr 28, 9:30 PM`. Used
/// in surfaces where context already implies the year (a
/// "logged today" badge, the right-now strip).
String formatTimestampShort(DateTime t) =>
    '${DateFormat.MMMd().format(t)}, ${DateFormat.jm().format(t)}';
