import 'package:basecamp/core/format/date.dart';
import 'package:flutter_test/flutter_test.dart';

/// `isSameCalendarDate` drives whether the Today screen shows its
/// live-clock affordances (hero NOW, close-out strip, lateness flags)
/// — any drift here would fire the live widgets on the wrong day
/// when the teacher is browsing prev/next via the AppBar chevrons.
void main() {
  group('isSameCalendarDate', () {
    test('same day, different clock minutes → true', () {
      final morning = DateTime(2026, 4, 24, 8);
      final evening = DateTime(2026, 4, 24, 21, 47);
      expect(isSameCalendarDate(morning, evening), isTrue);
    });

    test('midnight boundary — still same calendar day', () {
      final earlyMorning = DateTime(2026, 4, 24);
      final lateEvening = DateTime(2026, 4, 24, 23, 59);
      expect(isSameCalendarDate(earlyMorning, lateEvening), isTrue);
    });

    test('adjacent days → false', () {
      final today = DateTime(2026, 4, 24, 12);
      final tomorrow = DateTime(2026, 4, 25, 12);
      expect(isSameCalendarDate(today, tomorrow), isFalse);
    });

    test('same day-of-month different month → false', () {
      final april = DateTime(2026, 4, 24);
      final may = DateTime(2026, 5, 24);
      expect(isSameCalendarDate(april, may), isFalse);
    });

    test('same day-of-year different year → false', () {
      final thisYear = DateTime(2026, 4, 24);
      final lastYear = DateTime(2025, 4, 24);
      expect(isSameCalendarDate(thisYear, lastYear), isFalse);
    });
  });
}
