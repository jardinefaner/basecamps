import 'package:basecamp/features/schedule/conflicts.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure conflict-rule tests — no DB needed. Locks in the "isNoGroups
/// activity never conflicts with anything by group" invariant (user
/// reported spurious flags on intentional staff-prep full-day entries).
ScheduleItem _item({
  required String id,
  required String title,
  required String start,
  required String end,
  bool isFullDay = false,
  bool allGroups = true,
  List<String> groupIds = const [],
  String? specialistId,
  DateTime? date,
}) {
  return ScheduleItem(
    id: id,
    startTime: start,
    endTime: end,
    isFullDay: isFullDay,
    title: title,
    isFromTemplate: true,
    groupIds: groupIds,
    allGroups: allGroups,
    specialistId: specialistId,
    date: date ?? DateTime(2026, 4, 20),
  );
}

void main() {
  group('isNoGroups activity never flags as conflict', () {
    test('no-groups full-day vs. timed all-groups → no conflict', () {
      // Staff prep: allGroups=false, groupIds=[] → isNoGroups
      final staff = _item(
        id: 'staff',
        title: 'Staff prep',
        start: '00:00',
        end: '23:59',
        isFullDay: true,
        allGroups: false,
      );
      // Normal morning circle for everyone.
      final circle = _item(
        id: 'circle',
        title: 'Morning circle',
        start: '09:00',
        end: '10:00',
      );
      final conflicts = detectConflictingIds([staff, circle]);
      expect(conflicts, isEmpty,
          reason: 'staff-prep (no audience) should never clash on groups');
    });

    test('no-groups timed vs. no-groups timed → no conflict', () {
      final a = _item(
        id: 'a',
        title: 'Prep A',
        start: '09:00',
        end: '10:00',
        allGroups: false,
      );
      final b = _item(
        id: 'b',
        title: 'Prep B',
        start: '09:30',
        end: '10:30',
        allGroups: false,
      );
      expect(detectConflictingIds([a, b]), isEmpty);
    });

    test('broadcast vs. broadcast (both all-groups) still conflicts', () {
      // This is the legitimate wildcard case — two "everyone" activities
      // at overlapping times really do double-book.
      final a = _item(
        id: 'a',
        title: 'A',
        start: '09:00',
        end: '10:00',
      );
      final b = _item(
        id: 'b',
        title: 'B',
        start: '09:30',
        end: '10:30',
      );
      final conflicts = detectConflictingIds([a, b]);
      expect(conflicts, containsAll({'a', 'b'}));
    });

    test('specialist clash still fires even when one side isNoGroups', () {
      // Specialist double-booking is separate from group sharing — a
      // staff-prep slot that reserves a specialist should still conflict
      // with anything else using that specialist at the same time.
      final prep = _item(
        id: 'prep',
        title: 'Prep',
        start: '09:00',
        end: '10:00',
        allGroups: false,
        specialistId: 's1',
      );
      final lesson = _item(
        id: 'lesson',
        title: 'Art',
        start: '09:30',
        end: '10:30',
        specialistId: 's1',
      );
      final conflicts = detectConflictingIds([prep, lesson]);
      expect(conflicts, containsAll({'prep', 'lesson'}));
    });
  });
}
