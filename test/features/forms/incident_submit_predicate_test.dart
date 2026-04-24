import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:flutter_test/flutter_test.dart';

/// The incident form's submit predicate enforces a cross-field rule:
/// either the parent has been notified, or the teacher has documented
/// why notification hasn't happened yet. These cases exercise the
/// predicate directly as a pure function — the wizard/renderer path
/// is covered elsewhere.
void main() {
  group('incident submit predicate', () {
    test('passes when parent_notified is true', () {
      final err = incidentForm.submitPredicate!(
        <String, dynamic>{'parent_notified': true},
      );
      expect(err, isNull);
    });

    test('fails when parent_notified is false and no reason given', () {
      final err = incidentForm.submitPredicate!(
        <String, dynamic>{'parent_notified': false},
      );
      expect(err, isNotNull);
      expect(err, contains('Parent notification is required'));
    });

    test('passes when parent_notified is false but reason is provided', () {
      final err = incidentForm.submitPredicate!(<String, dynamic>{
        'parent_notified': false,
        'notification_not_yet_reason':
            'Happened 5 min before pickup; telling parent in person.',
      });
      expect(err, isNull);
    });

    test('fails when parent_notified key is missing entirely', () {
      // Teacher skipped the whole notification section. Unset bool is
      // treated the same as explicit false — the predicate should
      // still fire.
      final err = incidentForm.submitPredicate!(<String, dynamic>{});
      expect(err, isNotNull);
      expect(err, contains('Parent notification is required'));
    });

    test('treats a whitespace-only reason as not-given', () {
      // Don't let "   " through — that's not a real explanation.
      final err = incidentForm.submitPredicate!(<String, dynamic>{
        'parent_notified': false,
        'notification_not_yet_reason': '   ',
      });
      expect(err, isNotNull);
    });
  });
}
