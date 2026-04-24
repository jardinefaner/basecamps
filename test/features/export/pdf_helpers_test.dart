import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/export/lesson_plan_pdf.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildDayPdf', () {
    test('empty schedule still produces non-empty PDF bytes', () async {
      final bytes = await buildDayPdf(
        date: DateTime(2026, 4, 24),
        items: const [],
        groupNamesById: const {},
        adultNamesById: const {},
        roomNamesById: const {},
        programName: 'Basecamp',
      );
      expect(bytes, isNotEmpty);
      // PDFs start with the %PDF- magic string — the printing library
      // writes a well-formed doc.
      expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF-'));
    });

    test('a mix of whole-day and timed items renders a valid PDF', () async {
      final date = DateTime(2026, 4, 24);
      final items = <ScheduleItem>[
        ScheduleItem(
          id: 't1',
          date: date,
          startTime: '00:00',
          endTime: '23:59',
          isFullDay: true,
          title: 'Field trip to the aquarium',
          isFromTemplate: false,
          groupIds: const ['g1'],
          allGroups: false,
          notes: 'Bring lunches',
          adultId: 'a1',
          sourceUrl: 'https://aquarium.example.com',
        ),
        ScheduleItem(
          id: 't2',
          date: date,
          startTime: '09:00',
          endTime: '09:45',
          isFullDay: false,
          title: 'Morning meeting',
          isFromTemplate: true,
          groupIds: const [],
          allGroups: true,
          adultId: 'a1',
          roomId: 'r1',
        ),
        ScheduleItem(
          id: 't3',
          date: date,
          startTime: '10:00',
          endTime: '10:30',
          isFullDay: false,
          title: 'Reading circle',
          isFromTemplate: true,
          groupIds: const [],
          allGroups: false, // no-groups / staff-only
          location: 'Reading nook',
        ),
      ];
      final bytes = await buildDayPdf(
        date: date,
        items: items,
        groupNamesById: const {'g1': 'Tigers'},
        adultNamesById: const {'a1': 'Ms. Rose'},
        roomNamesById: const {'r1': 'Main room'},
        programName: 'Basecamp',
      );
      expect(bytes.length, greaterThan(500));
    });
  });

  group('buildWeekPdf', () {
    test('a mix of days with items produces a valid PDF', () async {
      final monday = DateTime(2026, 4, 20);
      final items = <int, List<ScheduleItem>>{
        1: [
          ScheduleItem(
            id: 'm1',
            date: monday,
            startTime: '09:00',
            endTime: '09:30',
            isFullDay: false,
            title: 'Morning meeting',
            isFromTemplate: true,
            groupIds: const [],
            allGroups: true,
          ),
        ],
        // Tuesday intentionally omitted to exercise the empty path.
        3: [
          ScheduleItem(
            id: 'w1',
            date: monday.add(const Duration(days: 2)),
            startTime: '00:00',
            endTime: '23:59',
            isFullDay: true,
            title: 'Spring picnic',
            isFromTemplate: false,
            groupIds: const ['g1'],
            allGroups: false,
          ),
        ],
      };
      final bytes = await buildWeekPdf(
        mondayOfWeek: monday,
        itemsByWeekday: items,
        groupNamesById: const {'g1': 'Tigers'},
        adultNamesById: const {},
        roomNamesById: const {},
        programName: 'Basecamp',
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF-'));
    });
  });

  group('buildSequencePdf', () {
    test('three items produce non-empty bytes', () async {
      final now = DateTime(2026, 4, 24);
      final sequence = LessonSequence(
        id: 's1',
        name: 'Ecosystems introduction',
        description: 'A three-day unit for the 8-10 class.',
        createdAt: now,
        updatedAt: now,
      );
      final items = [
        ActivityLibraryData(
          id: 'a1',
          title: 'What is an ecosystem?',
          audienceMinAge: 8,
          audienceMaxAge: 10,
          summary: 'Introduce the idea of interacting living and '
              'non-living things.',
          keyPoints: 'Living vs non-living\nInteractions matter',
          learningGoals: 'Name three parts of an ecosystem',
          materials: 'Whiteboard, markers',
          sourceUrl: 'https://example.com/ecosystems',
          sourceAttribution: 'via Example.com',
          createdAt: now,
          updatedAt: now,
        ),
        ActivityLibraryData(
          id: 'a2',
          title: 'Food chains',
          audienceMinAge: 8,
          audienceMaxAge: 8,
          summary: 'Follow the arrows from the sun.',
          keyPoints: 'Producers\nConsumers\nDecomposers',
          createdAt: now,
          updatedAt: now,
        ),
        ActivityLibraryData(
          id: 'a3',
          title: 'Build a terrarium',
          createdAt: now,
          updatedAt: now,
        ),
      ];
      final bytes = await buildSequencePdf(
        sequence: sequence,
        items: items,
        programName: 'Basecamp',
      );
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF-'));
    });

    test('empty sequence still renders a valid PDF', () async {
      final now = DateTime(2026, 4, 24);
      final sequence = LessonSequence(
        id: 's1',
        name: 'Empty one',
        createdAt: now,
        updatedAt: now,
      );
      final bytes = await buildSequencePdf(
        sequence: sequence,
        items: const [],
        programName: 'Basecamp',
      );
      expect(bytes, isNotEmpty);
    });
  });
}
