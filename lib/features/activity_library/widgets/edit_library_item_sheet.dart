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

/// Library / curriculum-ritual editor.
///
/// The form was a tower of ten labeled inputs (title, summary, hook,
/// key points, learning goals, age variants, duration, adult,
/// location, notes, materials, domain tags). Most teachers filled
/// two — title and a one-paragraph description — and bounced past
/// the rest.
///
/// Reduced to **two visible fields** by default:
///   * Title
///   * Description (the old `summary` column, renamed)
///
/// Everything else lives behind an "Advanced" expander:
///   * Default duration · default adult · default location
///   * Notes · materials
///   * Developmental domains (edit mode only)
///
/// Data we no longer surface in the editor but still preserve:
///   * Hook, key points, learning goals — kept as state-only so the
///     AI-fill path can still populate them; existing template data
///     stays intact when re-edited; we just stopped asking the user
///     to fill four overlapping "what is this" prompts.
///   * Age variants — feature retired (was lightly used; the curriculum
///     view used to scale ritual summaries by age, with ~nobody
///     authoring the variants). Column stays in the schema; existing
///     rows pass through unchanged.
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
  late final _summaryController =
      TextEditingController(text: widget.item?.summary ?? '');

  // Advanced-section text controllers.
  late final _locationController =
      TextEditingController(text: widget.item?.location ?? '');
  late final _notesController =
      TextEditingController(text: widget.item?.notes ?? '');
  late final _materialsController =
      TextEditingController(text: widget.item?.materials ?? '');

  late int? _durationMin = widget.item?.defaultDurationMin;
  late String? _adultId = widget.item?.adultId;

  // Rich-card fields kept as state only — no visible editors. AI-fill
  // populates these from a URL or description; manual editors used to
  // surface them as four separate inputs (hook / key points / learning
  // goals / age variants), which created more confusion than depth.
  // Preserving them on save means existing template data round-trips
  // unchanged through this sheet.
  late String? _hook = widget.item?.hook;
  late String? _keyPoints = widget.item?.keyPoints;
  late String? _learningGoals = widget.item?.learningGoals;
  late int? _audienceMinAge = widget.item?.audienceMinAge;
  late int? _audienceMaxAge = widget.item?.audienceMaxAge;
  late int? _engagementTimeMin = widget.item?.engagementTimeMin;
  late String? _sourceUrl = widget.item?.sourceUrl;
  late String? _sourceAttribution = widget.item?.sourceAttribution;
  late final String? _ageVariantsJson = widget.item?.ageVariants;

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
    if (trimOrNull(_summaryController.text) != item.summary) return true;
    if (_durationMin != item.defaultDurationMin) return true;
    if (_adultId != item.adultId) return true;
    if (trimOrNull(_locationController.text) != item.location) return true;
    if (trimOrNull(_notesController.text) != item.notes) return true;
    if (trimOrNull(_materialsController.text) != item.materials) return true;
    if (_hook != item.hook) return true;
    if (_keyPoints != item.keyPoints) return true;
    if (_learningGoals != item.learningGoals) return true;
    if (_audienceMinAge != item.audienceMinAge) return true;
    if (_audienceMaxAge != item.audienceMaxAge) return true;
    if (_engagementTimeMin != item.engagementTimeMin) return true;
    if (_sourceUrl != item.sourceUrl) return true;
    if (_sourceAttribution != item.sourceAttribution) return true;
    if (_ageVariantsJson != item.ageVariants) return true;
    return false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  /// Splat any non-null field from the AI draft into our state, but
  /// only where the current slot is empty — never clobber something
  /// the teacher already typed. Title and summary go through the
  /// visible controllers; the rich invisible fields land in state
  /// directly. Tracks which fields were filled so the post-fill
  /// readout can hint at what changed.
  void _applyDraft(LibraryCardDraft draft) {
    final filled = <String>[];
    void fillText(TextEditingController c, String? v, String label) {
      if (v == null || v.isEmpty) return;
      if (c.text.trim().isNotEmpty) return;
      c.text = v;
      filled.add(label);
    }

    void fillInvisible(
      String? Function() getter,
      void Function(String?) setter,
      String? v,
      String label,
    ) {
      if (v == null || v.isEmpty) return;
      if ((getter() ?? '').isNotEmpty) return;
      setter(v);
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

    fillText(_titleController, draft.title, 'title');
    fillText(_summaryController, draft.summary, 'description');
    fillInvisible(() => _hook, (v) => _hook = v, draft.hook, 'hook');
    fillInvisible(
      () => _keyPoints,
      (v) => _keyPoints = v,
      draft.keyPoints,
      'key points',
    );
    fillInvisible(
      () => _learningGoals,
      (v) => _learningGoals = v,
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

    String? newItemId;
    if (_isEdit) {
      // Pass through every field — visible state for the editor's
      // two prompts (title + summary) plus the invisible rich state
      // we preserved from the row. Value-wrapping lets us
      // distinguish "set to null" from "leave alone"; here we always
      // set explicitly because state was seeded from the row.
      await repo.updateItem(
        id: widget.item!.id,
        title: title,
        defaultDurationMin: Value(_durationMin),
        adultId: Value(_adultId),
        location: Value(location),
        notes: Value(notes),
        materials: Value(materials),
        summary: Value(summary),
        hook: Value(_hook),
        keyPoints: Value(_keyPoints),
        learningGoals: Value(_learningGoals),
        audienceMinAge: Value(_audienceMinAge),
        audienceMaxAge: Value(_audienceMaxAge),
        engagementTimeMin: Value(_engagementTimeMin),
        sourceUrl: Value(_sourceUrl),
        sourceAttribution: Value(_sourceAttribution),
        ageVariants: Value(_decodedAgeVariants()),
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
        hook: _hook,
        keyPoints: _keyPoints,
        learningGoals: _learningGoals,
        audienceMinAge: _audienceMinAge,
        audienceMaxAge: _audienceMaxAge,
        engagementTimeMin: _engagementTimeMin,
        sourceUrl: _sourceUrl,
        sourceAttribution: _sourceAttribution,
        ageVariants: _decodedAgeVariants(),
      );
    }
    if (!mounted) return;
    // On create, pop with the new library-item id so callers (e.g.
    // the activity wizard's "+ New library card" flow) can resolve
    // the newly-added row and pre-fill their own fields from it.
    // Edits still pop with null — nothing to hand back.
    Navigator.of(context).pop(newItemId);
  }

  /// Pass-through decoder — preserves whatever age-variants JSON the
  /// row carried (templates may have written some) without surfacing
  /// the data to the user. Returns null when the row had no variants.
  Map<int, AgeVariant>? _decodedAgeVariants() {
    final raw = _ageVariantsJson;
    if (raw == null || raw.isEmpty) return null;
    final decoded = ActivityLibraryRepository.decodeAgeVariants(raw);
    return decoded.isEmpty ? null : decoded;
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

    return StickyActionSheet(
      title: _isEdit ? 'Edit ritual' : 'New ritual',
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
        label: _isEdit ? 'Save' : 'Add',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AI-assist row — sits above the title field because the
          // whole point is to fill the fields below. The
          // _lastFilledLabels hint renders under the buttons after a
          // successful run.
          _AiAssistRow(
            onFillFromUrl: _fillFromUrl,
            onFillFromDescription: _fillFromDescription,
            lastFilled: _lastFilledLabels,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _titleController,
            label: 'Title',
            hint: 'e.g. Smell Walk · Body Map',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _summaryController,
            label: 'Description',
            hint: 'A paragraph describing what this practice is. '
                'What you do, what shape it takes, what to look for.',
            maxLines: 6,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          // The "Advanced" section holds everything secondary —
          // scheduling defaults, materials, notes, domain tags.
          // Collapsed by default so the canonical authoring path
          // is just two prompts.
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                const SizedBox(height: AppSpacing.sm),
                _AdvancedSection(
                  durationMin: _durationMin,
                  adultId: _adultId,
                  locationController: _locationController,
                  notesController: _notesController,
                  materialsController: _materialsController,
                  onDurationChanged: (m) =>
                      setState(() => _durationMin = m),
                  onAdultChanged: (id) => setState(() => _adultId = id),
                  isEdit: _isEdit,
                  itemId: widget.item?.id,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Advanced section body — everything that isn't title or description.
/// Pulled into its own widget so the main build stays readable.
class _AdvancedSection extends ConsumerWidget {
  const _AdvancedSection({
    required this.durationMin,
    required this.adultId,
    required this.locationController,
    required this.notesController,
    required this.materialsController,
    required this.onDurationChanged,
    required this.onAdultChanged,
    required this.isEdit,
    required this.itemId,
  });

  final int? durationMin;
  final String? adultId;
  final TextEditingController locationController;
  final TextEditingController notesController;
  final TextEditingController materialsController;
  final ValueChanged<int?> onDurationChanged;
  final ValueChanged<String?> onAdultChanged;
  final bool isEdit;
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adultsAsync = ref.watch(adultsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Default duration', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            _DurationChoice(
              label: '—',
              selected: durationMin == null,
              onTap: () => onDurationChanged(null),
            ),
            _DurationChoice(
              label: '15m',
              selected: durationMin == 15,
              onTap: () => onDurationChanged(15),
            ),
            _DurationChoice(
              label: '30m',
              selected: durationMin == 30,
              onTap: () => onDurationChanged(30),
            ),
            _DurationChoice(
              label: '45m',
              selected: durationMin == 45,
              onTap: () => onDurationChanged(45),
            ),
            _DurationChoice(
              label: '1h',
              selected: durationMin == 60,
              onTap: () => onDurationChanged(60),
            ),
            _DurationChoice(
              label: '90m',
              selected: durationMin == 90,
              onTap: () => onDurationChanged(90),
            ),
            _DurationChoice(
              label: '2h',
              selected: durationMin == 120,
              onTap: () => onDurationChanged(120),
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
            final resolvedId = adultId != null &&
                    adults.any((s) => s.id == adultId)
                ? adultId
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
              onChanged: onAdultChanged,
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: locationController,
          label: 'Default location (optional)',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: notesController,
          label: 'Notes (optional)',
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: materialsController,
          label: 'Materials (optional)',
          hint: "What you'll need — comma- or newline-separated.",
          keyboardType: TextInputType.multiline,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Developmental domains',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (isEdit && itemId != null)
          _DomainTagPicker(libraryItemId: itemId!)
        else
          Text(
            'Save once to enable tagging.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Two-button AI assist row: fill from a webpage URL, or fill from
/// a free-text description. Below the buttons, a small muted readout
/// confirms what the last run populated (handy for the invisible
/// rich fields — hook, key points, etc. — so the teacher isn't
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
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await widget.generate(input);
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: widget.maxLines,
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: (_) => _go(),
            enabled: !_busy,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
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
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }
}

/// Domain-tag chip picker. Lives at the bottom of the Advanced
/// section. Renders the seven `ObservationDomain` tags as toggle
/// chips against the row's current tags. Edit-only — needs an item
/// id to attach.
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
                  d == ObservationDomain.other
                      ? d.label
                      : '${d.code} · ${d.label}',
                  style: theme.textTheme.labelSmall,
                ),
                selected: selected.contains(d.name),
                onSelected: (v) async {
                  final repo =
                      ref.read(activityLibraryRepositoryProvider);
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
