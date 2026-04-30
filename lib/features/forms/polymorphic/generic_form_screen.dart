import 'dart:async';

import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/new_child_wizard.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart'
    as fd;
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_share.dart';
import 'package:basecamp/features/forms/widgets/inline_signature_pad.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/media_service.dart';
import 'package:basecamp/features/vehicles/vehicles_repository.dart';
import 'package:basecamp/features/vehicles/widgets/edit_vehicle_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/media_image.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Generic form renderer. Takes a [fd.FormDefinition] + optional
/// existing submission and produces a scrollable form that writes
/// every field into a single JSON blob on save. Per-form work is
/// reduced to defining the fd.FormDefinition — this widget handles
/// rendering, editing, validation, and save.
///
/// Status transitions:
///   - Fresh open on an existing draft → stays 'draft' until submit.
///   - Tap "Save draft" → writes `data` without changing status.
///   - Tap "Save" (the primary action) → flips to the next phase:
///     'completed' for simple one-shot forms, 'active' for forms
///     with a `parentTypeKey` (like behavior monitoring) that keep
///     running after first save.
class GenericFormScreen extends ConsumerStatefulWidget {
  const GenericFormScreen({
    required this.definition,
    this.submissionId,
    this.parentSubmissionId,
    this.prefillChildId,
    this.prefillGroupId,
    this.prefillTripId,
    this.prefillData = const {},
    super.key,
  });

  /// What form we're rendering. Drives sections, fields, icon, etc.
  final fd.FormDefinition definition;

  /// When non-null, we're editing an existing submission — its data
  /// gets loaded into the local state on mount.
  final String? submissionId;

  /// When non-null (and [submissionId] is null), the form is being
  /// CREATED as a follow-up — save will set `parent_submission_id`
  /// so the child form links back up.
  final String? parentSubmissionId;

  final String? prefillChildId;
  final String? prefillGroupId;
  final String? prefillTripId;

  /// Initial values for specific fields. Useful when a parent form
  /// wants to seed its child form with shared context (child names,
  /// concern description, etc.).
  final Map<String, dynamic> prefillData;

  @override
  ConsumerState<GenericFormScreen> createState() =>
      _GenericFormScreenState();
}

class _GenericFormScreenState extends ConsumerState<GenericFormScreen> {
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};

  /// Per-field controllers for the printed-name input inside
  /// FormSignatureField. Lifted out of _textControllers because
  /// signature fields don't pre-populate via the same hydration
  /// path; values come from the composite map under the field's
  /// own key.
  final Map<String, TextEditingController> _signatureNameControllers = {};

  bool _loading = true;
  bool _submitting = false;
  String? _resolvedSubmissionId;

  @override
  void initState() {
    super.initState();
    _resolvedSubmissionId = widget.submissionId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final isFresh = _resolvedSubmissionId == null;
    if (!isFresh) {
      final row = await ref
          .read(formSubmissionRepositoryProvider)
          .getSubmission(_resolvedSubmissionId!);
      if (row != null) {
        _values.addAll(decodeFormData(row));
      }
    }
    // Apply prefill — only for keys not already populated from an
    // existing submission. This way re-opening an edit doesn't get
    // its previously-saved values overwritten by parent context.
    for (final entry in widget.prefillData.entries) {
      _values.putIfAbsent(entry.key, () => entry.value);
    }
    // Fresh-submission auto-fills. Any field that declares a
    // default-at-creation behavior (currently just
    // FormDateField.defaultsToNow) gets seeded here so the first
    // render already shows the stamp — teacher sees "today, 9:30am"
    // without having to tap the picker. Editing an existing row
    // doesn't hit this path (isFresh=false).
    if (isFresh) {
      final now = DateTime.now();
      for (final section in widget.definition.sections) {
        for (final field in section.fields) {
          if (field is fd.FormDateField &&
              field.defaultsToNow &&
              !_values.containsKey(field.key)) {
            _values[field.key] = now.toIso8601String();
          }
          // Seed the child picker from the prefillChildId parameter.
          // Opening the incident form from a child-detail screen with
          // prefillChildId set lands on step 1 already pointing at
          // that child — teacher doesn't re-pick the subject they
          // came from.
          if (field is fd.FormChildPickerField &&
              widget.prefillChildId != null &&
              !_values.containsKey(field.key)) {
            _values[field.key] = widget.prefillChildId;
          }
        }
      }
    }
    _ensureControllers();
    if (mounted) setState(() => _loading = false);
  }

  /// Text fields need stable controllers across rebuilds. Build one
  /// per text-shaped field the first time we render. Number fields
  /// share the same controller map — the switch on type below picks
  /// the right initializer.
  void _ensureControllers() {
    for (final s in widget.definition.sections) {
      for (final f in s.fields) {
        if (f is fd.FormTextField) {
          _textControllers.putIfAbsent(
            f.key,
            () => TextEditingController(
              text: (_values[f.key] as String?) ?? '',
            ),
          );
        } else if (f is fd.FormNumberField) {
          _textControllers.putIfAbsent(
            f.key,
            () => TextEditingController(
              text: _formatStoredNumber(_values[f.key], f),
            ),
          );
        }
      }
    }
  }

  /// Stringify whatever's already stored under a number field's key
  /// (int, double, or null) so the controller seeds with the right
  /// shape on first build.
  String _formatStoredNumber(Object? value, fd.FormNumberField f) {
    if (value is num) {
      if (f.decimals == 0) return value.toInt().toString();
      return value.toStringAsFixed(f.decimals);
    }
    return '';
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    for (final c in _signatureNameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Resolve the child id to stamp onto the typed `child_id` column.
  /// Priority: any `FormChildPickerField` whose runtime value is set
  /// wins over the screen's prefill. That way a teacher who lands
  /// with a prefill, then changes their mind and picks a different
  /// child from the picker, gets the submission linked to the picked
  /// child — not the original prefill.
  String? _effectiveChildId() {
    for (final section in widget.definition.sections) {
      for (final field in section.fields) {
        if (field is fd.FormChildPickerField) {
          final v = _values[field.key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    }
    return widget.prefillChildId;
  }

  Future<void> _saveDraft() async {
    await _flushTextControllers();
    setState(() => _submitting = true);
    final repo = ref.read(formSubmissionRepositoryProvider);
    try {
      final childId = _effectiveChildId();
      if (_resolvedSubmissionId == null) {
        _resolvedSubmissionId = await repo.createDraft(
          formType: widget.definition.typeKey,
          data: Map<String, dynamic>.from(_values),
          childId: childId,
          groupId: widget.prefillGroupId,
          tripId: widget.prefillTripId,
          parentSubmissionId: widget.parentSubmissionId,
          reviewDueAt: _computeReviewDueAt(),
        );
      } else {
        await repo.updateSubmission(
          id: _resolvedSubmissionId!,
          data: Map<String, dynamic>.from(_values),
          childId: childId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    await _flushTextControllers();
    // Cross-field invariants (e.g. incident's parent-notified-or-
    // documented gate) run here and block the status transition if
    // they fail. Draft saves skip this — partial data is always OK
    // while drafting.
    final predicate = widget.definition.submitPredicate;
    if (predicate != null) {
      final err = predicate(Map<String, dynamic>.from(_values));
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        return;
      }
    }
    setState(() => _submitting = true);
    final repo = ref.read(formSubmissionRepositoryProvider);
    // Follow-up forms (those with a parent) land in 'active' on first
    // save — they keep running through the monitoring period. Simple
    // one-shots jump straight to 'completed'.
    final nextStatus = widget.definition.parentTypeKey != null
        ? fd.FormStatus.active
        : fd.FormStatus.completed;
    try {
      final childId = _effectiveChildId();
      _resolvedSubmissionId ??= await repo.createDraft(
        formType: widget.definition.typeKey,
        data: Map<String, dynamic>.from(_values),
        childId: childId,
        groupId: widget.prefillGroupId,
        tripId: widget.prefillTripId,
        parentSubmissionId: widget.parentSubmissionId,
        reviewDueAt: _computeReviewDueAt(),
      );
      await repo.updateSubmission(
        id: _resolvedSubmissionId!,
        data: Map<String, dynamic>.from(_values),
        status: nextStatus,
        submittedAt: DateTime.now(),
        childId: childId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Review-due deadline = creation date + definition's days, if any.
  /// Simple heuristic; complex forms can override by editing the row
  /// directly after creation.
  DateTime? _computeReviewDueAt() {
    final days = widget.definition.reviewDueAfterDays;
    if (days == null) return null;
    return DateTime.now().add(Duration(days: days));
  }

  /// Copy current controller text into [_values] so "Save" reads the
  /// latest keystrokes even when nothing's triggered a rebuild.
  /// Number fields go through the same map but parse to num; failures
  /// drop silently (the existing on-screen error already flagged it).
  Future<void> _flushTextControllers() async {
    final numberFields = <String, fd.FormNumberField>{};
    for (final s in widget.definition.sections) {
      for (final f in s.fields) {
        if (f is fd.FormNumberField) numberFields[f.key] = f;
      }
    }
    for (final entry in _textControllers.entries) {
      final numField = numberFields[entry.key];
      if (numField == null) {
        _values[entry.key] = entry.value.text;
      } else {
        final parsed = _parseNumber(entry.value.text, numField);
        if (parsed != null) {
          _values[entry.key] = parsed;
        } else if (entry.value.text.trim().isEmpty) {
          _values.remove(entry.key);
        }
      }
    }
  }

  /// Parse a number-field's raw text per its decimals setting. Returns
  /// null for blank input and for unparseable text — caller decides
  /// whether to clear or keep the previous value.
  num? _parseNumber(String raw, fd.FormNumberField field) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (field.decimals == 0) {
      return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
    }
    return double.tryParse(trimmed);
  }

  /// Opens the share bundle preview for the currently-edited
  /// submission. Only wired on the AppBar once [_resolvedSubmissionId]
  /// is non-null (i.e. a row actually exists to share). Unsaved text
  /// edits get flushed first so the share preview reflects what the
  /// teacher sees on screen.
  Future<void> _share() async {
    final id = _resolvedSubmissionId;
    if (id == null) return;
    await _flushTextControllers();
    final row =
        await ref.read(formSubmissionRepositoryProvider).getSubmission(id);
    if (!mounted) return;
    if (row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load this submission.")),
      );
      return;
    }
    await showFormSubmissionShareSheet(context, ref, row, widget.definition);
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(def.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return switch (def.presentation) {
      fd.FormPresentation.scroll => _buildScroll(def),
      fd.FormPresentation.wizard => _buildWizard(def),
    };
  }

  // ---- Presentation: scroll ----

  Widget _buildScroll(fd.FormDefinition def) {
    return Scaffold(
      appBar: AppBar(
        title: Text(def.title),
        actions: [
          // Share is only meaningful once there's a saved row to
          // share — fresh drafts have nothing useful to hand off yet.
          if (_resolvedSubmissionId != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share',
              onPressed: _share,
            ),
          TextButton(
            onPressed: _submitting ? null : _saveDraft,
            child: const Text('Save draft'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        children: [
          for (final section in def.sections)
            if (section.showWhen == null || section.showWhen!(_values)) ...[
              _SectionCard(
                title: section.title,
                subtitle: section.subtitle,
                children: [
                  for (final field in section.fields) _buildField(field),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(
              widget.definition.parentTypeKey == null
                  ? 'Save'
                  : 'Start monitoring',
            ),
          ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  // ---- Presentation: wizard ----

  /// Wraps each section of the form in a [WizardStep] and hands the
  /// whole list to the shared wizard scaffold. The final action is
  /// the same Save / Start-monitoring the scroll layout uses.
  ///
  /// Wizard pages don't pre-validate fields — draft saves are always
  /// allowed, so a half-filled checklist is fine between sessions.
  /// The final step's primary button runs `_submit` (which transitions
  /// the row out of `draft`).
  Widget _buildWizard(fd.FormDefinition def) {
    // Figure out which pages have text inputs so the wizard scaffold
    // knows when to leave the keyboard alone (pages with no text
    // input dismiss focus on transition, so a previous typing page
    // doesn't leave the keyboard up).
    bool sectionNeedsKeyboard(fd.FormSection s) =>
        s.fields.any((f) => f is fd.FormTextField);

    return StepWizardScaffold(
      title: def.title,
      dirty: _values.isNotEmpty,
      finalActionLabel: widget.definition.parentTypeKey == null
          ? 'Save'
          : 'Start monitoring',
      onFinalAction: _submit,
      // Only show the Share button once the wizard is editing an
      // existing row — fresh drafts have nothing useful to share.
      appBarActions: _resolvedSubmissionId == null
          ? null
          : [
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share',
                onPressed: _share,
              ),
            ],
      // Persist the draft on every step advance so the teacher's
      // partial work (vehicle identity on step 1, checklist items
      // as they walk through) survives swiping away, restarts, or
      // a mid-form phone call. Silent save — no snackbar per step.
      onStepAdvance: () async {
        await _flushTextControllers();
        final repo = ref.read(formSubmissionRepositoryProvider);
        final childId = _effectiveChildId();
        if (_resolvedSubmissionId == null) {
          _resolvedSubmissionId = await repo.createDraft(
            formType: widget.definition.typeKey,
            data: Map<String, dynamic>.from(_values),
            childId: childId,
            groupId: widget.prefillGroupId,
            tripId: widget.prefillTripId,
            parentSubmissionId: widget.parentSubmissionId,
            reviewDueAt: _computeReviewDueAt(),
          );
        } else {
          await repo.updateSubmission(
            id: _resolvedSubmissionId!,
            data: Map<String, dynamic>.from(_values),
            childId: childId,
          );
        }
      },
      steps: [
        for (var sectionIndex = 0;
            sectionIndex < def.sections.length;
            sectionIndex++)
          if (def.sections[sectionIndex].showWhen == null ||
              def.sections[sectionIndex].showWhen!(_values))
            _buildWizardStep(
              def: def,
              sectionIndex: sectionIndex,
              keyboardCheck: sectionNeedsKeyboard,
            ),
      ],
    );
  }

  /// Build a [WizardStep] for the section at [sectionIndex]. Splits
  /// the construction out of the for-comprehension so we can wedge
  /// in the per-section + per-form "Mark all OK" affordances
  /// without bloating the inline expression.
  ///
  /// **Section-level shortcut:** sections containing any
  /// `FormChecklistStatusField` get a "Mark all OK & continue →"
  /// button at the top — flips every checklist item to `ok` and
  /// taps Next in one go. Brings the happy-path tap count for a
  /// pre-trip vehicle check down from ~27 to ~10.
  ///
  /// **Form-level shortcut (step 0 only):** when the form has any
  /// checklist anywhere AND we're on the first step, also surface
  /// an "Everything OK — just need notes" button that flips every
  /// checklist field across every section to `ok` and jumps
  /// directly to the last step (typically the Notes / free-text
  /// finish). For "all is well" runs, that's effectively two taps
  /// to fill the form: identity + this button.
  WizardStep _buildWizardStep({
    required fd.FormDefinition def,
    required int sectionIndex,
    required bool Function(fd.FormSection) keyboardCheck,
  }) {
    final section = def.sections[sectionIndex];
    final hasChecklist =
        section.fields.any((f) => f is fd.FormChecklistStatusField);
    final formHasChecklist = def.sections.any(
      (s) => s.fields.any((f) => f is fd.FormChecklistStatusField),
    );
    final isFirstStep = sectionIndex == 0;
    return WizardStep(
      headline: section.title,
      subtitle: section.subtitle,
      canSkip: true,
      needsKeyboard: keyboardCheck(section),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isFirstStep && formHasChecklist)
            _FormMarkAllOkButton(
              definition: def,
              onApply: _markAllChecklistsOk,
            ),
          if (hasChecklist)
            _SectionMarkAllOkButton(
              section: section,
              onApply: () => _markSectionChecklistsOk(section),
            ),
          for (final field in section.fields) _buildField(field),
        ],
      ),
    );
  }

  /// Set every `FormChecklistStatusField` value in [section] to
  /// `'ok'`. Called by the per-section "Mark all OK" button —
  /// the button itself follows up with `WizardController.next()`
  /// to advance once values are flipped.
  void _markSectionChecklistsOk(fd.FormSection section) {
    setState(() {
      for (final f in section.fields) {
        if (f is fd.FormChecklistStatusField) {
          _values[f.key] = 'ok';
        }
      }
    });
  }

  /// Set every `FormChecklistStatusField` value across every
  /// section in this form's definition to `'ok'`. Called by the
  /// form-level "Everything OK" button — the button itself
  /// jumps to the last step (Notes) once values are flipped.
  void _markAllChecklistsOk() {
    setState(() {
      for (final section in widget.definition.sections) {
        for (final f in section.fields) {
          if (f is fd.FormChecklistStatusField) {
            _values[f.key] = 'ok';
          }
        }
      }
    });
  }

  // ---- Field renderers ----

  Widget _buildField(fd.FormField field) {
    // Visibility gate: skip the field entirely (no spacer, no label)
    // when its predicate evaluates false against the current data
    // map. Predicate runs every rebuild — the host setState calls in
    // each input's onChanged are what cause sibling fields with
    // showWhen to re-evaluate.
    if (field.showWhen != null && !field.showWhen!(_values)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: switch (field) {
        fd.FormTextField() => _buildText(field),
        fd.FormDateField() => _buildDate(field),
        fd.FormChecklistStatusField() => _buildChecklistStatus(field),
        fd.FormChoiceField() => _buildChoice(field),
        fd.FormMultiChoiceField() => _buildMultiChoice(field),
        fd.FormBoolField() => _buildBool(field),
        fd.FormVehiclePickerField() => _buildVehiclePicker(field),
        fd.FormChildPickerField() => _buildChildPicker(field),
        fd.FormAdultPickerField() => _buildAdultPicker(field),
        fd.FormMultiChildPickerField() => _buildMultiChildPicker(field),
        fd.FormNumberField() => _buildNumber(field),
        fd.FormImageField() => _buildImage(field),
        fd.FormSignatureField() => _buildSignature(field),
      },
    );
  }

  Widget _buildText(fd.FormTextField field) {
    // Controllers are created eagerly in _ensureControllers() right
    // after values load, so by the time we're rendering fields the
    // map is guaranteed populated. The bang is still needed for the
    // nullable Map<K, V> return type.
    final controller = _textControllers[field.key] ??
        (throw StateError('Missing controller for ${field.key}'));
    return AppTextField(
      controller: controller,
      label: field.label,
      hint: field.hint,
      maxLines: field.maxLines,
      keyboardType: _keyboardTypeFor(field.keyboard),
      onChanged: (v) => _values[field.key] = v,
    );
  }

  /// Map FormTextField.keyboard → Flutter TextInputType. Multiline
  /// tracks maxLines indirectly; we still return the explicit
  /// TextInputType.multiline here so iOS shows the enter-returns-
  /// newline keyboard instead of "Done."
  TextInputType? _keyboardTypeFor(fd.FormTextKeyboard k) {
    return switch (k) {
      fd.FormTextKeyboard.text => null,
      fd.FormTextKeyboard.number => const TextInputType.numberWithOptions(
          decimal: true,
        ),
      fd.FormTextKeyboard.phone => TextInputType.phone,
      fd.FormTextKeyboard.email => TextInputType.emailAddress,
      fd.FormTextKeyboard.multiline => TextInputType.multiline,
    };
  }

  Widget _buildDate(fd.FormDateField field) {
    final raw = _values[field.key] as String?;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    final display = parsed == null
        ? 'Pick a date${field.includeTime ? " & time" : ""}'
        : field.includeTime
            ? formatTimestamp(parsed)
            : DateFormat.yMMMd().format(parsed);
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: OutlinedButton.icon(
        onPressed: () => _pickDate(field, parsed),
        icon: const Icon(Icons.event),
        label: Text(display),
      ),
    );
  }

  Future<void> _pickDate(fd.FormDateField field, DateTime? existing) async {
    final base = existing ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    var result = date;
    if (field.includeTime && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (time != null) {
        result = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      }
    }
    setState(() => _values[field.key] = result.toIso8601String());
  }

  Widget _buildChecklistStatus(fd.FormChecklistStatusField field) {
    final current = _values[field.key] as String?;
    final theme = Theme.of(context);
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: SegmentedButton<String?>(
        segments: const [
          ButtonSegment<String?>(
            value: 'ok',
            icon: Icon(Icons.check, size: 16),
            label: Text('OK'),
          ),
          ButtonSegment<String?>(
            value: 'attention',
            icon: Icon(Icons.priority_high, size: 16),
            label: Text('Needs look'),
          ),
          ButtonSegment<String?>(
            value: null,
            icon: Icon(Icons.remove, size: 16),
            label: Text('—'),
          ),
        ],
        selected: {current},
        onSelectionChanged: (set) => setState(() {
          // `emptySelectionAllowed` means tapping the selected
          // segment deselects it — that lands here as an empty set,
          // not as a `{null}` selection. Treat empty as "clear the
          // value back to unset."
          _values[field.key] = set.isEmpty ? null : set.first;
        }),
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
        ),
      ),
    );
  }

  Widget _buildChoice(fd.FormChoiceField field) {
    final current = _values[field.key] as String?;
    // Single-pick list using FilterChips — cleanest path around the
    // deprecated RadioListTile API while keeping the "one-of-many"
    // semantics explicit. Each chip is tappable; the active one reads
    // as selected.
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final opt in field.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ChoiceChip(
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(opt.label),
                ),
                selected: current == opt.key,
                onSelected: (v) => setState(
                  () => _values[field.key] = v ? opt.key : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMultiChoice(fd.FormMultiChoiceField field) {
    final rawList = _values[field.key];
    final selected = <String>{
      if (rawList is List) ...rawList.whereType<String>(),
    };
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final opt in field.options)
            CheckboxListTile(
              value: selected.contains(opt.key),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  selected.add(opt.key);
                } else {
                  selected.remove(opt.key);
                }
                _values[field.key] = selected.toList();
              }),
              title: Text(opt.label),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
        ],
      ),
    );
  }

  /// Vehicle picker. Shows the currently-selected vehicle as a chip-
  /// like button; tap opens a modal list of all vehicles in the
  /// program, with an "Add vehicle…" tile at the bottom so a teacher
  /// mid-form can add a missing vehicle without bailing out. Stores
  /// the vehicle's id on the field's JSON key.
  Widget _buildVehiclePicker(fd.FormVehiclePickerField field) {
    final selectedId = _values[field.key] as String?;
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final vehicles = vehiclesAsync.asData?.value ?? const <Vehicle>[];
    Vehicle? selected;
    for (final v in vehicles) {
      if (v.id == selectedId) {
        selected = v;
        break;
      }
    }
    // When the stored id no longer resolves (vehicle deleted after
    // the form was filled), we still show the label with a
    // "(deleted)" note so the picker button reads informatively.
    final label = selected != null
        ? _vehicleSummary(selected)
        : selectedId == null
            ? 'Pick a vehicle'
            : '(deleted vehicle)';
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: OutlinedButton.icon(
        onPressed: () => _openVehiclePicker(field, vehicles),
        icon: const Icon(Icons.directions_bus_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
      ),
    );
  }

  String _vehicleSummary(Vehicle v) {
    // Name leads; make/model + plate fall in as a secondary chip
    // when set. Reads cleanly on the button even with just the name.
    final extras = <String>[];
    if (v.makeModel.isNotEmpty) extras.add(v.makeModel);
    if (v.licensePlate.isNotEmpty) extras.add(v.licensePlate);
    return extras.isEmpty ? v.name : '${v.name} · ${extras.join(" · ")}';
  }

  Future<void> _openVehiclePicker(
    fd.FormVehiclePickerField field,
    List<Vehicle> vehicles,
  ) async {
    final selectedId = _values[field.key] as String?;
    final picked = await showModalBottomSheet<_VehiclePickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VehiclePickerSheet(
        vehicles: vehicles,
        selectedId: selectedId,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.addNew) {
      // Open the add sheet; when it pops, the vehicles stream will
      // rebuild us automatically and the new row appears in the list.
      // We don't auto-select the just-created row here — the teacher
      // can re-open the picker and tap it, which is clearer than
      // silently snapping it in.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const EditVehicleSheet(),
      );
      return;
    }
    setState(() {
      _values[field.key] = picked.vehicleId;
    });
  }

  /// Child picker. Mirrors the vehicle picker: the current selection
  /// shows as a chip-like button, tap opens a scrollable modal list
  /// of every child in the program (alphabetical by first name, with
  /// the group label as the subtitle). An "Add new child…" tile at
  /// the bottom routes through the existing [NewChildWizardScreen]
  /// so a teacher mid-form can enroll a child without losing their
  /// draft. Stored id goes into the JSON blob; when the field key is
  /// `child_id`, it also stamps the typed FK column at save time
  /// (see `_effectiveChildId`).
  Widget _buildChildPicker(fd.FormChildPickerField field) {
    final selectedId = _values[field.key] as String?;
    final childrenAsync = ref.watch(childrenProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final children = childrenAsync.asData?.value ?? const <Child>[];
    final groups = groupsAsync.asData?.value ?? const <Group>[];
    Child? selected;
    for (final c in children) {
      if (c.id == selectedId) {
        selected = c;
        break;
      }
    }
    final label = selected != null
        ? _childDisplayName(selected)
        : selectedId == null
            ? 'Pick a child'
            : '(deleted child)';
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: OutlinedButton.icon(
        onPressed: () => _openChildPicker(field, children, groups),
        icon: const Icon(Icons.child_care_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
      ),
    );
  }

  String _childDisplayName(Child c) {
    final last = c.lastName;
    if (last == null || last.trim().isEmpty) return c.firstName;
    return '${c.firstName} ${last.trim()[0]}.';
  }

  Future<void> _openChildPicker(
    fd.FormChildPickerField field,
    List<Child> children,
    List<Group> groups,
  ) async {
    final selectedId = _values[field.key] as String?;
    final groupsById = {for (final g in groups) g.id: g};
    final picked = await showModalBottomSheet<_ChildPickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChildPickerSheet(
        children: children,
        groupsById: groupsById,
        selectedId: selectedId,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.addNew) {
      // Same inline-create pattern as the vehicle picker — we don't
      // auto-select the newly enrolled child. Stream rebuild brings
      // the new row into the list; teacher re-opens the picker and
      // taps it, which keeps the selection intent explicit.
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => NewChildWizardScreen(groups: groups),
        ),
      );
      return;
    }
    setState(() {
      _values[field.key] = picked.childId;
    });
  }

  // -- Adult picker -------------------------------------------------

  /// Adult picker. Mirrors the child picker exactly but reads
  /// [adultsProvider]; stores the adult's id under the field's key.
  /// Ids unresolvable at render time (deletion after save) read
  /// "(deleted adult)" on the picker button — same pattern as the
  /// vehicle and child variants.
  Widget _buildAdultPicker(fd.FormAdultPickerField field) {
    final selectedId = _values[field.key] as String?;
    final adultsAsync = ref.watch(adultsProvider);
    final adults = adultsAsync.asData?.value ?? const <Adult>[];
    Adult? selected;
    for (final a in adults) {
      if (a.id == selectedId) {
        selected = a;
        break;
      }
    }
    final label = selected != null
        ? selected.name
        : selectedId == null
            ? 'Pick an adult'
            : '(deleted adult)';
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: OutlinedButton.icon(
        onPressed: () => _openAdultPicker(field, adults),
        icon: const Icon(Icons.person_outline),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
      ),
    );
  }

  Future<void> _openAdultPicker(
    fd.FormAdultPickerField field,
    List<Adult> adults,
  ) async {
    final selectedId = _values[field.key] as String?;
    final picked = await showModalBottomSheet<_AdultPickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdultPickerSheet(
        adults: adults,
        selectedId: selectedId,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _values[field.key] = picked.adultId;
    });
  }

  // -- Number -------------------------------------------------------

  /// Numeric input. Reuses the existing [_textControllers] map (the
  /// controller was seeded in [_ensureControllers]). Stores int when
  /// `decimals == 0` and double otherwise. Out-of-range values render
  /// inline error text below the field; the renderer doesn't block
  /// edits — the user can keep typing while the warning sits.
  Widget _buildNumber(fd.FormNumberField field) {
    final controller = _textControllers[field.key] ??
        (throw StateError('Missing controller for ${field.key}'));
    final stored = _values[field.key];
    final current = stored is num ? stored : null;
    String? error;
    if (current != null) {
      if (field.min != null && current < field.min!) {
        error = 'Must be ≥ ${_formatBound(field.min!, field.decimals)}';
      } else if (field.max != null && current > field.max!) {
        error = 'Must be ≤ ${_formatBound(field.max!, field.decimals)}';
      }
    }
    final theme = Theme.of(context);
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(
              decimal: field.decimals > 0,
              signed: (field.min ?? 0) < 0,
            ),
            decoration: InputDecoration(
              suffixText: field.units,
              errorText: error,
            ),
            onChanged: (raw) {
              final parsed = _parseNumber(raw, field);
              setState(() {
                if (parsed != null) {
                  _values[field.key] = parsed;
                } else if (raw.trim().isEmpty) {
                  _values.remove(field.key);
                }
                // Failed-parse non-empty input keeps the previous
                // stored value; the inline error (if any) reflects
                // that prior value while the user keeps typing.
              });
            },
          ),
          // _LabeledField doesn't have a helper-text slot; AppTextField
          // doesn't surface errorText at all. We use the InputDecoration
          // errorText above which renders inline. No extra widget here.
          if (error != null && controller.text.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Format a min/max bound for the inline error label so a 0-decimals
  /// field doesn't read "Must be ≥ 5.0".
  String _formatBound(num bound, int decimals) {
    if (decimals == 0) return bound.toInt().toString();
    return bound.toStringAsFixed(decimals);
  }

  // -- Image --------------------------------------------------------

  /// Image / photo upload. Stores `{localPath, storagePath?}` under
  /// the field's key. Initial state is "Add photo"; once a file is
  /// captured, the button becomes a small thumbnail that re-opens
  /// the action sheet (Take photo / Choose from library / Remove).
  ///
  /// Capture kicks a fire-and-forget upload through MediaService;
  /// on success the storagePath is stamped back onto _values so other
  /// devices can pull the file from Storage on demand.
  Widget _buildImage(fd.FormImageField field) {
    final raw = _values[field.key];
    final map = raw is Map ? raw.cast<String, dynamic>() : null;
    final localPath = map?['localPath'] as String?;
    final storagePath = map?['storagePath'] as String?;
    final etag = map?['etag'] as String?;

    Widget thumbnail() {
      // MediaImage handles all the branching — native fast path
      // via FileImage when a local file exists, drift-cache
      // fallback (downloads from Supabase on first miss, reuses
      // forever after) for the cross-device case. Etag in the
      // source key forces re-fetch when another device re-picks.
      return MediaImage(
        source: MediaSource(
          localPath: localPath,
          storagePath: storagePath,
          etag: etag,
        ),
        width: 80,
        height: 80,
        borderRadius: BorderRadius.circular(8),
      );
    }

    final hasImage = localPath != null || storagePath != null;
    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: Align(
        alignment: Alignment.centerLeft,
        child: hasImage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _openImageSheet(field),
                    child: thumbnail(),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  TextButton.icon(
                    onPressed: () => _openImageSheet(field),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Change'),
                  ),
                ],
              )
            : OutlinedButton.icon(
                onPressed: () => _openImageSheet(field),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Add photo'),
              ),
      ),
    );
  }

  Future<void> _openImageSheet(fd.FormImageField field) async {
    final picker = ImagePicker();
    final raw = _values[field.key];
    final hasExisting = raw is Map &&
        ((raw['localPath'] as String?) != null ||
            (raw['storagePath'] as String?) != null);

    Future<void> capture(ImageSource source) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final file = await picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1600,
        );
        if (file == null) return;
        if (!mounted) return;
        setState(() {
          // Optimistic local state. Native gets the picker's
          // filesystem path so the thumbnail renders instantly;
          // web has no usable path until upload stamps the
          // storage_path + etag back in.
          _values[field.key] = <String, dynamic>{
            if (!kIsWeb) 'localPath': file.path else 'localPath': null,
          };
        });
        // Make sure the row exists so the storage path can scope to
        // its id; if there's no submission row yet we save a draft
        // to mint one. Then fire-and-forget the upload — XFile so
        // the upload works on web too.
        unawaited(_uploadFormImage(field, file));
      } on Object catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text("Couldn't capture photo: $e")),
        );
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(capture(ImageSource.camera));
                },
              ),
            if (field.allowGallery)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from library'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(capture(ImageSource.gallery));
                },
              ),
            if (hasExisting)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _values.remove(field.key));
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Resolves a submission id (creating a draft if needed) and kicks
  /// the MediaService upload. On success, the storagePath + etag
  /// are merged back into _values so cross-device readers can pull
  /// the right bytes. Errors are logged via debugPrint — same
  /// fire-and-forget shape as observation attachments.
  Future<void> _uploadFormImage(
    fd.FormImageField field,
    XFile source,
  ) async {
    try {
      // Need a submission id and a programId to scope the bucket key.
      final programId = ref.read(activeProgramIdProvider);
      if (programId == null) return;
      if (_resolvedSubmissionId == null) {
        await _saveDraft();
      }
      final submissionId = _resolvedSubmissionId;
      if (submissionId == null) return;

      final media = ref.read(mediaServiceProvider);
      final result = await media.uploadFormImage(
        submissionId: submissionId,
        fieldKey: field.key,
        source: source,
        programId: programId,
      );
      if (result == null) return;
      if (!mounted) return;
      // Stamp etag alongside the path. Other devices pull the
      // form submission row through realtime; the etag change
      // forces their MediaImage cache to re-fetch instead of
      // serving stale bytes for the same storage_path.
      setState(() {
        final current = _values[field.key];
        _values[field.key] = <String, dynamic>{
          if (current is Map) ...current.cast<String, dynamic>(),
          // On native we keep the local path for fast offline
          // render. On web `XFile.path` is a blob URL useless
          // outside the current page session, so skip it.
          if (!kIsWeb) 'localPath': source.path else 'localPath': null,
          'storagePath': result.storagePath,
          'etag': result.etag,
        };
      });
      // **Persist** the data blob so the row's `data` JSON
      // actually gets the new storagePath + etag. Without this
      // call the upload happens, the bytes land in Storage, but
      // the submission row's `data` never updates — so cross-
      // device readers (and even the local device after pop +
      // re-open) see an empty image slot. Without this line the
      // user's bug repro is "I uploaded a photo, no one sees it."
      try {
        await ref.read(formSubmissionRepositoryProvider).updateSubmission(
              id: submissionId,
              data: Map<String, dynamic>.from(_values),
              childId: _effectiveChildId(),
            );
      } on Object catch (e, st) {
        debugPrint('Form image data-blob persist failed: $e\n$st');
      }
    } on Object catch (e, st) {
      debugPrint('Form image upload failed: $e\n$st');
    }
  }

  Widget _buildBool(fd.FormBoolField field) {
    final current = _values[field.key] as bool? ?? false;
    return SwitchListTile(
      value: current,
      onChanged: (v) => setState(() => _values[field.key] = v),
      title: Text(field.label),
      subtitle: field.helpText == null ? null : Text(field.helpText!),
      contentPadding: EdgeInsets.zero,
    );
  }

  // -- Multi-child picker -------------------------------------------

  /// Multi-select wrapper around the existing child picker sheet.
  /// Stores `["id1", "id2"]` JSON arrays in the data blob. Tapping
  /// the chip area opens the same sheet as single-pick but with
  /// checkbox semantics.
  Widget _buildMultiChildPicker(fd.FormMultiChildPickerField field) {
    final raw = _values[field.key];
    final selectedIds = <String>{
      if (raw is List)
        for (final v in raw)
          if (v is String) v,
    };
    final childrenAsync = ref.watch(childrenProvider);
    final children = childrenAsync.asData?.value ?? const <Child>[];
    final picked = <Child>[
      for (final c in children)
        if (selectedIds.contains(c.id)) c,
    ];

    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: OutlinedButton.icon(
        onPressed: () => _openMultiChildPicker(field, children),
        icon: const Icon(Icons.group_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            picked.isEmpty
                ? 'Pick children'
                : picked.map(_childDisplayName).join(', '),
          ),
        ),
      ),
    );
  }

  Future<void> _openMultiChildPicker(
    fd.FormMultiChildPickerField field,
    List<Child> children,
  ) async {
    final raw = _values[field.key];
    final initial = <String>{
      if (raw is List)
        for (final v in raw)
          if (v is String) v,
    };
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MultiChildPickerSheet(
        children: children,
        initialSelected: initial,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _values[field.key] = picked.toList();
    });
  }

  // -- Signature ----------------------------------------------------

  /// Composite signature field: typed printed name, optional drawn
  /// signature image (via the InlineSignaturePad widget) plus the
  /// timestamp of when
  /// the signing happened. Stored as a single JSON object keyed
  /// by the field's `key`:
  ///   `{ name, signaturePath, signedAt }`
  ///
  /// The signature pad lives in a sub-sheet so the form's flow
  /// isn't blocked by an inline drawing surface — open, draw,
  /// commit, close. Existing signatures show the typed name with
  /// a small thumbnail; tapping re-opens the pad.
  Widget _buildSignature(fd.FormSignatureField field) {
    final raw = _values[field.key];
    final name = raw is Map ? (raw['name'] as String?) : null;
    final signaturePath =
        raw is Map ? (raw['signaturePath'] as String?) : null;
    final signatureStoragePath =
        raw is Map ? (raw['signatureStoragePath'] as String?) : null;
    final signatureEtag =
        raw is Map ? (raw['signatureEtag'] as String?) : null;
    final signedAt = raw is Map ? (raw['signedAt'] as String?) : null;
    // The "are we signed?" check looks at any of three things —
    // a local path, a cloud storage path, or a signed-at stamp.
    // Receive devices land here with no path but a storage path,
    // and we want them to render the signature thumbnail too.
    final hasSignature = signaturePath != null ||
        signatureStoragePath != null ||
        signedAt != null;

    return _LabeledField(
      label: field.label,
      help: field.helpText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _signatureNameController(field.key, name),
            label: 'Printed name',
            onChanged: (v) {
              final current = _values[field.key];
              final next = <String, dynamic>{
                if (current is Map) ...current.cast<String, dynamic>(),
                'name': v,
              };
              setState(() => _values[field.key] = next);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.draw_outlined),
            label: Text(
              hasSignature ? 'Re-sign' : 'Add signature',
            ),
            onPressed: () => _openSignaturePad(field),
          ),
          if (hasSignature) ...[
            // Cross-device signature preview. Routes through the
            // shared MediaImage pipeline: native fast-path on the
            // capture device, drift cache + Supabase fallback for
            // every other device + every web session.
            SignaturePreview(
              localPath: signaturePath,
              storagePath: signatureStoragePath,
              etag: signatureEtag,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              signedAt == null
                  ? 'Signed.'
                  : 'Signed ${_formatSignedAt(signedAt)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Per-field text controller for the printed-name input. Lazily
  /// instantiated so re-renders don't reset cursor position.
  TextEditingController _signatureNameController(
    String key,
    String? initialName,
  ) {
    final existing = _signatureNameControllers[key];
    if (existing != null) return existing;
    final ctrl = TextEditingController(text: initialName ?? '');
    _signatureNameControllers[key] = ctrl;
    return ctrl;
  }

  Future<void> _openSignaturePad(fd.FormSignatureField field) async {
    final result = await showModalBottomSheet<_SignatureResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: SizedBox(
          height: 360,
          child: InlineSignaturePad(
            onSigned: (signature, when) => Navigator.of(sheetCtx).pop(
              _SignatureResult(signature, when),
            ),
            onCancel: () => Navigator.of(sheetCtx).pop(),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final current = _values[field.key];
    setState(() {
      _values[field.key] = <String, dynamic>{
        if (current is Map) ...current.cast<String, dynamic>(),
        // Native: real disk path for fast offline render. Web:
        // null — the `blob:` URL doesn't survive a page reload
        // and isn't useful to dart:io.File anyway.
        if (!kIsWeb)
          'signaturePath': result.signature.path
        else
          'signaturePath': null,
        'signedAt': result.signedAt.toIso8601String(),
      };
    });
    // Fire-and-forget cloud upload of the signature PNG so signed
    // forms travel between devices visibly. Mirrors the form-image
    // path: stamps `storagePath` + `etag` into the same composite
    // map under the field's key. Other devices read storagePath
    // when their local signaturePath file is missing.
    unawaited(_uploadFormSignature(field, result.signature));
  }

  /// Uploads the signature [source] to MediaService under the same
  /// per-form bucket layout the image field uses. Reuses
  /// `MediaService.uploadFormImage` since signatures are just images
  /// from Storage's perspective — the bucket doesn't care.
  Future<void> _uploadFormSignature(
    fd.FormSignatureField field,
    XFile source,
  ) async {
    try {
      final programId = ref.read(activeProgramIdProvider);
      if (programId == null) return;
      if (_resolvedSubmissionId == null) {
        await _saveDraft();
      }
      final submissionId = _resolvedSubmissionId;
      if (submissionId == null) return;

      // The pad already gave us an XFile (path on native, blob URL
      // on web with bytes inline). Hand it straight to the
      // form-image upload — same pipeline images use.
      final media = ref.read(mediaServiceProvider);
      final result = await media.uploadFormImage(
        submissionId: submissionId,
        fieldKey: field.key,
        source: source,
        programId: programId,
      );
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        final current = _values[field.key];
        _values[field.key] = <String, dynamic>{
          if (current is Map) ...current.cast<String, dynamic>(),
          'signatureStoragePath': result.storagePath,
          // Etag isn't strictly necessary for signatures (they're
          // append-once per submission today) but threading it
          // through keeps the data shape uniform with image
          // fields and lets the cache invalidate correctly if a
          // signature ever gets re-drawn.
          'signatureEtag': result.etag,
        };
      });
      // Persist the data blob so the storage_path actually
      // travels to cloud. Same fix as the image-field path —
      // without this, cross-device readers never see the
      // signature exists.
      try {
        await ref.read(formSubmissionRepositoryProvider).updateSubmission(
              id: submissionId,
              data: Map<String, dynamic>.from(_values),
              childId: _effectiveChildId(),
            );
      } on Object catch (e, st) {
        debugPrint(
          'Form signature data-blob persist failed: $e\n$st',
        );
      }
    } on Object catch (e, st) {
      debugPrint('Signature upload failed: $e\n$st');
    }
  }

  String _formatSignedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    } on Object {
      return iso;
    }
  }
}

/// Tuple returned by the signature pad sheet — the freshly-saved
/// signature as an [XFile] (path on native, blob URL on web) plus
/// the moment the signature was committed.
class _SignatureResult {
  const _SignatureResult(this.signature, this.signedAt);
  final XFile signature;
  final DateTime signedAt;
}

/// Multi-select sheet for FormMultiChildPickerField. Mirrors the
/// shape of the existing single-pick sheet but with checkbox
/// semantics and a Done button.
class _MultiChildPickerSheet extends StatefulWidget {
  const _MultiChildPickerSheet({
    required this.children,
    required this.initialSelected,
  });

  final List<Child> children;
  final Set<String> initialSelected;

  @override
  State<_MultiChildPickerSheet> createState() =>
      _MultiChildPickerSheetState();
}

class _MultiChildPickerSheetState extends State<_MultiChildPickerSheet> {
  late final Set<String> _picked = {...widget.initialSelected};

  @override
  Widget build(BuildContext context) {
    final children = [...widget.children]
      ..sort((a, b) => a.firstName.toLowerCase()
          .compareTo(b.firstName.toLowerCase()));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pick children',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_picked),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: children.length,
              itemBuilder: (_, i) {
                final c = children[i];
                final selected = _picked.contains(c.id);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _picked.add(c.id);
                    } else {
                      _picked.remove(c.id);
                    }
                  }),
                  title: Text(c.firstName +
                      (c.lastName == null || c.lastName!.trim().isEmpty
                          ? ''
                          : ' ${c.lastName}')),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Wraps a field's input with a label + optional help text. Keeps
/// the layout consistent across the non-text field renderers (text
/// fields have their own label via AppTextField).
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.help,
  });

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (help != null) ...[
          const SizedBox(height: 2),
          Text(
            help!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

/// Bottom-sheet result from the vehicle picker. Either a pick
/// (`vehicleId` set) or an "add new vehicle" request (`addNew: true`).
/// Keeps the caller's state machine simple — two outcomes, one type.
class _VehiclePickResult {
  const _VehiclePickResult({this.vehicleId, this.addNew = false});
  final String? vehicleId;
  final bool addNew;
}

/// Modal list of vehicles + an "Add vehicle…" tile at the bottom.
/// Compact — name + optional subtitle, check-mark on the current
/// pick. Tapping any row pops with that row's id; tapping "Add"
/// pops with `addNew: true` so the caller can open the edit sheet.
class _VehiclePickerSheet extends StatelessWidget {
  const _VehiclePickerSheet({
    required this.vehicles,
    required this.selectedId,
  });

  final List<Vehicle> vehicles;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                'Pick a vehicle',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (vehicles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No vehicles yet. Add one below to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final v in vehicles)
              ListTile(
                leading: Icon(
                  v.id == selectedId
                      ? Icons.check_circle
                      : Icons.directions_bus_outlined,
                  color: v.id == selectedId
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(v.name),
                subtitle: _vehicleSubtitle(v) == null
                    ? null
                    : Text(_vehicleSubtitle(v)!),
                onTap: () => Navigator.of(context).pop(
                  _VehiclePickResult(vehicleId: v.id),
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add vehicle…'),
              onTap: () => Navigator.of(context).pop(
                const _VehiclePickResult(addNew: true),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  String? _vehicleSubtitle(Vehicle v) {
    final parts = <String>[];
    if (v.makeModel.isNotEmpty) parts.add(v.makeModel);
    if (v.licensePlate.isNotEmpty) parts.add(v.licensePlate);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Bottom-sheet result from the adult picker. Single shape — either
/// an id is picked or the sheet was dismissed (caller treats null as
/// no-op).
class _AdultPickResult {
  const _AdultPickResult({required this.adultId});
  final String adultId;
}

/// Modal list of adults. Sorted alphabetically by name. No "Add new
/// adult" affordance yet — staff onboarding lives outside the form
/// flow (admin screens).
class _AdultPickerSheet extends StatelessWidget {
  const _AdultPickerSheet({
    required this.adults,
    required this.selectedId,
  });

  final List<Adult> adults;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...adults]
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                'Pick an adult',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No adults yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final a in sorted)
              ListTile(
                leading: Icon(
                  a.id == selectedId
                      ? Icons.check_circle
                      : Icons.person_outline,
                  color: a.id == selectedId
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(a.name),
                subtitle: a.role == null || a.role!.trim().isEmpty
                    ? null
                    : Text(a.role!),
                onTap: () => Navigator.of(context).pop(
                  _AdultPickResult(adultId: a.id),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet result from the child picker. Either a pick
/// (`childId` set) or an "add new child" request (`addNew: true`).
/// Mirrors `_VehiclePickResult`.
class _ChildPickResult {
  const _ChildPickResult({this.childId, this.addNew = false});
  final String? childId;
  final bool addNew;
}

/// Modal list of children + an "Add new child…" tile at the bottom.
/// Sorted alphabetically by first name (same order the children
/// screen uses). Subtitle is the group label when present so
/// teachers in programs with same-first-name kids can disambiguate.
class _ChildPickerSheet extends StatelessWidget {
  const _ChildPickerSheet({
    required this.children,
    required this.groupsById,
    required this.selectedId,
  });

  final List<Child> children;
  final Map<String, Group> groupsById;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // watchChildren already orders by firstName; mirror that order
    // here in case the caller passed a differently-sorted list.
    final sorted = [...children]
      ..sort(
        (a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()),
      );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                'Pick a child',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No children yet. Add one below to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final c in sorted)
              ListTile(
                leading: Icon(
                  c.id == selectedId
                      ? Icons.check_circle
                      : Icons.child_care_outlined,
                  color: c.id == selectedId
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(_fullName(c)),
                subtitle: _groupLabel(c) == null
                    ? null
                    : Text(_groupLabel(c)!),
                onTap: () => Navigator.of(context).pop(
                  _ChildPickResult(childId: c.id),
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add new child…'),
              onTap: () => Navigator.of(context).pop(
                const _ChildPickResult(addNew: true),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  String _fullName(Child c) {
    final last = c.lastName;
    if (last == null || last.trim().isEmpty) return c.firstName;
    return '${c.firstName} ${last.trim()[0]}.';
  }

  String? _groupLabel(Child c) {
    final gid = c.groupId;
    if (gid == null) return null;
    return groupsById[gid]?.name;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// "Mark all OK & continue →" button at the top of every checklist
/// section. Single tap flips every `FormChecklistStatusField` in
/// that section to `'ok'` and advances the wizard to the next
/// step.
///
/// Lives outside the form's setState chain — the parent owns the
/// values map and passes [onApply] to mutate it. We only own the
/// "advance after apply" half of the action via the wizard
/// controller. Splitting it this way keeps the button decoupled
/// from any single form's data shape.
class _SectionMarkAllOkButton extends StatelessWidget {
  const _SectionMarkAllOkButton({
    required this.section,
    required this.onApply,
  });

  final fd.FormSection section;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              onApply();
              // Tiny delay so the user sees the items flip to ✓
              // before the page slides — feels less jarring than
              // an instant transition.
              await Future<void>.delayed(
                const Duration(milliseconds: 120),
              );
              if (!context.mounted) return;
              await WizardController.of(context).next();
            },
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Mark all OK & continue'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              'Or check items individually',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form-level "Everything OK — just need notes" shortcut. Shows
/// only on step 1 (vehicle info) of forms that contain at least
/// one `FormChecklistStatusField` somewhere. One tap flips every
/// checklist field across every section to `'ok'` and jumps to
/// the last step — typically Notes — so a teacher running an
/// "all is well" pre-trip check can be done in two taps after
/// picking the vehicle.
///
/// Visually de-emphasized vs the section-level button: this is a
/// power-user shortcut, not the recommended flow. The phrasing
/// reminds the user they're committing to all-OK without walking
/// the form.
class _FormMarkAllOkButton extends StatelessWidget {
  const _FormMarkAllOkButton({
    required this.definition,
    required this.onApply,
  });

  final fd.FormDefinition definition;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: OutlinedButton.icon(
        onPressed: () => _confirmAndApply(context),
        icon: const Icon(Icons.fast_forward, size: 18),
        label: Text(
          'Everything OK — just need notes',
          style: theme.textTheme.labelLarge,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _confirmAndApply(BuildContext context) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Mark every check as OK?',
      message:
          'Sets every item across the form to ✓ and skips you to '
          "the last step. Use only when you've actually walked "
          'the inspection and everything is acceptable. You can '
          'still change individual items afterward.',
      confirmLabel: 'Mark all OK',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    onApply();
    final controller = WizardController.of(context);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;
    // Jump to the last step. The wizard clamps the index, so the
    // exact value doesn't matter as long as it's >= last index.
    await controller.goTo(definition.sections.length - 1);
  }
}
