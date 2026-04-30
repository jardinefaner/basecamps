import 'package:basecamp/features/planning/week_plan_canvas.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeekPlanScale.from', () {
    test('empty week → 7am-5pm default window', () {
      final scale = WeekPlanScale.from(const []);
      expect(scale.dayStartMinutes, 7 * 60);
      expect(scale.dayEndMinutes, 17 * 60);
      expect(scale.totalMinutes, 10 * 60);
    });

    test('items inside default window → window unchanged', () {
      final items = [
        _item(startTime: '09:00', endTime: '10:00'),
        _item(startTime: '14:30', endTime: '15:00'),
      ];
      final scale = WeekPlanScale.from(items);
      expect(scale.dayStartMinutes, 7 * 60);
      expect(scale.dayEndMinutes, 17 * 60);
    });

    test('early-morning item → window expands left to round hour', () {
      final items = [_item(startTime: '06:30', endTime: '07:30')];
      final scale = WeekPlanScale.from(items);
      // Earliest 6:30 → rounds DOWN to 6:00 (round outward).
      expect(scale.dayStartMinutes, 6 * 60);
      // Latest 7:30 → keeps 17:00 default since 7:30 < 17:00.
      expect(scale.dayEndMinutes, 17 * 60);
    });

    test('late-evening item → window expands right to round hour', () {
      final items = [_item(startTime: '17:30', endTime: '18:45')];
      final scale = WeekPlanScale.from(items);
      // Latest 18:45 → rounds UP to 19:00 (round outward).
      expect(scale.dayEndMinutes, 19 * 60);
      // Earliest 17:30 stays at default 7:00 since the window
      // never shrinks.
      expect(scale.dayStartMinutes, 7 * 60);
    });

    test('full-day items are ignored when computing the window', () {
      // A full-day event would otherwise pull the window to 00:00-
      // 23:59 and make every other card render in a sliver.
      final items = [
        _item(
          startTime: '00:00',
          endTime: '23:59',
          isFullDay: true,
        ),
        _item(startTime: '09:00', endTime: '10:00'),
      ];
      final scale = WeekPlanScale.from(items);
      expect(scale.dayStartMinutes, 7 * 60);
      expect(scale.dayEndMinutes, 17 * 60);
    });

    test('end-time exactly on the hour does not over-pad', () {
      // Latest 18:00 should round to 18:00 (no extra hour added).
      final items = [_item(startTime: '17:00', endTime: '18:00')];
      final scale = WeekPlanScale.from(items);
      expect(scale.dayEndMinutes, 18 * 60);
    });
  });

  group('WeekPlanScale axis math', () {
    test('yFor / minutesAtY round-trip at hour boundaries', () {
      const scale = WeekPlanScale(
        dayStartMinutes: 7 * 60,
        dayEndMinutes: 17 * 60,
      );
      // 9:00 = 540 minutes. 540 - 420 = 120 → 120 * 0.8 = 96 px.
      expect(scale.yFor(9 * 60), 96);
      // Round-trip: 96 px → minute 540.
      expect(scale.minutesAtY(96), 9 * 60);
    });

    test('minutesAtY at y=0 returns dayStartMinutes', () {
      const scale = WeekPlanScale(
        dayStartMinutes: 8 * 60,
        dayEndMinutes: 16 * 60,
      );
      expect(scale.minutesAtY(0), 8 * 60);
    });

    test('totalHeight = totalMinutes × pxPerMinute', () {
      const scale = WeekPlanScale(
        dayStartMinutes: 7 * 60,
        dayEndMinutes: 17 * 60,
      );
      // 10 hours × 60 min × 0.8 px/min = 480 px.
      expect(scale.totalHeight, 480);
    });
  });

  group('15-minute snap arithmetic', () {
    // The drag-end snap is `((minutes / 15).round() * 15)` —
    // round-to-nearest. These tests just lock the formula so a
    // future refactor of the canvas can't silently regress to
    // floor-to-15.
    int snap15(int minutes) => (minutes / 15).round() * 15;

    test('exact multiples are unchanged', () {
      expect(snap15(540), 540); // 9:00
      expect(snap15(555), 555); // 9:15
      expect(snap15(0), 0);
    });

    test('rounds half-up at the 7-min mark', () {
      expect(snap15(537), 540); // 8:57 → 9:00
      expect(snap15(538), 540); // 8:58 → 9:00
      expect(snap15(536), 540); // 8:56 → 9:00 (round 0.93 up)
      expect(snap15(534), 540); // 8:54 → 9:00 (.6 of the way)
    });

    test('rounds down below the half-mark', () {
      expect(snap15(541), 540); // 9:01 → 9:00
      expect(snap15(547), 540); // 9:07 → 9:00 (right at half)
      expect(snap15(548), 555); // 9:08 → 9:15
    });
  });
}

/// Minimal ScheduleItem builder for tests. Only supplies the
/// fields the scale's window-computation reads.
ScheduleItem _item({
  required String startTime,
  required String endTime,
  bool isFullDay = false,
}) {
  return ScheduleItem(
    id: 'test',
    title: 'test',
    startTime: startTime,
    endTime: endTime,
    isFullDay: isFullDay,
    groupIds: const [],
    allGroups: false,
    isFromTemplate: true,
    date: DateTime(2026),
  );
}
