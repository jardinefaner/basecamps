import 'dart:convert';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/incident.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/vehicle_check.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stable fixtures so the "Submitted …" timestamp line reads the same
/// in every assertion regardless of CI clock skew.
final _submitted = DateTime(2026, 4, 24, 9, 30);
final _created = DateTime(2026, 4, 23, 8);

FormSubmission _submission({
  required String formType,
  required Map<String, dynamic> data,
  DateTime? submittedAt,
  DateTime? createdAt,
  String? authorName,
  String? childId,
}) {
  final stamp = createdAt ?? _created;
  return FormSubmission(
    id: 'sub-1',
    formType: formType,
    status: 'completed',
    submittedAt: submittedAt ?? _submitted,
    authorName: authorName,
    childId: childId,
    data: jsonEncode(data),
    createdAt: stamp,
    updatedAt: stamp,
  );
}

/// Minimal fake definition so the multi-choice / bool / date test
/// doesn't have to lean on a real form's evolving fields.
const FormDefinition _mixedForm = FormDefinition(
  typeKey: 'mixed_form',
  title: 'Mixed Form',
  shortTitle: 'Mixed',
  subtitle: 'Test fixture.',
  icon: Icons.assignment_outlined,
  subjectKind: FormSubjectKind.none,
  sections: [
    FormSection(
      title: 'Details',
      fields: [
        FormDateField(
          key: 'when',
          label: 'When',
          includeTime: true,
        ),
        FormMultiChoiceField(
          key: 'tags',
          label: 'Tags',
          options: [
            FormChoiceOption(key: 'a', label: 'Alpha'),
            FormChoiceOption(key: 'b', label: 'Beta'),
            FormChoiceOption(key: 'c', label: 'Gamma'),
          ],
        ),
        FormBoolField(
          key: 'resolved',
          label: 'Resolved',
        ),
      ],
    ),
  ],
);

void main() {
  group('buildFormSubmissionShareText', () {
    test('vehicle check with every section filled renders full bundle', () {
      final text = buildFormSubmissionShareText(
        submission: _submission(
          formType: 'vehicle_check',
          authorName: 'Ms. Rivera',
          data: {
            'vehicle_id': 'v-1',
            'driver_name': 'Ms. Rivera',
            'check_datetime': DateTime(2026, 4, 24, 8, 15).toIso8601String(),
            'odometer': '123456',
            'fuel_level': 'half',
            // A handful of checklist items — two OK, one attention.
            'headlights': 'ok',
            'brakes': 'ok',
            'brake_lights': 'attention',
            'tires_inflated': 'ok',
            'notes': '  Rear right tire low; topped off to 35 psi.  ',
          },
        ),
        definition: vehicleCheckForm,
        vehicleNamesById: {
          'v-1': 'Big Bus \u00b7 Ford Transit 350 \u00b7 ABC-1234',
        },
        childNamesById: const {},
      );

      expect(text, startsWith('Vehicle Safety Inspection Checklist\n'));
      expect(text, contains('Submitted Apr 24, 2026 \u00b7 9:30a \u00b7 Ms. Rivera'));
      expect(
        text,
        contains('Vehicle: Big Bus \u00b7 Ford Transit 350 \u00b7 ABC-1234'),
      );
      expect(text, contains('Driver name: Ms. Rivera'));
      expect(text, contains('\u2713 OK'));
      expect(text, contains('\u2717 Needs inspection'));
      // Notes field is trimmed before rendering.
      expect(
        text,
        contains('Rear right tire low; topped off to 35 psi.'),
      );
      expect(text, isNot(contains('  Rear right tire low')));
      expect(text, endsWith('\u2014 Basecamp'));
    });

    test('all-OK vehicle check with no notes omits empty sections', () {
      // Find one of the checklist sections in the form and mark every
      // status field OK. Leave every text field blank. Expect the
      // notes-ish text sections to disappear from the output and the
      // checklist sections to print a string of "✓ OK" lines.
      final data = <String, dynamic>{
        'vehicle_id': 'v-1',
      };
      for (final s in vehicleCheckForm.sections) {
        for (final f in s.fields) {
          if (f is FormChecklistStatusField) {
            data[f.key] = 'ok';
          }
        }
      }

      final text = buildFormSubmissionShareText(
        submission: _submission(
          formType: 'vehicle_check',
          data: data,
        ),
        definition: vehicleCheckForm,
        vehicleNamesById: {'v-1': 'Big Bus'},
        childNamesById: const {},
      );

      expect(text, contains('\u2713 OK'));
      expect(text, isNot(contains('\u2717')));
      // Driver name / odometer / notes (optional text fields) should
      // all be omitted — no bare labels with trailing colons.
      expect(text, isNot(contains('Driver name:')));
      expect(text, isNot(contains('Odometer')));
      expect(text, isNot(contains('Notes:')));
      // Author defaulted to "Basecamp" when authorName is null.
      expect(text, contains('\u00b7 Basecamp'));
    });

    test('incident with a deleted child renders the "(deleted child)" fallback', () {
      final text = buildFormSubmissionShareText(
        submission: _submission(
          formType: 'incident',
          childId: 'c-gone',
          data: {
            'child_id': 'c-gone',
            'incident_datetime':
                DateTime(2026, 4, 23, 14, 5).toIso8601String(),
            'description': 'Scraped knee on the playground.',
            'parent_notified': true,
          },
        ),
        definition: incidentForm,
        vehicleNamesById: const {},
        childNamesById: const {
          // Note: c-gone NOT in the map — simulates a deleted row.
          'c-other': 'Maya R.',
        },
      );

      expect(text, contains('(deleted child)'));
      // Rest of the form still renders intact.
      expect(text, contains('Scraped knee on the playground.'));
      expect(text, contains('Parent notified: Yes'));
      expect(text, contains('Apr 23, 2026 \u00b7 2:05p'));
    });

    test('multi-choice + bool + date render in spec format', () {
      final text = buildFormSubmissionShareText(
        submission: _submission(
          formType: 'mixed_form',
          data: {
            'when': DateTime(2026, 4, 24, 9, 30).toIso8601String(),
            // Store out-of-order to prove the formatter sorts by
            // definition order, not storage order.
            'tags': ['c', 'a'],
            'resolved': false,
          },
        ),
        definition: _mixedForm,
        vehicleNamesById: const {},
        childNamesById: const {},
      );

      expect(text, contains('When: Apr 24, 2026 \u00b7 9:30a'));
      expect(text, contains('Tags: Alpha, Gamma'));
      expect(text, contains('Resolved: No'));
    });

    test('missing submittedAt falls back to createdAt for the header line', () {
      final text = buildFormSubmissionShareText(
        submission: FormSubmission(
          id: 'sub-draft',
          formType: 'mixed_form',
          status: 'draft',
          data: jsonEncode({'resolved': true}),
          createdAt: DateTime(2026, 3, 15, 7, 5),
          updatedAt: DateTime(2026, 3, 15, 7, 5),
        ),
        definition: _mixedForm,
        vehicleNamesById: const {},
        childNamesById: const {},
      );

      expect(text, contains('Submitted Mar 15, 2026 \u00b7 7:05a'));
      expect(text, contains('Resolved: Yes'));
    });
  });
}
