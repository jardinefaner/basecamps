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
    this.showWhen,
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

  /// Optional predicate: render this field only when the predicate
  /// returns true given the current `data` map. Lets a form branch
  /// (e.g. "if `notify_parent` is true, show `notification_method`")
  /// without splitting into two FormDefinitions.
  ///
  /// `required` is also gated by this — a hidden required field
  /// doesn't block submit. The predicate runs on every rebuild, so
  /// keep it cheap (read keys, compare, return bool — no I/O).
  ///
  /// Null means "always show" (the default). Same predicate signature
  /// works at the [FormSection] level for whole-section gating.
  final FormVisibilityPredicate? showWhen;
}

/// Tiny shared signature for visibility gates so fields and sections
/// look at the same shape.
typedef FormVisibilityPredicate = bool Function(
  Map<String, dynamic> data,
);

/// Keyboard flavors a FormTextField can request. Numeric fields
/// (odometer, fuel level, phone number) pop the number pad instead
/// of the full QWERTY — teachers hit digits faster and can't
/// accidentally type letters into a count field.
enum FormTextKeyboard { text, number, phone, email, multiline }

/// Free-form single- or multi-line text. [maxLines] > 1 renders a
/// grow-to-content box; 1 keeps a single-line field. [keyboard]
/// picks which on-screen keyboard pops up — defaults to the full
/// text keyboard; switch to `number` on odometer / count / plate
/// fields, `phone` on phone-number fields, etc.
class FormTextField extends FormField {
  const FormTextField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
    this.hint,
    this.maxLines = 1,
    this.keyboard = FormTextKeyboard.text,
  });
  final String? hint;
  final int maxLines;
  final FormTextKeyboard keyboard;
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
    super.showWhen,
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
    super.showWhen,
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
    super.showWhen,
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
    super.showWhen,
  });
  final List<FormChoiceOption> options;
}

/// Simple on/off toggle.
class FormBoolField extends FormField {
  const FormBoolField({
    required super.key,
    required super.label,
    super.helpText,
    super.showWhen,
  });
}

/// Pick-from-list for a Vehicle row. Stores the vehicle's id in the
/// form's JSON data blob; the renderer resolves the id back into a
/// name + make/model + plate line when displaying. Historical forms
/// keep their recorded id even if the vehicle is deleted later — the
/// UI renders "(deleted vehicle)" in that case. Tap-through to
/// `/more/vehicles` is offered from the picker sheet so teachers
/// can add a missing vehicle inline without losing their draft.
class FormVehiclePickerField extends FormField {
  const FormVehiclePickerField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
  });
}

/// Pick-from-list for a Child row. Stores the child's id in the
/// form's JSON data blob. When the field's `key` is `child_id`
/// (the conventional FK key), the renderer ALSO writes through to
/// the typed `child_id` column on FormSubmission at save time, so
/// the submission genuinely joins to the child (vs. just carrying
/// the id in JSON). Keeps incidents and other child-scoped forms
/// queryable from the child detail screen.
class FormChildPickerField extends FormField {
  const FormChildPickerField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
  });
}

/// Pick-from-list for an Adult row. Mirror of [FormChildPickerField]
/// for staff. Stores the adult's id in the data blob. Forms that
/// reference a specific staff member (incident report's responding
/// staff, signed-off-by, etc.) use this instead of free-text.
///
/// On historical rows where the adult was deleted later, the
/// renderer shows "(deleted adult)" in place of the name.
class FormAdultPickerField extends FormField {
  const FormAdultPickerField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
  });
}

/// Numeric input. Stores as int (when [decimals] is 0) or double.
/// Validates against [min] / [max] before submit; out-of-range
/// values trigger inline error text on the field.
///
/// [units] renders as a suffix label inside the input ("min",
/// "miles", "°F", etc) — visual cue, doesn't affect storage.
class FormNumberField extends FormField {
  const FormNumberField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
    this.min,
    this.max,
    this.decimals = 0,
    this.units,
  });

  final num? min;
  final num? max;

  /// 0 = integer (renders without a decimal point in the keyboard);
  /// >0 = decimal field with that many places displayed. Stored
  /// values keep full precision regardless.
  final int decimals;

  /// Suffix label like "min", "%", "°F". Display-only; values
  /// don't include it in storage.
  final String? units;
}

/// Image / photo upload. Captures or picks a photo via the
/// device's image picker, uploads to MediaService into the
/// per-form bucket area, and stores both the storage path and the
/// local cache path under one composite JSON object keyed by the
/// field's [key]:
///
///     {
///       "localPath": "/path/...",
///       "storagePath": "<programId>/forms/<rowId>/<fieldKey>.<ext>"
///     }
///
/// Other devices read `storagePath` and lazy-download via
/// `MediaService.ensureLocalFile`. Original device sees its local
/// file directly until cache is cleared.
///
/// [allowGallery] gates whether the picker offers "choose from
/// library" alongside camera. False for forms that need
/// teacher-witnessed evidence (must be a fresh photo).
class FormImageField extends FormField {
  const FormImageField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
    this.allowGallery = true,
  });

  final bool allowGallery;
}

/// Multi-select picker for children. Stores a JSON array of child
/// ids in the data blob: `["id1", "id2", "id3"]`. Forms that
/// scope to multiple children (parent concern, group incident
/// reports) use this instead of the single-pick variant.
///
/// The renderer pre-fills from the typed `child_id` column when
/// `key` is the conventional `'child_ids'` and the submission's
/// child_id was set on a prior save (rare — covers the upgrade
/// path from single-child to multi-child forms).
class FormMultiChildPickerField extends FormField {
  const FormMultiChildPickerField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
  });
}

/// Multi-line free text + an inline signature pad + a captured
/// signed-on date. Stores all three under one composite JSON
/// object in the data blob:
///
///     {
///       "name": "Jardine Faner",       // typed printed name
///       "signaturePath": "/path/...",   // local file path of PNG
///       "signedAt": "2026-04-27T..."    // ISO timestamp
///     }
///
/// Either of the three can be missing (e.g. typed name without a
/// drawn signature is "typed signature"; a drawn signature alone
/// is anonymous). The renderer captures the signature drawing to
/// a per-form local file via the existing InlineSignaturePad
/// widget and stamps the path here.
///
/// Long-term the signaturePath will follow MediaService's
/// upload-on-attach pattern so signatures sync across devices like
/// observation attachments. For v1 the local-only path is fine —
/// signed forms are typically completed on one device and reviewed
/// from there.
class FormSignatureField extends FormField {
  const FormSignatureField({
    required super.key,
    required super.label,
    super.helpText,
    super.required,
    super.showWhen,
  });
}

/// Grouping of related fields on the form. Rendered as a titled
/// section — keeps long checklists scannable.
class FormSection {
  const FormSection({
    required this.title,
    required this.fields,
    this.subtitle,
    this.showWhen,
  });
  final String title;
  final String? subtitle;
  final List<FormField> fields;

  /// Optional predicate. When provided, the renderer skips the
  /// whole section (header + every field) unless the predicate
  /// returns true on the current data map. Use this when a wizard
  /// page should appear only on certain branches.
  final FormVisibilityPredicate? showWhen;
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
    this.submitPredicate,
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

  /// Optional gate run at submit time (not on draft saves). Returns
  /// a non-null error message when the form's cross-field invariant
  /// fails — "parent_notified must be true, or notification_reason
  /// must be filled in". Null return means pass. Rendered as a
  /// snackbar; the form stays in draft.
  final String? Function(Map<String, dynamic> data)? submitPredicate;
}
