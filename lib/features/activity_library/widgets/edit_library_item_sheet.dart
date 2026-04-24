import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
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
  late int? _durationMin = widget.item?.defaultDurationMin;
  late String? _adultId = widget.item?.adultId;
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
    return false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final repo = ref.read(activityLibraryRepositoryProvider);
    final title = _titleController.text.trim();
    final location = _locationController.text.trim().isEmpty
        ? null
        : _locationController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    final materials = _materialsController.text.trim().isEmpty
        ? null
        : _materialsController.text.trim();

    if (_isEdit) {
      // Only send the preset fields this sheet actually exposes; the
      // rich-card columns (audience/summary/hook/etc.) are left to
      // Value.absent() so a teacher editing a generated card's
      // title doesn't nuke its AI content.
      await repo.updateItem(
        id: widget.item!.id,
        title: title,
        defaultDurationMin: Value(_durationMin),
        adultId: Value(_adultId),
        location: Value(location),
        notes: Value(notes),
        materials: Value(materials),
      );
    } else {
      await repo.addItem(
        title: title,
        defaultDurationMin: _durationMin,
        adultId: _adultId,
        location: location,
        notes: notes,
        materials: materials,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
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
        onPressed:
            _isValid && (!_isEdit || _hasChanges) ? _submit : null,
        label: _isEdit ? 'Save' : 'Add to library',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
