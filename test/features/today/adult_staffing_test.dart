import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_timeline_repository.dart';
import 'package:basecamp/features/today/adult_staffing.dart';
import 'package:flutter_test/flutter_test.dart';

Adult _sp({
  required String id,
  String role = 'adult',
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

// Day 1 (Mon) is fine for these tests — resolveCurrentState doesn't
// inspect dayOfWeek, only startMinutes/endMinutes.
AdultTimelineBlock _block({
  required String start,
  required String end,
  required AdultBlockRole role,
  String? groupId,
}) =>
    AdultTimelineBlock(
      dayOfWeek: 1,
      startTime: start,
      endTime: end,
      role: role,
      groupId: groupId,
    );

int _at(int h, int m) => h * 60 + m;

void main() {
  group('resolveCurrentState', () {
    test('block straddling now wins — lead + pod', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'sarah'),
        blocksForAdult: [
          _block(
            start: '08:30',
            end: '11:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
        nowMinutes: _at(10, 0),
      );
      expect(state, isNotNull);
      expect(state!.role, AdultBlockRole.lead);
      expect(state.groupId, 'g-b');
      expect(state.blockStartMinutes, _at(8, 30));
      expect(state.blockEndMinutes, _at(11, 0));
    });

    test('adult between blocks → null (implied off)', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'sarah', role: 'lead', anchoredGroupId: 'g-b'),
        blocksForAdult: [
          _block(
            start: '08:30',
            end: '11:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
          _block(
            start: '12:00',
            end: '15:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
        nowMinutes: _at(11, 30),
      );
      // Blocks exist but none covers 11:30 → off. Static role does NOT
      // fall back (timeline is authoritative when present).
      expect(state, isNull);
    });

    test('no blocks, static lead + anchor → synthetic lead state', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'sarah', role: 'lead', anchoredGroupId: 'g-b'),
        blocksForAdult: const [],
        nowMinutes: _at(10, 0),
      );
      expect(state, isNotNull);
      expect(state!.role, AdultBlockRole.lead);
      expect(state.groupId, 'g-b');
      expect(state.blockStartMinutes, isNull);
    });

    test('no blocks, static adult → rotating adult', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'alex'),
        blocksForAdult: const [],
        nowMinutes: _at(10, 0),
      );
      expect(state!.role, AdultBlockRole.specialist);
      expect(state.groupId, isNull);
    });

    test('no blocks, static ambient → null (not on group grid)', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'dir', role: 'ambient'),
        blocksForAdult: const [],
        nowMinutes: _at(10, 0),
      );
      expect(state, isNull);
    });

    test('boundary: exactly at block start is covered', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'sarah'),
        blocksForAdult: [
          _block(
            start: '08:30',
            end: '11:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
        nowMinutes: _at(8, 30),
      );
      expect(state, isNotNull);
    });

    test('boundary: exactly at block end is NOT covered', () {
      final state = resolveCurrentState(
        adult: _sp(id: 'sarah'),
        blocksForAdult: [
          _block(
            start: '08:30',
            end: '11:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
        nowMinutes: _at(11, 0),
      );
      expect(state, isNull);
    });
  });

  group('leadsInGroupNow', () {
    test('includes timeline-leads and static-anchor-leads together', () {
      // Sarah: timeline-lead for g-b 8:30-11
      // Mike: static anchored lead for g-b (no timeline)
      // Alex: adult rotating — should NOT count
      // Jen: lead anchored to g-l — wrong pod, NOT in g-b
      final adults = [
        _sp(id: 'sarah'),
        _sp(id: 'mike', role: 'lead', anchoredGroupId: 'g-b'),
        _sp(id: 'alex'),
        _sp(id: 'jen', role: 'lead', anchoredGroupId: 'g-l'),
      ];
      final blocksBy = {
        'sarah': [
          _block(
            start: '08:30',
            end: '11:00',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
      };
      final leads = leadsInGroupNow(
        groupId: 'g-b',
        nowMinutes: _at(10, 0),
        adults: adults,
        blocksByAdult: blocksBy,
      );
      expect(leads, {'sarah', 'mike'});
    });

    test('rotating adult in a group via a lead block at that pod', () {
      // Sarah is normally a rotating adult (static role), but
      // her timeline overrides this morning to anchor g-b as lead.
      // leadsInGroupNow should include her.
      final adults = [_sp(id: 'sarah')];
      final blocksBy = {
        'sarah': [
          _block(
            start: '09:00',
            end: '10:30',
            role: AdultBlockRole.lead,
            groupId: 'g-b',
          ),
        ],
      };
      final leads = leadsInGroupNow(
        groupId: 'g-b',
        nowMinutes: _at(9, 30),
        adults: adults,
        blocksByAdult: blocksBy,
      );
      expect(leads, {'sarah'});
    });
  });

  group('groupBlocksByAdult', () {
    test('sorts per-adult lists by start time', () {
      final rows = [
        AdultDayBlock(
          id: 'b2',
          adultId: 'sarah',
          dayOfWeek: 1,
          startTime: '12:00',
          endTime: '15:00',
          role: 'lead',
          groupId: 'g-b',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        AdultDayBlock(
          id: 'b1',
          adultId: 'sarah',
          dayOfWeek: 1,
          startTime: '08:30',
          endTime: '11:00',
          role: 'lead',
          groupId: 'g-b',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      final grouped = groupBlocksByAdult(rows);
      expect(grouped['sarah']!.map((b) => b.startTime).toList(),
          ['08:30', '12:00']);
    });
  });
}
