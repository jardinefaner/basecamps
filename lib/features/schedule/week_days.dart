// The set of weekdays the schedule UI displays. The program is
// Monday–Friday only, so Saturday and Sunday are intentionally absent
// from every chip picker, copy-day selector, and week grid column.
// `dayOfWeek` on database rows still uses the standard ISO 1..7 values;
// existing Sat/Sun rows (if any) are simply filtered out at read time,
// preserving the data without surfacing it.

const List<String> scheduleDayLabels = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
];

const List<String> scheduleDayShortLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
];

/// Number of columns/rows rendered in every weekday iterator.
const int scheduleDayCount = 5;

/// ISO day-of-week values we display. Equivalent to
/// `List.generate(5, (i) => i + 1)` but `const`.
const List<int> scheduleDayValues = <int>[1, 2, 3, 4, 5];

/// Clamp an arbitrary weekday (1..7) into the displayed range so
/// "today's weekday" lookups don't crash on weekends. Saturday → Friday,
/// Sunday → Monday — feels right for a weekday-only program UI.
int clampToScheduleDay(int weekday) {
  if (weekday >= 1 && weekday <= 5) return weekday;
  if (weekday == 6) return 5; // Saturday → Friday
  return 1; // Sunday → Monday
}
