import 'package:basecamp/features/lesson_sequences/sequence_conflict_check.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure unit coverage for the sequence pre-check: given proposed
/// entries and a simulated existing-schedule map, confirm that
/// obvious clashes surface and a clean schedule returns nothing.
void main() {
  ScheduleItem existing({
    required String id,
    required String title,
    required DateTime date,
    required String startTime,
    required String endTime,
    String? adultId,
  }) {
    return ScheduleItem(
      id: id,
      date: date,
      startTime: startTime,
      endTime: endTime,
      isFullDay: false,
      title: title,
      groupIds: const [],
      allGroups: true,
      adultId: adultId,
      isFromTemplate: true,
    );
  }

  ProposedSequenceEntry proposal({
    required int position,
    required DateTime date,
    required String title,
    String startTime = '10:00',
    String endTime = '10:45',
    String? adultId,
  }) {
    return ProposedSequenceEntry(
      position: position,
      date: date,
      startTime: startTime,
      endTime: endTime,
      title: title,
      adultId: adultId,
    );
  }

  test('zero-conflict spread returns an empty list', () {
    final d1 = DateTime(2026, 4, 27);
    final d2 = DateTime(2026, 4, 28);
    final proposals = [
      proposal(position: 1, date: d1, title: 'Circle'),
      proposal(position: 2, date: d2, title: 'Art'),
    ];
    final existingByDate = <DateTime, List<ScheduleItem>>{
      d1: [
        existing(
          id: 'e1',
          title: 'Morning stretch',
          date: d1,
          // 08:00-08:30 doesn't overlap 10:00-10:45.
          startTime: '08:00',
          endTime: '08:30',
          adultId: 'adult-A',
        ),
      ],
      d2: const [],
    };
    final result = detectSequenceConflicts(
      proposals: proposals,
      existingByDate: existingByDate,
    );
    expect(result, isEmpty);
  });

  test('adult collision surfaces the expected reason string', () {
    final d1 = DateTime(2026, 4, 27);
    final proposals = [
      proposal(
        position: 1,
        date: d1,
        title: 'Circle Time',
        adultId: 'adult-A',
      ),
    ];
    final existingByDate = <DateTime, List<ScheduleItem>>{
      d1: [
        existing(
          id: 'e1',
          title: 'Morning Stretch',
          date: d1,
          // Overlaps 10:00-10:45.
          startTime: '10:15',
          endTime: '10:45',
          adultId: 'adult-A',
        ),
      ],
    };
    final result = detectSequenceConflicts(
      proposals: proposals,
      existingByDate: existingByDate,
    );
    expect(result, hasLength(1));
    expect(result.first.position, 1);
    expect(result.first.title, 'Circle Time');
    expect(result.first.reasons, hasLength(1));
    final reason = result.first.reasons.first;
    expect(reason, contains('Morning Stretch'));
    expect(reason, contains('same adult'));
  });

  test('only reports the day that actually clashes', () {
    final d1 = DateTime(2026, 4, 27);
    final d2 = DateTime(2026, 4, 28);
    final proposals = [
      proposal(
        position: 1,
        date: d1,
        title: 'Clean',
        adultId: 'adult-A',
      ),
      proposal(
        position: 2,
        date: d2,
        title: 'Clashy',
        adultId: 'adult-B',
      ),
    ];
    final existingByDate = <DateTime, List<ScheduleItem>>{
      // Day 1 existing adult doesn't overlap.
      d1: [
        existing(
          id: 'e1',
          title: 'Something Early',
          date: d1,
          startTime: '08:00',
          endTime: '09:00',
          adultId: 'adult-A',
        ),
      ],
      // Day 2 has an overlapping same-adult item.
      d2: [
        existing(
          id: 'e2',
          title: 'Staff Meeting',
          date: d2,
          startTime: '10:30',
          endTime: '11:30',
          adultId: 'adult-B',
        ),
      ],
    };
    final result = detectSequenceConflicts(
      proposals: proposals,
      existingByDate: existingByDate,
    );
    expect(result, hasLength(1));
    expect(result.first.position, 2);
    expect(result.first.title, 'Clashy');
    expect(result.first.reasons.first, contains('Staff Meeting'));
  });
}
