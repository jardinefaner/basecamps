import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adult_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure validity helpers surfaced from `adult_detail_screen.dart`.
/// They power the "Data issues" card — keeping them testable means a
/// copy tweak in the widget tree can't silently flip the rule.

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

AdultDayBlock _block({
  required String adultId,
  required int dayOfWeek,
  required String role,
  String? groupId,
}) {
  final now = DateTime(2026);
  return AdultDayBlock(
    id: '$adultId-$dayOfWeek',
    adultId: adultId,
    dayOfWeek: dayOfWeek,
    startTime: '08:00',
    endTime: '12:00',
    role: role,
    groupId: groupId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('leadWithoutAnchor', () {
    test('lead role + null anchor → flagged', () {
      expect(leadWithoutAnchor(_adult(id: 's1')), isTrue);
    });

    test('lead role + anchor set → not flagged', () {
      expect(
        leadWithoutAnchor(_adult(id: 's1', anchor: 'g-b')),
        isFalse,
      );
    });

    test('specialist with no anchor → not flagged', () {
      // A specialist with no anchor is normal — they rotate. The
      // check is strictly for leads.
      expect(
        leadWithoutAnchor(_adult(id: 's1', role: 'specialist')),
        isFalse,
      );
    });

    test('ambient role never flags', () {
      expect(
        leadWithoutAnchor(_adult(id: 's1', role: 'ambient')),
        isFalse,
      );
    });
  });

  group('leadBlocksMissingGroup', () {
    test('returns weekday of a lead block with no groupId', () {
      final bad = _block(adultId: 's1', dayOfWeek: 1, role: 'lead');
      expect(leadBlocksMissingGroup([bad]), [1]);
    });

    test('lead block with groupId set → not returned', () {
      final ok = _block(
        adultId: 's1',
        dayOfWeek: 1,
        role: 'lead',
        groupId: 'g-b',
      );
      expect(leadBlocksMissingGroup([ok]), isEmpty);
    });

    test('specialist block without groupId → not returned', () {
      // Specialist blocks having no groupId is correct behavior —
      // specialists rotate and don't own a group. Only 'lead' with
      // a null groupId is a data bug.
      final rotator = _block(
        adultId: 's1',
        dayOfWeek: 1,
        role: 'specialist',
      );
      expect(leadBlocksMissingGroup([rotator]), isEmpty);
    });

    test('de-duplicates same-day bad blocks', () {
      // The editor can let a teacher stack two bad blocks on Monday
      // (e.g. lead 8-10 and lead 10-12, both missing groupId).
      // The UI should say "Monday's" once, not "Monday's and
      // Monday's".
      final a = _block(adultId: 's1', dayOfWeek: 1, role: 'lead');
      final b = _block(adultId: 's1', dayOfWeek: 1, role: 'lead');
      expect(leadBlocksMissingGroup([a, b]), [1]);
    });

    test('sorts weekdays ascending', () {
      final wed = _block(adultId: 's1', dayOfWeek: 3, role: 'lead');
      final mon = _block(adultId: 's1', dayOfWeek: 1, role: 'lead');
      expect(leadBlocksMissingGroup([wed, mon]), [1, 3]);
    });
  });
}
