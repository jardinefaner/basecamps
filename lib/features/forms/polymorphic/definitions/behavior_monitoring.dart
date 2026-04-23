import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:flutter/material.dart';

/// Behavior monitoring — 1–2 week follow-up after a parent concern
/// is logged. Exists only as a child of a parent_concern submission;
/// the "Start monitoring" button on the concern detail creates one
/// linked via `parent_submission_id`.
///
/// Structured as three phases the paper form walks through:
///   1. Setup                       — who, when, what we're watching.
///   2. Monitoring period           — narrative of what happened.
///   3. Review + follow-up          — improved / not, final outcome.
///
/// The form's status transitions: draft → active (on first save) →
/// completed (when follow-up section is filled). Today's flags strip
/// uses `reviewDueAfterDays` to surface "review due" signals when the
/// period elapses without a final entry.
const FormDefinition behaviorMonitoringForm = FormDefinition(
  typeKey: 'behavior_monitoring',
  title: 'Behavior monitoring',
  shortTitle: 'Behavior monitoring',
  subtitle: '1–2 week follow-up after a parent concern.',
  icon: Icons.visibility_outlined,
  subjectKind: FormSubjectKind.child,
  parentTypeKey: 'parent_concern',
  // Paper form says "1–2 weeks following the completion of the
  // Parent Concern Checklist." We split the difference at 10 days —
  // that's when the "review due" flag fires on Today.
  reviewDueAfterDays: 10,
  sections: [
    FormSection(
      title: 'Setup',
      fields: [
        FormTextField(
          key: 'child_names',
          label: 'Child / children name(s)',
        ),
        FormDateField(
          key: 'monitoring_began',
          label: 'Date monitoring began',
        ),
        FormTextField(key: 'supervisor', label: 'Supervisor'),
        FormTextField(
          key: 'staff_involved',
          label: 'Staff involved',
          helpText: 'Names of everyone on the monitoring team.',
          maxLines: 2,
        ),
      ],
    ),
    FormSection(
      title: 'Behavior being monitored',
      subtitle: 'Brief description of the concern or situation.',
      fields: [
        FormTextField(
          key: 'concern_description',
          label: 'Concern',
          maxLines: 4,
        ),
      ],
    ),
    FormSection(
      title: 'Monitoring period',
      subtitle: 'During this time staff will observe, support, and '
          'document. Check the actions actively used.',
      fields: [
        FormMultiChoiceField(
          key: 'staff_actions',
          label: 'Staff actions during monitoring',
          options: [
            FormChoiceOption(
              key: 'increase_awareness',
              label: 'Increase staff awareness of the situation',
            ),
            FormChoiceOption(
              key: 'restorative_conversations',
              label: 'Support restorative conversations if peer '
                  'conflict occurs',
            ),
            FormChoiceOption(
              key: 'reinforce_expectations',
              label: 'Reinforce expectations of respect, safety, '
                  'and kindness',
            ),
            FormChoiceOption(
              key: 'positive_reinforcement',
              label: 'Provide positive reinforcement when '
                  'appropriate behaviors are observed',
            ),
            FormChoiceOption(
              key: 'document_bor',
              label: 'Document concerning behavior via BOR / '
                  'incident report if observed',
            ),
          ],
        ),
        FormTextField(
          key: 'period_notes',
          label: 'Notes',
          helpText: 'Observations from the monitoring period.',
          maxLines: 4,
        ),
      ],
    ),
    FormSection(
      title: 'Behavior review',
      subtitle: 'At the end of the monitoring period, supervisor + '
          'staff review observations together.',
      fields: [
        FormChoiceField(
          key: 'review_outcome',
          label: 'Outcome',
          options: [
            FormChoiceOption(
              key: 'improved',
              label: 'Improved — comfortable participating, no '
                  'further incidents',
            ),
            FormChoiceOption(
              key: 'not_improved',
              label: 'Not improved — next-step follow-ups needed',
            ),
          ],
        ),
        FormMultiChoiceField(
          key: 'next_steps',
          label: 'Next steps (if not improved)',
          options: [
            FormChoiceOption(
              key: 'parent_meeting',
              label: 'Schedule follow-up meeting with '
                  'parent / guardian',
            ),
            FormChoiceOption(
              key: 'adjust_support_plan',
              label: 'Adjust or expand the behavior support plan',
            ),
            FormChoiceOption(
              key: 'increase_supervision',
              label: 'Increase supervision and structured staff '
                  'check-ins',
            ),
            FormChoiceOption(
              key: 'restorative_conversation',
              label: 'Facilitate restorative conversation between '
                  'children involved',
            ),
            FormChoiceOption(
              key: 'continue_documentation',
              label: 'Continue documentation via BOR / incident '
                  'reports',
            ),
          ],
        ),
        FormTextField(
          key: 'additional_actions',
          label: 'Additional actions',
          maxLines: 3,
        ),
        FormTextField(
          key: 'review_notes',
          label: 'Review notes',
          maxLines: 3,
        ),
      ],
    ),
    FormSection(
      title: 'Final follow-up',
      fields: [
        FormDateField(
          key: 'followup_date',
          label: 'Date of follow-up',
        ),
        FormTextField(
          key: 'followup_summary',
          label: 'Summary of outcome',
          maxLines: 4,
        ),
        FormTextField(
          key: 'supervisor_signature',
          label: 'Supervisor signature (name)',
        ),
      ],
    ),
  ],
);
