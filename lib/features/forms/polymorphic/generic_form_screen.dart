import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/new_child_wizard.dart';
import 'package:basecamp/features/forms/polymorphic/form_definition.dart'
    as fd;
import 'package:basecamp/features/forms/polymorphic/form_submission_repository.dart';
import 'package:basecamp/features/forms/polymorphic/form_submission_share.dart';
import 'package:basecamp/features/forms/widgets/inline_signature_pad.dart';
import 'package:basecamp/features/vehicles/vehicles_repository.dart';
import 'package:basecamp/features/vehicles/widgets/edit_vehicle_sheet.dart';
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
  Future<void> _flushTextControllers() async {
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }
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
        for (final section in def.sections)
          WizardStep(
            headline: section.title,
            subtitle: section.subtitle,
            canSkip: true,
            needsKeyboard: sectionNeedsKeyboard(section),
            // All intermediate steps read "Next" — per-step auto-save
            // is silent plumbing; the final step's Save button is the
            // actual commit point.
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
        fd.FormVehiclePickerField() => _buildVehiclePicker(field),
        fd.FormChildPickerField() => _buildChildPicker(field),
        fd.FormMultiChildPickerField() => _buildMultiChildPicker(field),
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
    final signedAt = raw is Map ? (raw['signedAt'] as String?) : null;

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
              signaturePath == null
                  ? 'Add signature'
                  : 'Re-sign',
            ),
            onPressed: () => _openSignaturePad(field),
          ),
          if (signaturePath != null) ...[
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
            onSigned: (path, when) =>
                Navigator.of(sheetCtx).pop(_SignatureResult(path, when)),
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
        'signaturePath': result.path,
        'signedAt': result.signedAt.toIso8601String(),
      };
    });
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

/// Tuple returned by the signature pad sheet — the path of the
/// PNG on disk plus the moment the signature was committed.
class _SignatureResult {
  const _SignatureResult(this.path, this.signedAt);
  final String path;
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
