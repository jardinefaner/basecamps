import 'package:basecamp/features/forms/polymorphic/form_definition.dart'
    as fd;
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        }
      }
    }
    _ensureControllers();
    if (mounted) setState(() => _loading = false);
  }

  /// Text fields need stable controllers across rebuilds. Build one
  /// per text-shaped field the first time we render.
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
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveDraft() async {
    await _flushTextControllers();
    setState(() => _submitting = true);
    final repo = ref.read(formSubmissionRepositoryProvider);
    try {
      if (_resolvedSubmissionId == null) {
        _resolvedSubmissionId = await repo.createDraft(
          formType: widget.definition.typeKey,
          data: Map<String, dynamic>.from(_values),
          childId: widget.prefillChildId,
          groupId: widget.prefillGroupId,
          tripId: widget.prefillTripId,
          parentSubmissionId: widget.parentSubmissionId,
          reviewDueAt: _computeReviewDueAt(),
        );
      } else {
        await repo.updateSubmission(
          id: _resolvedSubmissionId!,
          data: Map<String, dynamic>.from(_values),
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
    setState(() => _submitting = true);
    final repo = ref.read(formSubmissionRepositoryProvider);
    // Follow-up forms (those with a parent) land in 'active' on first
    // save — they keep running through the monitoring period. Simple
    // one-shots jump straight to 'completed'.
    final nextStatus = widget.definition.parentTypeKey != null
        ? fd.FormStatus.active
        : fd.FormStatus.completed;
    try {
      _resolvedSubmissionId ??= await repo.createDraft(
        formType: widget.definition.typeKey,
        data: Map<String, dynamic>.from(_values),
        childId: widget.prefillChildId,
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
  Future<void> _flushTextControllers() async {
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }
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
          for (final section in def.sections) ...[
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
      // Persist the draft on every step advance so the teacher's
      // partial work (vehicle identity on step 1, checklist items
      // as they walk through) survives swiping away, restarts, or
      // a mid-form phone call. Silent save — no snackbar per step.
      onStepAdvance: () async {
        await _flushTextControllers();
        final repo = ref.read(formSubmissionRepositoryProvider);
        if (_resolvedSubmissionId == null) {
          _resolvedSubmissionId = await repo.createDraft(
            formType: widget.definition.typeKey,
            data: Map<String, dynamic>.from(_values),
            childId: widget.prefillChildId,
            groupId: widget.prefillGroupId,
            tripId: widget.prefillTripId,
            parentSubmissionId: widget.parentSubmissionId,
            reviewDueAt: _computeReviewDueAt(),
          );
        } else {
          await repo.updateSubmission(
            id: _resolvedSubmissionId!,
            data: Map<String, dynamic>.from(_values),
          );
        }
      },
      steps: [
        for (final (i, section) in def.sections.indexed)
          WizardStep(
            headline: section.title,
            subtitle: section.subtitle,
            canSkip: true,
            needsKeyboard: sectionNeedsKeyboard(section),
            // Step 1 reads "Save" so the teacher knows the vehicle
            // identity is committed before they walk the checklist.
            // Subsequent steps keep the default "Next" label;
            // per-step auto-save is silent plumbing either way.
            nextLabelOverride: i == 0 ? 'Save' : null,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in section.fields) _buildField(field),
              ],
            ),
          ),
      ],
    );
  }

  // ---- Field renderers ----

  Widget _buildField(fd.FormField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: switch (field) {
        fd.FormTextField() => _buildText(field),
        fd.FormDateField() => _buildDate(field),
        fd.FormChecklistStatusField() => _buildChecklistStatus(field),
        fd.FormChoiceField() => _buildChoice(field),
        fd.FormMultiChoiceField() => _buildMultiChoice(field),
        fd.FormBoolField() => _buildBool(field),
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
      onChanged: (v) => _values[field.key] = v,
    );
  }

  Widget _buildDate(fd.FormDateField field) {
    final raw = _values[field.key] as String?;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    final display = parsed == null
        ? 'Pick a date${field.includeTime ? " & time" : ""}'
        : field.includeTime
            ? DateFormat.yMMMd().add_jm().format(parsed)
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
