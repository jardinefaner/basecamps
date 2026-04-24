import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/today/ratio_check.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Tiny factories so the cases read as data, not boilerplate. ---

Child _child({
  required String id,
  String? groupId = 'g1',
  String? arrival,
  String? pickup,
}) =>
    Child(
      id: id,
      firstName: id,
      groupId: groupId,
      expectedArrival: arrival,
      expectedPickup: pickup,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Adult _adult({
  required String id,
  String role = 'lead',
  String? anchoredGroupId,
}) =>
    Adult(
      id: id,
      name: id,
      adultRole: role,
      anchoredGroupId: anchoredGroupId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

AdultAvailabilityData _avail({
  required String adultId,
  String? breakStart,
  String? breakEnd,
  String? lunchStart,
  String? lunchEnd,
  int dayOfWeek = 1,
  String start = '08:00',
  String end = '17:00',
}) =>
    AdultAvailabilityData(
      id: '$adultId-$dayOfWeek',
      adultId: adultId,
      dayOfWeek: dayOfWeek,
      startTime: start,
      endTime: end,
      breakStart: breakStart,
      breakEnd: breakEnd,
      lunchStart: lunchStart,
      lunchEnd: lunchEnd,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

AdultDayBlock _leadBlock({
  required String adultId,
  required String start,
  required String end,
  required String groupId,
  int dayOfWeek = 1,
}) =>
    AdultDayBlock(
      id: '$adultId-$start',
      adultId: adultId,
      dayOfWeek: dayOfWeek,
      startTime: start,
      endTime: end,
      role: 'lead',
      groupId: groupId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

// A deterministic Monday at 10:00 — easier to reason about than
// DateTime.now() and matches the weekday the fixtures use (1 = Mon).
DateTime _mondayAt(int h, int m) => DateTime(2026, 4, 20, h, m);

void main() {
  group('computeGroupRatioNow', () {
    test('normal ratio — under threshold, not flagged', () {
      // 4 kids, 1 lead, ratio 4:1 < 8 → OK.
      final kids = [
        for (var i = 1; i <= 4; i++)
          _child(id: 'k$i', arrival: '08:00', pickup: '16:00'),
      ];
      final adults = [_adult(id: 'a1', anchoredGroupId: 'g1')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [_avail(adultId: 'a1')],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(10, 0),
      );
      expect(result.childrenInGroupNow, 4);
      expect(result.adultsOnShiftForGroupNow, 1);
      expect(result.isUnderRatio, isFalse);
    });

    test('over ratio during break — the break strips the only adult', () {
      // 9 kids, 1 lead, but the lead is on break at 10:00 → 0 adults
      // effective, any kids present trips the flag.
      final kids = [
        for (var i = 1; i <= 9; i++)
          _child(id: 'k$i', arrival: '08:00', pickup: '16:00'),
      ];
      final adults = [_adult(id: 'a1', anchoredGroupId: 'g1')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [
          _avail(
            adultId: 'a1',
            breakStart: '09:45',
            breakEnd: '10:15',
          ),
        ],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(10, 0),
      );
      expect(result.adultsOnShiftForGroupNow, 0);
      expect(result.isUnderRatio, isTrue);
    });

    test('no adult on shift → any kids trips the flag', () {
      final kids = [_child(id: 'k1', arrival: '08:00', pickup: '16:00')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: const <Adult>[],
        allAvailability: const <AdultAvailabilityData>[],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(10, 0),
      );
      expect(result.adultsOnShiftForGroupNow, 0);
      expect(result.childrenInGroupNow, 1);
      expect(result.isUnderRatio, isTrue);
      expect(result.display, contains('no adult'));
    });

    test('null expected times → counted as all-day present', () {
      // Drop-in kid with no standing times should count regardless of
      // the current hour — treated as present for safety.
      final kids = [_child(id: 'k1')];
      final adults = [_adult(id: 'a1', anchoredGroupId: 'g1')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [_avail(adultId: 'a1')],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(10, 0),
      );
      expect(result.childrenInGroupNow, 1);
      expect(result.isUnderRatio, isFalse);
    });

    test('multi-lead group — timeline block adds a second lead', () {
      // Static anchor: a1. Per-day block: a2 also leading g1 from
      // 09:00-12:00. 10 kids / 2 adults = 5:1 → OK.
      final kids = [
        for (var i = 1; i <= 10; i++)
          _child(id: 'k$i', arrival: '08:00', pickup: '16:00'),
      ];
      final adults = [
        _adult(id: 'a1', anchoredGroupId: 'g1'),
        _adult(id: 'a2', role: 'adult'),
      ];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [
          _avail(adultId: 'a1'),
          _avail(adultId: 'a2'),
        ],
        todayBlocks: [
          _leadBlock(
            adultId: 'a2',
            start: '09:00',
            end: '12:00',
            groupId: 'g1',
          ),
        ],
        now: _mondayAt(10, 0),
      );
      expect(result.adultsOnShiftForGroupNow, 2);
      expect(result.isUnderRatio, isFalse);
    });

    test('pre-arrival kids are not counted as present', () {
      // 20 kids scheduled for 09:00 arrival; at 08:30 none are here yet.
      // Rule: no kids present → not under ratio even with zero adults.
      final kids = [
        for (var i = 1; i <= 20; i++)
          _child(id: 'k$i', arrival: '09:00', pickup: '16:00'),
      ];
      final adults = [_adult(id: 'a1', anchoredGroupId: 'g1')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [_avail(adultId: 'a1')],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(8, 30),
      );
      expect(result.childrenInGroupNow, 0);
      expect(result.isUnderRatio, isFalse);
    });

    test('picked-up kids drop out', () {
      // Half-day: arrival 08:00 pickup 12:00. At 13:00 nobody remains.
      final kids = [
        for (var i = 1; i <= 5; i++)
          _child(id: 'k$i', arrival: '08:00', pickup: '12:00'),
      ];
      final adults = [_adult(id: 'a1', anchoredGroupId: 'g1')];
      final result = computeGroupRatioNow(
        groupId: 'g1',
        childrenInGroup: kids,
        allAdults: adults,
        allAvailability: [_avail(adultId: 'a1')],
        todayBlocks: const <AdultDayBlock>[],
        now: _mondayAt(13, 0),
      );
      expect(result.childrenInGroupNow, 0);
      expect(result.isUnderRatio, isFalse);
    });

    test('display formats kids:adults and the decimal ratio', () {
      const result = GroupRatioNow(
        groupId: 'g1',
        childrenInGroupNow: 12,
        adultsOnShiftForGroupNow: 2,
        threshold: 8,
      );
      expect(result.display, '12:2 (6.0:1)');
    });
  });
}
