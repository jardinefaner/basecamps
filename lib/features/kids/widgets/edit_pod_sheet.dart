import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/kids/pod_colors.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/sticky_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit an existing pod. Dense sheet with name, color picker, and a
/// delete icon that explains what happens to kids when the pod goes
/// away. Creation flows through `NewGroupWizardScreen`; this sheet is
/// edit-only.
class EditGroupSheet extends ConsumerStatefulWidget {
  const EditGroupSheet({required this.pod, super.key});

  final Group pod;

  @override
  ConsumerState<EditGroupSheet> createState() => _EditPodSheetState();
}

class _EditPodSheetState extends ConsumerState<EditGroupSheet> {
  late final _name = TextEditingController(text: widget.pod.name);
  late String? _colorHex = widget.pod.colorHex;
  bool _submitting = false;

  bool get _isValid => _name.text.trim().isNotEmpty;

  bool get _hasChanges {
    return _name.text.trim() != widget.pod.name ||
        _colorHex != widget.pod.colorHex;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    final name = _name.text.trim();
    final repo = ref.read(childrenRepositoryProvider);
    await repo.updatePod(
      id: widget.pod.id,
      name: name,
      colorHex: _colorHex,
      clearColor: _colorHex == null && widget.pod.colorHex != null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete "${widget.pod.name}"?',
      message: 'Children in this group become unassigned — they stay on the '
          'Children tab and keep their profiles, notes, and observations. '
          'Cannot be undone.',
      confirmLabel: 'Delete group',
    );
    if (!confirmed) return;
    await ref.read(childrenRepositoryProvider).deleteGroup(widget.pod.id);
    if (!mounted) return;
    Navigator.of(context).pop();
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
        onPressed: _isValid && _hasChanges && !_submitting ? _save : null,
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
          Text('Color', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _PodColorGrid(
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
class _PodColorGrid extends StatelessWidget {
  const _PodColorGrid({
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
