import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/ai_authoring.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditLibraryItemSheet extends ConsumerStatefulWidget {
  const EditLibraryItemSheet({super.key, this.item});

  final ActivityLibraryData? item;

  @override
  ConsumerState<EditLibraryItemSheet> createState() =>
      _EditLibraryItemSheetState();
}

class _EditLibraryItemSheetState
    extends ConsumerState<EditLibraryItemSheet> {
  late final _titleController =
      TextEditingController(text: widget.item?.title ?? '');
  late final _locationController =
      TextEditingController(text: widget.item?.location ?? '');
  late final _notesController =
      TextEditingController(text: widget.item?.notes ?? '');
  late final _materialsController =
      TextEditingController(text: widget.item?.materials ?? '');

  // Visible rich-card editors (slice B). Curriculum daily-ritual
  // and milestone descriptions live in `summary`; the AI fill path
  // populates the rest. Without visible editors a teacher can't
  // hand-author a card, so we surface summary directly and the
  // others stay state-only (reachable via AI fill or kept from a
  // previous edit). Age variants get their own dedicated editor
  // below.
  late final _summaryController =
      TextEditingController(text: widget.item?.summary ?? '');
  late final _hookController =
      TextEditingController(text: widget.item?.hook ?? '');
  late final _keyPointsController =
      TextEditingController(text: widget.item?.keyPoints ?? '');
  late final _learningGoalsController =
      TextEditingController(text: widget.item?.learningGoals ?? '');

  late int? _durationMin = widget.item?.defaultDurationMin;
  late String? _adultId = widget.item?.adultId;

  // Rich-card fields without visible editors — kept around so the
  // AI-fill path's values survive a manual save.
  late int? _audienceMinAge = widget.item?.audienceMinAge;
  late int? _audienceMaxAge = widget.item?.audienceMaxAge;
  late int? _engagementTimeMin = widget.item?.engagementTimeMin;
  late String? _sourceUrl = widget.item?.sourceUrl;
  late String? _sourceAttribution = widget.item?.sourceAttribution;

  /// Age variants editor state: age (3..12) → summary text. Loaded
  /// from the row on edit; empty on create. Saved via the
  /// repository's `ageVariants:` arg (a `Map<int, AgeVariant>`).
  late Map<int, String> _ageVariants = {
    if (widget.item != null)
      ...ActivityLibraryRepository.decodeAgeVariants(
              widget.item!.ageVariants)
          .map((k, v) => MapEntry(k, v.summary ?? '')),
  };

  /// Newly-filled rich-field names from the most recent AI run.
  /// Shown as a small "AI added: …" readout so the teacher knows
  /// which invisible fields were populated behind the scenes.
  final _lastFilledLabels = <String>[];

  bool _submitting = false;

  bool get _isEdit => widget.item != null;
  bool get _isValid => _titleController.text.trim().isNotEmpty;

  bool get _hasChanges {
    final item = widget.item;
    if (item == null) return true;
    String? trimOrNull(String s) =>
        s.trim().isEmpty ? null : s.trim();
    if (_titleController.text.trim() != item.title) return true;
    if (_durationMin != item.defaultDurationMin) return true;
    if (_adultId != item.adultId) return true;
    if (trimOrNull(_locationController.text) != item.location) return true;
    if (trimOrNull(_notesController.text) != item.notes) return true;
    if (trimOrNull(_materialsController.text) != item.materials) return true;
    if (trimOrNull(_summaryController.text) != item.summary) return true;
    if (trimOrNull(_hookController.text) != item.hook) return true;
    if (trimOrNull(_keyPointsController.text) != item.keyPoints) {
      return true;
    }
    if (trimOrNull(_learningGoalsController.text) != item.learningGoals) {
      return true;
    }
    if (_audienceMinAge != item.audienceMinAge) return true;
    if (_audienceMaxAge != item.audienceMaxAge) return true;
    if (_engagementTimeMin != item.engagementTimeMin) return true;
    if (_sourceUrl != item.sourceUrl) return true;
    if (_sourceAttribution != item.sourceAttribution) return true;
    // Age variants — compare encoded shapes for structural
    // equality. Cheap (small map of strings).
    final original =
        ActivityLibraryRepository.decodeAgeVariants(item.ageVariants)
            .map((k, v) => MapEntry(k, v.summary ?? ''));
    if (!_mapsEqual(original, _ageVariants)) return true;
    return false;
  }

  static bool _mapsEqual(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if ((b[e.key] ?? '') != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    _summaryController.dispose();
    _hookController.dispose();
    _keyPointsController.dispose();
    _learningGoalsController.dispose();
    super.dispose();
  }

  /// Splat any non-null field from the draft into our state, but only
  /// where the current slot is empty — never clobber something the
  /// teacher already typed. Tracks which fields were filled so the
  /// post-fill readout can hint at what changed (especially useful
  /// for the invisible rich fields).
  void _applyDraft(LibraryCardDraft draft) {
    final filled = <String>[];
    void fillText(TextEditingController c, String? v, String label) {
      if (v == null || v.isEmpty) return;
      if (c.text.trim().isNotEmpty) return;
      c.text = v;
      filled.add(label);
    }

    void fillNullable<T>(
      T? Function() getter,
      void Function(T) setter,
      T? v,
      String label,
    ) {
      if (v == null) return;
      if (getter() != null) return;
      setter(v);
      filled.add(label);
    }

    // Title is special — the draft's title is required but we only
    // fill it when the field is blank, same rule as everything else.
    fillText(_titleController, draft.title, 'title');
    fillText(_summaryController, draft.summary, 'summary');
    fillText(_hookController, draft.hook, 'hook');
    fillText(_keyPointsController, draft.keyPoints, 'key points');
    fillText(
      _learningGoalsController,
      draft.learningGoals,
      'learning goals',
    );
    fillText(_materialsController, draft.materials, 'materials');
    fillNullable(
      () => _audienceMinAge,
      (v) => _audienceMinAge = v,
      draft.audienceMinAge,
      'min age',
    );
    fillNullable(
      () => _audienceMaxAge,
      (v) => _audienceMaxAge = v,
      draft.audienceMaxAge,
      'max age',
    );
    fillNullable(
      () => _engagementTimeMin,
      (v) => _engagementTimeMin = v,
      draft.engagementTimeMin,
      'engagement time',
    );
    fillNullable(
      () => _durationMin,
      (v) => _durationMin = v,
      draft.engagementTimeMin,
      'default duration',
    );
    fillNullable(
      () => _sourceUrl,
      (v) => _sourceUrl = v,
      draft.sourceUrl,
      'source link',
    );
    fillNullable(
      () => _sourceAttribution,
      (v) => _sourceAttribution = v,
      draft.sourceAttribution,
      'source attribution',
    );

    setState(() {
      _lastFilledLabels
        ..clear()
        ..addAll(filled.toSet());
    });
  }

  Future<void> _fillFromUrl() async {
    final draft = await showDialog<LibraryCardDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AiImportDialog(
        title: 'Fill from link',
        hint: 'https://…',
        generate: generateFromUrl,
      ),
    );
    if (draft == null || !mounted) return;
    _applyDraft(draft);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Draft filled from link — review before saving.'),
        ),
      );
  }

  Future<void> _fillFromDescription() async {
    final draft = await showDialog<LibraryCardDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AiImportDialog(
        title: 'Fill from description',
        hint: 'Describe the activity in a sentence or two…',
        maxLines: 5,
        generate: generateFromDescription,
      ),
    );
    if (draft == null || !mounted) return;
    _applyDraft(draft);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Draft filled from description — review before saving.',
          ),
        ),
      );
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(activityLibraryRepositoryProvider);
    final title = _titleController.text.trim();
    String? trimOrNull(String s) => s.trim().isEmpty ? null : s.trim();
    final location = trimOrNull(_locationController.text);
    final notes = trimOrNull(_notesController.text);
    final materials = trimOrNull(_materialsController.text);
    final summary = trimOrNull(_summaryController.text);
    final hook = trimOrNull(_hookController.text);
    final keyPoints = trimOrNull(_keyPointsController.text);
    final learningGoals = trimOrNull(_learningGoalsController.text);

    // Convert the editor's `Map<int, String>` into the repo's
    // `Map<int, AgeVariant>` shape. Empty / whitespace-only
    // entries are dropped so the row's `age_variants` column
    // doesn't carry phantom keys.
    final ageVariantsMap = <int, AgeVariant>{
      for (final e in _ageVariants.entries)
        if (e.value.trim().isNotEmpty)
          e.key: AgeVariant(summary: e.value.trim()),
    };
    final ageVariants =
        ageVariantsMap.isEmpty ? null : ageVariantsMap;

    String? newItemId;
    if (_isEdit) {
      // Pass through every field the sheet now carries — the rich
      // columns are Value-wrapped so we can distinguish "set to null"
      // (user cleared) from "leave alone" (field never touched). Here
      // we always explicitly set them, which is correct because the
      // sheet's state was seeded from the existing row.
      await repo.updateItem(
        id: widget.item!.id,
        title: title,
        defaultDurationMin: Value(_durationMin),
        adultId: Value(_adultId),
        location: Value(location),
        notes: Value(notes),
        materials: Value(materials),
        summary: Value(summary),
        hook: Value(hook),
        keyPoints: Value(keyPoints),
        learningGoals: Value(learningGoals),
        audienceMinAge: Value(_audienceMinAge),
        audienceMaxAge: Value(_audienceMaxAge),
        engagementTimeMin: Value(_engagementTimeMin),
        sourceUrl: Value(_sourceUrl),
        sourceAttribution: Value(_sourceAttribution),
        ageVariants: Value(ageVariants),
      );
    } else {
      newItemId = await repo.addItem(
        title: title,
        defaultDurationMin: _durationMin,
        adultId: _adultId,
        location: location,
        notes: notes,
        materials: materials,
        summary: summary,
        hook: hook,
        keyPoints: keyPoints,
        learningGoals: learningGoals,
        audienceMinAge: _audienceMinAge,
        audienceMaxAge: _audienceMaxAge,
        engagementTimeMin: _engagementTimeMin,
        sourceUrl: _sourceUrl,
        sourceAttribution: _sourceAttribution,
        ageVariants: ageVariants,
      );
    }
    if (!mounted) return;
    // On create, pop with the new library-item id so callers (e.g.
    // the activity wizard's "+ New library card" flow) can resolve
    // the newly-added row and pre-fill their own fields from it.
    // Edits still pop with null — nothing to hand back.
    Navigator.of(context).pop(newItemId);
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    await ref
        .read(activityLibraryRepositoryProvider)
        .deleteItem(widget.item!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adultsAsync = ref.watch(adultsProvider);

    return StickyActionSheet(
      title: _isEdit ? 'Edit library item' : 'New library item',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && (!_isEdit || _hasChanges)
            ? () => runWithErrorReport(context, _submit)
            : null,
        label: _isEdit ? 'Save' : 'Add to library',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AI-assist row sits above the title field because the whole
          // point is to fill the fields below. The _lastFilledLabels
          // hint renders under the buttons after a successful run.
          _AiAssistRow(
            onFillFromUrl: _fillFromUrl,
            onFillFromDescription: _fillFromDescription,
            lastFilled: _lastFilledLabels,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _titleController,
            label: 'Title',
            hint: 'e.g. Morning circle · Snack · Pickup',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Default duration', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              _DurationChoice(
                label: '—',
                selected: _durationMin == null,
                onTap: () => setState(() => _durationMin = null),
              ),
              _DurationChoice(
                label: '15m',
                selected: _durationMin == 15,
                onTap: () => setState(() => _durationMin = 15),
              ),
              _DurationChoice(
                label: '30m',
                selected: _durationMin == 30,
                onTap: () => setState(() => _durationMin = 30),
              ),
              _DurationChoice(
                label: '45m',
                selected: _durationMin == 45,
                onTap: () => setState(() => _durationMin = 45),
              ),
              _DurationChoice(
                label: '1h',
                selected: _durationMin == 60,
                onTap: () => setState(() => _durationMin = 60),
              ),
              _DurationChoice(
                label: '90m',
                selected: _durationMin == 90,
                onTap: () => setState(() => _durationMin = 90),
              ),
              _DurationChoice(
                label: '2h',
                selected: _durationMin == 120,
                onTap: () => setState(() => _durationMin = 120),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Default adult', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          adultsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (adults) {
              if (adults.isEmpty) {
                return Text(
                  'No adults yet.',
                  style: theme.textTheme.bodySmall,
                );
              }
              // Clamp to current list so an orphan adult
              // reference falls back to "None" instead of firing
              // DropdownButton's "exactly one item" assertion.
              final resolvedId = _adultId != null &&
                      adults.any((s) => s.id == _adultId)
                  ? _adultId
                  : null;
              return DropdownButtonFormField<String?>(
                initialValue: resolvedId,
                items: [
                  const DropdownMenuItem<String?>(child: Text('None')),
                  for (final s in adults)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        s.role == null || s.role!.isEmpty
                            ? s.name
                            : '${s.name} · ${s.role}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _adultId = v),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _locationController,
            label: 'Default location (optional)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _materialsController,
            label: 'Materials (optional)',
            hint: "What you'll need — comma- or newline-separated.",
            keyboardType: TextInputType.multiline,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.xl),
          // ── Activity-card content ─────────────────────────
          // Summary is the primary description shown in the
          // curriculum view's daily-ritual / milestone tile and
          // in the library card detail. Visible editor lets a
          // teacher hand-author cards without going through the
          // AI fill flow.
          Text('Card content', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _summaryController,
            label: 'Summary',
            hint: 'Short description shown on the activity tile.',
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _hookController,
            label: 'Hook (optional)',
            hint: 'One-line teaser, e.g. "What if everything was upside-down?"',
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _keyPointsController,
            label: 'Key points (optional)',
            hint: 'Bullets — newline-separated.',
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _learningGoalsController,
            label: 'Learning goals (optional)',
            hint: 'Bullets — newline-separated.',
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.xl),
          // ── Age variants ──────────────────────────────────
          // Per-age summary rewrites. The curriculum view's
          // "show age scaling" toggle picks the closest match
          // and renders this text instead of the canonical
          // summary above.
          _AgeVariantsEditor(
            variants: _ageVariants,
            onChanged: (next) =>
                setState(() => _ageVariants = next),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Developmental domains',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_isEdit)
            _DomainTagPicker(libraryItemId: widget.item!.id)
          else
            Text(
              'Save once to enable tagging.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Two-button AI assist row: fill from a webpage URL, or fill from
/// a free-text description. Below the buttons, a small muted readout
/// confirms what the last run populated (handy for the invisible rich
/// fields — summary, hook, key points, etc. — so the teacher isn't
/// surprised at save time).
class _AiAssistRow extends StatelessWidget {
  const _AiAssistRow({
    required this.onFillFromUrl,
    required this.onFillFromDescription,
    required this.lastFilled,
  });

  final VoidCallback onFillFromUrl;
  final VoidCallback onFillFromDescription;
  final List<String> lastFilled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AI assist',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: onFillFromUrl,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Fill from link'),
            ),
            OutlinedButton.icon(
              onPressed: onFillFromDescription,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Fill from description'),
            ),
          ],
        ),
        if (lastFilled.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Filled: ${lastFilled.join(", ")}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Reusable "enter text → generate → return draft" dialog. Both the
/// URL and description paths share the same shape: a blocking modal,
/// a single input field, Cancel + Generate. The modal can't be
/// dismissed while a generation is in flight — the teacher sees a
/// spinner in the primary button until the draft resolves or the
/// call throws.
class _AiImportDialog extends StatefulWidget {
  const _AiImportDialog({
    required this.title,
    required this.hint,
    required this.generate,
    this.maxLines = 1,
  });

  final String title;
  final String hint;
  final int maxLines;
  final Future<LibraryCardDraft> Function(String) generate;

  @override
  State<_AiImportDialog> createState() => _AiImportDialogState();
}

class _AiImportDialogState extends State<_AiImportDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await widget.generate(raw);
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } on LibraryDraftFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't generate: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // PopScope blocks back-gesture / Esc dismissal while a call's
    // in flight so the caller never races a half-finished draft.
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              maxLines: widget.maxLines,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(hintText: widget.hint),
              keyboardType: widget.maxLines > 1
                  ? TextInputType.multiline
                  : TextInputType.text,
              onSubmitted: widget.maxLines == 1 ? (_) => _go() : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate'),
          ),
        ],
      ),
    );
  }
}

/// Multi-select FilterChip grid over the shared [ObservationDomain]
/// enum — same taxonomy the observations screen uses so a library
/// card tagged "SSD3" lines up with observations in that domain. Each
/// tap writes through immediately; no local buffering because edits
/// here commit even if the teacher cancels the parent sheet (that
/// matches how deletes work from this surface).
class _DomainTagPicker extends ConsumerWidget {
  const _DomainTagPicker({required this.libraryItemId});

  final String libraryItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tagsAsync =
        ref.watch(libraryDomainsForItemProvider(libraryItemId));
    return tagsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Text('Error: $err'),
      data: (tags) {
        final selected = tags.toSet();
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final d in ObservationDomain.values)
              FilterChip(
                label: Text(
                  d == ObservationDomain.other ? d.label : '${d.code} · ${d.label}',
                  style: theme.textTheme.labelSmall,
                ),
                selected: selected.contains(d.name),
                onSelected: (v) async {
                  final repo = ref.read(activityLibraryRepositoryProvider);
                  if (v) {
                    await repo.addDomainTag(libraryItemId, d.name);
                  } else {
                    await repo.removeDomainTag(libraryItemId, d.name);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _DurationChoice extends StatelessWidget {
  const _DurationChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

/// Per-age summary rewrites editor.
///
/// Shape:
///   * Header with title + ages currently set as chips.
///   * "Add age" button reveals a row of age chips (3..12). Tap
///     to add. Adding pops up an inline summary editor for that
///     age.
///   * Each existing age has a row: "Age N · summary…" with a
///     remove (×) action and an inline multi-line text editor.
///
/// Why this shape: a teacher authoring a multi-age curriculum
/// usually targets 2–3 age bands (e.g. 5, 7, 10), so the editor
/// optimizes for "add a few specific ages" rather than "fill out
/// all 10." Empty entries get filtered out at save time.
class _AgeVariantsEditor extends StatefulWidget {
  const _AgeVariantsEditor({
    required this.variants,
    required this.onChanged,
  });

  final Map<int, String> variants;
  final ValueChanged<Map<int, String>> onChanged;

  @override
  State<_AgeVariantsEditor> createState() => _AgeVariantsEditorState();
}

class _AgeVariantsEditorState extends State<_AgeVariantsEditor> {
  bool _showAddRow = false;

  void _addAge(int age) {
    final next = Map<int, String>.from(widget.variants)
      ..putIfAbsent(age, () => '');
    widget.onChanged(next);
    setState(() => _showAddRow = false);
  }

  void _removeAge(int age) {
    final next = Map<int, String>.from(widget.variants)..remove(age);
    widget.onChanged(next);
  }

  void _updateText(int age, String text) {
    final next = Map<int, String>.from(widget.variants);
    next[age] = text;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ages = widget.variants.keys.toList()..sort();
    final available = [
      for (int a = 3; a <= 12; a++)
        if (!widget.variants.containsKey(a)) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Age variants',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (available.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _showAddRow = !_showAddRow),
                icon: Icon(
                  _showAddRow ? Icons.close : Icons.add,
                  size: 16,
                ),
                label: Text(_showAddRow ? 'Cancel' : 'Add age'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Adjacent-age rewrites of the summary above. The '
          'curriculum view picks the closest age match when the '
          '"show age scaling" toggle is on.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_showAddRow) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final a in available)
                ChoiceChip(
                  label: Text('Age $a'),
                  selected: false,
                  onSelected: (_) => _addAge(a),
                ),
            ],
          ),
        ],
        if (ages.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No age variants — the canonical summary above will '
            'be used at every age.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        for (final age in ages) ...[
          const SizedBox(height: AppSpacing.md),
          _AgeVariantEntry(
            age: age,
            text: widget.variants[age] ?? '',
            onChanged: (t) => _updateText(age, t),
            onRemove: () => _removeAge(age),
          ),
        ],
      ],
    );
  }
}

/// One age's editor row.
class _AgeVariantEntry extends StatefulWidget {
  const _AgeVariantEntry({
    required this.age,
    required this.text,
    required this.onChanged,
    required this.onRemove,
  });

  final int age;
  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  State<_AgeVariantEntry> createState() => _AgeVariantEntryState();
}

class _AgeVariantEntryState extends State<_AgeVariantEntry> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Age ${widget.age}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Remove',
                iconSize: 18,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Summary rewritten for this age',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
