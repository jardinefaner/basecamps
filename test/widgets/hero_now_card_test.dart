import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/today/widgets/hero_now_card.dart';
import 'package:basecamp/features/today/widgets/schedule_item_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump.dart';

ScheduleItem _item({
  String start = '09:00',
  String end = '10:00',
  String title = 'Morning Circle',
}) {
  return ScheduleItem(
    id: 'item-1',
    startTime: start,
    endTime: end,
    isFullDay: false,
    title: title,
    isFromTemplate: true,
    groupIds: const [],
    allGroups: true,
    date: DateTime(2026, 4, 20),
  );
}

void main() {
  group('HeroNowCard countdown formatting', () {
    testWidgets('85 min remaining → "ends in 1h 25m"', (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(end: '11:00'),
          // 9:35 during a 9:00–11:00 activity → 85 min remaining
          now: DateTime(2026, 4, 20, 9, 35),
          observationCount: 0,
          onTap: () {},
          onCapture: () {},
        ),
      );
      expect(find.text('ends in 1h 25m'), findsOneWidget);
      expect(find.text('35m in'), findsOneWidget);
    });

    testWidgets('exactly 60 min remaining → "ends in 1h"', (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(),
          now: DateTime(2026, 4, 20, 9),
          observationCount: 0,
          onTap: () {},
          onCapture: () {},
        ),
      );
      expect(find.text('ends in 1h'), findsOneWidget);
    });

    testWidgets('≤ 5 min left renders in error color', (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(),
          now: DateTime(2026, 4, 20, 9, 57),
          observationCount: 0,
          onTap: () {},
          onCapture: () {},
        ),
      );
      final text = tester.widget<Text>(find.text('ends in 3m'));
      final ctx = tester.element(find.byType(HeroNowCard));
      expect(text.style!.color, Theme.of(ctx).colorScheme.error);
    });

    testWidgets('0 min remaining → "wrapping up"', (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(),
          now: DateTime(2026, 4, 20, 10),
          observationCount: 0,
          onTap: () {},
          onCapture: () {},
        ),
      );
      expect(find.text('wrapping up'), findsOneWidget);
    });
  });

  group('HeroNowCard attendance strip', () {
    testWidgets('renders "N/N present" when a summary is passed',
        (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(),
          now: DateTime(2026, 4, 20, 9, 15),
          observationCount: 0,
          attendance: const AttendanceSummary(
            present: 3,
            absent: 1,
            total: 5,
          ),
          onTap: () {},
          onCapture: () {},
          onOpenAttendance: () {},
        ),
      );
      expect(find.textContaining('3/5 checked in'), findsOneWidget);
      expect(find.textContaining('1 absent'), findsOneWidget);
      expect(find.textContaining('1 pending'), findsOneWidget);
    });

    testWidgets('omits attendance strip when no summary', (tester) async {
      await pumpWithHost(
        tester,
        HeroNowCard(
          item: _item(),
          now: DateTime(2026, 4, 20, 9, 15),
          observationCount: 0,
          onTap: () {},
          onCapture: () {},
        ),
      );
      expect(find.textContaining('checked in'), findsNothing);
    });
  });

  group('AttendanceSummary', () {
    test('pending = total - present - absent, clamped', () {
      const s = AttendanceSummary(present: 2, absent: 1, total: 5);
      expect(s.pending, 2);
    });

    test('allSettled when nothing is pending', () {
      const s = AttendanceSummary(present: 3, absent: 2, total: 5);
      expect(s.allSettled, isTrue);
      expect(s.allPresent, isFalse);
    });

    test('allPresent when everyone present', () {
      const s = AttendanceSummary(present: 5, absent: 0, total: 5);
      expect(s.allPresent, isTrue);
    });
  });
}
