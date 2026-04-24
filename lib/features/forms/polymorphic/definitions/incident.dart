import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:flutter/material.dart';

/// Staff-observed incident on a child — scrapes, bumps, bites, and
/// behavior incidents. Distinct from parent_concern (which is a
/// parent-reported situation captured at pickup/drop-off); this one
/// is filled in by staff in the moment after something happens in
/// the room or on the playground.
///
/// Presentation is [FormPresentation.wizard] so the teacher gets
/// walked linearly through description → response → notification →
/// follow-up. The Notification section in particular has bitten
/// programs before when it gets skipped; forcing a page per section
/// makes "did we call the parent?" un-skippable.
///
/// Child selection goes through the typed [FormChildPickerField] so
/// the submission writes the typed `child_id` FK on form_submissions
/// — that's what lets the child detail screen's recap query pick
/// this incident up via `s.childId == child.id`.
/// Submit gate for the incident form: either the parent has been
/// notified, or the teacher has documented why notification hasn't
/// happened yet. Returns null on pass, an error message otherwise.
///
/// Pulled out as a top-level function so [incidentForm] stays `const`
/// (the registry declares the list const, and an inline closure
/// isn't a constant expression — a top-level function tear-off is).
String? incidentSubmitPredicate(Map<String, dynamic> data) {
  final notified = data['parent_notified'] as bool? ?? false;
  if (notified) return null;
  // Accept a "why not yet" explanation as a valid alternative —
  // first-aid-only incidents a teacher hasn't yet called home about
  // should be documentable, not blocked.
  final explain =
      (data['notification_not_yet_reason'] as String?)?.trim() ?? '';
  if (explain.isNotEmpty) return null;
  return 'Parent notification is required before submitting. '
      'Toggle Parent notified, or add a note in '
      "'If not notified yet — why' explaining.";
}

const FormDefinition incidentForm = FormDefinition(
  typeKey: 'incident',
  title: 'Incident report',
  shortTitle: 'Incident',
  subtitle: 'Injury, behavior, or other staff-observed incident on a child.',
  icon: Icons.report_problem_outlined,
  subjectKind: FormSubjectKind.child,
  presentation: FormPresentation.wizard,
  // Parent notification is the one section that's historically gotten
  // skipped with the wizard at its defaults; enforce a cross-field
  // gate at submit time via the top-level tear-off above. Either the
  // switch is flipped on, or the "why not yet" note is filled in —
  // otherwise, no submit.
  submitPredicate: incidentSubmitPredicate,
  sections: [
    FormSection(
      title: 'About the incident',
      fields: [
        FormChildPickerField(
          key: 'child_id',
          label: 'Who was affected',
          required: true,
        ),
        FormDateField(
          key: 'incident_datetime',
          label: 'When',
          includeTime: true,
          defaultsToNow: true,
          required: true,
        ),
        FormTextField(
          key: 'activity_label',
          label: 'Activity happening at the time',
        ),
        FormTextField(
          key: 'location',
          label: 'Where',
          hint: 'Main room, playground, hallway',
        ),
      ],
    ),
    FormSection(
      title: 'What happened',
      fields: [
        FormTextField(
          key: 'description',
          label: 'Description',
          maxLines: 5,
          required: true,
        ),
        FormChoiceField(
          key: 'severity',
          label: 'Type',
          required: true,
          options: [
            FormChoiceOption(
              key: 'bump_or_bruise',
              label: 'Bump / bruise',
            ),
            FormChoiceOption(
              key: 'scratch_or_scrape',
              label: 'Scratch / scrape',
            ),
            FormChoiceOption(
              key: 'cut_or_bite',
              label: 'Cut / bite',
            ),
            FormChoiceOption(
              key: 'behavioral',
              label: 'Behavioral incident',
            ),
            FormChoiceOption(
              key: 'other',
              label: 'Other',
            ),
          ],
        ),
        FormTextField(
          key: 'body_area',
          label: 'Part of body affected (if applicable)',
        ),
      ],
    ),
    FormSection(
      title: 'Response',
      fields: [
        FormTextField(
          key: 'immediate_action',
          label: 'Immediate action',
          hint: 'What staff did in the moment',
          maxLines: 3,
          required: true,
        ),
        FormBoolField(
          key: 'first_aid_administered',
          label: 'First aid administered',
        ),
        FormTextField(
          key: 'first_aid_details',
          label: 'First aid details',
          maxLines: 3,
        ),
      ],
    ),
    FormSection(
      title: 'Notification',
      subtitle: 'Who was told and how.',
      fields: [
        // Bool fields can't be marked required (a false is a
        // meaningful "no, haven't yet" answer — the renderer has no
        // tri-state for "unset"). Cross-field enforcement lives in
        // `incidentSubmitPredicate` above: submit requires either
        // this switch ON, or the "why not yet" note below filled in.
        FormBoolField(
          key: 'parent_notified',
          label: 'Parent notified',
        ),
        // Escape hatch for the submit predicate. A first-aid-only
        // scrape that happened ten minutes before pickup still needs
        // documenting — teacher can explain here instead of flipping
        // the switch, and the form submits.
        FormTextField(
          key: 'notification_not_yet_reason',
          label: 'If not notified yet — why',
          helpText: 'Required when Parent notified is left off.',
          maxLines: 2,
        ),
        // Not conditionally rendered — the renderer doesn't branch on
        // field values, and hiding-then-showing this would make the
        // wizard page count jiggle. Just leave it; it's a no-op when
        // parent_notified is false.
        FormDateField(
          key: 'notified_when',
          label: 'Notified when',
          includeTime: true,
        ),
        FormChoiceField(
          key: 'notified_how',
          label: 'Notified how',
          options: [
            FormChoiceOption(key: 'in_person', label: 'In person'),
            FormChoiceOption(key: 'phone', label: 'Phone'),
            FormChoiceOption(key: 'text', label: 'Text'),
            FormChoiceOption(key: 'email', label: 'Email'),
          ],
        ),
        FormBoolField(
          key: 'supervisor_notified',
          label: 'Supervisor notified',
        ),
      ],
    ),
    FormSection(
      title: 'Follow-up',
      fields: [
        FormBoolField(
          key: 'needs_followup',
          label: 'Needs follow-up',
        ),
        FormTextField(
          key: 'followup_plan',
          label: 'Follow-up plan',
          maxLines: 3,
        ),
        FormDateField(
          key: 'followup_date',
          label: 'Follow-up date',
        ),
      ],
    ),
  ],
);
