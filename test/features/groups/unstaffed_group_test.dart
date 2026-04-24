import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/groups/group_summary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// [isGroupStaffedToday] answers "is there at least one lead on the
/// clock for this group on this weekday?" These tests cover the
/// combinations a teacher can actually land on in the UI — static
/// anchor lead with/without availability, per-day block lead with/
/// without availability, and the specialist-only "nobody leads this
/// group" case.

Adult _adult({
  required String id,
  String role = 'lead',
  String? anchor,
}) {
  final now = DateTime(2026);
  return Adult(
    id: id,
    name: id,
    adultRole: role,
    anchoredGroupId: anchor,
    createdAt: now,
    updatedAt: now,
  );
}

AdultAvailabilityData _avail({
  required String adultId,
  required int dayOfWeek,
  String startTime = '08:00',
  String endTime = '17:00',
}) {
  final now = DateTime(2026);
  return AdultAvailabilityData(
    id: '$adultId-$dayOfWeek',
    adultId: adultId,
    dayOfWeek: dayOfWeek,
    startTime: startTime,
    endTime: endTime,
    createdAt: now,
    updatedAt: now,
  );
}

AdultDayBlock _block({
  required String adultId,
  required int dayOfWeek,
  required String role,
  String? groupId,
  String startTime = '08:00',
  String endTime = '12:00',
}) {
  final now = DateTime(2026);
  return AdultDayBlock(
    id: '$adultId-$dayOfWeek-$startTime',
    adultId: adultId,
    dayOfWeek: dayOfWeek,
    startTime: startTime,
    endTime: endTime,
    role: role,
    groupId: groupId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('isGroupStaffedToday', () {
    test('anchored lead with availability today → staffed', () {
      final sarah = _adult(id: 'sarah', anchor: 'g-b');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [sarah],
          todayDayBlocks: const [],
          availability: [_avail(adultId: 'sarah', dayOfWeek: 1)],
        ),
        isTrue,
      );
    });

    test('anchored lead with NO availability today → not staffed', () {
      // Regression guard for the spec's explicit rule: anchored lead
      // who isn't on the schedule today doesn't count.
      final sarah = _adult(id: 'sarah', anchor: 'g-b');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [sarah],
          todayDayBlocks: const [],
          availability: [_avail(adultId: 'sarah', dayOfWeek: 2)],
        ),
        isFalse,
      );
    });

    test('per-day lead block + availability today → staffed', () {
      // Alex is a specialist statically but is subbing in as lead
      // today via a day block.
      final alex = _adult(id: 'alex', role: 'specialist');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [alex],
          todayDayBlocks: [
            _block(
              adultId: 'alex',
              dayOfWeek: 1,
              role: 'lead',
              groupId: 'g-b',
            ),
          ],
          availability: [_avail(adultId: 'alex', dayOfWeek: 1)],
        ),
        isTrue,
      );
    });

    test('per-day lead block but no availability → not staffed', () {
      final alex = _adult(id: 'alex', role: 'specialist');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [alex],
          todayDayBlocks: [
            _block(
              adultId: 'alex',
              dayOfWeek: 1,
              role: 'lead',
              groupId: 'g-b',
            ),
          ],
          availability: const [],
        ),
        isFalse,
      );
    });

    test('lead anchored to a DIFFERENT group → not staffed here', () {
      final sarah = _adult(id: 'sarah', anchor: 'g-l');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [sarah],
          todayDayBlocks: const [],
          availability: [_avail(adultId: 'sarah', dayOfWeek: 1)],
        ),
        isFalse,
      );
    });

    test('specialist with no anchor and no lead block → not staffed', () {
      final alex = _adult(id: 'alex', role: 'specialist');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [alex],
          todayDayBlocks: const [],
          availability: [_avail(adultId: 'alex', dayOfWeek: 1)],
        ),
        isFalse,
      );
    });

    test('block role is lead but groupId mismatches → not staffed', () {
      final alex = _adult(id: 'alex', role: 'specialist');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [alex],
          todayDayBlocks: [
            _block(
              adultId: 'alex',
              dayOfWeek: 1,
              role: 'lead',
              groupId: 'g-l',
            ),
          ],
          availability: [_avail(adultId: 'alex', dayOfWeek: 1)],
        ),
        isFalse,
      );
    });

    test('block role specialist on this group → not a lead, not staffed',
        () {
      final alex = _adult(id: 'alex', role: 'specialist');
      expect(
        isGroupStaffedToday(
          groupId: 'g-b',
          weekday: 1,
          adults: [alex],
          todayDayBlocks: [
            _block(
              adultId: 'alex',
              dayOfWeek: 1,
              role: 'specialist',
              groupId: 'g-b',
            ),
          ],
          availability: [_avail(adultId: 'alex', dayOfWeek: 1)],
        ),
        isFalse,
      );
    });
  });
}
