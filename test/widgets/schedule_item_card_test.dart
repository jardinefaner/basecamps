import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';

ScheduleItem _item({String title = 'Morning Circle'}) {
  return ScheduleItem(
    id: 'item-1',
    startTime: '09:00',
    endTime: '10:00',
    isFullDay: false,
    title: title,
    isFromTemplate: true,
    groupIds: const [],
    allGroups: true,
    date: DateTime(2026, 4, 20),
  );
}

void main() {
  group('trailing badge', () {
    testWidgets('isNow=true shows "NOW" chip', (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: true,
          isPast: false,
        ),
      );
      expect(find.text('NOW'), findsOneWidget);
    });

    testWidgets('minutesUntilStart=20 shows "IN 20 MIN"', (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: false,
          isPast: false,
          minutesUntilStart: 20,
        ),
      );
      expect(find.text('IN 20 MIN'), findsOneWidget);
    });

    testWidgets('minutesUntilStart=1 shows "IN 1 MIN" (singular)',
        (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: false,
          isPast: false,
          minutesUntilStart: 1,
        ),
      );
      expect(find.text('IN 1 MIN'), findsOneWidget);
    });

    testWidgets('minutesUntilStart > 60 hides the chip', (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: false,
          isPast: false,
          minutesUntilStart: 75,
        ),
      );
      expect(find.textContaining('IN '), findsNothing);
    });
  });

  group('prompt strips', () {
    testWidgets('showLogObservationsPrompt → "Log observations" strip',
        (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: false,
          isPast: true,
          showLogObservationsPrompt: true,
        ),
      );
      expect(find.text('Log observations'), findsOneWidget);
    });

    testWidgets('concernMatch renders the preview', (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: false,
          isPast: false,
          concernMatch: const ConcernMatch(
            id: 'c-1',
            preview: 'Maya — tough morning drop-off',
          ),
        ),
      );
      expect(
        find.text('Maya — tough morning drop-off'),
        findsOneWidget,
      );
    });

    testWidgets('attendance strip renders "N/M present"', (tester) async {
      await pumpWithHost(
        tester,
        ScheduleItemCard(
          item: _item(),
          isNow: true,
          isPast: false,
          attendance: const AttendanceSummary(
            present: 2,
            absent: 1,
            total: 4,
          ),
        ),
      );
      expect(find.textContaining('2/4 present'), findsOneWidget);
    });
  });

  group('isOneOff "TODAY ONLY" chip', () {
    testWidgets('isOneOff (non-template) shows TODAY ONLY when not current',
        (tester) async {
      final item = ScheduleItem(
        id: 'item-1',
        startTime: '09:00',
        endTime: '10:00',
        isFullDay: false,
        title: 'Field trip',
        isFromTemplate: false, // → isOneOff
        groupIds: const [],
        allGroups: true,
        date: DateTime(2026, 4, 20),
        entryId: 'entry-1',
      );
      await pumpWithHost(
        tester,
        ScheduleItemCard(item: item, isNow: false, isPast: false),
      );
      expect(find.text('TODAY ONLY'), findsOneWidget);
    });
  });
}
