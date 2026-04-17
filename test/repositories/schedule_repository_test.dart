import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ScheduleRepository sch;
  late ChildrenRepository kids;

  setUp(() {
    db = createTestDatabase();
    sch = ScheduleRepository(db);
    kids = ChildrenRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('three-state audience (allGroups / specific / none)', () {
    test('addTemplate with allGroups=true records it', () async {
      await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Recess',
        // default allGroups=true
      );
      final t = await sch.templatesForDay(1);
      expect(t.single.allGroups, isTrue);
    });

    test('addTemplate with allGroups=false + no groups = "nobody"',
        () async {
      await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Staff prep',
        allGroups: false,
      );
      final t = await sch.templatesForDay(1);
      expect(t.single.allGroups, isFalse);
    });

    test('addTemplate with specific groupIds persists the join', () async {
      final g1 = await kids.addGroup(name: 'Seedlings');
      final g2 = await kids.addGroup(name: 'Dolphins');
      final id = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Art',
        groupIds: [g1, g2],
        allGroups: false,
      );
      final pods = await sch.podsForTemplate(id);
      expect(pods, containsAll([g1, g2]));
    });
  });

  group('shiftTemplateForDate', () {
    test('creates an override entry carrying all other fields', () async {
      final g = await kids.addGroup(name: 'Seedlings');
      final id = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Morning Circle',
        groupIds: [g],
        allGroups: false,
        location: 'Room 3',
      );
      final date = DateTime(2026, 4, 20);
      await sch.shiftTemplateForDate(
        templateId: id,
        date: date,
        startTime: '10:30',
        endTime: '11:30',
      );
      final items = await sch.watchScheduleForDate(date).first;
      // One merged item on that date — the override wins.
      final shifted = items.firstWhere((i) => i.templateId == id);
      expect(shifted.startTime, '10:30');
      expect(shifted.endTime, '11:30');
      expect(shifted.title, 'Morning Circle');
      expect(shifted.location, 'Room 3');
      expect(shifted.groupIds, contains(g));
    });

    test('is idempotent — shifting twice replaces the override', () async {
      final id = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Circle',
      );
      final date = DateTime(2026, 4, 20);
      await sch.shiftTemplateForDate(
        templateId: id,
        date: date,
        startTime: '09:30',
        endTime: '10:30',
      );
      await sch.shiftTemplateForDate(
        templateId: id,
        date: date,
        startTime: '11:00',
        endTime: '12:00',
      );
      // Only one override entry exists (second replaced the first).
      final overrides = await db.select(db.scheduleEntries).get();
      expect(overrides.where((e) => e.kind == 'override'), hasLength(1));
    });
  });

  group('cancelTemplateForDate', () {
    test('suppresses the template on that date only', () async {
      final id = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Circle',
      );
      final cancelled = DateTime(2026, 4, 20); // a Monday
      final other = DateTime(2026, 4, 27); // next Monday
      await sch.cancelTemplateForDate(templateId: id, date: cancelled);

      final cancelledItems =
          await sch.watchScheduleForDate(cancelled).first;
      expect(cancelledItems.where((i) => i.title == 'Circle'), isEmpty,
          reason: 'Cancellation entry must suppress the template that day.');

      final otherItems = await sch.watchScheduleForDate(other).first;
      expect(otherItems.where((i) => i.title == 'Circle'), hasLength(1),
          reason: 'Other weeks stay untouched.');
    });
  });

  group('deleteTemplateGroupFor', () {
    test('deletes every template sharing the series id', () async {
      // Simulate a three-weekday activity the wizard creates with a
      // shared groupId.
      const series = 'series-abc';
      final ids = <String>[];
      for (final day in [1, 3, 5]) {
        ids.add(await sch.addTemplate(
          dayOfWeek: day,
          startTime: '09:00',
          endTime: '10:00',
          title: 'Art',
          seriesId: series,
        ));
      }
      expect(await sch.countTemplatesInGroupFor(ids.first), 3);

      final deleted = await sch.deleteTemplateGroupFor(ids.first);
      expect(deleted, 3);

      final remaining = await sch.watchTemplates().first;
      expect(remaining, isEmpty);
    });

    test('falls back to shape-match for legacy rows without groupId',
        () async {
      // Two "Art" templates matching title/start/end but no groupId.
      final a = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Art',
      );
      await sch.addTemplate(
        dayOfWeek: 3,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Art',
      );
      final count = await sch.countTemplatesInGroupFor(a);
      expect(count, 2, reason: 'Shape-match fallback collects siblings');
    });
  });

  group('FK: deleting a specialist nulls the reference (setNull)', () {
    test('deleting referenced specialist leaves template with null '
        'specialistId', () async {
      await db.into(db.specialists).insert(
            SpecialistsCompanion.insert(id: 'sp-1', name: 'Ms. Park'),
          );
      final id = await sch.addTemplate(
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:00',
        title: 'Art',
        specialistId: 'sp-1',
      );
      await (db.delete(db.specialists)..where((s) => s.id.equals('sp-1')))
          .go();

      final t = await sch.getTemplate(id);
      expect(t!.specialistId, isNull,
          reason: 'ON DELETE SET NULL must fire — without it the '
              'template would still point at a deleted specialist, '
              'which was the source of the dropdown crash.');
    });
  });
}
