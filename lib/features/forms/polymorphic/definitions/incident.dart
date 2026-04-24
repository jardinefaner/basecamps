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
/// Child is picked as free text for now — a proper FormChildPickerField
/// can land in a follow-up slice (same shape as the existing
/// FormVehiclePickerField, just pointing at children). The typed
/// child_id FK on form_submissions already handles the linkage once
/// a picker exists, so swapping in a picker later is purely a
/// renderer change.
const FormDefinition incidentForm = FormDefinition(
  typeKey: 'incident',
  title: 'Incident report',
  shortTitle: 'Incident',
  subtitle: 'Injury, behavior, or other staff-observed incident on a child.',
  icon: Icons.report_problem_outlined,
  subjectKind: FormSubjectKind.child,
  presentation: FormPresentation.wizard,
  sections: [
    FormSection(
      title: 'About the incident',
      fields: [
        // Until a proper child picker lands, this is a free-text
        // field. The child_id FK on form_submissions stays unset for
        // now — the data blob holds the typed name.
        FormTextField(
          key: 'child_name',
          label: 'Child',
          hint: "Child's name",
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
        // tri-state for "unset"). We flag this as the
        // notification-section anchor via the wizard's forced walk
        // instead: the teacher can't submit without seeing this page.
        FormBoolField(
          key: 'parent_notified',
          label: 'Parent notified',
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
