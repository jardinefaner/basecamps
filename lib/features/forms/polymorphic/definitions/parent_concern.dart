import 'package:basecamp/features/forms/polymorphic/form_definition.dart';
import 'package:flutter/material.dart';

/// Parent-reported concern raised at pickup / drop-off / over the
/// phone. Distinct from `incident` (staff-observed in the room) —
/// this one captures what a parent told staff, the response staff
/// gave in the moment, and the follow-up plan. Migrated from a
/// bespoke ParentConcernNotes table into the polymorphic system so
/// every form type now lives under one schema.
///
/// Wizard presentation. Six pages walk the staff member through:
///   1. Who + when (children, parent, date, who took it)
///   2. How it was raised (in person / phone / email / other text)
///   3. What was said + the in-the-moment response
///   4. Supervisor notified
///   5. Follow-up plan (checkboxes + free-text + due-by date)
///   6. Signatures (staff + supervisor)
///
/// Multi-child via [FormMultiChildPickerField] — most concerns scope
/// to one kid but siblings come up enough that picking multiple
/// up-front is the right default. Signatures via the new
/// [FormSignatureField] (typed name + drawn pad + signed-at).
const FormDefinition parentConcernForm = FormDefinition(
  typeKey: 'parent_concern',
  title: 'Parent concern note',
  shortTitle: 'Parent concern',
  subtitle:
      'Parent raised a concern at pickup, on the phone, or over email — '
      'capture what they said and the follow-up plan.',
  icon: Icons.support_agent_outlined,
  subjectKind: FormSubjectKind.child,
  presentation: FormPresentation.wizard,
  sections: [
    FormSection(
      title: 'Who and when',
      fields: [
        FormMultiChildPickerField(
          key: 'child_ids',
          label: 'Children involved',
          helpText: 'Pick every child the concern is about — siblings, '
              'classmates, etc. Most concerns scope to one.',
          required: true,
        ),
        FormTextField(
          key: 'parent_name',
          label: "Parent / guardian's name",
          required: true,
        ),
        FormDateField(
          key: 'concern_date',
          label: 'Date the concern was raised',
          defaultsToNow: true,
          required: true,
        ),
        FormTextField(
          key: 'staff_receiving',
          label: 'Staff who took the concern',
          helpText: 'Your name (or the name of whoever heard it).',
        ),
      ],
    ),
    FormSection(
      title: 'How it was raised',
      subtitle: 'Multiple methods are allowed — a phone call followed '
          'by an email about the same issue ticks both.',
      fields: [
        FormBoolField(
          key: 'method_in_person',
          label: 'In person',
        ),
        FormBoolField(
          key: 'method_phone',
          label: 'Phone',
        ),
        FormBoolField(
          key: 'method_email',
          label: 'Email',
        ),
        FormTextField(
          key: 'method_other',
          label: 'Other (specify)',
          hint: 'Text message, written note, etc.',
        ),
      ],
    ),
    FormSection(
      title: 'What was said',
      fields: [
        FormTextField(
          key: 'concern_description',
          label: 'The concern, in their words',
          maxLines: 6,
          keyboard: FormTextKeyboard.multiline,
          required: true,
        ),
        FormTextField(
          key: 'immediate_response',
          label: 'What you said back in the moment',
          maxLines: 4,
          keyboard: FormTextKeyboard.multiline,
        ),
      ],
    ),
    FormSection(
      title: 'Notification',
      fields: [
        FormTextField(
          key: 'supervisor_notified',
          label: 'Supervisor notified',
          helpText: 'Who you told and when, or "not yet — will call '
              'after pickup."',
        ),
      ],
    ),
    FormSection(
      title: 'Follow-up plan',
      subtitle: 'Tick everything that applies plus add detail in the '
          'notes field. The date is when this should be revisited.',
      fields: [
        FormBoolField(
          key: 'follow_up_monitor',
          label: 'Monitor and observe',
        ),
        FormBoolField(
          key: 'follow_up_staff_check_ins',
          label: 'Schedule staff check-ins',
        ),
        FormBoolField(
          key: 'follow_up_supervisor_review',
          label: 'Bring to supervisor review',
        ),
        FormBoolField(
          key: 'follow_up_parent_conversation',
          label: 'Schedule parent conversation',
        ),
        FormTextField(
          key: 'follow_up_other',
          label: 'Other follow-up steps',
          hint: 'Anything not covered by the toggles above.',
          maxLines: 3,
          keyboard: FormTextKeyboard.multiline,
        ),
        FormDateField(
          key: 'follow_up_date',
          label: 'Follow-up by',
        ),
        FormTextField(
          key: 'additional_notes',
          label: 'Additional notes',
          maxLines: 4,
          keyboard: FormTextKeyboard.multiline,
        ),
      ],
    ),
    FormSection(
      title: 'Signatures',
      subtitle: 'Type the printed name; draw on the pad to capture a '
          'visible signature; the date is auto-stamped at sign time.',
      fields: [
        FormSignatureField(
          key: 'staff_signature',
          label: 'Staff signature',
        ),
        FormSignatureField(
          key: 'supervisor_signature',
          label: 'Supervisor signature',
        ),
      ],
    ),
  ],
);
