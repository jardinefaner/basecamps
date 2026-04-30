import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/themes/themes_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Palette teachers pick from. Hex strings match the material tonal
/// surfaces so the theme swatch reads well in both light + dark.
const _themePalette = <_ThemeSwatch>[
  _ThemeSwatch(label: 'Blue', hex: '#3D5AFE'),
  _ThemeSwatch(label: 'Green', hex: '#2E7D32'),
  _ThemeSwatch(label: 'Amber', hex: '#F57C00'),
  _ThemeSwatch(label: 'Pink', hex: '#D81B60'),
  _ThemeSwatch(label: 'Purple', hex: '#6A1B9A'),
  _ThemeSwatch(label: 'Teal', hex: '#00838F'),
];

class _ThemeSwatch {
  const _ThemeSwatch({required this.label, required this.hex});
  final String label;
  final String hex;
}

Color? parseThemeColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final clean = hex.startsWith('#') ? hex.substring(1) : hex;
  if (clean.length != 6) return null;
  final n = int.tryParse(clean, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}

/// Create / edit a program theme — name + date range + optional color
/// swatch + optional notes. Used for both paths since themes are
/// simple; no wizard needed.
class EditThemeSheet extends ConsumerStatefulWidget {
  const EditThemeSheet({super.key, this.theme});

  /// Null → create. Non-null → edit.
  final ProgramTheme? theme;

  @override
  ConsumerState<EditThemeSheet> createState() => _EditThemeSheetState();
}

class _EditThemeSheetState extends ConsumerState<EditThemeSheet> {
  late final _nameController =
      TextEditingController(text: widget.theme?.name ?? '');
  late final _notesController =
      TextEditingController(text: widget.theme?.notes ?? '');
  late DateTime _startDate;
  late DateTime _endDate;
  late String? _colorHex = widget.theme?.colorHex;
  bool _submitting = false;

  bool get _isEdit => widget.theme != null;
  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      !_endDate.isBefore(_startDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = now.dayOnly;
    _startDate = widget.theme?.startDate ?? today;
    _endDate =
        widget.theme?.endDate ?? today.add(const Duration(days: 4));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final repo = ref.read(themesRepositoryProvider);
    final name = _nameController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    if (_isEdit) {
      await repo.updateTheme(
        id: widget.theme!.id,
        name: name,
        startDate: _startDate,
        endDate: _endDate,
        colorHex: Value(_colorHex),
        notes: Value(notes),
      );
    } else {
      await repo.addTheme(
        name: name,
        startDate: _startDate,
        endDate: _endDate,
        colorHex: _colorHex,
        notes: notes,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final theme = widget.theme!;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${theme.name}"?',
      message: 'Removes the theme and clears its date range. '
          "You'll get a 5-second window to undo.",
      onDelete: () =>
          ref.read(themesRepositoryProvider).deleteTheme(theme.id),
      undoLabel: '"${theme.name}" removed',
      onUndo: () =>
          ref.read(themesRepositoryProvider).restoreTheme(theme),
    );
    if (!confirmed || !mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StickyActionSheet(
      title: _isEdit ? 'Edit theme' : 'New theme',
      titleTrailing: _isEdit
          ? IconButton(
              onPressed: _delete,
              tooltip: 'Delete theme',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            )
          : null,
      actionBar: AppButton.primary(
        onPressed: _isValid && !_submitting
            ? () => runWithErrorReport(context, _submit)
            : null,
        label: _isEdit ? 'Save' : 'Add theme',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Name',
            hint: 'e.g. Bug Week · Kindness week',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Date range', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Start',
                  date: _startDate,
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _DateField(
                  label: 'End',
                  date: _endDate,
                  onTap: _pickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Color (optional)', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('No color'),
                selected: _colorHex == null,
                onSelected: (_) => setState(() => _colorHex = null),
              ),
              for (final swatch in _themePalette)
                ChoiceChip(
                  label: Text(swatch.label),
                  avatar: CircleAvatar(
                    backgroundColor: parseThemeColor(swatch.hex),
                    radius: 10,
                  ),
                  selected: _colorHex == swatch.hex,
                  onSelected: (_) =>
                      setState(() => _colorHex = swatch.hex),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _notesController,
            label: 'Notes (optional)',
            hint: 'What this theme covers',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat.MMMd().add_y().format(date),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
