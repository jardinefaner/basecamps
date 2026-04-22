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
  String? roomId,
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
    roomId: roomId,
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

    test('room clash fires even when groups differ', () {
      // Two activities at the same time, in the same tracked room,
      // but targeting different groups. Previously (v27) this was
      // invisible because location was a free-form string. Now roomId
      // catches it.
      final a = _item(
        id: 'a',
        title: 'Art · Seedlings',
        start: '09:00',
        end: '10:00',
        groupIds: const ['seedlings'],
        allGroups: false,
        roomId: 'art-room',
      );
      final b = _item(
        id: 'b',
        title: 'Art · Sprouts',
        start: '09:30',
        end: '10:30',
        groupIds: const ['sprouts'],
        allGroups: false,
        roomId: 'art-room',
      );
      expect(detectConflictingIds([a, b]), containsAll({'a', 'b'}));
    });

    test('same-room, non-overlapping times does NOT clash', () {
      // Back-to-back slots in the same room — this is the normal
      // rotation pattern. Must not flag.
      final a = _item(
        id: 'a',
        title: 'Art · Seedlings',
        start: '09:00',
        end: '10:00',
        groupIds: const ['seedlings'],
        allGroups: false,
        roomId: 'art-room',
      );
      final b = _item(
        id: 'b',
        title: 'Art · Sprouts',
        start: '10:00',
        end: '11:00',
        groupIds: const ['sprouts'],
        allGroups: false,
        roomId: 'art-room',
      );
      expect(detectConflictingIds([a, b]), isEmpty);
    });

    test('different rooms, overlapping times does NOT clash', () {
      final a = _item(
        id: 'a',
        title: 'Art',
        start: '09:00',
        end: '10:00',
        groupIds: const ['seedlings'],
        allGroups: false,
        roomId: 'art-room',
      );
      final b = _item(
        id: 'b',
        title: 'Music',
        start: '09:30',
        end: '10:30',
        groupIds: const ['sprouts'],
        allGroups: false,
        roomId: 'music-room',
      );
      expect(detectConflictingIds([a, b]), isEmpty);
    });

    test('free-form location strings still never clash (no roomId)', () {
      // Pre-v28 rows and field-trip entries carry only free-form
      // text. They must never produce a false conflict based on
      // string equality. Using different specific groups so the
      // group rule doesn't fire either.
      final a = _item(
        id: 'a',
        title: 'Trip A',
        start: '09:00',
        end: '12:00',
        groupIds: const ['seedlings'],
        allGroups: false,
      );
      final b = _item(
        id: 'b',
        title: 'Trip B',
        start: '10:00',
        end: '11:00',
        groupIds: const ['sprouts'],
        allGroups: false,
      );
      expect(detectConflictingIds([a, b]), isEmpty);
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
