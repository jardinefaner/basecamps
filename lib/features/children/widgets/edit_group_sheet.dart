import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/save_action.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit an existing group. Dense sheet with name, color picker, and a
/// delete icon that explains what happens to children when the group goes
/// away. Creation flows through `NewGroupWizardScreen`; this sheet is
/// edit-only.
class EditGroupSheet extends ConsumerStatefulWidget {
  const EditGroupSheet({required this.group, super.key});

  final Group group;

  @override
  ConsumerState<EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends ConsumerState<EditGroupSheet> {
  late final _name = TextEditingController(text: widget.group.name);
  late final _audienceAge = TextEditingController(
    text: widget.group.audienceAgeLabel ?? '',
  );
  late String? _colorHex = widget.group.colorHex;
  bool _submitting = false;

  bool get _isValid => _name.text.trim().isNotEmpty;

  bool get _hasChanges {
    final ageTrimmed = _audienceAge.text.trim();
    final ageWasNull = widget.group.audienceAgeLabel == null;
    final ageChanged = ageWasNull
        ? ageTrimmed.isNotEmpty
        : ageTrimmed != widget.group.audienceAgeLabel;
    return _name.text.trim() != widget.group.name ||
        _colorHex != widget.group.colorHex ||
        ageChanged;
  }

  @override
  void dispose() {
    _name.dispose();
    _audienceAge.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final name = _name.text.trim();
    final ageTrimmed = _audienceAge.text.trim();
    final repo = ref.read(childrenRepositoryProvider);
    await repo.updateGroup(
      id: widget.group.id,
      name: name,
      colorHex: _colorHex,
      clearColor: _colorHex == null && widget.group.colorHex != null,
      // Distinguish "leave alone" (no edit) from "clear" (user
      // emptied the field). Empty after a non-null original = clear.
      audienceAgeLabel: ageTrimmed.isEmpty ? null : ageTrimmed,
      clearAudienceAgeLabel: ageTrimmed.isEmpty &&
          widget.group.audienceAgeLabel != null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final group = widget.group;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete "${group.name}"?',
      message: 'Children in this group become unassigned — they stay on '
          'the Children tab and keep their profiles, notes, and '
          "observations. You'll get a 5-second window to undo.",
      confirmLabel: 'Delete group',
      onDelete: () =>
          ref.read(childrenRepositoryProvider).deleteGroup(group.id),
      undoLabel: '"${group.name}" removed',
      onUndo: () =>
          ref.read(childrenRepositoryProvider).restoreGroup(group),
    );
    if (!confirmed || !mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StickyActionSheet(
      title: 'Edit group',
      titleTrailing: IconButton(
        tooltip: 'Delete group',
        onPressed: _delete,
        icon: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.error,
        ),
      ),
      actionBar: AppButton.primary(
        onPressed: _isValid && _hasChanges && !_submitting
            ? () => runWithErrorReport(context, _save)
            : null,
        label: 'Save changes',
        isLoading: _submitting,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Group name',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Free-text age range. Used as AI generation context
          // wherever a feature picks an activity for this group
          // (monthly plan ✨, future activity-library suggestions,
          // etc.). "3-5 years", "preschool", "toddlers" all work.
          AppTextField(
            controller: _audienceAge,
            label: 'Age range',
            hint: 'e.g. 3–5 years, preschool, toddlers',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Color', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _GroupColorGrid(
            selectedHex: _colorHex,
            onChanged: (hex) => setState(() => _colorHex = hex),
          ),
        ],
      ),
    );
  }
}

/// Same shape as the color picker on the wizard (kept local so the
/// wizard and sheet don't import each other's privates).
class _GroupColorGrid extends StatelessWidget {
  const _GroupColorGrid({
    required this.selectedHex,
    required this.onChanged,
  });

  final String? selectedHex;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Dot(
          color: theme.colorScheme.surfaceContainerHigh,
          selected: selectedHex == null,
          border: theme.colorScheme.outlineVariant,
          icon: Icons.block,
          iconColor: theme.colorScheme.onSurfaceVariant,
          onTap: () => onChanged(null),
        ),
        for (final c in groupColors)
          _Dot(
            color: c.color,
            selected: c.hex == selectedHex,
            onTap: () => onChanged(c.hex),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.border,
    this.icon,
    this.iconColor,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color? border;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : (border ?? Colors.transparent),
            width: selected ? 3 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: iconColor, size: 20)
            : (selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null),
      ),
    );
  }
}
