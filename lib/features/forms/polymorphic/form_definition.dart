import 'package:flutter/material.dart';

/// What sort of subject a form scopes to. Drives which context-link
/// column on `form_submissions` is populated at save time, and
/// whether the form shows a subject picker at the top.
enum FormSubjectKind {
  /// Trip-scoped — vehicle check, trip sign-off. Links to `trip_id`.
  trip,

  /// Child-scoped — behavior monitoring, incident report. Links to
  /// `child_id`.
  child,

  /// Group-scoped. Links to `group_id`.
  group,

  /// No structured subject — general-purpose form (daily note, etc).
  none,
}

/// Lifecycle states a submission can be in. Most forms live briefly
/// in `draft` while being filled, then snap to `completed` on save.
/// Long-running forms (behavior monitoring has a 1–2 week window)
/// sit in `active` between creation and final review.
enum FormStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  archived('archived');

  const FormStatus(this.dbValue);
  final String dbValue;

  static FormStatus fromDb(String? raw) {
    for (final s in FormStatus.values) {
      if (s.dbValue == raw) return s;
    }
    return FormStatus.draft;
  }
}

/// One field on a form. Subclassed per input type so the generic
/// renderer can switch on shape without a mapping table.
sealed class FormField {
  const FormField({
    required this.key,
    required this.label,
    this.helpText,
    this.required = false,
  });

  /// Stable identifier — becomes the JSON key in the submission's
  /// `data` blob. Keep stable forever once a form ships; renaming
  /// orphans existing data.
  final String key;

  /// Human-readable label next to the input.
  final String label;

  /// Optional secondary text under the label.
  final String? helpText;

  /// Whether the form blocks "Submit" when this field is empty. Draft
  /// saves ignore this.
  final bool required;
}

/// Free-form single- or multi-line text. [maxLines] > 1 renders a
/// grow-to-content box; 1 keeps a single-line field.
class FormTextField extends FormField {
  const FormTextField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    this.hint,
    this.maxLines = 1,
  });
  final String? hint;
  final int maxLines;
}

/// Date picker. [includeTime] adds a time-of-day component when the
/// form actually cares when-of-day (most vehicle checks do).
///
/// [defaultsToNow] pre-fills the field with `DateTime.now()` on a
/// fresh submission so teachers don't have to tap through a picker
/// for "just stamp it with when I'm filling this out." Ignored for
/// existing submissions — editing an old row keeps the value that
/// was already there.
class FormDateField extends FormField {
  const FormDateField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    this.includeTime = false,
    this.defaultsToNow = false,
  });
  final bool includeTime;
  final bool defaultsToNow;
}

/// Three-state check-mark / x / unset. Mirrors the paper checklists'
/// "check = acceptable, x = needs attention" convention. Stored as
/// 'ok' | 'attention' | null in the JSON blob.
class FormChecklistStatusField extends FormField {
  const FormChecklistStatusField({
    required super.key,
    required super.label,
    super.helpText,
  });
}

/// Single-choice picker from a fixed list.
class FormChoiceField extends FormField {
  const FormChoiceField({
    required super.key,
    required super.label,
    required this.options,
    super.helpText,
    super.required,
  });
  final List<FormChoiceOption> options;
}

class FormChoiceOption {
  const FormChoiceOption({required this.key, required this.label});
  final String key;
  final String label;
}

/// Multi-select from a fixed list. Stored as a JSON array of option
/// keys in the blob.
class FormMultiChoiceField extends FormField {
  const FormMultiChoiceField({
    required super.key,
    required super.label,
    required this.options,
    super.helpText,
  });
  final List<FormChoiceOption> options;
}

/// Simple on/off toggle.
class FormBoolField extends FormField {
  const FormBoolField({
    required super.key,
    required super.label,
    super.helpText,
  });
}

/// Grouping of related fields on the form. Rendered as a titled
/// section — keeps long checklists scannable.
class FormSection {
  const FormSection({
    required this.title,
    required this.fields,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<FormField> fields;
}

/// Layout shape for a form. `scroll` renders every section stacked
/// on a single screen — right for short forms and for editing
/// existing rows where the teacher wants random access. `wizard`
/// renders one section per page with Next/Back buttons — right for
/// fill-from-scratch checklists where working top-to-bottom keeps
/// the teacher from missing rows.
enum FormPresentation { scroll, wizard }

/// Top-level description of a form type. One of these per form
/// (vehicle_check, behavior_monitoring, …). The generic renderer
/// walks it to build the UI; the registry maps `typeKey` strings
/// back to definitions at read-time.
class FormDefinition {
  const FormDefinition({
    required this.typeKey,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.icon,
    required this.subjectKind,
    required this.sections,
    this.parentTypeKey,
    this.reviewDueAfterDays,
    this.presentation = FormPresentation.scroll,
  });

  /// On-disk encoding — stays stable forever. 'vehicle_check', etc.
  final String typeKey;

  /// Full human title, shown in the form's own AppBar.
  final String title;

  /// Short scannable label for the forms hub + list-screen tiles.
  /// "Vehicle check", "Behavior monitoring."
  final String shortTitle;

  /// One-line description shown under the tile on the forms hub.
  final String subtitle;

  final IconData icon;
  final FormSubjectKind subjectKind;
  final List<FormSection> sections;

  /// For follow-up forms — the typeKey of the parent form. A
  /// `behavior_monitoring` declares `parentTypeKey: 'parent_concern'`
  /// so UIs know to only allow creation from a concern context.
  final String? parentTypeKey;

  /// How many days after creation the form should flag "review due"
  /// on Today. Null = never flags.
  final int? reviewDueAfterDays;

  /// Scroll (one-page-all-sections) vs wizard (one-section-per-page).
  /// Defaults to scroll; form types that benefit from forced linear
  /// progression (checklists, end-of-day reports) flip to wizard.
  final FormPresentation presentation;
}
